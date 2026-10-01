import {storyAt,chapterStops} from './timeline.mjs';

const clamp=value=>Math.max(0,Math.min(1,value));

export function mountStorageStory(root){
  if(!root)return;
  const track=root.querySelector('.scene-track');
  const stage=root.querySelector('.scene-stage');
  const chapters=[...root.querySelectorAll('[data-scene-chapter]')];
  const buttons=[...root.querySelectorAll('[data-scene-step]')];
  const slider=root.querySelector('.scene-scrubber');
  const status=root.querySelector('.scene-status');
  const reduced=matchMedia('(prefers-reduced-motion: reduce)');
  const compact=matchMedia('(max-width: 800px), (max-height: 720px)');
  const names=['Understand','Review','Protect','Make room'];
  const anchors={'#changes':0,'#understand':0,'#make-room':1,'#review':1,'#protection':2,'#outcome':3};
  const cleanup=[];
  let progress=0,chapter=-1,frame=0,disposed=false;
  const on=(element,type,handler,options)=>{element.addEventListener(type,handler,options);cleanup.push(()=>element.removeEventListener(type,handler,options));};
  const manual=()=>reduced.matches||compact.matches;
  const header=()=>document.querySelector('.site-header')?.getBoundingClientRect().height||76;
  function selectChapter(index,announce=false){
    if(chapter!==index){
      chapter=index;
      root.dataset.chapter=String(index);
      chapters.forEach((node,i)=>{node.hidden=i!==index;});
      buttons.forEach((node,i)=>node.setAttribute('aria-pressed',String(i===index)));
    }
    slider.setAttribute('aria-valuetext',`${names[index]}, step ${index+1} of 4`);
    if(announce)status.textContent=`${names[index]}, step ${index+1} of 4`;
  }
  function setProgress(value,announce=false){
    progress=clamp(value);
    const state=storyAt(progress);
    root.style.setProperty('--story-progress',String(progress));
    root.style.setProperty('--flow-pose',String(state.pose));
    root.dataset.holding=String(state.holding);
    selectChapter(state.chapter,announce);
    slider.value=String(Math.round(progress*1000));
  }
  function readScroll(){
    frame=0;
    if(manual()||disposed)return;
    const travel=Math.max(1,track.offsetHeight-stage.offsetHeight);
    setProgress((header()-track.getBoundingClientRect().top)/travel);
  }
  function scheduleScroll(){if(!frame&&!document.hidden)frame=requestAnimationFrame(readScroll);}
  function scrollToProgress(value,behavior='smooth'){
    const travel=Math.max(0,track.offsetHeight-stage.offsetHeight);
    window.scrollTo({top:scrollY+track.getBoundingClientRect().top-header()+travel*value,behavior});
  }
  function jump(index,{immediate=false,announce=true}={}){
    setProgress(chapterStops[index],announce);
    if(!manual())scrollToProgress(chapterStops[index],immediate?'auto':'smooth');
  }
  on(slider,'input',()=>{const value=Number(slider.value)/1000;setProgress(value);if(!manual())scrollToProgress(value,'auto');});
  on(slider,'change',()=>selectChapter(chapter,true));
  buttons.forEach((button,index)=>{
    on(button,'click',()=>jump(index));
    on(button,'keydown',event=>{
      const next=event.key==='ArrowRight'?(index+1)%4:event.key==='ArrowLeft'?(index+3)%4:event.key==='Home'?0:event.key==='End'?3:null;
      if(next===null)return;
      event.preventDefault();buttons[next].focus();jump(next);
    });
  });
  function followHash(){
    const index=anchors[location.hash];
    if(index===undefined)return;
    jump(index,{immediate:true,announce:false});
    if(manual())stage.scrollIntoView({block:'start',behavior:'auto'});
  }
  on(document,'click',event=>{
    if(event.defaultPrevented||event.button!==0||event.metaKey||event.ctrlKey||event.shiftKey||event.altKey)return;
    const link=event.target.closest?.('a[href^="#"]'),href=link?.getAttribute('href');
    if(!(href in anchors))return;
    event.preventDefault();
    try{history.replaceState(null,'',href);}catch{location.hash=href;}
    jump(anchors[href]);
    if(manual())stage.scrollIntoView({block:'start',behavior:reduced.matches?'auto':'smooth'});
  });
  on(window,'scroll',scheduleScroll,{passive:true});
  on(window,'resize',scheduleScroll,{passive:true});
  on(window,'hashchange',followHash);
  on(reduced,'change',scheduleScroll);
  on(compact,'change',scheduleScroll);
  on(document,'visibilitychange',()=>{if(document.hidden){cancelAnimationFrame(frame);frame=0;}else scheduleScroll();});
  root.classList.add('is-ready');
  root.querySelector('.scene-controls').hidden=false;
  setProgress(0);
  scheduleScroll();
  followHash();
  return {setProgress,jump,get progress(){return storyAt(progress).pose;},get timeline(){return progress;},destroy(){disposed=true;cancelAnimationFrame(frame);cleanup.forEach(fn=>fn());}};
}
