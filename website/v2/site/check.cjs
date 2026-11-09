const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {JSDOM,VirtualConsole} = require('jsdom');
const {pages} = require('./content.cjs');
const sourceRoot = path.resolve(__dirname,'..');
const root = path.resolve(process.argv[2] || sourceRoot);
const docs = JSON.parse(fs.readFileSync(path.join(sourceRoot,'docs/docs.json'))).navigation.groups.flatMap(g=>g.pages).map(x=>`docs-preview/${x}.html`);
const files = ['story.html',...pages.map(x=>`${x.slug}.html`),...docs];
const titles = new Set(), descriptions = new Set();
let localLinks = 0;
const cache = new Map();
const documentFor = file => {
 if(!cache.has(file)) cache.set(file,new JSDOM(fs.readFileSync(file,'utf8')).window.document);
 return cache.get(file);
};
for(const route of files){
 const file = path.join(root,route), document = documentFor(file);
 const title=document.title, description=document.querySelector('meta[name=description]')?.content;
 assert(title&&!titles.has(title),`${route}: missing or duplicate title`); titles.add(title);
 assert(description&&!descriptions.has(description),`${route}: missing or duplicate description`);descriptions.add(description);
 assert.equal(document.querySelectorAll('main').length,1,`${route}: one main landmark`);
 assert.equal(document.querySelectorAll('h1').length,1,`${route}: one h1`);
 const ids=[...document.querySelectorAll('[id]')].map(x=>x.id);
 assert.equal(new Set(ids).size,ids.length,`${route}: duplicate ids`);
 for(const image of document.querySelectorAll('img')) assert(image.hasAttribute('alt'),`${route}: image alt`);
 for(const element of document.querySelectorAll('a[href],link[href],script[src],img[src],source[src],video[poster]')){
  const ref=element.getAttribute('href')||element.getAttribute('src')||element.getAttribute('poster');
  if(!ref) continue;
  assert(!ref.startsWith('javascript:'),`${route}: script link`);
  if(/^[a-z]+:/i.test(ref)||ref.startsWith('//')) continue;
  const [pathname,fragment]=ref.split('#');
  const target=pathname?path.resolve(path.dirname(file),decodeURIComponent(pathname.split('?')[0])):file;
  assert(fs.existsSync(target),`${route}: broken local reference ${ref}`);localLinks++;
  if(fragment&&target.endsWith('.html')) assert(documentFor(target).getElementById(decodeURIComponent(fragment)),`${route}: missing anchor ${ref}`);
 }
 for(const control of document.querySelectorAll('[aria-controls]')) assert(document.getElementById(control.getAttribute('aria-controls')),`${route}: missing controlled element`);
 if(!route.startsWith('docs-preview')){
  assert.equal(document.querySelectorAll('.main-nav a').length,5);
  for(const page of pages.filter(x=>x.slug!=='404')) assert(document.querySelector(`footer a[href="${page.slug}.html"]`),`${route}: unreachable ${page.slug}`);
  if(route!=='story.html'&&route!=='404.html') assert(document.querySelector(`[aria-current=page][href="${route}"]`),`${route}: no current page`);
 }
 assert.equal(document.querySelectorAll('form,input[type=email],a[href*="checkout"],a[href$=".dmg"],a[href$=".zip"]').length,0,`${route}: unverified commercial or download action`);
}
for(const name of ['site/site.css','night-refined.css','screen-showcase.css','footer-matrix.css','storage-story.css','flow-story.css','ui/interactions.css','story.css','beam-hero.css','site/home-navigation.css']){
 const css=fs.readFileSync(path.join(root,name),'utf8');
 const errors=[];const virtualConsole=new VirtualConsole();virtualConsole.on('jsdomError',error=>errors.push(error.message));
 const dom=new JSDOM(`<style>${css}</style>`,{virtualConsole});
 assert(dom.window.document.styleSheets.length,`${name}: stylesheet did not parse`);
 assert.deepEqual(errors,[],`${name}: CSS parse errors`);
 for(const match of css.matchAll(/url\(\s*["']?([^)'"\s]+)["']?\s*\)/g)){
  if(/^(data:|https?:|#)/.test(match[1]))continue;
  assert(fs.existsSync(path.resolve(root,path.dirname(name),match[1])),`${name}: missing CSS asset ${match[1]}`);
 }
 dom.window.close();
}
const script=fs.readFileSync(path.join(root,'site/site.js'),'utf8');
for(const page of pages){
 const dom=new JSDOM(fs.readFileSync(path.join(root,`${page.slug}.html`),'utf8'),{url:`https://cairn.test/${page.slug}.html`,runScripts:'outside-only',pretendToBeVisual:true});
 const w=dom.window,d=w.document; let mobile=true,change;
 w.matchMedia=()=>({get matches(){return mobile;},addEventListener(type,fn){change=fn;}});
 w.eval(script);
 const button=d.querySelector('.menu-toggle');
 assert(!button.hidden);assert(d.documentElement.classList.contains('nav-ready'));
 for(let round=0;round<3;round++){
  button.click();assert.equal(button.getAttribute('aria-expanded'),'true');
  d.dispatchEvent(new w.KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true}));
  assert.equal(button.getAttribute('aria-expanded'),'false');assert.equal(d.activeElement,button);
 }
 button.click();d.querySelector('main').click();assert.equal(button.getAttribute('aria-expanded'),'false');
 button.click();d.querySelector('.brand').focus();assert.equal(button.getAttribute('aria-expanded'),'false');
 button.click();w.dispatchEvent(new w.PopStateEvent('popstate'));assert.equal(button.getAttribute('aria-expanded'),'false');
 button.click();w.dispatchEvent(new w.PageTransitionEvent('pageshow'));assert.equal(button.getAttribute('aria-expanded'),'false');
 button.click();button.focus();mobile=false;change();assert.equal(button.getAttribute('aria-expanded'),'false');assert.equal(d.activeElement,d.querySelector('.brand'));
 const answer=d.querySelector('details');
 if(answer){w.history.replaceState({},'',`#${answer.id}`);w.dispatchEvent(new w.HashChangeEvent('hashchange'));assert(answer.open,'hash opens native answer');answer.open=false;assert(!answer.open);}
 w.history.replaceState({},'','#%invalid');w.dispatchEvent(new w.HashChangeEvent('hashchange'));
 dom.window.close();
}
const privacy=fs.readFileSync(path.join(root,'privacy.html'),'utf8');
for(const required of ['hardware UUID','Polar','Google Fonts','licence key','not a final commercial privacy policy']) assert(privacy.includes(required),`privacy disclosure missing: ${required}`);
console.log(`PASS: ${files.length} active pages, ${localLinks} local references, unique metadata/IDs, anchors, assets, navigation, stylesheet parsing, non-commercial status and ${pages.length} repeated mobile-menu/lifecycle/FAQ DOM flows.`);
console.log('DOM checks do not establish rendered layout or native keyboard behaviour.');
