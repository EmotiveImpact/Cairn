// Checks the shipped pages, including descriptions used by the animated gallery.
// Evidence and exact approved edits: artifacts/launch-claims-20261110/CLAIM-REVIEW.md.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {JSDOM}=require('jsdom');
const {pages}=require('./content.cjs');
const root=path.resolve(process.argv[2]||path.join(__dirname,'..'));
const docs=JSON.parse(fs.readFileSync(path.join(__dirname,'../docs/docs.json'))).navigation.groups.flatMap(g=>g.pages);
const routes=['story.html',...pages.map(p=>`${p.slug}.html`),...docs.map(p=>`docs-preview/${p}.html`)];
const forbidden=[/typical developer Mac/i,/never touched/i,/0 files/i,/every clean is reviewed first/i,/every item before anything goes/i,/free at once/i,/way back for each one/i,/free updates for every new macOS/i,/at least two years after you buy/i,/licence never runs out/i,/small upgrade fee/i,/scheduled-rule consent (?:is still|remains) under safety review/i];
function publicClaims(html,route){
 const dom=new JSDOM(html),d=dom.window.document;
 const copy=[d.body.textContent,...[...d.querySelectorAll('*')].flatMap(el=>['alt','aria-label','data-alt','title','content'].map(a=>el.getAttribute(a)||''))].join(' ');
 for(const pattern of forbidden)assert(!pattern.test(copy),`${route}: unsupported public claim ${pattern}`);
 for(const a of d.querySelectorAll('a')) assert(!/^(Buy Cairn|Download (?:app|for Mac))/.test(a.textContent.trim()),`${route}: unavailable transaction advertised`);
 dom.window.close();
}
for(const route of routes)publicClaims(fs.readFileSync(path.join(root,route),'utf8'),route);
const home=fs.readFileSync(path.join(root,'story.html'),'utf8');
const dom=new JSDOM(home),d=dom.window.document;
for(const selector of ['#open','#number','#disk','#ask'])assert(/illustrative|sample data/i.test(d.querySelector(selector).textContent),`${selector}: example needs its own visible label`);
assert(/Trash alone frees none/.test(d.querySelector('.disk-done').textContent),'animated result must explain Trash accounting');
assert(/Estimates and partial scans/.test(d.querySelector('#ask').textContent));
assert(/off by default/.test(d.querySelector('#ask').textContent));
assert(/separate permission/.test(d.querySelector('#touches').textContent));
assert(/Recovery depends/.test(d.querySelector('.app-steps').textContent));
assert(/Sales are not open/.test(d.querySelector('.footer-price').textContent));
assert(/future macOS compatibility and upgrade pricing are not promised/.test(d.querySelector('.footer-price').textContent));
assert(/Targets macOS.*Hardware acceptance/.test(d.querySelector('.footer-availability').textContent));
for(const el of d.querySelectorAll('[data-alt],.product-screen img'))assert(/^Sample /.test(el.getAttribute('data-alt')||el.getAttribute('alt')),'gallery accessible description must label sample data');
dom.window.close();
// Negative fixtures ensure text, metadata, hidden gallery descriptions and
// unavailable calls to action cannot bypass the public-copy scanner.
for(const injected of ['<p>Found on a typical developer Mac</p>','<meta content="free updates for every new macOS">','<button data-alt="Your code is never touched">Gallery</button>','<a href="pricing.html">Buy Cairn Pro</a>']){
 assert.throws(()=>publicClaims(`<html><body>${injected}</body></html>`,'negative fixture'));
}
console.log(`PASS: ${routes.length} active pages checked for unsupported claims; local sample labels, accounting, consent, recovery, commercial and platform limits; four negative fixtures.`);
