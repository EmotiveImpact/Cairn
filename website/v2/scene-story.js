(() => {
  'use strict';
  const root = document.querySelector('.scene-story');
  if (!root) return;
  const track = root.querySelector('.scene-track'), stage = root.querySelector('.scene-stage');
  const film = root.querySelector('video'), poster = root.querySelector('.scene-poster');
  const chapters = [...root.querySelectorAll('[data-scene-chapter]')];
  const buttons = [...root.querySelectorAll('[data-scene-step]')];
  const slider = root.querySelector('.scene-scrubber'), status = root.querySelector('.scene-status');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const compact = matchMedia('(max-width: 800px), (max-height: 720px)');
  const names = ['Understand','Review','Protect','Check'];
  const anchors = {'#changes':0,'#understand':0,'#make-room':1,'#review':1,'#protection':2,'#outcome':3};
  let progress=0,selected=-1,wanted=0,ready=false,failed=false,near=false,scrollFrame=0,tween=0;
  const clamp=n=>Math.min(1,Math.max(0,n));
  const manual=()=>reduced.matches||compact.matches;
  const header=()=>document.querySelector('.site-header')?.getBoundingClientRect().height||76;
  function select(index,announce=false){
    if(index!==selected){
      selected=index;
      chapters.forEach((el,i)=>{el.hidden=i!==index;});
      buttons.forEach((el,i)=>el.setAttribute('aria-pressed',String(i===index)));
      poster.src=chapters[index].dataset.poster;
      root.dataset.chapter=String(index);
    }
    slider.setAttribute('aria-valuetext',`${names[index]}, step ${index+1} of 4`);
    if(announce)status.textContent=`${names[index]}, step ${index+1} of 4`;
  }
  function seek(){
    if(!ready||failed||reduced.matches||document.hidden||film.seeking)return;
    if(Math.abs(film.currentTime-wanted)>1/48){try{film.currentTime=wanted;}catch{fail();}}
    else root.classList.add('has-frame');
  }
  function setProgress(value,announce=false){
    progress=clamp(value);select(Math.round(progress*3),announce);slider.value=String(Math.round(progress*1000));
    wanted=progress*Math.max(0,(Number(film.dataset.frames)||96)-1)/(Number(film.dataset.fps)||24);
    if(ready)wanted=Math.min(wanted,Math.max(0,film.duration-1/24));
    seek();
  }
  function load(){
    if(film.hasAttribute('src')||reduced.matches||navigator.connection?.saveData||failed)return;
    film.src=film.dataset.src;film.preload='auto';film.load();
  }
  function fail(){if(!film.hasAttribute('src'))return;failed=true;ready=false;root.classList.remove('has-frame');film.pause();}
  film.addEventListener('loadeddata',()=>{ready=true;setProgress(progress);});
  film.addEventListener('seeked',()=>{if(!ready||failed||reduced.matches)return;seek();});
  film.addEventListener('error',fail);
  function scrollUpdate(){
    scrollFrame=0;if(manual())return;
    setProgress((header()-track.getBoundingClientRect().top)/Math.max(1,track.offsetHeight-stage.offsetHeight));
  }
  function schedule(){if(!scrollFrame&&!document.hidden)scrollFrame=requestAnimationFrame(scrollUpdate);}
  function scrollToProgress(p,behavior){
    window.scrollTo({top:scrollY+track.getBoundingClientRect().top-header()+(track.offsetHeight-stage.offsetHeight)*p,behavior});
  }
  function jump(index,{announce=true,immediate=false}={}){
    cancelAnimationFrame(tween);load();const target=index/3;
    if(manual()){
      if(reduced.matches||immediate||!ready){setProgress(target,announce);return;}
      const from=progress,start=performance.now();
      const animate=time=>{const t=clamp((time-start)/700);setProgress(from+(target-from)*(t*t*(3-2*t)));if(t<1)tween=requestAnimationFrame(animate);else select(index,announce);};
      tween=requestAnimationFrame(animate);
    }else{
      scrollToProgress(target,immediate?'auto':'smooth');
      if(immediate)setProgress(target,announce);else select(index,announce);
    }
  }
  slider.addEventListener('input',()=>{
    cancelAnimationFrame(tween);load();const p=Number(slider.value)/1000;
    setProgress(p);if(!manual())scrollToProgress(p,'auto');
  });
  slider.addEventListener('change',()=>select(selected,true));
  buttons.forEach((button,index)=>{
    button.addEventListener('click',()=>jump(index));
    button.addEventListener('keydown',event=>{
      const key=event.key;let next;
      if(key==='ArrowRight')next=(index+1)%4;if(key==='ArrowLeft')next=(index+3)%4;if(key==='Home')next=0;if(key==='End')next=3;
      if(next===undefined)return;event.preventDefault();buttons[next].focus();jump(next);
    });
  });
  function followHash(){const index=anchors[location.hash];if(index===undefined)return;jump(index,{announce:false,immediate:true});if(manual())stage.scrollIntoView({block:'start',behavior:'auto'});}
  document.addEventListener('click',event=>{
    if(event.defaultPrevented||event.button!==0||event.metaKey||event.ctrlKey||event.shiftKey||event.altKey)return;
    const link=event.target.closest('a[href^="#"]');const href=link?.getAttribute('href');if(!(href in anchors))return;
    event.preventDefault();try{history.replaceState(null,'',href);}catch{location.hash=href;}
    jump(anchors[href]);if(manual())stage.scrollIntoView({block:'start',behavior:reduced.matches?'auto':'smooth'});
  });
  function preferenceChanged(){
    cancelAnimationFrame(tween);
    if(reduced.matches){film.pause();film.removeAttribute('src');film.load();ready=false;root.classList.remove('has-frame');}
    else if(near)load();
    if(!manual())schedule();
  }
  reduced.addEventListener('change',preferenceChanged);compact.addEventListener('change',preferenceChanged);
  window.addEventListener('hashchange',followHash);window.addEventListener('scroll',schedule,{passive:true});window.addEventListener('resize',schedule,{passive:true});
  document.addEventListener('visibilitychange',()=>{if(document.hidden){cancelAnimationFrame(scrollFrame);scrollFrame=0;cancelAnimationFrame(tween);film.pause();}else{schedule();seek();}});
  root.classList.add('is-ready');root.querySelector('.scene-controls').hidden=false;select(0);
  if('IntersectionObserver' in window)new IntersectionObserver(entries=>{near=entries.some(e=>e.isIntersecting);if(near){load();schedule();}},{rootMargin:'500px'}).observe(root);
  else{near=true;load();}
  schedule();followHash();
})();
