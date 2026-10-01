const{JSDOM}=require('jsdom');const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const root=path.resolve(__dirname,'..');let html=fs.readFileSync(path.join(root,'night.html'),'utf8');
if(!html.includes('class="scene-story"')){const start=html.indexOf('<section class="flow-story"'),end=html.indexOf('<section class="features section"',start);html=html.slice(0,start)+fs.readFileSync(path.join(root,'cinematic-concepts/scene-story-fragment.html'),'utf8')+html.slice(end);}
const script=fs.readFileSync(path.join(root,'scene-story.js'),'utf8'),tick=()=>new Promise(r=>setTimeout(r,35));
async function setup({reduced=false,compact=false,hash=''}={}){
 const dom=new JSDOM(html,{url:'file://'+root+'/night.html'+hash,runScripts:'outside-only',pretendToBeVisual:true}),w=dom.window,d=w.document;
 const state={reduced,compact,top:76,scrolls:[],seeks:[],loads:0,observer:null},callbacks=[];
 w.matchMedia=q=>({get matches(){return q.includes('reduced')?state.reduced:state.compact;},addEventListener(t,cb){callbacks.push(cb);}});
 w.IntersectionObserver=class{constructor(cb){state.observer=cb;}observe(){}};
 w.scrollTo=o=>state.scrolls.push(o);w.HTMLElement.prototype.scrollIntoView=function(){};
 const track=d.querySelector('.scene-track'),stage=d.querySelector('.scene-stage'),film=d.querySelector('.scene-film');
 track.getBoundingClientRect=()=>({top:state.top});Object.defineProperty(track,'offsetHeight',{value:3200});Object.defineProperty(stage,'offsetHeight',{value:800});
 d.querySelector('.site-header').getBoundingClientRect=()=>({height:76});
 let time=0,seeking=false;Object.defineProperty(film,'duration',{value:4});Object.defineProperty(film,'seeking',{get:()=>seeking});
 Object.defineProperty(film,'currentTime',{get:()=>time,set:v=>{time=v;seeking=true;state.seeks.push(v);w.setTimeout(()=>{seeking=false;film.dispatchEvent(new w.Event('seeked'));},0);}});
 film.load=()=>state.loads++;film.pause=()=>{};film.play=()=>{throw Error('Story must never autoplay');};
 w.eval(script);await tick();return{dom,w,d,film,state,callbacks};
}
(async()=>{
 const a=await setup();assert(!a.film.hasAttribute('src'));a.state.observer([{isIntersecting:true}]);assert(a.film.hasAttribute('src'));
 a.film.dispatchEvent(new a.w.Event('loadeddata'));await tick();a.state.top=76-2400*2/3;a.w.dispatchEvent(new a.w.Event('scroll'));await tick();await tick();
 assert.equal(a.d.querySelector('.scene-story').dataset.chapter,'2');assert(Math.abs(a.film.currentTime-95/36)<.01);
 const slider=a.d.querySelector('input[type=range]');slider.value='1000';slider.dispatchEvent(new a.w.Event('input'));await tick();
 assert.equal(a.d.querySelector('.scene-story').dataset.chapter,'3');assert(Math.abs(a.film.currentTime-95/24)<.01);assert.equal(a.state.scrolls.at(-1).behavior,'auto');
 slider.value='0';slider.dispatchEvent(new a.w.Event('input'));await tick();assert.equal(a.film.currentTime,0,'slider reverses animation');
 a.film.dispatchEvent(new a.w.Event('error'));assert(!a.d.querySelector('.scene-story').classList.contains('has-frame'));
 for(const id of ['changes','understand','make-room','review','protection','outcome'])assert.equal(a.d.querySelectorAll('#'+id).length,1);
 a.dom.window.close();
 const b=await setup({reduced:true,hash:'#protection'});assert.equal(b.d.querySelector('.scene-story').dataset.chapter,'2');assert(!b.film.hasAttribute('src'));
 const btn=b.d.querySelector('[data-scene-step="2"]');btn.dispatchEvent(new b.w.KeyboardEvent('keydown',{key:'End',bubbles:true,cancelable:true}));assert.equal(b.d.activeElement.dataset.sceneStep,'3');assert.equal(b.state.seeks.length,0);b.dom.window.close();
 const c=await setup({compact:true});const s=c.d.querySelector('input');s.value='333';s.dispatchEvent(new c.w.Event('input'));assert.equal(c.d.querySelector('.scene-story').dataset.chapter,'1');assert.equal(c.state.scrolls.length,0);c.dom.window.close();
 console.log('PASS: scroll-linked scene, bidirectional slider, no autoplay, bounded seeks, legacy anchors, keyboard chapters, reduced motion, mobile/manual mode and media fallback.');
})().catch(e=>{console.error(e);process.exit(1);});
