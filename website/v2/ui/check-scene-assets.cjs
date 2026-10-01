const fs=require('fs'),path=require('path'),assert=require('assert/strict'),cp=require('child_process');
const root=path.resolve(__dirname,'..');
const {JSDOM}=require('jsdom');
const d=new JSDOM(fs.readFileSync(path.join(root,'night.html'),'utf8')).window.document;
assert(d.querySelector('.scene-story'),'native story installed');
assert(!d.querySelector('.flow-story'),'previous loop replaced');
const film=d.querySelector('.scene-film');
assert(!film.hasAttribute('autoplay')&&!film.hasAttribute('loop'),'scrubbing only');
for(const node of d.querySelectorAll('.scene-story [src],.scene-story [data-src],.scene-story [data-poster],.scene-story a[data-preview]')){
 for(const attr of ['src','data-src','data-poster','href']){
  const value=node.getAttribute(attr);if(value&&value.startsWith('assets/'))assert(fs.existsSync(path.join(root,value)),value);
 }
}
const p=JSON.parse(cp.execFileSync('/opt/homebrew/bin/ffprobe',['-v','error','-select_streams','v:0','-show_entries','stream=nb_frames,width,height,duration','-of','json',path.join(root,film.dataset.src)],{encoding:'utf8'})).streams[0];
assert.equal(+p.nb_frames,+film.dataset.frames);assert.equal(p.width,1280);assert.equal(p.height,900);assert.equal(+p.duration,4);
assert.equal(fs.realpathSync(path.join(root,'night-refined.html')),fs.realpathSync(path.join(root,'night.html')));
console.log('PASS: installed native story, all media and preview links exist, no autoplay/loop, 96 frames at 1280 × 900, refined-page alias intact.');
