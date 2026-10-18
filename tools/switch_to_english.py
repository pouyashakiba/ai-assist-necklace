"""Make English the default while retaining the original Farsi command catalog."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
path=ROOT/'locales/fa/commands.json'
path.parent.mkdir(parents=True,exist_ok=True)
if not path.exists():path.write_bytes((ROOT/'commands.json').read_bytes())
rows=[
('hello','Hi! I am your little companion. It is good to see you.','happy'),
('how are you','I am doing well. How is your day going?','happy'),
('what is your name','You can call me Milo. I am happy to be here with you.','shy'),
('make me laugh','Why did the robot take a nap? It needed to recharge its personality!','laughing'),
('go to sleep','All right. I will take a little rest.','sleeping'),
('wake up','I am awake and ready. What shall we do?','neutral'),
('I love you','I am happy to be your companion.','affectionate'),
('I feel sad','I am sorry you are having a hard time. I am here with you.','sad'),
('tell me a joke','Why was the robot bad at hide and seek? It kept giving away its location!','playful'),
('what can you do','By myself, I recognize phrases you teach me. With your phone, I can answer much more.','curious'),
('be surprised','Wow! Now that is a surprise!','surprised'),
('goodbye','See you soon. I will be right here.','sleepy'),
('unknown','I did not recognize that. Please try a phrase you have taught me.','curious')]
commands=[dict(id=i,phrase=p,reply=r,face=f) for i,(p,r,f) in enumerate(rows)]
(ROOT/'commands.json').write_text(json.dumps(commands,indent=2)+'\n',encoding='utf-8')
print('English command catalog selected; Farsi catalog retained in locales/fa.')
