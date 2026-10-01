// Emit actual Radix SVG marks into the static page so they work without JavaScript.
const fs = require('node:fs');
const path = require('node:path');
const React = require('react');
const { renderToStaticMarkup } = require('react-dom/server');
const icons = require('@radix-ui/react-icons');
const file = path.join(__dirname, '..', 'night.html');
const mapping = {
 'Build output': 'CodeIcon',
 'Packages &amp; runtimes': 'CubeIcon',
 'Files, apps &amp; duplicates': 'CopyIcon',
 'Browser &amp; creative tools': 'DesktopIcon',
 'Local AI tools': 'TokensIcon',
 'Storage &amp; alerts': 'ArchiveIcon',
};
let html = fs.readFileSync(file, 'utf8');
for (const [title, name] of Object.entries(mapping)) {
 const svg = renderToStaticMarkup(React.createElement(icons[name], {
  className: 'feature-icon', width: 23, height: 23, 'aria-hidden': true, focusable: false,
 }));
 const pattern = new RegExp(`<h3>(?:<svg[\\s\\S]*?<\\/svg><span>)?${title.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?:<\\/span>)?<\\/h3>`);
 if (!pattern.test(html)) throw new Error(`Feature heading missing: ${title}`);
 html = html.replace(pattern, `<h3>${svg}<span>${title}</span></h3>`);
}
html = html.replace('night-refined.css?v=20260929-12', 'night-refined.css?v=20260929-13');
fs.writeFileSync(file, html);
console.log('Added six static Radix feature icons.');
