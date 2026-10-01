import { clamp, layers, layerPose, coreSpread } from './model.mjs';
import { storyAt, chapterStops } from './timeline.mjs';

export function mountStorageStory(root, createView) {
  if(!root)return;
  const track=root.querySelector('.scene-track'),stage=root.querySelector('.scene-stage'),host=root.querySelector('.storage-view');
  const chapters=[...root.querySelectorAll('[data-scene-chapter]')],buttons=[...root.querySelectorAll('[data-scene-step]')];
  const slider=root.querySelector('.scene-scrubber'),status=root.querySelector('.scene-status');
  const reduced=matchMedia('(prefers-reduced-motion: reduce)'),compact=matchMedia('(max-width: 800px), (max-height: 720px)');
  const names=['Understand','Review','Protect','Make room'];
  const anchors={'#changes':0,'#understand':0,'#make-room':1,'#review':1,'#protection':2,'#outcome':3};
  const fallback=root.querySelector('.storage-fallback-stack');
  const fallbackLayers=layers.map(layer=>{
    const node=document.createElement('i');node.className=`storage-wafer storage-wafer--${layer.kind}`;fallback.append(node);return node;
  });
  let target=0,drawn=0,selected=-1,near=false,frame=0,scrollFrame=0,view=null,failed=false,disposed=false;
  let pointer={x:0,y:0},pointerTarget={x:0,y:0},timeline=0,lastRender=0,effectTime=0;
  const cleanup=[];
  const on=(el,name,fn,opts)=>{el.addEventListener(name,fn,opts);cleanup.push(()=>el.removeEventListener(name,fn,opts));};
  const manual=()=>reduced.matches||compact.matches;
  const header=()=>document.querySelector('.site-header')?.getBoundingClientRect().height||76;
  function setChapter(index,announce){
    if(index!==selected){
      selected=index;root.dataset.chapter=String(index);
      chapters.forEach((el,i)=>{el.hidden=i!==index;});
      buttons.forEach((el,i)=>{el.setAttribute('aria-pressed',String(i===index));});
    }
    slider.setAttribute('aria-valuetext',`${names[index]}, step ${index+1} of 4`);
    if(announce)status.textContent=`${names[index]}, step ${index+1} of 4`;
  }
  function fallbackPose(p){
    fallbackLayers.forEach((node,i)=>{
      const pose=layerPose(layers[i],p);
      node.style.setProperty('--x',`${pose.x*58}px`);node.style.setProperty('--y',`${-pose.y*58}px`);node.style.setProperty('--z',`${pose.z*58}px`);
      node.style.setProperty('--scale',String(pose.scale));node.hidden=!pose.visible;
    });
    fallback.style.setProperty('--open',String(coreSpread(p)));
  }
  function fail(){failed=true;root.classList.remove('has-webgl');fallbackPose(target);}
  function ensureView(){
    if(view||failed||!near||reduced.matches||navigator.connection?.saveData)return;
    try{view=createView(host,fail);}catch(error){fail();console.warn('Cairn: using the static storage illustration.',error);}
  }
  function tick(now){
    frame=0;if(disposed||document.hidden||!near)return;
    ensureView();
    const ambient=Boolean(view&&!failed&&!reduced.matches&&!navigator.connection?.saveData);
    if(ambient&&lastRender&&now-lastRender<32){wake();return;}
    if(lastRender)effectTime+=Math.min((now-lastRender)/1000,.05);
    lastRender=now;
    const ease=reduced.matches?1:.13;
    drawn+=(target-drawn)*ease;
    pointer.x+=(pointerTarget.x-pointer.x)*.09;pointer.y+=(pointerTarget.y-pointer.y)*.09;
    if(Math.abs(target-drawn)<.0001)drawn=target;
    if(view&&!failed&&!reduced.matches){
      try{if(view.render(drawn,pointer,effectTime))root.classList.add('has-webgl');}catch(error){fail();console.warn('Cairn: storage scene fallback.',error);}
    }
    if(!view||failed||reduced.matches)fallbackPose(drawn);
    if(ambient||Math.abs(target-drawn)>.0001||Math.abs(pointerTarget.x-pointer.x)>.001||Math.abs(pointerTarget.y-pointer.y)>.001)wake();
  }
  function wake(){if(!frame&&!disposed&&near&&!document.hidden)frame=requestAnimationFrame(tick);}
  function setProgress(p,announce=false,snap=false){
    timeline=clamp(p);const state=storyAt(timeline);target=state.pose;if(snap||reduced.matches)drawn=target;
    root.style.setProperty('--story-progress',String(timeline));root.dataset.holding=String(state.holding);
    setChapter(state.chapter,announce);slider.value=String(Math.round(timeline*1000));
    if(!view||failed||reduced.matches)fallbackPose(target);wake();
  }
  function readScroll(){scrollFrame=0;if(manual())return;setProgress((header()-track.getBoundingClientRect().top)/Math.max(1,track.offsetHeight-stage.offsetHeight));}
  function scheduleScroll(){if(!scrollFrame&&!document.hidden)scrollFrame=requestAnimationFrame(readScroll);}
  function scrollToProgress(p,behavior){window.scrollTo({top:scrollY+track.getBoundingClientRect().top-header()+Math.max(0,track.offsetHeight-stage.offsetHeight)*p,behavior});}
  function jump(index,{immediate=false,announce=true}={}){
    setProgress(chapterStops[index],announce,immediate);
    if(!manual())scrollToProgress(chapterStops[index],immediate?'auto':'smooth');
  }
  on(slider,'input',()=>{const p=Number(slider.value)/1000;setProgress(p);if(!manual())scrollToProgress(p,'auto');});
  on(slider,'change',()=>setChapter(selected,true));
  buttons.forEach((button,i)=>{
    on(button,'click',()=>jump(i));
    on(button,'keydown',event=>{
      const next=event.key==='ArrowRight'?(i+1)%4:event.key==='ArrowLeft'?(i+3)%4:event.key==='Home'?0:event.key==='End'?3:null;
      if(next===null)return;event.preventDefault();buttons[next].focus();jump(next);
    });
  });
  function followHash(){
    const i=anchors[location.hash];if(i===undefined)return;
    jump(i,{immediate:true,announce:false});
    if(manual())stage.scrollIntoView({block:'start',behavior:'auto'});
  }
  on(document,'click',event=>{
    if(event.defaultPrevented||event.button!==0||event.metaKey||event.ctrlKey||event.shiftKey||event.altKey)return;
    const link=event.target.closest?.('a[href^="#"]'),href=link?.getAttribute('href');
    if(!(href in anchors))return;
    event.preventDefault();try{history.replaceState(null,'',href);}catch{location.hash=href;}
    jump(anchors[href]);if(manual())stage.scrollIntoView({block:'start',behavior:reduced.matches?'auto':'smooth'});
  });
  on(stage,'pointermove',event=>{
    if(reduced.matches||event.pointerType==='touch')return;
    const r=stage.getBoundingClientRect();pointerTarget={x:(event.clientX-r.left)/r.width*2-1,y:(event.clientY-r.top)/r.height*2-1};wake();
  },{passive:true});
  on(stage,'pointerleave',()=>{pointerTarget={x:0,y:0};wake();});
  function resize(){view?.resize();if(!manual())scheduleScroll();wake();}
  function preferenceChanged(){
    if(reduced.matches){view?.dispose();view=null;root.classList.remove('has-webgl');drawn=target;pointer=pointerTarget={x:0,y:0};fallbackPose(target);}
    else ensureView();resize();
  }
  on(reduced,'change',preferenceChanged);on(compact,'change',resize);
  on(window,'scroll',scheduleScroll,{passive:true});on(window,'resize',resize,{passive:true});on(window,'hashchange',followHash);
  on(document,'visibilitychange',()=>{
    if(document.hidden){cancelAnimationFrame(frame);frame=0;cancelAnimationFrame(scrollFrame);scrollFrame=0;lastRender=0;}
    else{scheduleScroll();wake();}
  });
  on(host,'storage-context-restored',()=>{failed=false;wake();});
  let observer;
  if('IntersectionObserver' in window){observer=new IntersectionObserver(entries=>{near=entries.some(e=>e.isIntersecting);if(near){wake();scheduleScroll();}else{cancelAnimationFrame(frame);frame=0;lastRender=0;}},{rootMargin:'0px'});observer.observe(stage);}
  else{near=true;}
  let sizeObserver;
  if('ResizeObserver' in window){sizeObserver=new ResizeObserver(resize);sizeObserver.observe(host);}
  root.classList.add('is-ready');root.querySelector('.scene-controls').hidden=false;
  setProgress(0,false,true);scheduleScroll();followHash();
  return {setProgress,jump,get progress(){return target;},get timeline(){return timeline;},destroy(){disposed=true;cancelAnimationFrame(frame);cancelAnimationFrame(scrollFrame);observer?.disconnect();sizeObserver?.disconnect();cleanup.forEach(fn=>fn());view?.dispose();}};
}
