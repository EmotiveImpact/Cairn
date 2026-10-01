(() => {
  const root = document.querySelector('.cairn-process');
  if (!root) return;
  const canvas = root.querySelector('canvas');
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  const stage = root.querySelector('.process-stage');
  const track = root.querySelector('.process-track');
  const buttons = [...root.querySelectorAll('[data-process-step]')];
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const compact = matchMedia('(max-width: 800px), (max-height: 700px)');
  const preview = root.querySelector('.process-preview');
  const inspect = root.querySelector('.process-inspect');
  const titles = ['Start with a clear picture.', 'Make a considered choice.', 'Keep what got you here.', 'Leave with a clear record.'];
  const descriptions = [
    'Build output, packages, local models, working files. Cairn compares readings and compatible scans so your next decision starts with what it can actually measure.',
    'Decide how much room you need. Then review exact paths, sizes and requirements. A cleanup candidate becomes a decision only when you approve it.',
    'The code is only part of the project. Known source-control, coding-session and credential locations stay protected. Uncertain rebuildability means review is required.',
    'See what changed, what can be recovered, and how much space is available now. A fresh reading checks the result; moving to Trash alone does not free that space.'
  ];
  const evidence = [
    ['MEASURED, NOT GUESSED', 'Read the disk.', 'Dated space readings', 'Compatible scan comparisons', 'Partial coverage made visible'],
    ['YOU MAKE THE CALL', 'Review the trade-off.', 'Your available-space target', 'Exact paths and requirements', 'Approval before a change'],
    ['THE WORK STAYS YOURS', 'Protect the context.', 'Known source-control history', 'Known coding conversations', 'Credentials and recovery data'],
    ['CHECK THE RESULT', 'Close the loop.', 'A local action record', 'Recovery for eligible Trash items', 'A fresh available-space reading']
  ];
  const captions = ['01 / Understand', '02 / Decide', '03 / Protect', '04 / Verify'];
  const screenKeys = ['changes', 'make-room', 'developer', 'activity'];
  const sources = ['Build output', 'Packages', 'Local tools', 'Working state'];
  const details = [
    'Foundation / Understand — use measured readings and visible scan coverage.',
    'Decision / Review — inspect the path and requirements before approving.',
    'Protection / Keep — known code, session and credential locations stay protected.',
    'Confidence / Verify — recorded actions, eligible recovery, fresh capacity.'
  ];
  const particles = Array.from({length: 620}, (_, i) => ({
    group: i % 4, rank: Math.floor(i / 4), seed: i,
    u: fract(Math.sin(i * 12.9898 + 4) * 43758.5453),
    v: fract(Math.sin(i * 78.233 + 8) * 15634.234),
    r: 1 + (i % 7 === 0 ? 1 : .1)
  }));
  let width = 1, height = 1, progress = 0, target = 0, selected = -1, frame = 0, visible = false, pointer = null;
  let last = 0, hoverGroup = -1;
  const clamp = v => Math.min(1, Math.max(0, v));
  function fract(v) { return v - Math.floor(v); }
  const mix = (a, b, t) => a + (b - a) * t;
  const ease = v => v * v * (3 - 2 * v);
  const manual = () => reduced.matches || compact.matches;
  // Stones represent successive decisions; particles illustrate information, not byte counts.
  const stones = [
    {y:.88,rx:.205,ry:.13}, {y:.61,rx:.162,ry:.112},
    {y:.365,rx:.117,ry:.10}, {y:.145,rx:.077,ry:.085}
  ];
  const centerX = () => width < 700 ? .65 : .51;
  function point(p, scene) {
    if (p.group > scene) {
      const lane=p.rank%4;
      return [.055+p.u*.245, .12+lane*.23+(p.v-.5)*.12];
    }
    const stone=stones[p.group];
    const angle=p.u*Math.PI*2, radius=Math.sqrt(p.v);
    return [centerX()+Math.cos(angle)*radius*stone.rx, stone.y+Math.sin(angle)*radius*stone.ry*.85];
  }
  function map(x,y) { return [width*(.04+x*.92),height*.385+y*height*.36]; }
  function text(label,x,y,alpha=1,color='#a8c0d1') {
    const q=map(x,y);ctx.save();ctx.globalAlpha=alpha;ctx.fillStyle=color;ctx.textAlign='left';
    ctx.font=`${width < 500 ? 9 : 11}px ui-monospace, monospace`;ctx.fillText(label,...q);ctx.restore();
  }
  function pebble(index, solidity) {
    const stone=stones[index], [x,y]=map(centerX(),stone.y);
    const rx=width*.92*stone.rx,ry=height*.36*stone.ry;
    ctx.save();ctx.beginPath();
    ctx.moveTo(x-rx,y+ry*.08);
    ctx.bezierCurveTo(x-rx*1.03,y-ry*.54,x-rx*.42,y-ry*1.08,x+rx*.05,y-ry*.94);
    ctx.bezierCurveTo(x+rx*.68,y-ry*.91,x+rx*1.07,y-ry*.21,x+rx,y+ry*.29);
    ctx.bezierCurveTo(x+rx*.88,y+ry*.95,x-rx*.8,y+ry*1.05,x-rx,y+ry*.08);
    ctx.closePath();
    const fill=ctx.createLinearGradient(x-rx,y-ry,x+rx*.5,y+ry);
    fill.addColorStop(0,`rgba(163,222,255,${solidity*.62})`);
    fill.addColorStop(.45,`rgba(45,142,232,${solidity*.52})`);
    fill.addColorStop(1,`rgba(10,72,139,${solidity*.6})`);
    ctx.fillStyle=fill;ctx.fill();
    ctx.strokeStyle=`rgba(145,213,255,${.06+solidity*.5})`;ctx.lineWidth=1;ctx.stroke();
    ctx.clip();
    ctx.beginPath();ctx.moveTo(x-rx,y+ry*.4);ctx.lineTo(x+rx,y-ry*.65);ctx.lineTo(x+rx,y-ry*1.3);ctx.lineTo(x-rx,y-ry*1.3);ctx.closePath();
    ctx.fillStyle=`rgba(202,238,255,${solidity*.085})`;ctx.fill();
    ctx.restore();
  }
  function diagram(scene, opacity) {
    if(opacity<.01)return;
    ctx.save();ctx.globalAlpha=opacity;
    // Open streams remain visible: the story does not depict automatic deletion.
    const labels=width<700?['Build','Packages','Models','Sessions']:['Build output','Package stores','Local models','Coding sessions'];
    for(let lane=0;lane<4;lane++) {
      const sy=.12+lane*.23;
      text(labels[lane],.015,sy-.09,opacity*.75);
      for(let line=0;line<5;line++) {
        const from=map(.025,sy+line*.014),to=map(centerX()-stones[scene].rx,stones[scene].y);
        ctx.beginPath();ctx.moveTo(...from);ctx.bezierCurveTo(width*.27,from[1],width*.28,to[1],...to);
        ctx.strokeStyle=`rgba(114,180,229,${.05+line*.014})`;ctx.lineWidth=.7;ctx.stroke();
      }
    }
    ctx.restore();
    // One stone for each step: understand, decide, protect, verify.
    for(let i=0;i<4;i++) {
      ctx.save();ctx.globalAlpha=opacity;
      pebble(i,i<=scene?(i===scene?1:.68):0);
      ctx.restore();
    }
    if(scene===2) {
      const [x,y]=map(centerX(),.55);
      ctx.save();ctx.strokeStyle=`rgba(128,199,255,${opacity*.22})`;ctx.setLineDash([3,7]);
      ctx.beginPath();ctx.ellipse(x,y,width*(width<700?.275:.25),height*.215,0,0,Math.PI*2);ctx.stroke();ctx.restore();
    }
    if(scene===3) {
      text('UNDERSTOOD  /  REVIEWED  /  PROTECTED  /  VERIFIED',width<700?.015:.265,1.13,opacity*.65,'#95ccef');
    }
  }
  function selectText(index) {
    if (index===selected) return; selected=index;
    root.querySelector('.process-eyebrow').textContent=captions[index];
    root.querySelector('.process-copy h3').textContent=titles[index];
    root.querySelector('.process-description').textContent=descriptions[index];
    const panel=root.querySelector('.process-evidence');
    if(panel){panel.querySelector('small').textContent=evidence[index][0];panel.querySelector('h4').textContent=evidence[index][1];panel.querySelectorAll('li').forEach((li,i)=>li.textContent=evidence[index][i+2]);}
    buttons.forEach((b,i)=>b.setAttribute('aria-pressed',String(i===index)));
    preview.dataset.preview=screenKeys[index];
    preview.href=`assets/app-${screenKeys[index]}-current.png`;
    preview.setAttribute('aria-label',`See ${['Changes','Make room','Developer Cleanup','Activity and Recovery'][index]} in Cairn`);
  }
  function render(time) {
    frame=0;
    const delta = Math.min(50,time-last || 16); last=time;
    progress = reduced.matches ? target : mix(progress,target,1-Math.exp(-delta/95));
    if (Math.abs(progress-target)<.001) progress=target;
    const a=Math.floor(progress), b=Math.min(3,a+1), t=ease(progress-a);
    selectText(Math.round(progress));
    root.querySelector('.process-progress span').style.width=`${25+progress*25}%`;
    ctx.clearRect(0,0,width,height);
    diagram(a,1-t); if (a!==b) diagram(b,t);
    let nearest=Infinity, group=-1;
    const drift = reduced.matches ? 0 : time*.0003;
    ctx.save();ctx.globalCompositeOperation='lighter';
    for (const p of particles) {
      const pa=point(p,a),pb=point(p,b);
      const q=map(mix(pa[0],pb[0],t),mix(pa[1],pb[1],t));
      const x=q[0]+Math.sin(drift+p.seed)*1.4, y=q[1]+Math.cos(drift+p.seed*.7)*1.4;
      let near=0;
      if(pointer){ const dist=Math.hypot(pointer.x-x,pointer.y-y);near=Math.max(0,1-dist/80);if(dist<nearest){nearest=dist;group=p.group;} }
      const rgb=p.group===2?'190,220,245':'100,191,255';
      ctx.fillStyle=`rgba(${rgb},${.24+near*.6})`;ctx.beginPath();ctx.arc(x,y,p.r+near*1.5,0,Math.PI*2);ctx.fill();
      if (p.seed%11===0 || near>.5) {ctx.fillStyle=`rgba(${rgb},${.045+near*.08})`;ctx.beginPath();ctx.arc(x,y,5+near*4,0,Math.PI*2);ctx.fill();}
    }
    ctx.restore();
    const current=nearest<90?group:-1;
    if(current!==hoverGroup){hoverGroup=current;inspect.textContent=current>=0?details[current]:'Data becomes a clearer decision. Each stone marks a step.';}
    if(visible && !document.hidden && !reduced.matches && (Math.abs(progress-target)>.001 || pointer)) frame=requestAnimationFrame(render);
  }
  function wake(){if(!frame && !document.hidden) frame=requestAnimationFrame(render);}
  function scroll(){
    if(manual())return;
    const rect=track.getBoundingClientRect();
    const top=parseFloat(getComputedStyle(stage).top)||0;
    const range=track.offsetHeight-stage.offsetHeight-60;
    target=clamp((top-rect.top)/Math.max(1,range))*3;wake();
  }
  function resize(){
    const r=stage.getBoundingClientRect();width=r.width;height=r.height;
    const ratio=Math.min(devicePixelRatio||1,2);canvas.width=Math.round(width*ratio);canvas.height=Math.round(height*ratio);ctx.setTransform(ratio,0,0,ratio,0,0);
    scroll();wake();
  }
  function go(index){
    target=index;
    if(!manual()){
      const top=parseFloat(getComputedStyle(stage).top)||0;
      window.scrollTo({top:window.scrollY+track.getBoundingClientRect().top-top+(track.offsetHeight-stage.offsetHeight-60)*index/3,behavior:'auto'});
    }
    wake();
  }
  buttons.forEach((button,i)=>{
    button.addEventListener('click',()=>go(i));
    button.addEventListener('keydown',event=>{
      let n;if(event.key==='ArrowRight')n=(i+1)%4;else if(event.key==='ArrowLeft')n=(i+3)%4;else if(event.key==='Home')n=0;else if(event.key==='End')n=3;else return;
      event.preventDefault();buttons[n].focus();go(n);
    });
  });
  stage.addEventListener('pointermove',event=>{if(event.pointerType==='touch'||reduced.matches)return;const r=stage.getBoundingClientRect();pointer={x:event.clientX-r.left,y:event.clientY-r.top};wake();},{passive:true});
  stage.addEventListener('pointerleave',()=>{pointer=null;wake();});
  const deepLinks={'#make-room':1,'#review':2,'#outcome':3};
  function hash(){const index=deepLinks[location.hash];if(index===undefined)return;if(manual())root.scrollIntoView({block:'start'});go(index);}
  window.addEventListener('hashchange',hash);
  window.addEventListener('scroll',scroll,{passive:true});
  reduced.addEventListener('change',resize);compact.addEventListener('change',resize);
  document.addEventListener('visibilitychange',()=>{if(document.hidden){cancelAnimationFrame(frame);frame=0;}else wake();});
  root.classList.add('is-ready');
  new ResizeObserver(resize).observe(stage);
  new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;if(visible)wake();else{cancelAnimationFrame(frame);frame=0;} }).observe(stage);
  resize();hash();
})();
