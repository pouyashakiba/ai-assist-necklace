import io
import json
import unittest
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from server import Bridge

class FakePort:
    is_open=True
    def __init__(self,data):self.input=io.BytesIO(data);self.output=bytearray()
    def write(self,data):self.output.extend(data);return len(data)
    def readline(self):return self.input.readline()
    def read(self,size):return self.input.read(min(size,3)) # force partial frames
    def flush(self):pass
    def close(self):self.is_open=False

class ProtocolTests(unittest.TestCase):
    def test_audio_frame_is_consumed_before_next_status(self):
        b=Bridge();b.port=FakePort(b'boot noise\n'+json.dumps({'ok':True,'audio_bytes':8}).encode()+b'\nRIFFtest'+b'{"ok":true,"trained":[0]}\n')
        first=b.command('SAY 0');self.assertEqual(first['audio'],'UklGRnRlc3Q=')
        self.assertEqual(b.command('STATUS')['trained'],[0])
    def test_audio_handshake_sends_binary_unchanged(self):
        b=Bridge();b.port=FakePort(b'{"ready":true}\n{"ok":true}\n')
        b.command('AUDIO train 0 8',b'\x00\n\xff\xc0test')
        self.assertTrue(b.port.output.endswith(b'\x00\n\xff\xc0test'))
    def test_rejected_header_does_not_send_audio(self):
        b=Bridge();b.port=FakePort(b'{"ok":false,"error":"bad"}\n')
        b.command('AUDIO bad',b'private-pcm')
        self.assertNotIn(b'private-pcm',b.port.output)
    def test_truncated_audio_closes_connection(self):
        b=Bridge();port=FakePort(b'{"audio_bytes":9}\nRIFF');b.port=port
        with self.assertRaises(TimeoutError):b.command('SAY 0')
        self.assertFalse(port.is_open)
    def test_disconnect_is_clear_error(self):
        with self.assertRaisesRegex(ValueError,'Connect'):Bridge().command('STATUS')

if __name__=='__main__':unittest.main()
