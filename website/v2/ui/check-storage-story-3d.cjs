const {JSDOM}=require('jsdom');
const esbuild=require('esbuild'),fs=require('fs'),path=require('path'),assert=require('assert/strict');
const root=path.resolve(__dirname,'..');
const html=fs.readFileSync(path.join(root,'night.html'),'utf8');
const bundle=esbuild.buildSync({entryPoints:[path.join(__dirname,'storage/controller.mjs')],bundle:true,format:'iife',globalName:'StorageController',write:false}).outputFiles[0].text;
const tick=()=>new Promise(resolve=>setTimeout(resolve,45));
async function setup({reduced=false,compact=false,hash='',fail=false,saveData=false}={}){
  const dom=new JSDOM(html,{url:'file://'+root+'/night.html'+hash,runScripts:'outside-only',pretendToBeVisual:true}),w=dom.window,d=w.document;
  const state={reduced,compact,top:76,scrolls:[],renders:[],created:0,disposed:0,observer:null,callbacks:{}};
  if(fail)w.console.warn=()=>{};
  w.matchMedia=q=>({get matches(){return q.includes('reduced')?state.reduced:state.compact;},addEventListener(t,fn){state.callbacks[q.includes('reduced')?'reduced':'compact']=fn;},removeEventListener(){}});
  Object.defineProperty(w.navigator,'connection',{value:{saveData}});
  w.IntersectionObserver=class{constructor(cb){state.observer=cb;}observe(){}disconnect(){}};
  w.scrollTo=o=>state.scrolls.push(o);w.HTMLElement.prototype.scrollIntoView=function(){};
  const track=d.querySelector('.scene-track'),stage=d.querySelector('.scene-stage');
  track.getBoundingClientRect=()=>({top:state.top});Object.defineProperty(track,'offsetHeight',{value:3200});Object.defineProperty(stage,'offsetHeight',{value:800});
  stage.getBoundingClientRect=()=>({top:76,left:0,width:1260,height:800});
  d.querySelector('.site-header').getBoundingClientRect=()=>({height:76});
  w.eval(bundle);
  const controller=w.StorageController.mountStorageStory(d.querySelector('.scene-story'),()=>{
    state.created++;if(fail)throw Error('Simulated unavailable WebGL');
    return{resize(){},render(p){state.renders.push(p);return true;},dispose(){state.disposed++;}};
  });
  await tick();return{dom,w,d,state,controller,close(){controller.destroy();w.close();}};
}
(async()=>{
  const {storyAt,holds,chapterStops}=await import('./storage/timeline.mjs');
  for(let i=0;i<4;i++){
    const [start,end]=holds[i];
    for(const p of [start,start+(end-start)*.25,(start+end)/2,end]){
      assert.equal(storyAt(p).pose,i/3,'scrolling within a hold leaves the composition fixed');
      assert.equal(storyAt(p).holding,true);
    }
    assert.equal(storyAt(chapterStops[i]).pose,i/3,'chapter links land within their hold');
  }
  let last=0;
  for(let i=0;i<=1000;i++){
    const p=storyAt(i/1000).pose;assert(p>=last,'forward scroll remains monotonic');last=p;
  }
  for(let i=1000;i>=0;i--){
    const p=storyAt(i/1000).pose;assert(p<=last,'reverse scroll retraces the story');last=p;
  }
  const {createStorageModel,layers,layerPose}=await import('./storage/model.mjs');
  const model=createStorageModel();assert.equal(layers.length,26);
  // Use the actual extruded geometry bounds, including bevels. Since all slabs
  // share the same parent rotation, local bounds prove separation in world space.
  const slabBounds=model.pieces.map(piece=>{
    const geometry=piece.children[0].geometry;geometry.computeBoundingBox();
    return geometry.boundingBox.clone();
  });
  for(let sample=0;sample<=6000;sample++){
    const progress=sample/6000,poses=layers.map(layer=>layerPose(layer,progress));
    for(let i=0;i<layers.length;i++)for(let j=i+1;j<layers.length;j++){
      const a=poses[i],b=poses[j];if(!a.visible||!b.visible)continue;
      const intersects=['x','y','z'].every(axis=>{
        const max=Math.min(a[axis]+slabBounds[i].max[axis]*a.scale,b[axis]+slabBounds[j].max[axis]*b.scale);
        const min=Math.max(a[axis]+slabBounds[i].min[axis]*a.scale,b[axis]+slabBounds[j].min[axis]*b.scale);
        return max-min>1e-6;
      });
      assert(!intersects,`${layers[i].kind}[${layers[i].index}] intersects ${layers[j].kind}[${layers[j].index}] at ${progress}`);
    }
  }
  const identity=model.pieces.map(p=>p.uuid);
  for(const p of [0,1/3,2/3,1,.45,0]){
    model.update(p);assert.deepEqual(model.pieces.map(p=>p.uuid),identity);
    model.pieces.forEach(piece=>assert([...piece.position,...piece.scale].every(Number.isFinite)));
    assert.equal(model.pieces.filter(p=>p.userData.layer.kind==='work'&&p.visible).length,3,'protected layers always remain');
  }
  model.update(1);assert.equal(model.pieces.filter(p=>p.visible).length,10,'only reviewed layers depart');
  for(let p=0;p<=1;p+=.02){
    const glass=layers.filter(l=>l.kind==='work').map(l=>layerPose(l,p).y);
    assert(glass[1]-glass[0]>.11&&glass[2]-glass[1]>.11,'glass layers do not intersect');
  }
  model.dispose();
  const a=await setup();assert.equal(a.state.created,0,'GPU initialization stays lazy');
  a.state.observer([{isIntersecting:true}]);await tick();assert.equal(a.state.created,1);assert(a.state.renders.length);
  a.state.top=76-2400*2/3;a.w.dispatchEvent(new a.w.Event('scroll'));await tick();
  assert.equal(a.d.querySelector('.scene-story').dataset.chapter,'2');
  for(const progress of [.29,.35,.41]){
    a.state.top=76-2400*progress;a.w.dispatchEvent(new a.w.Event('scroll'));await tick();
    assert.equal(a.controller.progress,1/3,'real scroll events preserve the review hold');
    assert.equal(a.d.querySelector('.scene-story').dataset.holding,'true');
  }
  a.controller.jump(2);
  assert.equal(a.controller.timeline,chapterStops[2],'navigation targets the hold centre');
  const slider=a.d.querySelector('.scene-scrubber');slider.value='1000';slider.dispatchEvent(new a.w.Event('input'));
  assert.equal(a.controller.progress,1);assert.equal(a.d.querySelector('.scene-story').dataset.chapter,'3');
  slider.value='0';slider.dispatchEvent(new a.w.Event('input'));assert.equal(a.controller.progress,0,'timeline reverses');
  assert.equal(a.state.scrolls.at(-1).behavior,'auto');
  a.state.observer([{isIntersecting:false}]);await tick();const count=a.state.renders.length;await tick();assert.equal(a.state.renders.length,count,'no offscreen render loop');
  for(const id of ['changes','understand','make-room','review','protection','outcome'])assert.equal(a.d.querySelectorAll('#'+id).length,1);
  a.close();assert.equal(a.state.disposed,1);
  const b=await setup({reduced:true,hash:'#protection'});b.state.observer([{isIntersecting:true}]);await tick();
  assert.equal(b.state.created,0);assert.equal(b.d.querySelector('.scene-story').dataset.chapter,'2');
  const btn=b.d.querySelector('[data-scene-step="2"]');btn.dispatchEvent(new b.w.KeyboardEvent('keydown',{key:'End',bubbles:true,cancelable:true}));
  assert.equal(b.d.activeElement.dataset.sceneStep,'3');assert.equal(b.controller.progress,1);assert.equal(b.state.created,0);b.close();
  const c=await setup({compact:true});c.state.observer([{isIntersecting:true}]);await tick();c.d.querySelector('[data-scene-step="1"]').click();
  assert.equal(c.controller.progress,1/3);assert.equal(c.state.scrolls.length,0,'mobile controls do not hijack document scroll');
  c.state.reduced=true;c.state.callbacks.reduced();assert.equal(c.state.disposed,1);assert(!c.d.querySelector('.scene-story').classList.contains('has-webgl'));c.close();
  const f=await setup({fail:true});f.state.observer([{isIntersecting:true}]);await tick();f.controller.jump(3,{immediate:true});
  assert(!f.d.querySelector('.scene-story').classList.contains('has-webgl'));assert.equal(f.d.querySelectorAll('.storage-wafer:not([hidden])').length,10);f.close();
  const s=await setup({saveData:true});s.state.observer([{isIntersecting:true}]);await tick();assert.equal(s.state.created,0);s.close();
  const d=new JSDOM(html).window.document;
  assert(!d.querySelector('.scene-story video'),'old Blender film is replaced');
  assert.equal(d.querySelectorAll('[data-scene-chapter]').length,4);
  assert.equal(d.querySelectorAll('.hero .product-screen').length,1,'original single hero screenshot restored');
  assert.equal(d.querySelectorAll('.screen-showcase .product-tour-screen').length,1,'one static preview before interactive enhancement');
  assert.equal(d.querySelectorAll('#product-tour-controls > article').length,3,'three progressive product steps');
  assert.equal(d.querySelector('#features').previousElementSibling.id,'inside-cairn','showcase immediately precedes remaining features');
  assert.equal(d.querySelector('.hero-atmosphere img')?.getAttribute('src'),'assets/stone-seam.png','original stone hero background restored');
  for(const selector of ['script[src]','link[rel="stylesheet"][href]'])for(const el of d.querySelectorAll(selector)){
    const url=el.getAttribute('src')||el.getAttribute('href');if(!url.startsWith('http'))assert(fs.existsSync(path.resolve(root,url.split('?')[0])),url);
  }
  assert.equal(fs.realpathSync(path.join(root,'night-refined.html')),path.join(root,'night.html'));
  console.log('PASS: 6001 full-timeline collision samples using actual slab geometry; four scroll holds; monotonic and reversible transitions; chapter stop navigation; persistent 26-layer geometry; retained core; lazy rendering; offscreen pause; keyboard/hash navigation; mobile; reduced motion; data saver; unavailable-WebGL fallback; page assets and hero preservation. GPU/browser visual validation is separate.');
})().catch(error=>{console.error(error);process.exit(1);});
