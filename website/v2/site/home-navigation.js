(() => {
 const menu=document.querySelector('#site-explore');
 if(!menu) return;
 const summary=menu.querySelector('summary');
 const close=(focus=false)=>{menu.open=false;if(focus)summary.focus();};
 menu.addEventListener('click',event=>{if(event.target.closest('a'))close();});
 document.addEventListener('click',event=>{if(menu.open&&!menu.contains(event.target))close();});
 document.addEventListener('focusin',event=>{if(menu.open&&!menu.contains(event.target))close();});
 document.addEventListener('keydown',event=>{
  if(!menu.open)return;
  if(event.key==='Escape'){event.preventDefault();event.stopPropagation();close(true);}
  else if(menu.contains(event.target)&&['ArrowDown','ArrowUp','PageDown','PageUp',' '].includes(event.key))event.stopPropagation();
 });
 // Keep scrolling in the open navigation panel independent of the homepage's scroll story.
 for(const event of ['wheel','touchstart','touchmove','touchend'])menu.addEventListener(event,e=>e.stopPropagation(),{passive:true});
 for(const event of ['pageshow','pagehide','popstate'])window.addEventListener(event,()=>close());
})();
