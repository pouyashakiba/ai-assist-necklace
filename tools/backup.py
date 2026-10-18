"""Read the original flash in bounded chunks (native USB stalls on large stub reads)."""
import contextlib
import hashlib
import io
import pathlib
import time
import esptool
import struct

ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'backups'
OUT.mkdir(exist_ok=True)
SIZE=0x1000000
CHUNK=0x40000

def connect():
    with contextlib.redirect_stdout(io.StringIO()):
        esp=esptool.detect_chip(port='COM3',baud=115200)
        esp=esp.run_stub()
        esptool.cmds.attach_flash(esp)
        esp.flash_set_parameters(SIZE)
    return esp

def bounded_read(esp,offset,size):
    # The default stub pipelines 64 sectors, which overruns this USB connection.
    # Request one 1 KiB block in flight and retain the stub's MD5 validation.
    block=1024
    esp.check_command('read flash',esp.ESP_CMDS['READ_FLASH'],struct.pack('<IIII',offset,size,block,1))
    data=bytearray()
    while len(data)<size:
        esp._port.timeout=15
        frame=esp.read()
        if len(frame)!=min(block,size-len(data)):
            raise ValueError('unexpected flash frame')
        data.extend(frame)
        esp.write(struct.pack('<I',len(data)))
    digest=esp.read()
    if digest!=hashlib.md5(data).digest():
        raise ValueError('flash MD5 mismatch')
    return data

esp=connect()
try:
    for offset in range(0,SIZE,CHUNK):
        path=OUT/f'chunk-{offset:08x}.bin'
        if path.exists() and path.stat().st_size==CHUNK:
            continue
        for attempt in range(3):
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    data=bounded_read(esp,offset,CHUNK)
                if len(data)!=CHUNK:
                    raise ValueError('short read')
                path.write_bytes(data)
                print(f'backed up {offset+CHUNK}/{SIZE}',flush=True)
                break
            except Exception:
                if attempt==2:
                    raise
                esp._port.close()
                time.sleep(1)
                esp=connect()
    data=b''.join((OUT/f'chunk-{o:08x}.bin').read_bytes() for o in range(0,SIZE,CHUNK))
    (OUT/'original-flash.bin').write_bytes(data)
    (OUT/'original-flash.sha256').write_text(hashlib.sha256(data).hexdigest()+'\n')
    print('Full flash backup saved and hashed.',flush=True)
finally:
    with contextlib.redirect_stdout(io.StringIO()):
        esp.hard_reset()
    esp._port.close()
