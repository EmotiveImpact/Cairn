const {JSDOM}=require('jsdom');
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const root=path.resolve(__dirname,'..');
const page=fs.readFileSync(path.join(root,'night.html'),'utf8');
const dom=new JSDOM(page,{url:'file://'+root+'/night.html',runScripts:'outside-only',pretendToBeVisual:true});
const w=dom.window,d=w.document;
let reduce=false,observer,callbacks=[],scrolls=[];
w.matchMedia=q=>({get matches(){return q.includes('reduced')?reduce:false;},addEventListener(type,cb){callbacks.push(cb);}});
w.IntersectionObserver=class{constructor(cb){observer=cb;}observe(){}};
w.HTMLMediaElement.prototype.load=function(){};
w.HTMLMediaElement.prototype.pause=function(){};
w.HTMLMediaElement.prototype.play=function(){return Promise.resolve();};
w.HTMLElement.prototype.scrollIntoView=function(options){scrolls.push({id:this.id,...options});};
const tick=()=>new Promise(r=>setTimeout(r,40));
(async()=>{
 for(const id of ['changes','understand','protection','outcome','make-room','review'])assert.equal(d.querySelectorAll('#'+id).length,1,'unique anchor '+id);
 assert.equal(d.querySelectorAll('.flow-chapter').length,3);
 assert(!d.querySelector('.cinema-film'),'old movie must not load');
 assert(!d.querySelector('.protection-layout'),'no duplicate protection section');
 assert.equal(d.querySelectorAll('.flow-copy h2').length,3,'all chapters readable before JS');
 for(const a of d.querySelectorAll('.flow-story a')){
  const href=a.getAttribute('href');
  if(href.startsWith('#'))assert(d.querySelector(href),'anchor exists '+href);
  else assert(fs.existsSync(path.join(root,href)),'preview asset exists '+href);
 }
 assert(fs.existsSync(path.join(root,'assets/flow-story-background.webp')));
 w.eval(fs.readFileSync(path.join(root,'flow-story.js'),'utf8'));
 observer([{isIntersecting:true}]);await tick();
 const link=d.querySelector('.flow-steps a[href="#protection"]');link.click();
 assert.equal(scrolls.at(-1).id,'protection');assert.equal(scrolls.at(-1).behavior,'smooth');
 assert.equal(d.activeElement.id,'protection');assert.equal(w.location.hash,'#protection');
 reduce=true;callbacks.forEach(cb=>cb());await tick();
 d.querySelector('.flow-steps a[href="#outcome"]').click();assert.equal(scrolls.at(-1).behavior,'auto');
 assert.equal(d.querySelector('.flow-story').style.getPropertyValue('--flow-drift'),'');
 const n=scrolls.length;link.dispatchEvent(new w.MouseEvent('click',{bubbles:true,cancelable:true,ctrlKey:true}));assert.equal(scrolls.length,n,'modified links retain native behavior');
 observer([{isIntersecting:false}]);
 console.log('Flow checks passed: anchor integrity, readable no-JS chapters, preview assets, keyboard focus destination, reduced motion and modified links.');
 dom.window.close();
})().catch(e=>{console.error(e);dom.window.close();process.exit(1);});
