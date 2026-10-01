(() => {
  const footer = document.querySelector('.site-footer');
  if (!footer) return;
  const canvas = document.createElement('canvas');
  canvas.className = 'footer-matrix';
  canvas.setAttribute('aria-hidden', 'true');
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  footer.prepend(canvas);
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const fine = matchMedia('(hover: hover) and (pointer: fine)');
  const glyphs = '01:./{}';
  const step = 25;
  let width = 0, height = 0, drops = [], still = [], frame = 0, visible = false;
  let pointer = null, lastTime = 0, nextAmbient = 0, nextPointer = 0;
  const enabled = () => !reduced.matches && fine.matches && !document.hidden && visible;
  const random = (min, max) => min + Math.random() * (max - min);
  function spawn(now, local = false) {
    if (drops.length >= 64) return;
    // Independent columns with uneven offsets; no radial illumination or hard radius.
    const offset = (Math.random() + Math.random() + Math.random() - 1.5) * 74;
    const x = local ? pointer.x + offset : random(12, width - 12);
    drops.push({
      x: Math.round(x / step) * step + 12,
      y: local ? pointer.y + random(-42, 18) : random(-50, height * .8),
      born: now, life: random(3800, 6800), speed: random(28, 61),
      length: Math.floor(random(3, 8)), seed: Math.floor(random(0, 100)),
      opacity: local ? random(.12, .21) : random(.045, .11)
    });
  }
  function paint(now) {
    ctx.clearRect(0, 0, width, height);
    ctx.font = '11px ui-monospace, SFMono-Regular, Menlo, monospace';
    ctx.textAlign = 'center';
    if (!enabled()) {
      ctx.fillStyle = 'rgba(132,201,245,.025)';
      for (const cell of still) ctx.fillText(glyphs[cell.seed], cell.x, cell.y);
      return;
    }
    if (now >= nextAmbient) {
      spawn(now); nextAmbient = now + random(220, 650) * Math.max(.65, 1100 / width);
    }
    if (pointer && now >= nextPointer) {
      spawn(now, true); nextPointer = now + random(95, 260);
    }
    drops = drops.filter(drop => now - drop.born < drop.life);
    for (const drop of drops) {
      const age = now - drop.born, seconds = age / 1000;
      const fadeIn = Math.min(1, age / 700);
      const fadeOut = Math.min(1, (drop.life - age) / 1800);
      const envelope = fadeIn * fadeOut;
      const head = drop.y + drop.speed * seconds + 2 * seconds * seconds;
      for (let i = 0; i < drop.length; i++) {
        const y = head - i * 20;
        if (y < 0 || y > height) continue;
        const tail = Math.exp(-i * .48);
        // Soft vertical boundaries and long, staggered tails prevent a spotlight shape.
        const edge = Math.min(1, y / 65, (height - y) / 90);
        const alpha = drop.opacity * envelope * tail * Math.max(0, edge);
        ctx.fillStyle = `rgba(132,201,245,${alpha})`;
        const change = Math.floor(age / (340 + (drop.seed % 5) * 90));
        ctx.fillText(glyphs[(drop.seed + i * 3 + change) % glyphs.length], drop.x, y);
      }
    }
  }
  function tick(now) {
    frame = 0;
    if (now - lastTime >= 33) { lastTime = now; paint(now); }
    if (enabled()) frame = requestAnimationFrame(tick);
  }
  function wake() {
    if (!frame && !document.hidden) frame = requestAnimationFrame(now => {
      frame = 0; lastTime = now; paint(now);
      if (enabled()) frame = requestAnimationFrame(tick);
    });
  }
  function resize() {
    const rect = footer.getBoundingClientRect();
    width = rect.width; height = rect.height;
    const ratio = Math.min(devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * ratio); canvas.height = Math.round(height * ratio);
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    drops = []; still = [];
    for (let i = 0; i < Math.min(150, width * height / 10000); i++) {
      still.push({x: random(12, width - 12), y: random(15, height - 15), seed: Math.floor(random(0, glyphs.length))});
    }
    wake();
  }
  footer.addEventListener('pointermove', event => {
    if (!enabled() || event.pointerType === 'touch') return;
    const rect = footer.getBoundingClientRect();
    pointer = {x: event.clientX - rect.left, y: event.clientY - rect.top}; wake();
  }, {passive: true});
  function leave() { pointer = null; }
  footer.addEventListener('pointerleave', leave);
  footer.addEventListener('pointercancel', leave);
  window.addEventListener('scroll', leave, {passive: true});
  function reset() {
    pointer = null; drops = [];
    if (frame) cancelAnimationFrame(frame);
    frame = 0; lastTime = 0; nextAmbient = 0; nextPointer = 0;
    wake();
  }
  reduced.addEventListener('change', reset);
  fine.addEventListener('change', reset);
  document.addEventListener('visibilitychange', reset);
  new ResizeObserver(resize).observe(footer);
  new IntersectionObserver(entries => { visible = entries[0].isIntersecting; reset(); }).observe(footer);
  resize();
})();
