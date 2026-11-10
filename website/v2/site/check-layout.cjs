// Render only the local static export. Never connects to app data or deployment APIs.
const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const root=path.resolve(process.argv[2]||path.join(__dirname,'../dist'));
const output=path.resolve(process.argv[3]||path.join(__dirname,'../../../artifacts/launch-claims-20261110/browser'));
fs.mkdirSync(output,{recursive:true});
const types={'.html':'text/html','.css':'text/css','.js':'text/javascript','.png':'image/png','.webp':'image/webp','.jpg':'image/jpeg','.svg':'image/svg+xml'};
const server=http.createServer((req,res)=>{
 const file=path.resolve(root,'.'+decodeURIComponent(req.url.split('?')[0]==='/'?'/index.html':req.url.split('?')[0]));
 if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}
 fs.readFile(file,(err,data)=>{res.writeHead(err?404:200,{'Content-Type':types[path.extname(file)]||'application/octet-stream'});res.end(err?'Not found':data);});
});
const report={viewports:[],errors:[],failures:[],limits:'Chromium viewport emulation, not physical Safari/iPhone or native Mac acceptance.'};
const changedSelectors='.open-lead,.open-stats,.open-more,.open-cta,.dive-words h2,.dive-words .label,.story-disk .centre,.legend,.disk-done,.promises,.story-ask .lead,.ans,.got,.ask-btns,.chat-tabs,.app-steps,.app-sample,.more-list,.more-also,.touches-foot,.footer-price,.footer-availability';
async function measure(page,label,staged=false){
 const value=await page.evaluate(({selectors,staged})=>{
  const visible=e=>{for(let p=e;p;p=p.parentElement){const s=getComputedStyle(p);if(s.display==='none'||s.visibility==='hidden'||+s.opacity<0.95)return false;}return true;};
  const boxes=[...document.querySelectorAll(selectors)].filter(visible).map(e=>{const r=e.getBoundingClientRect();return {selector:e.className||e.tagName,text:e.textContent.trim(),x:r.x,y:r.y,right:r.right,bottom:r.bottom,width:r.width,height:r.height,staged:!!e.closest('.chapter')};});
  return {width:innerWidth,height:innerHeight,documentWidth:document.documentElement.scrollWidth,fontLoaded:document.fonts.check('16px Inter'),boxes};
 },{selectors:changedSelectors,staged});
 const bad=value.boxes.filter(b=>b.right>value.width+1||b.x< -1||(staged&&b.staged&&(b.bottom>value.height+1||b.y<0)));
 if(value.documentWidth>value.width+1)report.failures.push(`${label}: document overflows ${value.documentWidth}/${value.width}`);
 for(const b of bad)report.failures.push(`${label}: copy outside viewport: ${b.selector} (${Math.round(b.x)},${Math.round(b.y)}) to (${Math.round(b.right)},${Math.round(b.bottom)})`);
 return {label,...value};
}
(async()=>{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const base=`http://127.0.0.1:${server.address().port}`;
 const browser=await chromium.launch();
 try{
 const {pages}=require('./content.cjs');
 const docs=JSON.parse(fs.readFileSync(path.join(__dirname,'../docs/docs.json'))).navigation.groups.flatMap(g=>g.pages);
 for(const [width,height] of [[320,568],[390,844],[768,1024],[1024,768],[1440,900]]){
  const page=await browser.newPage({viewport:{width,height},deviceScaleFactor:1});
  page.on('pageerror',e=>report.errors.push({width,message:e.message}));
  await page.goto(base+'/story.html',{waitUntil:'networkidle'});
  const frames=[];
  const stops=await page.evaluate(()=>[...document.querySelectorAll('.stage > .chapter')].reduce((sum,e)=>sum+Number(e.dataset.stops||1),0));
  for(let stop=0;stop<stops;stop++){
   if(stop){await page.locator('body').press('PageDown');await page.waitForFunction(({stop,last})=>{const t=document.querySelector('.stage-track');return Math.abs(scrollY-(t.offsetTop+(t.offsetHeight-innerHeight)*stop/last))<2;},{stop,last:stops-1},{timeout:10000});}
   // Wait for copy reveals/counts, rather than disabling approved animation.
   await page.waitForTimeout(1800);
   if(stop===(width<760?5:4))await page.waitForFunction(()=>[...document.querySelectorAll('#ask .step')].every(e=>+getComputedStyle(e).opacity>=0.95),null,{timeout:10000});
   frames.push(await measure(page,`${width} stop ${stop}`,true));
   if([320,390,1440].includes(width))await page.screenshot({path:path.join(output,`${width}-story-${stop}.png`)});
   if(stop===6){
    await page.locator('.product-screen').click();
    const note=page.locator('.radix-preview .preview-note');
    await note.waitFor({state:'visible'});
    await page.locator('.radix-preview').evaluate(async el=>Promise.all(el.getAnimations({subtree:true}).map(a=>a.finished)));
    assert((await note.textContent()).includes('No guarantee that every code file or conversation is protected.'));
    const box=await note.boundingBox();
    if(!box||box.x<0||box.y<0||box.x+box.width>width+1||box.y+box.height>height+1)report.failures.push(`${width}: gallery limitation outside viewport`);
    if([320,390,1440].includes(width))await page.screenshot({path:path.join(output,`${width}-gallery.png`)});
    await page.keyboard.press('Escape');
    await note.waitFor({state:'hidden'});
   }
  }
  await page.locator('#touches').scrollIntoViewIfNeeded();
  frames.push(await measure(page,`${width} protection`));
  await page.locator('.footer-price').scrollIntoViewIfNeeded();
  frames.push(await measure(page,`${width} commercial`));
  if([320,390,1440].includes(width))await page.screenshot({path:path.join(output,`${width}-footer.png`)});
  for(const route of [...pages.map(p=>p.slug+'.html'),...docs.map(p=>'docs-preview/'+p+'.html')]){
   await page.goto(base+'/'+route,{waitUntil:'networkidle'});
   frames.push(await measure(page,`${width} ${route}`));
   if([390,1440].includes(width)&&['features.html','pricing.html','protection.html'].includes(route))await page.screenshot({path:path.join(output,`${width}-${route.replace('.html','.png')}`),fullPage:true});
  }
  report.viewports.push({width,height,frames});
  console.log(`Checked ${width}x${height}: ${stops} animated stops and 17 supporting pages`);
  await page.close();
 }
 // Reduced motion should remain a readable, ordinary scrolling page.
 const page=await browser.newPage({viewport:{width:390,height:844},reducedMotion:'reduce'});
 await page.goto(base+'/story.html',{waitUntil:'networkidle'});
 assert.equal(await page.locator('body').evaluate(e=>e.classList.contains('staged')),false);
 report.reducedMotion=await measure(page,'390 reduced motion');
 await page.screenshot({path:path.join(output,'390-reduced-motion.png'),fullPage:true});
 await page.close();
 }finally{await browser.close();server.close();fs.writeFileSync(path.join(output,'layout-report.json'),JSON.stringify(report,null,2));}
 assert.deepEqual(report.errors,[],'site JavaScript errors');
 assert.deepEqual(report.failures,[],'copy layout failures');
 console.log('PASS: animated desktop/mobile layouts, 18 pages at five viewport sizes, reduced motion, no site JavaScript errors.');
})().catch(e=>{console.error(e);server.close();process.exitCode=1;});
