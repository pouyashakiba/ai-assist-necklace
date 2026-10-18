"""Board maintenance. Stop/disconnect the web bridge before running."""
import argparse
import json
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from server import Bridge

parser=argparse.ArgumentParser()
parser.add_argument('--port',default='COM3')
parser.add_argument('--hardware',choices=['on','off'])
parser.add_argument('--format-training',action='store_true',help='Erase only the new companion training filesystem, after making a flash backup')
parser.add_argument('--threshold',type=float)
args=parser.parse_args()
bridge=Bridge()
try:
    result=bridge.connect(args.port)
    if result.get('firmware')!='little-companion-1.0':
        raise SystemExit('Companion firmware not found')
    if args.format_training:result=bridge.command('FORMAT TRAINING')
    if args.hardware:result=bridge.command('HARDWARE '+args.hardware.upper())
    if args.threshold is not None:
        if not .1<=args.threshold<=4:parser.error('threshold must be 0.1–4')
        result=bridge.command('THRESHOLD '+str(args.threshold))
    print(json.dumps(result,ensure_ascii=True,indent=2))
finally:
    bridge.close()
