(() => {
  const header = document.querySelector('.site-header');
  const menu = document.querySelector('.menu-toggle');
  if (header && menu) {
    const mobile = window.matchMedia('(max-width: 800px)');
    const closeMenu = () => menu.setAttribute('aria-expanded', 'false');
    document.documentElement.classList.add('nav-ready');
    menu.hidden = false;
    menu.addEventListener('click', () => {
      menu.setAttribute('aria-expanded', String(menu.getAttribute('aria-expanded') !== 'true'));
    });
    header.querySelectorAll('a').forEach(link => link.addEventListener('click', closeMenu));
    document.addEventListener('click', event => { if (!header.contains(event.target)) closeMenu(); });
    document.addEventListener('keydown', event => {
      if (event.key === 'Escape' && menu.getAttribute('aria-expanded') === 'true') {
        closeMenu(); menu.focus();
      }
    });
    header.addEventListener('focusout', event => { if (!header.contains(event.relatedTarget)) closeMenu(); });
    mobile.addEventListener('change', closeMenu);
  }

  const dialog = document.querySelector('.app-preview');
  if (!dialog || typeof dialog.showModal !== 'function') return;
  const image = dialog.querySelector('.preview-image');
  const canvas = dialog.querySelector('.preview-image-wrap');
  const title = dialog.querySelector('#preview-title');
  const zoom = dialog.querySelector('.preview-zoom');
  const original = dialog.querySelector('.preview-original');
  const hint = dialog.querySelector('.preview-hint');
  const choices = [...dialog.querySelectorAll('[data-screen]')];

  function resetScroll() { canvas.scrollTo({ left: 0, top: 0, behavior: 'instant' }); }
  function setZoom(enabled) {
    canvas.classList.toggle('is-zoomed', enabled);
    zoom.setAttribute('aria-pressed', String(enabled));
    zoom.textContent = enabled ? 'Fit to window' : 'Actual size';
    hint.textContent = enabled ? 'Scroll across the image to inspect the details.' : 'Choose Actual size to read the details.';
    resetScroll();
  }
  function selectScreen(key) {
    const choice = choices.find((button) => button.dataset.screen === key);
    if (!choice) return false;
    image.src = choice.dataset.src;
    image.alt = choice.dataset.alt;
    original.href = choice.dataset.src;
    title.textContent = choice.textContent;
    choices.forEach((button) => button.setAttribute('aria-pressed', String(button === choice)));
    resetScroll();
    return true;
  }

  document.querySelectorAll('[data-preview]').forEach((link) => {
    link.addEventListener('click', (event) => {
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      if (!selectScreen(link.dataset.preview)) return;
      event.preventDefault();
      setZoom(false);
      if (!dialog.open) dialog.showModal();
      document.body.classList.add('preview-open');
    });
  });
  choices.forEach((button) => button.addEventListener('click', () => selectScreen(button.dataset.screen)));
  zoom.addEventListener('click', () => {
    const enabled = zoom.getAttribute('aria-pressed') !== 'true';
    setZoom(enabled);
    if (enabled) canvas.focus({ preventScroll: true });
  });
  dialog.querySelector('.preview-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('close', () => {
    document.body.classList.remove('preview-open');
    setZoom(false);
  });
  dialog.addEventListener('click', (event) => {
    if (event.target !== dialog) return;
    const bounds = dialog.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right ||
        event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
  });
})();
