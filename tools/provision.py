"""One-time, internet-connected asset provisioning; no inference dependency at runtime."""
import json
import pathlib
import wave
import requests
import argparse

ROOT = pathlib.Path(__file__).resolve().parents[1]

def download(url, path):
    if path.exists():
        return
    with requests.get(url, stream=True, timeout=120) as response:
        response.raise_for_status()
        with path.with_suffix(path.suffix + '.part').open('wb') as stream:
            for chunk in response.iter_content(1024 * 1024):
                stream.write(chunk)
    path.with_suffix(path.suffix + '.part').replace(path)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--language',choices=['en','fa'],default='en')
    language=parser.parse_args().language
    from piper import PiperVoice, SynthesisConfig
    voice_name='en_US-lessac-medium' if language=='en' else 'fa_IR-amir-medium'
    models = ROOT / 'models' / voice_name
    models.mkdir(parents=True,exist_ok=True)
    route='en/en_US/lessac/medium/' if language=='en' else 'fa/fa_IR/amir/medium/'
    base = 'https://huggingface.co/rhasspy/piper-voices/resolve/main/'+route
    model = models / (voice_name+'.onnx')
    for name in [model.name, model.name + '.json', 'MODEL_CARD']:
        download(base + name, models / name)
    voice = PiperVoice.load(str(model))
    catalog=ROOT/'commands.json' if language=='en' else ROOT/'locales/fa/commands.json'
    commands = json.loads(catalog.read_text(encoding='utf-8'))
    out = ROOT / 'web' / 'audio'
    out.mkdir(parents=True, exist_ok=True)
    header = ['#pragma once', '#include <Arduino.h>', 'struct ReplyAudio {const uint8_t* data; uint32_t size;};']
    for command in commands:
        path = out / f"{command['id']}.wav"
        with wave.open(str(path), 'wb') as wav:
            voice.synthesize_wav(command['reply'], wav, syn_config=SynthesisConfig(length_scale=1.05))
        # Downsample to 16 kHz PCM to keep firmware small and I2S playback simple.
        import numpy as np
        with wave.open(str(path), 'rb') as wav:
            rate = wav.getframerate()
            pcm = np.frombuffer(wav.readframes(wav.getnframes()), dtype='<i2')
        samples = np.interp(np.arange(int(len(pcm)*16000/rate))*rate/16000, np.arange(len(pcm)), pcm).astype('<i2')
        with wave.open(str(path), 'wb') as wav:
            wav.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
            wav.writeframes(samples.tobytes())
        data = path.read_bytes()
        header.append(f"const uint8_t audio_{command['id']}[] PROGMEM = {{" + ','.join(map(str, data)) + '};')
        print('reply', command['id'], 'bytes', len(data), flush=True)
    header.append('const ReplyAudio REPLIES[] = {' + ','.join(f'{{audio_{c["id"]},sizeof(audio_{c["id"]})}}' for c in commands) + '};')
    (ROOT / 'firmware' / 'companion' / 'replies.h').write_text('\n'.join(header), encoding='utf-8')
    # Command metadata is also embedded so the USB response originates on the board.
    meta = ['#pragma once', 'struct Command { const char* phrase; const char* reply; const char* face; };', 'const Command COMMANDS[] = {']
    for c in commands:
        meta.append('{' + ','.join(json.dumps(c[k], ensure_ascii=False) for k in ['phrase','reply','face']) + '},')
    meta.append('};')
    (ROOT / 'firmware' / 'companion' / 'commands.h').write_text('\n'.join(meta), encoding='utf-8')

if __name__ == '__main__':
    main()
