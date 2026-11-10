const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {JSDOM}=require('jsdom');
const source=path.resolve(__dirname,'..'),root=path.resolve(process.argv[2]||source);
const sha=s=>crypto.createHash('sha256').update(s).digest('hex');
const saved=JSON.parse(fs.readFileSync(path.join(__dirname,'homepage-invariants.json')));
for(const file of ['story.js','story.css','beam-hero.js','beam-hero.css'])assert.equal(sha(fs.readFileSync(path.join(root,file))),saved[file],`${file}: confirmed animation/style changed`);
const html=fs.readFileSync(path.join(root,'story.html'),'utf8');
// Reverse only the reviewed copy edits before checking the original design.
// Keep the existing October main-markup hash and all four motion/style hashes.
const copy=JSON.parse(fs.readFileSync(path.join(__dirname,'claim-copy-changes.json')));
let original=html.replaceAll('common-assets/','../assets/');
for(const change of copy.changes.filter(x=>x.file==='website/v2/story.html').reverse()){
 assert.equal(original.split(change.new).length-1,change.count,`reviewed homepage wording missing or duplicated: ${change.new}`);
 original=original.replaceAll(change.new,change.old);
}
assert.equal(sha(original),copy.original_homepage_sha256,'homepage changed beyond the reviewed text and accessible descriptions');
const main=original.slice(original.indexOf('<main '),original.indexOf('</main>')+7).replace('class="open-cta reveal" href="download.html"','class="open-cta reveal" href="#close"');
assert.equal(sha(main),saved.main_markup,'confirmed homepage main markup changed beyond its CTA destination');
const dom=new JSDOM(html,{url:'https://cairn.test/story.html',runScripts:'outside-only'}),w=dom.window,d=w.document;
w.eval(fs.readFileSync(path.join(root,'site/home-navigation.js'),'utf8'));
const menu=d.querySelector('#site-explore'),summary=menu.querySelector('summary');
assert(menu&&summary,'native Explore menu exists');
for(let i=0;i<3;i++){
 menu.open=true;d.dispatchEvent(new w.KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true}));assert(!menu.open);assert.equal(d.activeElement,summary);
 menu.open=true;d.querySelector('main').click();assert(!menu.open);
 menu.open=true;w.dispatchEvent(new w.PageTransitionEvent('pageshow'));assert(!menu.open);
}
menu.open=true;d.querySelector('.brand').focus();assert(!menu.open);
let bubbled=false;w.addEventListener('wheel',()=>bubbled=true);menu.dispatchEvent(new w.WheelEvent('wheel',{bubbles:true}));assert(!bubbled,'menu wheel must not move homepage story');
assert.equal(d.querySelector('.header-action').getAttribute('href'),'download.html');
assert.equal(d.querySelector('.open-cta').getAttribute('href'),'download.html');
assert(d.querySelector('.footer-actions a[href="pricing.html"]'));
for(const name of ['features','how-it-works','protection','pricing','download','support','about','changelog','privacy','terms']){
 assert(d.querySelector(`.site-explore a[href="${name}.html"]`));assert(d.querySelector(`.site-directory a[href="${name}.html"]`));
 const content=new JSDOM(fs.readFileSync(path.join(root,`${name}.html`),'utf8')).window.document;
 assert.equal(content.querySelector('.brand').getAttribute('href'),'story.html');
 assert(!content.querySelector('a[href="night.html"]'));
}
assert(!fs.readFileSync(path.join(root,'docs-preview/index.html'),'utf8').includes('night.html'));
assert(html.includes('Sales are not open.'),'homepage must state current availability');
dom.window.close();
console.log('PASS: homepage matches its original bytes after reversing reviewed copy edits; original main structure and four motion/style hashes retained; navigation, Explore lifecycle and scroll isolation pass.');
