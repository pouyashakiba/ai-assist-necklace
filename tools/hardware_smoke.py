"""Opt-in real-board validation, only on a board with no user training.

Synthetic Persian command audio exercises actual on-device DSP. It does not
measure human-speaker accuracy or validate a physical I2S microphone/speaker.
"""
import base64
import hashlib
import io
import json
from pathlib import Path
import sys
import time
import wave
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from server import Bridge

ROOT=Path(__file__).resolve().parents[1]

def fixture(text):
    from piper import PiperVoice
    voice=PiperVoice.load(str(ROOT/'models/fa_IR-amir-medium.onnx'))
    stream=io.BytesIO()
    with wave.open(stream,'wb') as wav:voice.synthesize_wav(text,wav)
    stream.seek(0)
    with wave.open(stream,'rb') as wav:
        rate=wav.getframerate();data=np.frombuffer(wav.readframes(wav.getnframes()),dtype='<i2')
    return np.interp(np.arange(int(len(data)*16000/rate))*rate/16000,np.arange(len(data)),data).astype('<i2')

def variant(pcm,speed):
    return np.interp(np.arange(0,len(pcm),speed),np.arange(len(pcm)),pcm).astype('<i2').tobytes()

def main():
    bridge=Bridge();results={};safe_to_clear=False
    try:
        status=bridge.connect('COM3');results['initial_status']=status
        assert status['firmware']=='little-companion-1.0'
        assert status['psram']==8388608
        assert status['lcd']=='off'
        assert not any(status['trained']),'Do not overwrite user training'
        safe_to_clear=True
        if not status['storage']:
            assert bridge.command('FORMAT TRAINING')['storage']
        for id in range(13):
            result=bridge.command(f'SAY {id}')
            wav=base64.b64decode(result['audio'])
            expected=(ROOT/f'web/audio/{id}.wav').read_bytes()
            assert wav==expected,f'WAV mismatch {id}'
            with wave.open(io.BytesIO(wav),'rb') as w:
                assert w.getframerate()==16000 and w.getnchannels()==1
            print('verified board reply',id,flush=True)
        results['reply_audio']='13/13 WAVs byte-identical to embedded originals'
        sources=[fixture('سلام'),fixture('حالت چطوره')]
        for id,source in enumerate(sources):
            for speed in [1.,.94]:
                pcm=variant(source,speed)
                s=bridge.command(f'AUDIO train {id} {len(pcm)}',pcm)
                assert s.get('trained',[0]*12)[id]>=1,{k:v for k,v in s.items() if k!='audio'}
                print('trained',id,speed,flush=True)
        s=bridge.command('STATUS');assert s['trained'][:2]==[2,2]
        results['training']='two MFCC templates for each of two synthesized Persian phrases'
        recognized=[]
        for id,source in enumerate(sources):
            pcm=variant(source,1.04)
            result=bridge.command(f'AUDIO recognize -1 {len(pcm)}',pcm)
            recognized.append(result.get('id'))
            assert result.get('id')==id,(id,result.get('id'))
        results['recognition']=recognized
        silence=bytes(32000)
        result=bridge.command(f'AUDIO recognize -1 {len(silence)}',silence)
        assert result.get('error')=='silence_or_short_audio',result
        results['silence']='rejected'
        bridge.command('RESTART');bridge.close();time.sleep(2)
        s=bridge.connect('COM3');assert s['trained'][:2]==[2,2],s
        results['reboot_persistence']='passed'
    finally:
        try:
            if bridge.port and safe_to_clear:
                for id in [0,1]:bridge.command(f'CLEAR {id}')
                results['final_status']=bridge.command('STATUS')
        finally:bridge.close()
        (ROOT/'hardware-validation.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(results,ensure_ascii=True,indent=2))

if __name__=='__main__':main()
