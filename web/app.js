'use strict';
const $=id=>document.getElementById(id);
let connected=false,busy=false,recording=false,commands=[],counts=Array(12).fill(0),mood='neutral',speaking=false,currentAudio=null,stopCapture=null;
const labels={neutral:'آمادهٔ آشنایی',happy:'خوشحالم که اینجایی',laughing:'یه خندهٔ کوچیک!',shy:'کمی خجالت کشیدم',curious:'کنجکاوم بدونم',surprised:'وای، چه جالب!',sleepy:'یه کم خوابم میاد',sleeping:'در حال استراحت',affectionate:'خوشحالم که کنارتم',playful:'وقت بازیه',sad:'من اینجام، کنارت',listening:'دارم گوش می‌دم…',thinking:'دارم فرمان رو بررسی می‌کنم…'};
const errorLabels={silence_or_short_audio:'صدا خیلی کوتاه یا آرام بود. نزدیک‌تر به میکروفون و بلافاصله بعد از شروع ضبط صحبت کن.',training_unavailable:'حافظهٔ آموزش برد آماده نیست.',audio_timeout:'انتقال صدا ناقص ماند؛ اتصال را دوباره برقرار کن.'};
function notice(text,error=false){$('notice').textContent=text;$('notice').classList.toggle('error',error)}
function updateControls(){
 $('talk').disabled=!connected||busy&&!recording;
 $('connect').disabled=busy;
 document.querySelectorAll('.train,.preview,.reset').forEach(b=>b.disabled=!connected||busy);
 $('port').disabled=connected||busy;
 $('refresh').disabled=connected||busy;
}
function setMood(value){mood=value;$('moodLabel').textContent=labels[value]||value;$('face').setAttribute('aria-label','چهرهٔ ربات: '+(Faces.names[value]||value));document.querySelectorAll('.expression').forEach(b=>b.classList.toggle('selected',b.dataset.face===value))}
function applyStatus(s){
 if(s.lcd==='off')$('lcdState').textContent='LCD فیزیکی: خاموش';
 if(s.trained){counts=s.trained;$('trainedCount').textContent=`${counts.filter(n=>n>=2).length.toLocaleString('fa-IR')} از ۱۲`;renderCommands()}
 if(s.psram!==undefined)$('ram').textContent=(s.psram/1048576).toFixed(0)+' MB';
}
async function api(path,options={}){
 const response=await fetch('/api/'+path,options);
 const data=await response.json();
 if(!response.ok)throw new Error(data.detail||'ارتباط با برد برقرار نشد.');
 if(data.ok===false)throw new Error(errorLabels[data.error]||data.error);
 return data;
}
const post=(path,body)=>api(path,{method:'POST',...(body?{headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}:{})});
async function refresh(){
 try{const ports=await api('ports');$('port').replaceChildren();for(const p of ports){const o=document.createElement('option');o.value=p.port;o.textContent=p.port+' · ESP32-S3';$('port').append(o)}if(!ports.length){const o=document.createElement('option');o.value='';o.textContent='برد پیدا نشد';$('port').append(o)}}catch(e){notice(e.message,true)}
}
$('refresh').onclick=refresh;
$('connect').onclick=async()=>{
 busy=true;updateControls();
 try{
  if(connected){await post('disconnect');connected=false;notice('اتصال USB قطع شد.');$('connectionBadge').textContent='متصل نیست'}
  else{if(!$('port').value)throw Error('برد را با کابل USB داده متصل کن و جست‌وجو را بزن.');const s=await post('connect',{port:$('port').value});if(s.firmware!=='little-companion-1.0'){await post('disconnect');throw Error('فریمور همراه کوچک روی این برد شناسایی نشد.')}connected=true;applyStatus(s);$('connectionBadge').textContent='متصل · '+$('port').value;notice('برد متصل شد. اول دو فرمان را هرکدام حداقل دو بار آموزش بده؛ سه نمونه بهتر است.');$('recordHint').textContent='ضبط کوتاه ۲٫۵ ثانیه‌ای · پردازش کاملاً روی برد'}
 }catch(e){notice(e.message,true)}finally{busy=false;$('connect').textContent=connected?'قطع اتصال':'اتصال';$('connectionBadge').classList.toggle('connected',connected);updateControls()}
};
for(const [name,label] of Object.entries(Faces.names)){
 const button=document.createElement('button');button.className='expression';button.dataset.face=name;button.setAttribute('aria-label','نمایش حالت '+label);
 const canvas=document.createElement('canvas');canvas.width=320;canvas.height=172;canvas.setAttribute('aria-hidden','true');Faces.draw(canvas,name);
 const caption=document.createElement('span');caption.textContent=label;button.append(canvas,caption);
 button.onclick=async()=>{if(busy)return;$('autoMood').checked=false;setMood(name);if(connected)try{await post('face',{face:name})}catch(e){notice(e.message,true)}};
 $('expressionGrid').append(button);
}
for(let i=0;i<23;i++){const bar=document.createElement('i');bar.style.animationDelay=(i%7*.07)+'s';$('wave').append(bar)}
const reduced=matchMedia('(prefers-reduced-motion: reduce)');
let nextBlink=performance.now()+3000;
function animate(t){let blink=0;if(!reduced.matches&&t>nextBlink){const d=t-nextBlink;blink=d<80?d/80:d<150?1:1-(d-150)/100;if(d>250){nextBlink=t+2800+Math.random()*3000;blink=0}}Faces.draw($('face'),mood==='thinking'?'curious':mood,blink,speaking&&!reduced.matches?Math.floor(t/150)%3:0);requestAnimationFrame(animate)}requestAnimationFrame(animate);
function log(text,type='assistant'){
 const empty=$('log').querySelector('.empty-log');if(empty)empty.remove();
 const message=document.createElement('div');message.className='message '+type;const label=document.createElement('small');label.textContent=type==='user'?'فرمان تشخیص‌داده‌شده توسط برد':'همراه کوچک';const content=document.createElement('span');content.textContent=text;message.append(label,content);$('log').append(message);message.scrollIntoView({block:'nearest',behavior:reduced.matches?'instant':'smooth'});
}
$('clearLog').onclick=()=>{$('log').replaceChildren();notice('تاریخچهٔ همین صفحه پاک شد. نمونه‌های آموزشی روی برد باقی هستند.')};
async function play(result,addLog=true){
 if(addLog)log(result.text);
 if($('autoMood').checked)setMood(result.face);
 if(!result.audio)return;
 const bytes=Uint8Array.from(atob(result.audio),c=>c.charCodeAt(0));const url=URL.createObjectURL(new Blob([bytes],{type:'audio/wav'}));
 currentAudio=new Audio(url);
 try{speaking=true;await currentAudio.play();await new Promise((resolve,reject)=>{currentAudio.onended=resolve;currentAudio.onerror=()=>reject(Error('پخش صدا ناموفق بود.'))})}finally{speaking=false;currentAudio=null;URL.revokeObjectURL(url)}
}
function renderCommands(){
 $('commandGrid').replaceChildren();
 for(const command of commands.filter(c=>c.id<12)){
  const box=document.createElement('article');box.className='command';const heading=document.createElement('h3');heading.textContent=command.phrase;
  const samples=document.createElement('div');samples.className='samples';for(let i=0;i<3;i++){const dot=document.createElement('i');dot.classList.toggle('done',counts[command.id]>i);samples.append(dot)}const n=document.createElement('span');n.textContent=`${counts[command.id]}/3`;samples.append(n);
  const actions=document.createElement('div');actions.className='command-actions';
  const train=document.createElement('button');train.textContent=counts[command.id]===3?'ضبط مجدد نمونهٔ سوم':'آموزش با صدای من';train.className='secondary train';train.onclick=()=>capture('train',command.id);
  const preview=document.createElement('button');preview.textContent='شنیدن پاسخ';preview.className='text-button preview';preview.onclick=()=>previewReply(command.id);
  const reset=document.createElement('button');reset.textContent='از نو';reset.className='text-button reset';reset.setAttribute('aria-label','پاک‌کردن نمونه‌های '+command.phrase);reset.onclick=async()=>{busy=true;updateControls();try{applyStatus(await post('clear/'+command.id));notice('نمونه‌های این فرمان پاک شد.')}catch(e){notice(e.message,true)}finally{busy=false;updateControls()}};
  actions.append(train,preview,reset);box.append(heading,samples,actions);$('commandGrid').append(box);
 }updateControls();
}
async function previewReply(id){busy=true;updateControls();try{await play(await post('say/'+id));notice('پاسخ ذخیره‌شده از حافظهٔ خود برد پخش شد.')}catch(e){notice(e.message,true)}finally{busy=false;updateControls()}}
async function record(){
 if(!navigator.mediaDevices?.getUserMedia)throw Error('میکروفون فقط روی localhost یا HTTPS در دسترس است.');
 let stream,context;
 try{
  stream=await navigator.mediaDevices.getUserMedia({audio:{channelCount:1,echoCancellation:true,noiseSuppression:true,autoGainControl:true}});
  context=new AudioContext();await context.resume();await context.audioWorklet.addModule('/assets/recorder.js');
  const source=context.createMediaStreamSource(stream),lowpass=context.createBiquadFilter();lowpass.type='lowpass';lowpass.frequency.value=7000;
  const captureNode=new AudioWorkletNode(context,'companion-capture'),mute=context.createGain();mute.gain.value=0;source.connect(lowpass).connect(captureNode).connect(mute).connect(context.destination);
  const chunks=[];captureNode.port.onmessage=e=>chunks.push(e.data);
  recording=true;$('talk').classList.add('recording');$('talk').querySelector('span').textContent='پایان ضبط';$('wave').classList.add('active');if($('autoMood').checked)setMood('listening');updateControls();
  await new Promise(resolve=>{const timer=setTimeout(resolve,2500);stopCapture=()=>{clearTimeout(timer);resolve()}});
  captureNode.disconnect();source.disconnect();
  const total=chunks.reduce((n,a)=>n+a.length,0),samples=new Float32Array(total);let offset=0;for(const chunk of chunks){samples.set(chunk,offset);offset+=chunk.length}
  const size=Math.min(64000,Math.floor(total*16000/context.sampleRate));if(size<3200)throw Error('ضبط خیلی کوتاه بود؛ دوباره تلاش کن.');
  const pcm=new ArrayBuffer(size*2),view=new DataView(pcm),ratio=context.sampleRate/16000;
  for(let i=0;i<size;i++){const p=i*ratio,base=Math.floor(p),a=samples[base]||0,b=samples[base+1]||0,sample=a+(b-a)*(p-base);view.setInt16(i*2,Math.round(Math.max(-1,Math.min(1,sample))*32767),true)}
  return pcm;
 }finally{
  recording=false;stopCapture=null;stream?.getTracks().forEach(t=>t.stop());if(context)await context.close();$('wave').classList.remove('active');$('talk').classList.remove('recording');$('talk').querySelector('span').textContent='شروع صحبت';
 }
}
async function capture(mode,id=-1){
 if(busy)return;
 if(mode==='recognize'&&counts.filter(n=>n>=2).length<2){notice('حداقل دو فرمان را هرکدام دو بار آموزش بده تا مقایسهٔ صدا ممکن شود.',true);return}
 busy=true;updateControls();
 try{
  notice(mode==='train'?`اجازهٔ میکروفون را بده، سپس «${commands[id].phrase}» را یک بار بگو.`:'بعد از شروع ضبط یکی از فرمان‌های آموزش‌دیده را بگو.');
  const pcm=await record();if($('autoMood').checked)setMood('thinking');notice('صدا برای پردازش به خود برد فرستاده شد…');updateControls();
  const form=new FormData();form.append('file',new Blob([pcm],{type:'application/octet-stream'}),'audio.pcm');
  const result=await api(`audio/${mode}/${id}`,{method:'POST',body:form});
  if(mode==='train'){applyStatus(result);if($('autoMood').checked)setMood('happy');notice(`نمونهٔ ${counts[id].toLocaleString('fa-IR')} از «${commands[id].phrase}» روی برد ذخیره شد.`)}
  else{log(result.id<12?commands[result.id].phrase:'عبارت نامشخص','user');await play(result);notice(result.id===12?'برد این عبارت را با اطمینان کافی نشناخت. دوباره واضح‌تر بگو یا نمونه‌های بیشتری آموزش بده.':'پاسخ از خود برد دریافت و پخش شد.')}
 }catch(e){notice(e.name==='NotAllowedError'?'اجازهٔ میکروفون داده نشد. از تنظیمات مرورگر اجازه بده و دوباره تلاش کن.':e.message,true);if($('autoMood').checked)setMood('curious')}
 finally{busy=false;updateControls()}
}
$('talk').onclick=()=>{if(recording)stopCapture?.();else capture('recognize')};
$('autoMood').onchange=()=>{if($('autoMood').checked)setMood('neutral')};
Promise.all([refresh(),api('commands').then(data=>{commands=data;renderCommands()})]).catch(e=>notice(e.message,true));
setMood('neutral');
