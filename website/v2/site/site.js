(() => {
  const button = document.querySelector('.menu-toggle');
  const navigation = document.querySelector('#main-navigation');
  if (!button || !navigation) return;
  const media = window.matchMedia('(max-width: 800px)');
  let open = false;
  function setOpen(value, returnFocus = false) {
    open = value && media.matches;
    button.setAttribute('aria-expanded', String(open));
    button.textContent = open ? 'Close' : 'Menu';
    button.setAttribute('aria-label', open ? 'Close navigation' : 'Open navigation');
    if (returnFocus) button.focus();
  }
  button.hidden = false;
  document.documentElement.classList.add('nav-ready');
  setOpen(false);
  button.addEventListener('click', () => setOpen(!open));
  navigation.addEventListener('click', event => {
    if(event.target.closest('a')) setOpen(false);
  });
  document.addEventListener('keydown', event => {
    if(event.key === 'Escape' && open) { event.preventDefault(); setOpen(false, true); }
  });
  document.addEventListener('click', event => {
    if(open && !navigation.contains(event.target) && !button.contains(event.target)) setOpen(false);
  });
  document.addEventListener('focusin', event => {
    if(open && !navigation.contains(event.target) && !button.contains(event.target)) setOpen(false);
  });
  media.addEventListener('change', () => {
    if(!media.matches && document.activeElement === button) document.querySelector('.brand').focus();
    setOpen(false);
  });
  // A bfcache restore should not reopen a navigation menu left open on another page.
  window.addEventListener('pageshow', () => setOpen(false));
  window.addEventListener('pagehide', () => setOpen(false));
  window.addEventListener('popstate', () => setOpen(false));
  function openLinkedAnswer() {
    let id;
    try { id = decodeURIComponent(location.hash.slice(1)); } catch { return; }
    const target = document.getElementById(id);
    if(target?.tagName === 'DETAILS') target.open = true;
  }
  window.addEventListener('hashchange', openLinkedAnswer);
  openLinkedAnswer();
})();
