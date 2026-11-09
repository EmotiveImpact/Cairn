// Portable static output; publication is a separate, explicitly authorised step.
const fs = require('node:fs');
const path = require('node:path');
const {pages} = require('./content.cjs');
const root = path.resolve(__dirname,'..');
const output = path.resolve(process.argv[2] || path.join(root,'dist'));
if (fs.existsSync(output)) throw Error(`Output already exists: ${output}. Choose a new output directory to preserve existing work.`);
fs.mkdirSync(output,{recursive:true});
for(const file of ['story.html',...pages.map(page=>`${page.slug}.html`)]) {
 let html = fs.readFileSync(path.join(root,file),'utf8').replaceAll('../assets/','common-assets/');
 if(file==='404.html') html=html.replace('<head>','<head><base href="/">');
 fs.writeFileSync(path.join(output,file),html);
 if(file==='story.html') fs.writeFileSync(path.join(output,'index.html'),html);
}
for(const file of ['night-refined.css','screen-showcase.css','footer-matrix.css','footer-matrix.js','storage-story.css','flow-story.css','story.css','story.js','beam-hero.css','beam-hero.js']) fs.copyFileSync(path.join(root,file),path.join(output,file));
for(const dir of ['assets','docs-preview']) fs.cpSync(path.join(root,dir),path.join(output,dir),{recursive:true});
for(const file of ['site/site.css','site/site.js','site/home-navigation.css','site/home-navigation.js','ui/interactions.css','docs/logo.png','docs/favicon.png']) {
 fs.mkdirSync(path.dirname(path.join(output,file)),{recursive:true});
 fs.copyFileSync(path.join(root,file),path.join(output,file));
}
fs.cpSync(path.join(root,'../assets'),path.join(output,'common-assets'),{recursive:true});
console.log(`Exported the active site to ${output}. No publication performed.`);
// Keep the already-shared private preview's original route working.
fs.mkdirSync(path.join(output,'v2'),{recursive:true});
fs.writeFileSync(path.join(output,'v2/story.html'),'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="0;url=../story.html"><title>Cairn</title><script>location.replace("../story.html"+location.search+location.hash)</script></head><body><a href="../story.html">Open Cairn</a></body></html>');
