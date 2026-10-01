const {JSDOM}=require('jsdom');
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const root=path.resolve(__dirname,'..'),html=fs.readFileSync(path.join(root,'night.html'),'utf8'),source=fs.readFileSync(path.join(root,'flow-story.js'),'utf8');
const tick=()=>new Promise(r=>setTimeout(r,35));
async function setup({reduce=false,compact=false,saveData=false}={}){
 const dom=new JSDOM(html,{url:'file://'+root+'/night.html',runScripts:'outside-only',pretendToBeVisual:true});
 const w=dom.window,d=w.document,callbacks=[];
 const state={reduce,compact,saveData,observer:null,playCount:0,positions:[0,900,1800]};
 w.matchMedia=q=>({get matches(){return q.includes('reduced')?state.reduce:state.compact;},addEventListener(t,cb){callbacks.push(cb);}});
 Object.defineProperty(w.navigator,'connection',{value:{get saveData(){return state.saveData;}}});
 w.IntersectionObserver=class{constructor(cb){state.observer=cb;}observe(){}};
 d.querySelectorAll('.flow-chapter').forEach((el,i)=>el.getBoundingClientRect=()=>({top:state.positions[i],bottom:state.positions[i]+800}));
 const videos=[...d.querySelectorAll('video')];
 for(const video of videos){let paused=true;Object.defineProperty(video,'paused',{get:()=>paused});video.load=()=>{};video.pause=()=>{paused=true;};video.play=()=>{paused=false;state.playCount++;video.dispatchEvent(new w.Event('playing'));return Promise.resolve();};}
 w.eval(source);await tick();
 return {w,d,dom,state,videos,callbacks,show:async()=>{state.observer([{isIntersecting:true}]);await tick();},hide:async()=>{state.observer([{isIntersecting:false}]);await tick();}};
}
(async()=>{
 const a=await setup();assert(a.videos.every(v=>!v.hasAttribute('src')),'media lazy until section visible');
 await a.show();const desktop=a.videos[0];assert(desktop.getAttribute('src').includes('flow-story-motion'));assert(!desktop.paused);assert(desktop.classList.contains('is-playing'));
 assert(a.videos.slice(1).every(v=>!v.hasAttribute('src')),'desktop never loads mobile videos');
 const toggle=a.d.querySelector('.flow-motion-toggle');toggle.click();assert(desktop.paused);assert.equal(toggle.textContent,'Play animation');toggle.click();await tick();assert(!desktop.paused);
 await a.hide();assert(a.videos.every(v=>v.paused),'offscreen pauses all video');
 await a.show();a.state.reduce=true;a.callbacks.forEach(cb=>cb());await tick();assert(a.videos.every(v=>!v.hasAttribute('src')),'reduce motion unloads movies');assert(toggle.hidden);a.dom.window.close();
 const b=await setup({compact:true});await b.show();assert(!b.videos[0].hasAttribute('src'));assert(!b.videos[1].paused);assert(b.videos.slice(2).every(v=>v.paused));
 b.state.positions=[-900,0,900];b.w.dispatchEvent(new b.w.Event('scroll'));await tick();assert(b.videos[1].paused);assert(!b.videos[2].paused,'mobile only plays visible chapter');
 b.videos[2].dispatchEvent(new b.w.Event('error'));assert(!b.videos[2].classList.contains('is-playing'));assert(b.videos[2].paused);b.dom.window.close();
 const c=await setup({saveData:true});await c.show();assert.equal(c.state.playCount,0);assert(c.videos.every(v=>!v.hasAttribute('src')));c.dom.window.close();
 const e=await setup();e.videos[0].play=()=>Promise.reject(Error('autoplay denied'));await e.show();await tick();assert.equal(e.d.querySelector('.flow-motion-toggle').textContent,'Play animation');assert(!e.d.querySelector('.flow-motion-toggle').hidden);e.dom.window.close();
 console.log('PASS: Blender video lazy load, playback, pause/resume, offscreen pause, one mobile decoder, reduced motion, Save-Data, error and autoplay fallback.');
})().catch(e=>{console.error(e);process.exit(1);});
