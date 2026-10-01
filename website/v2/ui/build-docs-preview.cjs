const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const source = path.join(root, 'docs');
const output = path.join(root, 'docs-preview');
const config = JSON.parse(fs.readFileSync(path.join(source, 'docs.json'), 'utf8'));
const groups = config.navigation.groups;
const routes = groups.flatMap(group => group.pages);
const pages = new Map();
const escape = value => String(value).replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const localLink = (from, to) => `${path.posix.relative(path.posix.dirname(from), to) || path.posix.basename(to)}.html`;

for (const route of routes) {
  const file = path.join(source, `${route}.mdx`);
  if (!fs.existsSync(file)) throw Error(`Missing Mintlify page: ${route}`);
  const text = fs.readFileSync(file, 'utf8');
  const front = text.match(/^---\n([\s\S]*?)\n---\n/);
  if (!front) throw Error(`Missing frontmatter: ${route}`);
  const field = key => front[1].match(new RegExp(`^${key}:\\s*"([^"]+)"`, 'm'))?.[1];
  const title = field('title'), description = field('description');
  if (!title || !description) throw Error(`Missing title or description: ${route}`);
  pages.set(route, {title, description, body:text.slice(front[0].length)});
}

function inline(text, current) {
  return escape(text)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_,label,href) => {
      if (/^https?:\/\//.test(href) || href.startsWith('#')) return `<a href="${escape(href)}">${label}</a>`;
      const target = path.posix.normalize(path.posix.join(path.posix.dirname(current), href));
      if (!pages.has(target)) throw Error(`Broken docs link in ${current}: ${href}`);
      return `<a href="${escape(localLink(current,target))}">${label}</a>`;
    });
}

function render(body, current) {
  const lines = body.trim().split(/\r?\n/);
  const parts = [], toc = [];
  let paragraph = [], list = '', items = [];
  const flushParagraph = () => {if (paragraph.length) {parts.push(`<p>${inline(paragraph.join(' '),current)}</p>`); paragraph=[];}};
  const flushList = () => {if (list) {parts.push(`<${list}>${items.join('')}</${list}>`); list=''; items=[];}};
  for (const line of lines) {
    const heading = line.match(/^(#{2,3})\s+(.+)$/);
    const bullet = line.match(/^(-|\d+\.)\s+(.+)$/);
    if (!line.trim()) {flushParagraph();flushList();continue;}
    if (heading) {
      flushParagraph();flushList();
      const id=heading[2].toLowerCase().replace(/[^a-z0-9\s-]/g,'').trim().replace(/\s+/g,'-');
      const level=heading[1].length;
      parts.push(`<h${level} id="${id}">${inline(heading[2],current)}</h${level}>`);
      if (level===2) toc.push({id,title:heading[2]});
      continue;
    }
    if (bullet) {
      flushParagraph();
      const kind=bullet[1]==='-'?'ul':'ol';
      if(list&&list!==kind)flushList();
      list=kind;items.push(`<li>${inline(bullet[2],current)}</li>`);
      continue;
    }
    flushList();paragraph.push(line.trim());
  }
  flushParagraph();flushList();
  return {html:parts.join('\n'),toc};
}

fs.mkdirSync(output,{recursive:true});
for (const [index,route] of routes.entries()) {
  const page=pages.get(route), {html,toc}=render(page.body,route);
  const prefix=route.includes('/')?'../':'';
  const site=`${prefix}../night.html`;
  const currentGroup=groups.find(group=>group.pages.includes(route));
  const side=groups.map(group=>`<details class="nav-group"${group===currentGroup?' open':''}><summary>${escape(group.group)}</summary><div class="nav-links">${group.pages.map(target=>`<a href="${escape(localLink(route,target))}"${target===route?' aria-current="page"':''}>${escape(pages.get(target).title)}</a>`).join('')}</div></details>`).join('');
  const next=routes[index+1];
  const nextLink=next?`<a class="next-page" href="${escape(localLink(route,next))}"><span>Next</span><strong>${escape(pages.get(next).title)} <span aria-hidden="true">↗</span></strong></a>`:'';
  const tocHtml=toc.map(item=>`<a href="#${item.id}">${escape(item.title)}</a>`).join('');
  const document=`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="theme-color" content="#090d11"><meta name="description" content="${escape(page.description)}"><title>${escape(page.title)} · Cairn docs</title><link rel="icon" href="${prefix}../docs/favicon.png"><link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet"><link rel="stylesheet" href="${prefix}style.css"></head>
<body><a class="skip" href="#content">Skip to content</a><header class="topbar"><a class="brand" href="${prefix}index.html"><img src="${prefix}../docs/logo.png" alt="" width="32" height="32"><span>Cairn <em>Docs</em></span></a><div class="topbar-main"><span class="breadcrumb"><span>${escape(currentGroup.group)}</span><span aria-hidden="true">/</span><strong>${escape(page.title)}</strong></span><div class="topbar-actions"><span class="status">In development</span><a class="website" href="${site}">Cairn website <span aria-hidden="true">↗</span></a></div></div></header>
<div class="layout"><aside class="sidebar" aria-label="Documentation navigation"><nav class="sidebar-inner" aria-label="Pages">${side}</nav><div class="sidebar-bottom"><a href="${prefix}index.html">Docs home</a><a href="${site}">Cairn website <span aria-hidden="true">↗</span></a><span>In development for macOS</span></div></aside><main id="content" class="content"><h1>${escape(page.title)}</h1><p class="lead">${escape(page.description)}</p><div class="article">${html}</div>${nextLink}<div class="last-note">Cairn is in development for macOS. No public download is available yet.</div></main><aside class="toc" aria-label="On this page"><div>${tocHtml}</div></aside></div>
<footer><span>Cairn documentation · In development</span><a href="${site}">Return to Cairn</a></footer></body></html>`;
  const destination=path.join(output,`${route}.html`);
  fs.mkdirSync(path.dirname(destination),{recursive:true});
  fs.writeFileSync(destination,document);
}
console.log(`Built ${routes.length} local docs pages from Mintlify MDX.`);
