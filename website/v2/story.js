// story.html: the opening scene, the stacked chapters, and each chapter's
// arrival (reveals, the count, the disk lighting up, the chat typing itself out).
(function () {
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  document.body.classList.add('story-page');
  // review only: the data tunnel (default) or one of the hero photos
  var o = document.getElementById('open'), ph = o && o.querySelector('.open-photo');
  function pick(name) {
    if (!o) return;
    if (name !== 'tunnel') ph.src = 'assets/hero/cairn-hero-' + name + '.jpg';
    o.dataset.photo = name;
    o.querySelectorAll('.photo-switch button').forEach(function (b) { b.setAttribute('aria-pressed', String(b.dataset.photo === name)); });
    if (name === 'tunnel' && window.startTunnel) window.startTunnel();
  }
  if (o) o.querySelectorAll('.photo-switch button').forEach(function (b) { b.addEventListener('click', function () { pick(b.dataset.photo); }); });
  if (/^#(profile|desk|window)$/.test(location.hash)) pick(location.hash.slice(1));
  // review only: the floating pill menu, or the earlier full-width bar
  function menu(style) {
    document.body.classList.toggle('menu-bar', style === 'bar');
    document.querySelectorAll('.menu-switch button').forEach(function (b) { b.setAttribute('aria-pressed', String(b.dataset.menu === style)); });
    try { localStorage.setItem('cairn-menu', style); } catch (e) {}
  }
  document.querySelectorAll('.menu-switch button').forEach(function (b) { b.addEventListener('click', function () { menu(b.dataset.menu); }); });
  try { if (localStorage.getItem('cairn-menu') === 'bar') menu('bar'); } catch (e) {}
  // review only: try the pictures behind the app panel
  var appSec = document.getElementById('app');
  if (appSec) appSec.querySelectorAll('.app-switch button').forEach(function (b) {
    b.addEventListener('click', function () {
      var n = b.dataset.bg, img = appSec.querySelector('.app-photo img');
      appSec.dataset.bg = n;
      if (n !== 'none') img.src = 'assets/app-bg/' + n + '.jpg';
      appSec.querySelectorAll('.app-switch button').forEach(function (x) { x.setAttribute('aria-pressed', String(x === b)); });
    });
  });
  function clamp(v) { return Math.min(1, Math.max(0, v)); }
  function ease(t) { return 1 - Math.pow(1 - t, 3); }

  // ---- the stack: chapters hold still and dissolve into one another ----
  var track = document.querySelector('.stage-track');
  var layers = track ? [].slice.call(track.querySelectorAll('.stage > .chapter')) : [];
  var staged = !!track && !reduced && innerWidth >= 760 && innerHeight >= 600;
  var stageAt = 0;            // stops: 0 opening, 1 number, 2 disk, 3 disk cleaned, 4 cleaned and held, 5 ask
  // a chapter can hold more than one stop (data-stops), so the disk can be shown and then cleaned
  var starts = [], ends = [], N = 0;
  layers.forEach(function (el, i) { var s = +(el.dataset.stops || 1); starts[i] = N; ends[i] = N + s - 1; N += s; });
  N = Math.max(1, N - 1);
  var disk = document.getElementById('disk');
  var open = document.getElementById('open'), number = document.getElementById('number');
  var arrive = [];            // callbacks per chapter, run the first time it settles
  var here = [], at = [];     // enter/leave pairs per chapter, run each time it settles or leaves
  if (staged) { document.body.classList.add('staged'); track.style.height = 'calc(100svh + ' + N + ' * 115svh)'; }
  function lerp(a, b, t) { return a + (b - a) * t; }
  function stage() {
    if (!staged) return;
    var len = track.offsetHeight - innerHeight;
    stageAt = clamp((scrollY - track.offsetTop) / Math.max(1, len)) * N;
    layers.forEach(function (el, i) {
      var d = stageAt < starts[i] ? stageAt - starts[i] : stageAt > ends[i] ? stageAt - ends[i] : 0;
      var inn = i === 0 ? 1 : clamp((d + 0.6) / 0.4);        // dissolves in from d = -0.6 to -0.2
      var out = i === layers.length - 1 ? 0 : clamp((d - 0.2) / 0.4); // and out from 0.2 to 0.6
      var o = Math.min(inn, 1 - out);
      el.style.opacity = o.toFixed(3);
      // the number scrolls up and fades as you move on; the others shrink back and blur
      var lift = el === number;
      el.style.filter = 'blur(' + ((1 - inn) * 14 + (lift ? 0 : out * 8)).toFixed(1) + 'px)';
      el.style.transform = 'scale(' + (lerp(1.04, 1, inn) * (lift ? 1 : lerp(1, 0.94, out))).toFixed(4) + ') translateY(' + (-out * (lift ? 0.3 * innerHeight : 28)).toFixed(1) + 'px)';
      el.style.pointerEvents = o > 0.5 ? 'auto' : 'none';
      el.style.visibility = o < 0.01 ? 'hidden' : 'visible';
      if (Math.abs(d) < 0.2 && arrive[i]) { var fs = arrive[i]; arrive[i] = null; fs.forEach(function (f) { f(); }); }
      if (here[i] && !at[i] && Math.abs(d) < 0.06) { at[i] = true; here[i].forEach(function (p) { p[0](); }); }
      if (here[i] && at[i] && Math.abs(d) > 0.7) { at[i] = false; here[i].forEach(function (p) { p[1](); }); }
      if (el === disk && ends[i] > starts[i] && built) setCleaned(stageAt >= starts[i] + 0.5);
    });
  }
  if (staged) { window.addEventListener('scroll', stage, { passive: true }); window.addEventListener('resize', stage); stage(); }

  // one flick, one stop: inside the stack, a wheel, swipe or key press moves exactly one stop,
  // glides there, and then holds until the gesture has finished
  if (staged) {
    document.documentElement.style.scrollBehavior = 'auto';
    var moving = false, quietUntil = 0, lastWheel = 0, lastMag = 0;
    var stopY = function (k) { return Math.round(track.offsetTop + (track.offsetHeight - innerHeight) * k / N); };
    var stopNow = function () { return Math.round(clamp((scrollY - track.offsetTop) / Math.max(1, track.offsetHeight - innerHeight)) * N); };
    var inside = function () { return scrollY >= track.offsetTop - 2 && scrollY <= stopY(N) + 2; };
    var go = function (k) {
      k = Math.max(0, Math.min(N, k));
      var from = scrollY, to = stopY(k), s0 = performance.now(), dur = Math.min(1100, 650 + Math.abs(to - from) / innerHeight * 180);
      if (Math.abs(to - from) < 2) return;
      moving = true;
      (function step(now) {
        var t = clamp((now - s0) / dur), e = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
        window.scrollTo(0, from + (to - from) * e);
        if (t < 1) requestAnimationFrame(step); else { moving = false; quietUntil = performance.now() + 250; }
      })(s0);
    };
    // a new gesture, rather than the tail of the last one: a pause, or a clearly harder push
    // (every wheel event updates the record, even mid-glide, so a long trackpad tail never counts twice)
    var rising = 0, peak = 0, held = false;   // held: this gesture has already moved a stop
    var newGesture = function (mag, now) {
      // a tail only ever fades, so once it has faded, a push that builds again is a new flick
      rising = mag > lastMag + 3 ? rising + 1 : 0;
      var faded = lastMag < peak * 0.6;
      var isNew = now - lastWheel > 220 || (faded && (mag > lastMag * 1.8 + 12 || rising >= 2));
      peak = isNew ? mag : Math.max(peak, mag);
      lastWheel = now; lastMag = mag;
      return isNew;
    };
    window.addEventListener('wheel', function (e) {
      if (e.ctrlKey || Math.abs(e.deltaY) < Math.abs(e.deltaX)) return;
      var now = performance.now(), mag = Math.abs(e.deltaY), down = e.deltaY > 0, k = stopNow();
      if (newGesture(mag, now)) held = false;
      if (!inside()) return;
      // at either end, a new gesture scrolls on as normal; the tail of the one that brought us here does not
      if (!moving && ((down && k >= N && scrollY >= stopY(N) - 2) || (!down && k <= 0 && scrollY <= stopY(0) + 2))) { if (held) e.preventDefault(); return; }
      e.preventDefault();
      if (moving || held || now < quietUntil || mag < 2) return;
      held = true;
      // caught between two stops (say, coming back up from below): settle on the next one in that direction,
      // or back on the one just passed if it is only a little way behind
      var raw = clamp((scrollY - track.offsetTop) / Math.max(1, track.offsetHeight - innerHeight)) * N, f = raw - Math.floor(raw);
      if (Math.abs(raw - Math.round(raw)) * (track.offsetHeight - innerHeight) / N > 2) { go(down ? (f < 0.3 ? Math.floor(raw) : Math.ceil(raw)) : (f > 0.7 ? Math.ceil(raw) : Math.floor(raw))); return; }
      go(k + (down ? 1 : -1));
    }, { passive: false });
    // coming back up from the page below: land on the last stop rather than part-way
    window.addEventListener('scroll', function () {
      if (moving) return;
      var y = scrollY, end = stopY(N);
      if (y < end - 2 && y > track.offsetTop + 2 && Math.abs(y - stopY(stopNow())) > 2 && performance.now() - lastWheel > 120) {
        clearTimeout(window.__stackSettle); window.__stackSettle = setTimeout(function () { if (!moving && inside()) go(stopNow()); }, 140);
      }
    }, { passive: true });
    var ty = null;
    window.addEventListener('touchstart', function (e) { ty = inside() ? e.touches[0].clientY : null; }, { passive: true });
    window.addEventListener('touchmove', function (e) { if (ty !== null && (moving || inside())) { var k = stopNow(), d = ty - e.touches[0].clientY; if ((d > 0 && k < N) || (d < 0 && k > 0)) e.preventDefault(); } }, { passive: false });
    window.addEventListener('touchend', function (e) {
      if (ty === null || moving) return; var d = ty - e.changedTouches[0].clientY, k = stopNow(); ty = null;
      if (Math.abs(d) > 40) go(k + (d > 0 ? 1 : -1));
    }, { passive: true });
    window.addEventListener('keydown', function (e) {
      if (!inside() || e.target.closest('input, textarea, button, [contenteditable]')) return;
      var k = stopNow(), dir = { ArrowDown: 1, PageDown: 1, ' ': e.shiftKey ? -1 : 1, ArrowUp: -1, PageUp: -1 }[e.key];
      if (!dir || (dir > 0 && k >= N) || (dir < 0 && k <= 0)) return;
      e.preventDefault(); if (!moving) go(k + dir);
    });
    // the menu links go to a chapter's first stop
    document.querySelectorAll('a[href^="#"]').forEach(function (a) {
      var el = document.getElementById(a.getAttribute('href').slice(1)), i = layers.indexOf(el);
      if (i >= 0) a.addEventListener('click', function (e) { e.preventDefault(); go(starts[i]); });
    });
  }






  // ---- opening tunnel: flying slowly down a corridor of glowing data ----
  window.startTunnel = function () {
  if (window.startTunnel.done) return; window.startTunnel.done = true;
  var tc = document.getElementById('tunnel');
  var tg = tc && tc.getContext('webgl', { antialias: false });
  if (!tg) return;
  var tfs = [
    'precision highp float;',
    'uniform vec2 res; uniform float t; uniform float z0;',
    'float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }',
    // one wall of data: rows of short lit dashes and specks, drifting past
    'vec3 wall(vec2 q, float dist){',
    '  vec3 c = vec3(0.0);',
    '  vec2 g = vec2(q.x / 0.16, q.y / 0.045); vec2 id = floor(g), f = fract(g);',
    '  float r = h(id), r2 = h(id + 17.3);',
    '  float on = step(0.55, r);',
    '  float len = 0.25 + 0.65 * r2;',
    '  float dash = smoothstep(0.0, 0.06, f.x) * smoothstep(len, len - 0.06, f.x) * smoothstep(0.15, 0.35, f.y) * smoothstep(0.85, 0.65, f.y);',
    '  float flick = 0.55 + 0.45 * sin(t * (0.6 + 2.0 * r2) + r * 40.0);',
    '  vec3 tint = mix(vec3(0.12, 0.42, 1.0), vec3(0.42, 0.76, 1.0), step(0.78, r2));',
    '  float soft = smoothstep(-0.2, 0.3, f.x) * smoothstep(len + 0.3, len - 0.1, f.x) * exp(-pow((f.y - 0.5) * 3.0, 2.0));',
    '  c += tint * (dash + soft * 0.35) * on * flick * (0.7 + 1.8 * step(0.93, r));',
    '  vec2 g2 = vec2(q.x / 0.05, q.y / 0.02); vec2 id2 = floor(g2), f2 = fract(g2);',
    '  float s = step(0.88, h(id2 + 5.1)) * smoothstep(0.5, 0.1, length(f2 - 0.5));',
    '  c += vec3(0.4, 0.7, 1.0) * s * (0.4 + 0.6 * sin(t * 1.7 + h(id2) * 30.0));',
    '  vec2 pan = abs(fract(vec2(q.x / 1.2, q.y / 0.36)) - 0.5);',
    '  c += vec3(0.05, 0.1, 0.2) * smoothstep(0.49, 0.5, max(pan.x, pan.y));',
    '  c = mix(c, vec3(0.1, 0.28, 0.75) * 0.45, smoothstep(3.5, 11.0, dist));',
    '  return c;',
    '}',
    'void main(){',
    '  vec2 uv = (gl_FragCoord.xy - 0.5 * res) / res.y;',
    '  vec3 rd = normalize(vec3(uv, 1.25));',
    '  float W = 1.15, F = -0.55, C = 0.95;',
    '  float tx = (sign(rd.x) * W) / rd.x;',
    '  float ty = rd.y < 0.0 ? F / rd.y : C / rd.y;',
    '  float d = min(tx, ty); vec3 p = rd * d; float z = p.z + z0;',
    '  vec3 col = vec3(0.0);',
    '  if (tx < ty) { col = wall(vec2(z, p.y + (rd.x > 0.0 ? 7.0 : 0.0)), d);',
    '    col += vec3(0.25, 0.55, 1.0) * (exp(-abs(p.y - F) * 30.0) * 1.2 + exp(-abs(p.y - C) * 30.0) * 0.5); }',
    '  else if (rd.y > 0.0) col = wall(vec2(z, p.x + 3.0), d) * 0.7;',
    '  else {',
    // the floor: dark glossy tiles, with the light of the walls and the far end reflected in it
    '    vec2 tile = abs(fract(vec2(p.x / 0.32, z / 0.32)) - 0.5);',
    '    float seam = smoothstep(0.47, 0.5, max(tile.x, tile.y));',
    '    col = vec3(0.02, 0.04, 0.08) + vec3(0.08, 0.16, 0.3) * seam * 0.6;',
    '    col += vec3(0.2, 0.45, 0.9) * exp(-abs(abs(p.x) - W) * 6.0) * 0.5;',
    '    col += vec3(0.3, 0.6, 1.0) * exp(-abs(p.x) * 2.5) * exp(-d * 0.05) * 0.18;',
    '    vec3 rr = vec3(rd.x, -rd.y, rd.z); float t2 = (sign(rd.x) * W - p.x) / rd.x; vec3 q2 = p + rr * t2;',
    '    col += wall(vec2(q2.z + z0, q2.y + (rd.x > 0.0 ? 7.0 : 0.0)), d + t2) * 0.4 * step(q2.y, C) * exp(-t2 * 0.6);',
    '    col += vec3(0.25, 0.55, 1.0) * exp(-abs(abs(p.x) - W) * 30.0) * 1.0;',
    '  }',
    '  col *= exp(-d * 0.085) * smoothstep(0.15, 1.2, d);',
    // the bright doorway at the end, and the haze around it
    '  vec2 a = abs(uv - vec2(0.0, 0.035));',
    '  float door = smoothstep(0.022, 0.018, max(a.x, a.y));',
    '  float halo = exp(-length(uv - vec2(0.0, 0.035)) * 7.0);',
    '  col += vec3(0.3, 0.62, 1.0) * halo * 0.9 + vec3(0.55, 0.82, 1.0) * door * 1.3 + vec3(0.8, 0.93, 1.0) * door * smoothstep(0.02, 0.0, max(a.x, a.y)) * 0.6;',
    '  col += vec3(0.05, 0.12, 0.25) * exp(-length(uv) * 2.2);',
    '  col = 1.0 - exp(-col * 1.4);',
    '  col *= 1.0 - 0.45 * pow(length(uv * vec2(0.8, 1.0)), 2.0);',
    '  gl_FragColor = vec4(col, 1.0);',
    '}'
  ].join('\n');
  var tv = tg.createShader(tg.VERTEX_SHADER); tg.shaderSource(tv, 'attribute vec2 p; void main(){ gl_Position = vec4(p, 0.0, 1.0); }'); tg.compileShader(tv);
  var tf = tg.createShader(tg.FRAGMENT_SHADER); tg.shaderSource(tf, tfs); tg.compileShader(tf);
  if (!tg.getShaderParameter(tf, tg.COMPILE_STATUS)) { console.log(tg.getShaderInfoLog(tf)); return; }
  var tp = tg.createProgram(); tg.attachShader(tp, tv); tg.attachShader(tp, tf); tg.linkProgram(tp); tg.useProgram(tp);
  tg.bindBuffer(tg.ARRAY_BUFFER, tg.createBuffer()); tg.bufferData(tg.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), tg.STATIC_DRAW);
  tg.enableVertexAttribArray(0); tg.vertexAttribPointer(0, 2, tg.FLOAT, false, 0, 0);
  var tres = tg.getUniformLocation(tp, 'res'), tt = tg.getUniformLocation(tp, 't'), tz = tg.getUniformLocation(tp, 'z0');
  var tresize = function () {
    var dpr = Math.min(window.devicePixelRatio || 1, 1.5);
    tc.width = Math.round(tc.clientWidth * dpr); tc.height = Math.round(tc.clientHeight * dpr); tg.viewport(0, 0, tc.width, tc.height);
  };
  window.addEventListener('resize', tresize); tresize();
  var last = performance.now(), zpos = 0;
  var tframe = function (now) {
    var dt = Math.min(0.05, (now - last) / 1000); last = now;
    // a slow glide forward that quickens as you scroll towards the number
    var push = staged ? clamp(stageAt) : clamp(scrollY / innerHeight);
    zpos += dt * (0.5 + push * 6.0);
    if ((staged ? stageAt < 1 : scrollY < innerHeight * 1.2) && o && o.dataset.photo === 'tunnel') {
      tg.uniform2f(tres, tc.width, tc.height); tg.uniform1f(tt, now / 1000); tg.uniform1f(tz, zpos); tg.drawArrays(tg.TRIANGLES, 0, 3);
    }
    if (!reduced) requestAnimationFrame(tframe);
  };
  requestAnimationFrame(tframe);
  };
  if (o && o.dataset.photo === 'tunnel') window.startTunnel();

  // ---- chapter arrivals ----
  function once(el, threshold, fn) {
    if (!el) return;
    if (reduced) { fn(); return; }
    var k = layers.indexOf(el);
    if (staged && k >= 0) { (arrive[k] = arrive[k] || []).push(fn); setTimeout(stage); return; }
    new IntersectionObserver(function (es, io) { if (es[0].isIntersecting) { io.disconnect(); fn(); } }, { threshold: threshold }).observe(el);
  }
  document.querySelectorAll('.chapter').forEach(function (c) { once(c, 0.25, function () { c.classList.add('in'); }); });

  // run enter() each time a chapter settles on screen, and leave() once it has gone
  function whenHere(el, enter, leave) {
    if (!el) return;
    if (reduced) { enter(); return; }
    var k = layers.indexOf(el);
    if (staged && k >= 0) { (here[k] = here[k] || []).push([enter, leave]); setTimeout(stage); return; }
    var on = false;
    new IntersectionObserver(function (es) {
      if (es[0].intersectionRatio >= 0.6 && !on) { on = true; enter(); }
      else if (!es[0].isIntersecting && on) { on = false; leave(); }
    }, { threshold: [0, 0.6] }).observe(el);
  }

  // the count runs once the number chapter has settled, and again each time you come back to it
  var count = document.getElementById('count'), run = 0;
  whenHere(number, function () {
    if (reduced) { count.textContent = '38.6'; number.classList.add('done'); return; }
    var s = performance.now(), mine = ++run;
    (function step(now) { if (mine !== run) return; var t = clamp((now - s) / 1800); count.textContent = (38.6 * ease(t)).toFixed(1); if (t < 1) requestAnimationFrame(step); else number.classList.add('done'); })(s);
  }, function () { run++; count.textContent = '0.0'; number.classList.remove('done'); });

  // the disk: words first, then the bar builds, the junk lights up, and scrolling on cleans it away
  var freeGb = document.getElementById('free-gb'), built = false, cleaned = false, freeRun = 0;
  function countFree(to) {
    var from = parseFloat(freeGb.textContent), s = performance.now(), mine = ++freeRun;
    if (reduced) { freeGb.textContent = to.toFixed(1); return; }
    setTimeout(function () {
      (function step(now) { if (mine !== freeRun) return; var t = clamp((now - s - 500) / 1200); freeGb.textContent = (from + (to - from) * ease(t)).toFixed(1); if (t < 1) requestAnimationFrame(step); })(performance.now());
    }, 0);
  }
  function setCleaned(on) {
    if (on === cleaned) return;
    cleaned = on; disk.classList.toggle('cleaned', on); countFree(on ? 72.4 : 33.8);
  }
  once(disk, 0.4, function () {
    disk.classList.add('build');
    setTimeout(function () {
      disk.classList.add('lit'); built = true;
      if (staged) stage(); else setTimeout(function () { setCleaned(true); }, reduced ? 0 : 2600);
    }, reduced ? 0 : 1900);
  });

  // chat tabs: the same answer in whichever tool you use
  document.querySelectorAll('.chat-tabs button').forEach(function (b) {
    b.addEventListener('click', function () {
      document.querySelectorAll('.chat-tabs button').forEach(function (o) { o.setAttribute('aria-pressed', String(o === b)); });
      var bar = document.querySelector('.chat-bar .who'); if (bar) { bar.querySelector('img').src = b.dataset.icon; bar.querySelector('span').textContent = b.textContent + ' · ~/Developer'; }
    });
  });

  var ask = document.getElementById('ask'), typed = document.getElementById('typed');
  once(ask, 0.4, function () {
    var q = 'What’s taking up space on my Mac?', steps = ask.querySelectorAll('.step');
    function reveal() { steps.forEach(function (s, i) { setTimeout(function () { s.classList.add('on'); }, reduced ? 0 : 500 + i * 380); }); }
    if (reduced) { typed.textContent = q; reveal(); return; }
    var i = 0;
    (function type() { typed.textContent = q.slice(0, ++i); if (i < q.length) setTimeout(type, 38); else setTimeout(reveal, 250); })();
  });
})();
