import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { createPortal } from 'react-dom';
import { Dialog, Tabs, Popover, Tooltip, Collapsible } from 'radix-ui';
import { ProductTour } from './product-tour.jsx';

const tourControls=document.querySelector('#product-tour-controls');
const tourVisual=document.querySelector('#product-tour-visual');
if(tourControls&&tourVisual){tourControls.replaceChildren();tourVisual.replaceChildren();}

const legacyDialog = document.querySelector('.app-preview');
const screens = [...legacyDialog.querySelectorAll('[data-screen]')].map(el => ({
  key: el.dataset.screen, src: el.dataset.src, alt: el.dataset.alt, name: el.textContent,
}));
const navigation = [...document.querySelectorAll('.main-nav a')].map(el => ({ href: el.getAttribute('href'), name: el.textContent }));
const tools = [...document.querySelectorAll('.stack-strip li')].map(el => ({
  el, name: el.querySelector('span').textContent, image: el.querySelector('img').getAttribute('src'), description: el.title,
}));
const legacyName = document.querySelector('.footer-name');
const nameCopy = { title: legacyName.querySelector('summary').textContent, body: legacyName.querySelector('p').textContent };
const nameMount = document.createElement('div');
nameMount.id = 'name'; nameMount.className = 'footer-name';
legacyName.replaceWith(nameMount);
const menuMount = document.createElement('div');
menuMount.id = 'cairn-menu-root';
document.querySelector('.menu-toggle').replaceWith(menuMount);
legacyDialog.remove();
tools.forEach(({ el }) => { el.removeAttribute('title'); el.replaceChildren(); });
const mount = document.createElement('div');
mount.id = 'cairn-interactions';
document.body.append(mount);

function Navigation() {
  const [open, setOpen] = useState(false);
  useEffect(() => {
    const query = window.matchMedia('(max-width: 800px)');
    const change = () => setOpen(false);
    query.addEventListener('change', change);
    return () => query.removeEventListener('change', change);
  }, []);
  return <Popover.Root open={open} onOpenChange={setOpen}>
    <Popover.Trigger className="menu-toggle" aria-label={open ? 'Close navigation' : 'Open navigation'}>Menu<span className="menu-lines" aria-hidden="true"><i/><i/></span></Popover.Trigger>
    <Popover.Portal><Popover.Content className="cairn-navigation" align="end" sideOffset={16} collisionPadding={20} aria-label="Navigation"
      onCloseAutoFocus={event => { if (!window.matchMedia('(max-width: 800px)').matches) { event.preventDefault(); document.querySelector('.brand').focus(); } }}>
      <nav aria-label="Mobile navigation">{navigation.map(link => <Popover.Close asChild key={link.href}><a href={link.href}>{link.name}</a></Popover.Close>)}</nav>
      <p>Native to macOS · In development</p>
    </Popover.Content></Popover.Portal>
  </Popover.Root>;
}

function App() {
  const [open, setOpen] = useState(false);
  const [screen, setScreen] = useState(screens[0].key);
  const [zoom, setZoom] = useState(false);
  const trigger = useRef(null);
  const viewport = useRef(null);
  const active = screens.find(item => item.key === screen);
  useEffect(() => {
    document.documentElement.classList.add('nav-ready', 'radix-ready');
    const onClick = event => {
      const link = event.target.closest('[data-preview]');
      if (!link || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const selected = screens.find(item => item.key === link.dataset.preview);
      if (!selected) return;
      event.preventDefault(); trigger.current = link; setScreen(selected.key); setZoom(false); setOpen(true);
    };
    document.addEventListener('click', onClick);
    return () => document.removeEventListener('click', onClick);
  }, []);
  useEffect(() => {
    if (viewport.current) { viewport.current.scrollLeft = 0; viewport.current.scrollTop = 0; }
  }, [screen, zoom, open]);
  return <Tooltip.Provider delayDuration={350} skipDelayDuration={150}>
    {createPortal(<Navigation/>, menuMount)}
    {tourControls && tourVisual && <ProductTour controls={tourControls} visual={tourVisual}/>}
    {createPortal(<Collapsible.Root><Collapsible.Trigger className="name-trigger">{nameCopy.title}</Collapsible.Trigger><Collapsible.Content className="name-content"><p>{nameCopy.body}</p></Collapsible.Content></Collapsible.Root>, nameMount)}
    {tools.map(tool => createPortal(<Tooltip.Root>
      <Tooltip.Trigger asChild><a className="tool-mark" href={['Codex', 'Cursor', 'Claude Code'].includes(tool.name) ? '#protection' : '#features'}>
        <img src={tool.image} width="24" height="24" alt=""/><span>{tool.name}</span>
      </a></Tooltip.Trigger>
      <Tooltip.Portal><Tooltip.Content className="cairn-tooltip" sideOffset={12} collisionPadding={16}>{tool.description}<Tooltip.Arrow className="tooltip-arrow"/></Tooltip.Content></Tooltip.Portal>
    </Tooltip.Root>, tool.el, tool.name))}
    <Dialog.Root open={open} onOpenChange={setOpen}>
      <Dialog.Portal>
        <Dialog.Overlay className="cairn-overlay"/>
        <Dialog.Content className="app-preview radix-preview" onCloseAutoFocus={event => { event.preventDefault(); trigger.current?.focus({ preventScroll: true }); }}>
          <div className="preview-heading"><div><span>Inside Cairn</span><Dialog.Title>{active.name}</Dialog.Title></div><Dialog.Close className="preview-close">Close<span aria-hidden="true">×</span></Dialog.Close></div>
          <Tabs.Root value={screen} onValueChange={key => { setScreen(key); setZoom(false); }}>
            <Tabs.List className="preview-choices" aria-label="Choose an app screen">{screens.map(item => <Tabs.Trigger key={item.key} value={item.key}>{item.name}</Tabs.Trigger>)}</Tabs.List>
            <div className="preview-toolbar"><button className="preview-zoom" aria-pressed={zoom} onClick={() => { setZoom(!zoom); if (!zoom) viewport.current?.focus({ preventScroll: true }); }}>{zoom ? 'Fit to window' : 'Actual size'}</button><a className="preview-original" href={active.src} target="_blank" rel="noopener">Open image</a><span className="preview-hint" aria-live="polite">{zoom ? 'Scroll across the image to inspect the details.' : 'Choose Actual size to read the details.'}</span></div>
            {screens.map(item => <Tabs.Content key={item.key} value={item.key} className="preview-panel" tabIndex={-1}>
              <div className={`preview-image-wrap${zoom ? ' is-zoomed' : ''}`} ref={item.key === screen ? viewport : undefined} role="region" aria-label="App screenshot; scroll to inspect at actual size" tabIndex={0}>
                <img className="preview-image" src={item.src} alt={item.alt} width="1120" height="740"/>
              </div>
            </Tabs.Content>)}
          </Tabs.Root>
          <Dialog.Description className="preview-note">Sample data. Disk actions are disabled in these native app captures.</Dialog.Description>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  </Tooltip.Provider>;
}

createRoot(mount).render(<App/>);
