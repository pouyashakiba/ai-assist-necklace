"""Loopback-only USB/audio bridge. No speech model or response selection runs here."""
import asyncio
import base64
import json
import pathlib
import threading
import time
from contextlib import asynccontextmanager

import serial
from serial.tools import list_ports
from fastapi import FastAPI, HTTPException, Request, UploadFile, File
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from starlette.middleware.trustedhost import TrustedHostMiddleware
from pydantic import BaseModel

ROOT = pathlib.Path(__file__).resolve().parent
COMMANDS = json.loads((ROOT / 'commands.json').read_text(encoding='utf-8'))

class Bridge:
    def __init__(self):
        self.port = None
        self.lock = threading.Lock()

    def close(self):
        if self.port:
            self.port.close()
            self.port = None

    def connect(self, device):
        allowed = {p.device for p in list_ports.comports() if p.vid == 0x303A}
        if device not in allowed:
            raise ValueError('Select the connected Espressif USB board.')
        with self.lock:
            self.close()
            # Establish the USB line state once, then allow boot to settle.
            # Keep the port open for the complete transaction (including format).
            self.port = serial.Serial(device, baudrate=115200, timeout=15, write_timeout=15)
            self.port.dtr = False
            self.port.rts = False
            time.sleep(1)
            self.port.reset_input_buffer()
            # Native HWCDC may discard its first IN frame after reopening.
            # STATUS is idempotent; retry the handshake before any mutation.
            self.port.timeout = .8
            for _ in range(8):
                self.port.write(b'STATUS\n')
                try:
                    result = self.read_json(1)
                    if result.get('firmware'):
                        # Retried STATUS requests can leave extra complete
                        # responses queued. Drain only this idempotent startup
                        # phase before starting the request/response protocol.
                        self.port.timeout = .2
                        while True:
                            pending = self.port.readline()
                            if not pending:
                                break
                            try:
                                extra = json.loads(pending)
                                if extra.get('firmware'):
                                    result = extra
                            except (ValueError, UnicodeError, AttributeError):
                                pass
                        self.port.timeout = 15
                        return result
                except TimeoutError:
                    continue
            self.close()
            raise TimeoutError('Board handshake failed. Reconnect USB and try again.')

    def read_json(self, timeout=20):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            raw = self.port.readline()
            if not raw:
                break
            try:
                obj = json.loads(raw)
                if isinstance(obj, dict):
                    return obj
            except (ValueError, UnicodeError):
                pass
        raise TimeoutError('Board did not respond. Reconnect USB and try again.')

    def read_exact(self, size):
        data = bytearray()
        while len(data) < size:
            chunk = self.port.read(size - len(data))
            if not chunk:
                raise TimeoutError('Incomplete audio from the board.')
            data.extend(chunk)
        return bytes(data)

    def command(self, line, pcm=None):
        with self.lock:
            if not self.port or not self.port.is_open:
                raise ValueError('Connect the board first.')
            try:
                self.port.timeout = 120 if line == 'FORMAT TRAINING' else 15
                self.port.write((line + '\n').encode('ascii'))
                result = self.read_json(180 if line == 'FORMAT TRAINING' else 20)
                if pcm is not None:
                    if not result.get('ready'):
                        return result
                    # HWCDC's default RX queue is only 256 bytes. Bound each
                    # burst so native USB cannot outrun the MCU's PCM reader.
                    for offset in range(0, len(pcm), 128):
                        self.port.write(pcm[offset:offset + 128])
                        time.sleep(.003)
                    self.port.flush()
                    result = self.read_json()
                size = result.get('audio_bytes', 0)
                if not isinstance(size, int) or not 0 <= size <= 2_000_000:
                    raise ValueError('Invalid board audio frame.')
                if size:
                    result['audio'] = base64.b64encode(self.read_exact(size)).decode('ascii')
                return result
            except (serial.SerialException, TimeoutError):
                self.close()
                raise

bridge = Bridge()

@asynccontextmanager
async def lifespan(app):
    yield
    bridge.close()

app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None)
app.add_middleware(TrustedHostMiddleware, allowed_hosts=['127.0.0.1', 'localhost', '[::1]'])

@app.middleware('http')
async def same_origin(request: Request, call_next):
    origin = request.headers.get('origin')
    if request.method != 'GET' and origin and origin not in {'http://127.0.0.1:8765', 'http://localhost:8765'}:
        from fastapi.responses import JSONResponse
        return JSONResponse({'detail': 'Origin rejected'}, status_code=403)
    return await call_next(request)

async def run(fn, *args):
    try:
        return await asyncio.to_thread(fn, *args)
    except (ValueError, TimeoutError, serial.SerialException, OSError) as error:
        raise HTTPException(503, str(error)) from error

class Connection(BaseModel):
    port: str

class Face(BaseModel):
    face: str

@app.get('/api/ports')
def ports():
    return [{'port': p.device, 'name': p.description} for p in list_ports.comports() if p.vid == 0x303A]

@app.post('/api/connect')
async def connect(body: Connection):
    return await run(bridge.connect, body.port)

@app.post('/api/disconnect')
async def disconnect():
    # Serialize closing against ongoing PCM transactions.
    def close():
        with bridge.lock:
            bridge.close()
    await run(close)
    return {'ok': True}

@app.get('/api/status')
async def status():
    return await run(bridge.command, 'STATUS')

@app.get('/api/commands')
def commands():
    return COMMANDS

@app.post('/api/face')
async def face(body: Face):
    if body.face not in {'neutral','happy','laughing','shy','curious','surprised','sleepy','sleeping','affectionate','playful','sad','listening','thinking','speaking'}:
        raise HTTPException(400, 'Invalid face')
    return await run(bridge.command, 'FACE ' + body.face)

@app.post('/api/say/{command_id}')
async def say(command_id: int):
    if not 0 <= command_id <= 12:
        raise HTTPException(400, 'Invalid command')
    return await run(bridge.command, f'SAY {command_id}')

@app.post('/api/clear/{command_id}')
async def clear(command_id: int):
    if not 0 <= command_id < 12:
        raise HTTPException(400, 'Invalid command')
    return await run(bridge.command, f'CLEAR {command_id}')

@app.post('/api/audio/{mode}/{command_id}')
async def audio(mode: str, command_id: int, file: UploadFile = File(...)):
    if mode not in {'train', 'recognize'} or not -1 <= command_id < 12 or (mode == 'train' and command_id < 0):
        raise HTTPException(400, 'Invalid mode or command')
    pcm = await file.read(128001)
    if not 6400 <= len(pcm) <= 128000 or len(pcm) % 2:
        raise HTTPException(400, 'Audio must be 0.2–4s of mono 16 kHz PCM16.')
    return await run(bridge.command, f'AUDIO {mode} {command_id} {len(pcm)}', pcm)

@app.get('/')
def index():
    return FileResponse(ROOT / 'web' / 'index.html')

app.mount('/assets', StaticFiles(directory=ROOT / 'web'), name='assets')

if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='127.0.0.1', port=8765)
