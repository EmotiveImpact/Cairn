(() => {
  'use strict';
  const root = document.querySelector('.flow-story');
  if (!root) return;
  const chapters = [...root.querySelectorAll('.flow-chapter')];
  const links = [...root.querySelectorAll('.flow-steps a')];
  const videos = [...root.querySelectorAll('[data-flow-film]')];
  const toggle = root.querySelector('.flow-motion-toggle');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const compact = matchMedia('(max-width: 760px)');
  const failures = new WeakSet(), pending = new WeakSet();
  let frame = 0, visible = false, paused = false;
  const allowed = () => !reduced.matches && !navigator.connection?.saveData;
  function activeVideo() {
    if (!visible || document.hidden || !allowed()) return null;
    if (!compact.matches) return videos.find(video => video.dataset.flowFilm === 'desktop');
    const chapter = chapters.reduce((best, item) => {
      const rect = item.getBoundingClientRect();
      const area = Math.max(0, Math.min(innerHeight, rect.bottom) - Math.max(0, rect.top));
      return area > best.area ? { item, area } : best;
    }, { item: null, area: 0 }).item;
    return chapter?.querySelector('video') || null;
  }
  function syncMedia() {
    const current = activeVideo();
    toggle.hidden = !allowed() || !current || failures.has(current);
    videos.forEach(video => {
      if (video !== current || paused || failures.has(video)) { video.pause(); return; }
      if (!video.getAttribute('src')) {
        video.muted = true;
        video.src = video.dataset.src;
        video.preload = 'auto';
        video.load();
      }
      if (!video.paused || pending.has(video)) return;
      pending.add(video);
      const play = video.play();
      if (play?.then) play.then(() => {
        pending.delete(video);
        if (paused || activeVideo() !== video) video.pause();
      }).catch(() => {
        pending.delete(video);
        if (activeVideo() === video) {
          paused = true; toggle.hidden = false;
          toggle.textContent = 'Play animation'; toggle.setAttribute('aria-pressed', 'true');
        }
      });
      else pending.delete(video);
    });
  }
  videos.forEach(video => {
    video.addEventListener('playing', () => video.classList.add('is-playing'));
    video.addEventListener('error', () => {
      failures.add(video); video.classList.remove('is-playing'); video.pause(); syncMedia();
    });
  });
  toggle.addEventListener('click', () => {
    paused = !paused;
    toggle.textContent = paused ? 'Play animation' : 'Pause animation';
    toggle.setAttribute('aria-pressed', String(paused));
    syncMedia();
  });
  function update() {
    frame = 0;
    if (!visible || document.hidden) return;
    const focus = innerHeight * .45;
    const current = chapters.reduce((closest, chapter) => Math.abs(chapter.getBoundingClientRect().top - focus) < Math.abs(closest.getBoundingClientRect().top - focus) ? chapter : closest);
    root.dataset.activeChapter = current.id;
    syncMedia();
  }
  function schedule() { if (visible && !frame && !document.hidden) frame = requestAnimationFrame(update); }
  if ('IntersectionObserver' in window) new IntersectionObserver(entries => {
    visible = entries.some(entry => entry.isIntersecting);
    if (visible) schedule();
    else { cancelAnimationFrame(frame); frame = 0; syncMedia(); }
  }, { threshold: 0 }).observe(root);
  else { visible = true; schedule(); }
  window.addEventListener('scroll', schedule, { passive: true });
  window.addEventListener('resize', schedule, { passive: true });
  function preferencesChanged() {
    videos.forEach(video => {
      video.pause(); video.classList.remove('is-playing');
      if (!allowed() || (compact.matches === (video.dataset.flowFilm === 'desktop'))) {
        video.removeAttribute('src'); video.load();
      }
    });
    syncMedia();
  }
  reduced.addEventListener('change', preferencesChanged);
  compact.addEventListener('change', preferencesChanged);
  navigator.connection?.addEventListener?.('change', preferencesChanged);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) { cancelAnimationFrame(frame); frame = 0; }
    syncMedia();
  });
  links.forEach(link => link.addEventListener('click', event => {
    if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey || event.button !== 0) return;
    const target = document.querySelector(link.getAttribute('href'));
    if (!target) return;
    event.preventDefault();
    try { history.replaceState(null, '', link.getAttribute('href')); }
    catch { location.hash = link.getAttribute('href'); }
    target.scrollIntoView({ behavior: reduced.matches ? 'auto' : 'smooth', block: 'start' });
    target.tabIndex = -1; target.focus({ preventScroll: true });
  }));
})();
