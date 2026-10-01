const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const {JSDOM}=require('jsdom');
const root=path.resolve(__dirname,'..');
const source=path.join(root,'docs');
const preview=path.join(root,'docs-preview');
const config=JSON.parse(fs.readFileSync(path.join(source,'docs.json'),'utf8'));
const routes=config.navigation.groups.flatMap(group=>group.pages);
assert.equal(new Set(routes).size,routes.length,'Mintlify navigation routes must be unique');
for(const route of routes){
 const mdx=path.join(source,`${route}.mdx`);
 const html=path.join(preview,`${route}.html`);
 assert(fs.existsSync(mdx),`missing source: ${route}`);
 assert(fs.existsSync(html),`missing local page: ${route}`);
 const document=new JSDOM(fs.readFileSync(html,'utf8')).window.document;
 assert(document.querySelector('h1')?.textContent,`missing title: ${route}`);
 assert.equal(document.querySelectorAll('.sidebar a[aria-current="page"]').length,1,`missing active navigation: ${route}`);
 for(const element of document.querySelectorAll('a[href],link[href],img[src]')){
  const url=element.getAttribute('href')||element.getAttribute('src');
  if(url.startsWith('#')||/^[a-z]+:/i.test(url))continue;
  const target=path.resolve(path.dirname(html),url.split('#')[0]);
  assert(fs.existsSync(target),`broken local reference in ${route}: ${url}`);
 }
}
const website=new JSDOM(fs.readFileSync(path.join(root,'night.html'),'utf8')).window.document;
assert(website.querySelector('.main-nav a[href="docs-preview/index.html"]'));
assert(website.querySelector('.footer-links a[href="docs-preview/index.html"]'));
console.log(`PASS: ${routes.length} Mintlify pages, generated navigation, local links/assets, and website entry points.`);
