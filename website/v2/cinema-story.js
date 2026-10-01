(() => {
  'use strict';
  const root = document.querySelector('.cinema-story');
  if (!root) return;
  const track = root.querySelector('.cinema-track');
  const stage = root.querySelector('.cinema-stage');
  const film = root.querySelector('.cinema-film');
  const poster = root.querySelector('.cinema-poster');
  const chapters = [...root.querySelectorAll('[data-chapter]')];
  const buttons = [...root.querySelectorAll('[data-cinema-step]')];
  const status = root.querySelector('.cinema-status');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const compact = matchMedia('(max-width: 800px), (max-height: 700px)');
  const names = ['Understand', 'Review', 'Protect', 'Verify'];
  const anchors = { '#changes': 0, '#make-room': 1, '#review': 2, '#outcome': 3 };
  let selected = -1, progress = 0, wantedTime = 0, scrollFrame = 0;
  let loaded = false, failed = false, inView = false, animationFrame = 0;
  const fps = Number(film.dataset.fps) || 24;
  const totalFrames = Number(film.dataset.totalFrames) || 96;
  const renderedFrames = Number(film.dataset.renderedFrames) || totalFrames;
  const available = () => wantedTime <= Math.min((renderedFrames - 1) / fps, Math.max(0, film.duration - 1 / fps)) + .001;
  function updateFilm() {
    wantedTime = progress * (totalFrames - 1) / fps;
    if (!available()) root.classList.remove('has-film');
    else seek();
  }
  const clamp = value => Math.max(0, Math.min(1, value));
  const manual = () => compact.matches || reduced.matches;
  const headerHeight = () => document.querySelector('.site-header')?.getBoundingClientRect().height || 76;

  function select(index, announce = false) {
    index = Math.max(0, Math.min(3, index));
    if (index !== selected) {
      selected = index;
      chapters.forEach((chapter, i) => { chapter.hidden = i !== index; });
      buttons.forEach((button, i) => button.setAttribute('aria-pressed', String(i === index)));
      poster.src = chapters[index].dataset.poster;
      root.dataset.chapter = String(index);
    }
    if (announce) status.textContent = `Step ${index + 1} of 4: ${names[index]}`;
  }

  function seek() {
    if (!loaded || failed || reduced.matches || document.hidden || !available() || film.seeking) return;
    if (Math.abs(film.currentTime - wantedTime) > 1 / 48) {
      try { film.currentTime = wantedTime; } catch { fail(); }
    } else root.classList.add('has-film');
  }
  function setProgress(value) {
    progress = clamp(value);
    select(Math.round(progress * 3));
    updateFilm();
  }
  function loadFilm() {
    if (loaded || failed || reduced.matches || film.getAttribute('src') || navigator.connection?.saveData) return;
    film.preload = 'auto';
    film.src = film.dataset.src;
    film.load();
  }
  function fail() {
    if (!film.getAttribute('src')) return;
    failed = true; loaded = false;
    root.classList.remove('has-film');
    film.pause();
  }
  film.addEventListener('loadeddata', () => {
    loaded = true; setProgress(progress);
    // Do not reveal a stale opening frame after a deep-link jump.
    if (!reduced.matches && available() && !film.seeking && wantedTime < 1 / 48) root.classList.add('has-film');
  });
  film.addEventListener('seeked', () => {
    if (reduced.matches || failed || !available()) return;
    if (Math.abs(film.currentTime - wantedTime) <= 1 / 48) root.classList.add('has-film');
    else seek();
  });
  film.addEventListener('error', fail);

  function scrollProgress() {
    scrollFrame = 0;
    if (manual()) return;
    const distance = Math.max(1, track.offsetHeight - stage.offsetHeight);
    setProgress((headerHeight() - track.getBoundingClientRect().top) / distance);
  }
  function scheduleScroll() {
    if (!scrollFrame && !document.hidden) scrollFrame = requestAnimationFrame(scrollProgress);
  }
  function go(index, announce = true) {
    index = Math.max(0, Math.min(3, index));
    cancelAnimationFrame(animationFrame);
    loadFilm();
    if (manual()) {
      const from = progress, to = index / 3;
      select(index, announce);
      if (reduced.matches || !loaded || failed) setProgress(to);
      else {
        const start = performance.now();
        const animate = time => {
          const t = clamp((time - start) / 650), eased = t * t * (3 - 2 * t);
          progress = from + (to - from) * eased;
          updateFilm();
          if (t < 1) animationFrame = requestAnimationFrame(animate);
        };
        animationFrame = requestAnimationFrame(animate);
      }
    } else {
      const y = scrollY + track.getBoundingClientRect().top - headerHeight()
        + (track.offsetHeight - stage.offsetHeight) * index / 3;
      window.scrollTo({ top: y, behavior: 'smooth' });
      select(index, announce);
    }
  }
  buttons.forEach((button, index) => {
    button.addEventListener('click', () => go(index));
    button.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight') next = (index + 1) % 4;
      if (event.key === 'ArrowLeft') next = (index + 3) % 4;
      if (event.key === 'Home') next = 0;
      if (event.key === 'End') next = 3;
      if (next === undefined) return;
      event.preventDefault(); buttons[next].focus(); go(next);
    });
  });
  function followHash() {
    if (!(location.hash in anchors)) return;
    const index = anchors[location.hash];
    if (manual()) { go(index, false); stage.scrollIntoView({ block: 'start', behavior: 'auto' }); }
    else {
      const y = scrollY + track.getBoundingClientRect().top - headerHeight()
        + (track.offsetHeight - stage.offsetHeight) * index / 3;
      window.scrollTo({ top: y, behavior: 'auto' }); setProgress(index / 3);
    }
  }
  function preferencesChanged() {
    cancelAnimationFrame(animationFrame);
    if (reduced.matches) {
      film.pause(); film.removeAttribute('src'); film.load(); loaded = false;
      root.classList.remove('has-film');
      progress = selected / 3;
    } else if (inView) loadFilm();
    if (!manual()) scheduleScroll();
  }
  reduced.addEventListener('change', preferencesChanged);
  compact.addEventListener('change', preferencesChanged);
  window.addEventListener('scroll', scheduleScroll, { passive: true });
  window.addEventListener('resize', scheduleScroll, { passive: true });
  window.addEventListener('hashchange', followHash);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) { cancelAnimationFrame(scrollFrame); cancelAnimationFrame(animationFrame); scrollFrame = 0; film.pause(); }
    else { scheduleScroll(); seek(); }
  });
  root.classList.add('is-ready');
  root.querySelector('.cinema-navigation').hidden = false;
  select(0);
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(entries => {
      inView = entries.some(entry => entry.isIntersecting);
      if (inView) { loadFilm(); scheduleScroll(); }
    }, { rootMargin: '600px 0px' }).observe(root);
  } else { inView = true; loadFilm(); }
  scheduleScroll();
  followHash();
})();
