// Portable static output; publication is a separate, explicitly authorised step.
const fs = require('node:fs');
const path = require('node:path');
const {pages} = require('./content.cjs');
const root = path.resolve(__dirname,'..');
const output = path.resolve(process.argv[2] || path.join(root,'dist'));
if (fs.existsSync(output)) throw Error(`Output already exists: ${output}. Choose a new output directory to preserve existing work.`);
fs.mkdirSync(output,{recursive:true});
for(const file of ['night.html',...pages.map(page=>`${page.slug}.html`)]) {
 let html = fs.readFileSync(path.join(root,file),'utf8').replaceAll('../assets/','common-assets/');
 if(file==='404.html') html=html.replace('<head>','<head><base href="/">');
 fs.writeFileSync(path.join(output,file),html);
 if(file==='night.html') fs.writeFileSync(path.join(output,'index.html'),html);
}
for(const file of ['night-refined.css','screen-showcase.css','footer-matrix.css','footer-matrix.js','storage-story.css','flow-story.css']) fs.copyFileSync(path.join(root,file),path.join(output,file));
for(const dir of ['assets','docs-preview']) fs.cpSync(path.join(root,dir),path.join(output,dir),{recursive:true});
for(const file of ['site/site.css','site/site.js','ui/interactions.css','docs/logo.png','docs/favicon.png']) {
 fs.mkdirSync(path.dirname(path.join(output,file)),{recursive:true});
 fs.copyFileSync(path.join(root,file),path.join(output,file));
}
fs.cpSync(path.join(root,'../assets'),path.join(output,'common-assets'),{recursive:true});
console.log(`Exported the active site to ${output}. No publication performed.`);
