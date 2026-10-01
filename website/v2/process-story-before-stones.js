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
  const titles = ['See what grew.', 'Choose with context.', 'Keep your working state.', 'Know what happened.'];
  const descriptions = [
    'Compare space readings and compatible scans. Bring build output, packages and local tools into view, with scan coverage clearly shown.',
    'Set the space target for your next build. Inspect each path, size and requirement before approving a change. These are candidates, not automatic deletions.',
    'Your repository is only part of your work. Known source-control, coding-session and credential locations stay protected, even inside a larger candidate.',
    'Check the action record and recover eligible Trash items. Read available space again: moving an item to Trash does not immediately free that space.'
  ];
  const captions = ['01 / Understand', '02 / Decide', '03 / Protect', '04 / Verify'];
  const screenKeys = ['changes', 'make-room', 'developer', 'activity'];
  const sources = ['Build output', 'Packages', 'Local tools', 'Working state'];
  const details = [
    'Build output · Check requirements and close the owning app when needed.',
    'Packages · Check rebuildability before approving a change.',
    'Local tools · Model downloads and tool data need individual review.',
    'Working state · Known code, session and credential locations stay protected.'
  ];
  const particles = Array.from({length: 420}, (_, i) => ({
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
  function point(p, scene) {
    const angle = p.u * Math.PI * 2;
    const radius = Math.sqrt(p.v);
    if (scene === 0) {
      const x = .09 + p.u * .77;
      const converge = ease(p.u);
      return [x, mix(.12 + p.group * .255 + (p.v - .5) * .16, .5, converge)];
    }
    if (scene === 1) return [.15 + p.group * .235 + Math.cos(angle) * radius * .085, .51 + Math.sin(angle) * radius * .23];
    if (scene === 2) {
      if (p.group === 3) return [.76 + Math.cos(angle) * radius * .1, .5 + Math.sin(angle) * radius * .3];
      return [.16 + p.group * .12 + (p.u - .5) * .09, .22 + p.v * .56];
    }
    const column = p.group === 3 ? 2 : p.rank % 3;
    return [.18 + column * .32 + (p.u - .5) * .14, .32 + p.v * .34];
  }
  function map(x,y) { return [width * (.04 + x * .92), height * .43 + y * height * .32]; }
  function path(points, alpha, color = '121,177,216') {
    ctx.strokeStyle = `rgba(${color},${alpha})`; ctx.lineWidth = 1; ctx.beginPath();
    points.forEach((p, i) => { const q = map(...p); if (i) ctx.lineTo(...q); else ctx.moveTo(...q); }); ctx.stroke();
  }
  function text(label, x,y, alpha=1, color='#a8c0d1') {
    const q=map(x,y); ctx.globalAlpha=alpha;ctx.fillStyle=color;ctx.textAlign='center';ctx.font=`${width < 500 ? 10 : 12}px Inter, system-ui, sans-serif`;ctx.fillText(label,...q);ctx.globalAlpha=1;
  }
  function diagram(scene, opacity) {
    if (opacity < .01) return;
    ctx.save();ctx.globalAlpha=opacity;
    if (scene === 0) {
      for (let g=0;g<4;g++) {
        for (let j=0;j<10;j++) {
          const a=map(.07,.12+g*.255+(j-5)*.016), b=map(.9,.5);
          ctx.beginPath();ctx.moveTo(...a);ctx.bezierCurveTo(width*.43,a[1],width*.56,b[1],...b);
          ctx.strokeStyle='rgba(144,198,237,.14)';ctx.stroke();
        }
        text(width < 500 ? ['Build','Packages','Tools','Work'][g] : sources[g], .12, -.03+g*.255, opacity);
      }
      const end=map(.9,.5);ctx.fillStyle='#d5ebff';ctx.beginPath();ctx.arc(...end,5,0,Math.PI*2);ctx.fill();
      text('Your Mac',.9,.65,opacity);
    }
    if (scene === 1) {
      sources.forEach((label,g) => { path([[.06+g*.235,.9],[.23+g*.235,.9]],opacity*.35);text(width<500 ? ['Build','Packages','Tools','Protected'][g]:label,.15+g*.235,.08,opacity); });
      text('Inspect paths · sizes · requirements',.5,1.08,opacity,'#7ea4be');
    }
    if (scene === 2) {
      path([[.55,.05],[.55,.95]],opacity*.3);
      const center=map(.76,.5);
      ctx.strokeStyle=`rgba(169,215,250,${opacity*.6})`;ctx.beginPath();ctx.ellipse(...center,width*.13,height*.135,0,0,Math.PI*2);ctx.stroke();
      ctx.strokeStyle=`rgba(169,215,250,${opacity*.13})`;ctx.beginPath();ctx.ellipse(...center,width*.145,height*.151,0,0,Math.PI*2);ctx.stroke();
      text('Review required',.28,-.05,opacity);text('Protected',.76,-.05,opacity,'#d0eaff');
      text(width<500 ? 'Code · sessions · access' : '.git · coding sessions · credentials',.76,1.05,opacity);
    }
    if (scene === 3) {
      path([[.18,.5],[.82,.5]],opacity*.25);
      ['Action record','Recovery','Fresh reading'].forEach((label,i) => {
        const x=.18+i*.32;path([[x-.085,.23],[x+.085,.23]],opacity*.65);
        text(label,x,.07,opacity);text(['What changed','Eligible items','Available space'][i],x,.93,opacity,'#7c9db5');
      });
    }
    ctx.restore();
  }
  function selectText(index) {
    if (index===selected) return; selected=index;
    root.querySelector('.process-eyebrow').textContent=captions[index];
    root.querySelector('.process-copy h3').textContent=titles[index];
    root.querySelector('.process-description').textContent=descriptions[index];
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
      const rgb=p.group===3?'188,207,233':'96,184,255';
      ctx.fillStyle=`rgba(${rgb},${.35+near*.6})`;ctx.beginPath();ctx.arc(x,y,p.r+near*1.5,0,Math.PI*2);ctx.fill();
      if (p.seed%11===0 || near>.5) {ctx.fillStyle=`rgba(${rgb},${.045+near*.08})`;ctx.beginPath();ctx.arc(x,y,5+near*4,0,Math.PI*2);ctx.fill();}
    }
    ctx.restore();
    const current=nearest<90?group:-1;
    if(current!==hoverGroup){hoverGroup=current;inspect.textContent=current>=0?details[current]:'Illustrative files · '+(manual()?'Choose a stage to explore':'Scroll to follow the process · Hover to inspect');}
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
