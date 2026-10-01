const {JSDOM}=require('jsdom');
const esbuild=require('esbuild');
const fs=require('fs');
const path=require('path');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const html=fs.readFileSync(path.join(root,'night.html'),'utf8');
const script=esbuild.buildSync({entryPoints:[path.join(__dirname,'storage/controller.mjs')],bundle:true,format:'iife',globalName:'Story',write:false}).outputFiles[0].text;
const tick=()=>new Promise(resolve=>setTimeout(resolve,40));

async function setup({compact=false,reduced=false,hash=''}={}){
 const dom=new JSDOM(html,{url:'file://'+root+'/night.html'+hash,runScripts:'outside-only',pretendToBeVisual:true});
 const w=dom.window,d=w.document,state={compact,reduced,top:76,scrolls:[]};
 w.matchMedia=query=>({get matches(){return query.includes('reduced')?state.reduced:state.compact;},addEventListener(){},removeEventListener(){}});
 w.scrollTo=options=>state.scrolls.push(options);
 w.HTMLElement.prototype.scrollIntoView=function(){};
 const track=d.querySelector('.scene-track'),stage=d.querySelector('.scene-stage');
 track.getBoundingClientRect=()=>({top:state.top});
 Object.defineProperty(track,'offsetHeight',{value:3200});
 Object.defineProperty(stage,'offsetHeight',{value:800});
 d.querySelector('.site-header').getBoundingClientRect=()=>({height:76});
 w.eval(script);
 const controller=w.Story.mountStorageStory(d.querySelector('.scene-story'));
 await tick();
 return {dom,w,d,state,controller,close(){controller.destroy();w.close();}};
}

(async()=>{
 const {storyAt,holds,chapterStops}=await import('./storage/timeline.mjs');
 for(let i=0;i<4;i++){
  const [start,end]=holds[i];
  for(const p of [start,(start+end)/2,end]){
   assert.equal(storyAt(p).pose,i/3,'each scroll hold keeps its state');
   assert.equal(storyAt(p).holding,true);
  }
  assert.equal(storyAt(chapterStops[i]).pose,i/3);
 }
 let last=0;
 for(let i=0;i<=1000;i++){const value=storyAt(i/1000).pose;assert(value>=last);last=value;}
 for(let i=1000;i>=0;i--){const value=storyAt(i/1000).pose;assert(value<=last);last=value;}

 const a=await setup();
 const rootNode=a.d.querySelector('.scene-story');
 assert.equal(a.d.querySelectorAll('.flow-source').length,1);
 assert.equal(a.d.querySelectorAll('.flow-node-review').length,1);
 assert.equal(a.d.querySelectorAll('.flow-node-protect').length,1);
 assert.equal(a.d.querySelectorAll('.flow-node-record').length,1);
 assert.match(a.d.querySelector('.flow-node-protect').textContent,/Source control.*sessions.*credentials/);
 assert.match(a.d.querySelector('.flow-node-review').textContent,/Exact paths.*size.*requirements/);
 for(const [p,index] of [[.04,0],[.35,1],[.65,2],[.96,3],[.65,2],[.35,1]]){
  a.state.top=76-2400*p;a.w.dispatchEvent(new a.w.Event('scroll'));await tick();
  assert.equal(rootNode.dataset.chapter,String(index),'scroll advances and reverses chapter');
  assert.equal(a.d.querySelectorAll('.scene-chapter:not([hidden])').length,1);
 }
 a.controller.jump(3);
 assert.equal(a.controller.timeline,chapterStops[3]);
 assert.equal(a.state.scrolls.at(-1).behavior,'smooth');
 const slider=a.d.querySelector('.scene-scrubber');
 slider.value='0';slider.dispatchEvent(new a.w.Event('input'));
 assert.equal(rootNode.dataset.chapter,'0','slider reverses to first state');
 assert.equal(a.state.scrolls.at(-1).behavior,'auto');
 for(const id of ['changes','understand','make-room','review','protection','outcome'])assert.equal(a.d.querySelectorAll('#'+id).length,1);
 a.close();

 const b=await setup({reduced:true,hash:'#protection'});
 assert.equal(b.d.querySelector('.scene-story').dataset.chapter,'2');
 const button=b.d.querySelector('[data-scene-step="2"]');
 button.dispatchEvent(new b.w.KeyboardEvent('keydown',{key:'End',bubbles:true,cancelable:true}));
 assert.equal(b.d.activeElement.dataset.sceneStep,'3');
 assert.equal(b.controller.progress,1);
 assert.equal(b.state.scrolls.length,0,'reduced motion keeps manual navigation');
 b.close();

 const c=await setup({compact:true});
 c.d.querySelector('[data-scene-step="1"]').click();
 assert.equal(c.controller.progress,1/3);
 assert.equal(c.state.scrolls.length,0,'compact screens use manual controls');
 c.close();

 const d=new JSDOM(html).window.document;
 assert.equal(d.querySelectorAll('.hero .product-screen').length,1);
 assert.equal(d.querySelector('#features').previousElementSibling.id,'inside-cairn');
 assert.equal(d.querySelector('.hero-atmosphere img').getAttribute('src'),'assets/stone-seam.png');
 for(const selector of ['script[src]','link[rel="stylesheet"][href]'])for(const element of d.querySelectorAll(selector)){
  const url=element.getAttribute('src')||element.getAttribute('href');
  if(!url.startsWith('http'))assert(fs.existsSync(path.resolve(root,url.split('?')[0])),url);
 }
 console.log('PASS: four stable scroll holds, forward/reverse story, semantic review/protect/record branches, slider/buttons/keyboard/hash navigation, compact and reduced-motion controls, hero and asset integrity. Layout remains unverified in a browser.');
})().catch(error=>{console.error(error);process.exitCode=1;});
