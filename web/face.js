// Pixel geometry recreated from the supplied expression/keyframe sheets.
window.Faces = (() => {
 const names={neutral:'لبخند ساده',happy:'خوشحال',laughing:'خندان',shy:'خجالتی',curious:'کنجکاو',surprised:'متعجب',sleepy:'خواب‌آلود',sleeping:'خواب',affectionate:'مهربان',playful:'بازیگوش',sad:'ناراحت',listening:'در حال شنیدن'};
 function draw(canvas,emotion='neutral',blink=0,mouth=0){
  const c=canvas.getContext('2d'),unit=canvas.width/80;c.clearRect(0,0,canvas.width,canvas.height);
  c.fillStyle='#66f0f5';
  function rect(x,y,w,h,color){c.fillStyle=color||'#66f0f5';for(let i=0;i<w;i++)for(let j=0;j<h;j++)c.fillRect((x+i)*unit,(y+j)*unit,unit*.94,unit*.94)}
  function poly(points,color){const xs=points.map(p=>p[0]),ys=points.map(p=>p[1]);for(let y=Math.min(...ys);y<=Math.max(...ys);y++)for(let x=Math.min(...xs);x<=Math.max(...xs);x++){let inside=false;for(let i=0,j=points.length-1;i<points.length;j=i++){const a=points[i],b=points[j];if((a[1]>y+.5)!=(b[1]>y+.5)&&(x+.5<(b[0]-a[0])*(y+.5-a[1])/(b[1]-a[1])+a[0]))inside=!inside}if(inside)rect(x,y,1,1,color)}}
  function oval(x,y,h=14){rect(x+2,y,4,1);rect(x+1,y+1,6,1);rect(x,y+2,8,h-4);rect(x+1,y+h-2,6,1);rect(x+2,y+h-1,4,1)}
  function arch(x,y){poly([[x,y+7],[x,y+4],[x+2,y+4],[x+2,y+2],[x+4,y+2],[x+4,y],[x+8,y],[x+8,y+2],[x+10,y+2],[x+10,y+4],[x+12,y+4],[x+12,y+7],[x+10,y+7],[x+10,y+5],[x+8,y+5],[x+8,y+3],[x+4,y+3],[x+4,y+5],[x+2,y+5],[x+2,y+7]])}
  function chevron(x,y,flip=false){const pts=[[0,0],[3,0],[3,2],[6,2],[6,4],[9,4],[9,7],[6,7],[6,9],[3,9],[3,11],[0,11],[0,8],[3,8],[3,7],[5,7],[5,4],[3,4],[3,3],[0,3]];poly(pts.map(([a,b])=>[x+(flip?9-a:a),y+b]))}
  function heart(x,y){poly([[x,y+2],[x+2,y+2],[x+2,y],[x+5,y],[x+5,y+2],[x+7,y+2],[x+7,y],[x+10,y],[x+10,y+2],[x+12,y+2],[x+12,y+7],[x+10,y+7],[x+10,y+9],[x+8,y+9],[x+8,y+11],[x+6,y+11],[x+6,y+13],[x+4,y+11],[x+4,y+9],[x+2,y+9],[x+2,y+7],[x,y+7]])}
  const eyes=[23,51];
  for(let i=0;i<2;i++){
    const x=eyes[i];
    if(blink>0.8){rect(x-2,24,12,2);continue}
    if(blink>0.2){rect(x,22,8,5);continue}
    if(emotion==='happy'){arch(x-2,17);continue}
    if(emotion==='laughing'){chevron(x-1,16,i===1);continue}
    if(emotion==='affectionate'){heart(x-2,15);continue}
    if(emotion==='playful'&&i===1){chevron(x-1,17,true);continue}
    if(emotion==='sleeping'){rect(x-2,24,12,2);continue}
    if(emotion==='sleepy'){rect(x-2,22,12,2);rect(x,24,8,2);rect(x+1,26,6,1);continue}
    if(emotion==='sad'){poly(i===0?[[x-2,23],[x+8,17],[x+8,24],[x+5,24],[x+5,27],[x+1,27],[x+1,25],[x-2,25]]:[[x-1,17],[x+9,23],[x+9,25],[x+6,25],[x+6,27],[x+2,27],[x+2,24],[x-1,24]]);continue}
    if(emotion==='surprised'){rect(x-1,16,10,2);rect(x-3,18,2,8);rect(x+9,18,2,8);rect(x-1,26,10,2);continue}
    oval(x,emotion==='curious'&&i===0?12:16,emotion==='curious'&&i===0?18:14);
  }
  if(emotion==='shy'){rect(19,29,2,2,'#f5a1ca');rect(22,30,2,2,'#f5a1ca');rect(61,29,2,2,'#f5a1ca');rect(58,30,2,2,'#f5a1ca')}
  if(mouth===2||emotion==='laughing'){rect(36,29,9,4);rect(37,33,7,2);rect(38,35,5,1)}
  else if(mouth===1||emotion==='surprised'){rect(38,29,4,1);rect(37,30,2,5);rect(41,30,2,5);rect(38,35,4,1)}
  else if(emotion==='sad'){rect(37,32,6,2);rect(36,34,2,1);rect(42,34,2,1)}
  else if(emotion==='sleeping'||emotion==='listening'||emotion==='sleepy'){rect(39,32,3,1);if(emotion==='listening')for(let i=0;i<3;i++)rect(63+i*4,32,2,2)}
  else{rect(36,30,2,2);rect(43,30,2,2);rect(38,32,5,2)}
 }
 return {names,draw};
})();
