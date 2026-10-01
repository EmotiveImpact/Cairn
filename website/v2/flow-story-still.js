(() => {
  'use strict';
  const root = document.querySelector('.flow-story');
  if (!root) return;
  const chapters = [...root.querySelectorAll('.flow-chapter')];
  const links = [...root.querySelectorAll('.flow-steps a')];
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const compact = matchMedia('(max-width: 760px)');
  let frame = 0, visible = false;
  function update() {
    frame = 0;
    if (!visible || document.hidden) return;
    const focus = innerHeight * .45;
    const current = chapters.reduce((closest, chapter) => Math.abs(chapter.getBoundingClientRect().top - focus) < Math.abs(closest.getBoundingClientRect().top - focus) ? chapter : closest);
    root.dataset.activeChapter = current.id;
    if (!reduced.matches && !compact.matches) {
      const rect = root.getBoundingClientRect();
      const progress = Math.max(0, Math.min(1, (innerHeight - rect.top) / (rect.height + innerHeight)));
      root.style.setProperty('--flow-drift', `${((progress - .5) * 20).toFixed(2)}px`);
    } else root.style.removeProperty('--flow-drift');
  }
  function schedule() { if (visible && !frame && !document.hidden) frame = requestAnimationFrame(update); }
  if ('IntersectionObserver' in window) new IntersectionObserver(entries => {
    visible = entries.some(entry => entry.isIntersecting);
    if (visible) schedule();
    else { cancelAnimationFrame(frame); frame = 0; }
  }, { rootMargin: '200px' }).observe(root);
  else { visible = true; schedule(); }
  window.addEventListener('scroll', schedule, { passive: true });
  window.addEventListener('resize', schedule, { passive: true });
  reduced.addEventListener('change', () => { root.style.removeProperty('--flow-drift'); schedule(); });
  compact.addEventListener('change', schedule);
  document.addEventListener('visibilitychange', () => { if (document.hidden) { cancelAnimationFrame(frame); frame = 0; } else schedule(); });
  links.forEach(link => link.addEventListener('click', event => {
    if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey || event.button !== 0) return;
    const target = document.querySelector(link.getAttribute('href'));
    if (!target) return;
    event.preventDefault();
    try { history.replaceState(null, '', link.getAttribute('href')); }
    catch { location.hash = link.getAttribute('href'); }
    target.scrollIntoView({ behavior: reduced.matches ? 'auto' : 'smooth', block: 'start' });
    target.tabIndex = -1;
    target.focus({ preventScroll: true });
  }));
})();
