// story.html: the opening scene, the stacked chapters, and each chapter's
// arrival (reveals, the count, the disk lighting up, the chat typing itself out).
(function () {
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  document.body.classList.add('story-page');
  // review only: the data tunnel (default), each hero photo, or the earlier swirl
  var o = document.getElementById('open'), ph = o && o.querySelector('.open-photo');
  function pick(name) {
    if (!o) return;
    o.classList.toggle('look-photo', name !== 'swirl');
    if (name !== 'swirl' && name !== 'tunnel') ph.src = 'assets/hero/cairn-hero-' + name + '.jpg';
    o.dataset.photo = name;
    o.querySelectorAll('.photo-switch button').forEach(function (b) { b.setAttribute('aria-pressed', String(b.dataset.photo === name)); });
    if (name === 'swirl' && window.startScene) window.startScene();
    if (name === 'tunnel' && window.startTunnel) window.startTunnel();
  }
  if (o) o.querySelectorAll('.photo-switch button').forEach(function (b) { b.addEventListener('click', function () { pick(b.dataset.photo); }); });
  if (/^#(profile|desk|window|swirl)$/.test(location.hash)) pick(location.hash.slice(1));
  function clamp(v) { return Math.min(1, Math.max(0, v)); }
  function ease(t) { return 1 - Math.pow(1 - t, 3); }

  // ---- the stack: chapters hold still and dissolve into one another ----
  var track = document.querySelector('.stage-track');
  var layers = track ? [].slice.call(track.querySelectorAll('.stage > .chapter')) : [];
  var staged = !!track && !reduced && innerWidth >= 760 && innerHeight >= 600;
  var stageAt = 0;            // 0 = opening, 1 = number, 2 = disk, 3 = ask
  var arrive = [];            // callbacks per chapter, run the first time it settles
  var here = [], at = [];     // enter/leave pairs per chapter, run each time it settles or leaves
  if (staged) document.body.classList.add('staged');
  function lerp(a, b, t) { return a + (b - a) * t; }
  function stage() {
    if (!staged) return;
    var len = track.offsetHeight - innerHeight;
    stageAt = clamp((scrollY - track.offsetTop) / Math.max(1, len)) * (layers.length - 1);
    layers.forEach(function (el, i) {
      var d = stageAt - i;
      var inn = i === 0 ? 1 : clamp((d + 0.6) / 0.4);        // dissolves in from d = -0.6 to -0.2
      var out = i === layers.length - 1 ? 0 : clamp((d - 0.2) / 0.4); // and out from 0.2 to 0.6
      var o = Math.min(inn, 1 - out);
      el.style.opacity = o.toFixed(3);
      el.style.filter = 'blur(' + ((1 - inn) * 14 + out * 8).toFixed(1) + 'px)';
      el.style.transform = 'scale(' + (lerp(1.04, 1, inn) * lerp(1, 0.94, out)).toFixed(4) + ') translateY(' + (-out * 28).toFixed(1) + 'px)';
      el.style.pointerEvents = o > 0.5 ? 'auto' : 'none';
      el.style.visibility = o < 0.01 ? 'hidden' : 'visible';
      if (Math.abs(d) < 0.2 && arrive[i]) { var fs = arrive[i]; arrive[i] = null; fs.forEach(function (f) { f(); }); }
      if (here[i] && !at[i] && Math.abs(d) < 0.06) { at[i] = true; here[i].forEach(function (p) { p[0](); }); }
      if (here[i] && at[i] && Math.abs(d) > 0.7) { at[i] = false; here[i].forEach(function (p) { p[1](); }); }
    });
  }
  if (staged) { window.addEventListener('scroll', stage, { passive: true }); window.addEventListener('resize', stage); stage(); }

  var open = document.getElementById('open'), number = document.getElementById('number');



  // ---- opening scene: a dusk sky with a slow swirl of light over dark hills ----
  window.startScene = function () {
  if (window.startScene.done) return; window.startScene.done = true;
  var scene = document.getElementById('scene');
  var sg = scene && scene.getContext('webgl', { premultipliedAlpha: false, antialias: false });
  if (sg) {
    var sfs = [
      'precision highp float;',
      'uniform vec2 res; uniform float t;',
      'float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }',
      'float n(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);',
      '  return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }',
      'float fbm(vec2 p){ float v = 0.0, a = 0.5; for (int i = 0; i < 5; i++) { v += a * n(p); p *= 2.03; a *= 0.5; } return v; }',
      'void main(){',
      '  vec2 uv = gl_FragCoord.xy / res; float ar = res.x / res.y;',
      '  float hz = 0.5;',
      // sky: deep blue above, soft lavender haze at the horizon
      '  vec3 col = mix(vec3(0.30, 0.34, 0.47), vec3(0.06, 0.08, 0.13), smoothstep(hz, 1.05, uv.y));',
      '  col += vec3(0.10, 0.10, 0.16) * fbm(vec2(uv.x * 2.0 + t * 0.006, uv.y * 5.0)) * smoothstep(1.0, hz, uv.y);',
      // the swirl: rings of light in perspective, turning faster near the middle
      '  vec2 c = vec2(0.56, 0.66); vec2 q = uv - c; q.x *= ar; q.y /= 0.21;',
      '  float r = length(q), a = atan(q.y, q.x);',
      '  float a2 = a + t * 0.06 / (r + 0.25) + r * 2.2;',
      '  float ring = pow(0.5 + 0.5 * sin(r * 150.0 + fbm(vec2(cos(a2), sin(a2)) * 1.6 + r * 4.0) * 8.0), 34.0);',
      '  float arcs = smoothstep(0.38, 0.8, fbm(vec2(cos(a2), sin(a2)) * 3.2 + vec2(r * 14.0, -r * 9.0)));',
      '  float env = smoothstep(0.08, 0.3, r) * exp(-pow(max(r - 0.35, 0.0) * 2.4, 2.0)) * smoothstep(1.2, 0.5, r);',
      '  float glow = exp(-r * r * 6.0) * 0.35;',
      '  float sw = (ring * arcs * 1.9 + arcs * 0.12 + glow) * env + glow * 0.4;',
      '  sw *= smoothstep(hz - 0.02, hz + 0.06, uv.y);',
      '  col += vec3(0.80, 0.88, 1.0) * sw;',
      // a calm, misty plain under the horizon
      '  float plain = smoothstep(hz + 0.005, hz - 0.005, uv.y);',
      '  vec3 pc = mix(vec3(0.22, 0.25, 0.36), vec3(0.12, 0.14, 0.21), smoothstep(hz, hz - 0.2, uv.y));',
      '  pc += 0.05 * fbm(vec2(uv.x * 8.0 - t * 0.01, uv.y * 40.0));',
      '  col = mix(col, pc, plain);',
      '  col += vec3(0.20, 0.22, 0.32) * exp(-pow((uv.y - hz) * 22.0, 2.0)) * 0.6;',
      // dark rolling hills in front
      '  float hill = 0.30 + 0.07 * fbm(vec2(uv.x * 2.2 + 3.0, 1.0)) - 0.14 * pow(abs(uv.x - 0.6), 1.6) + 0.012 * n(vec2(uv.x * 60.0, 2.0));',
      '  float hm = smoothstep(hill + 0.004, hill - 0.004, uv.y);',
      '  float tex = fbm(vec2(uv.x * 70.0, uv.y * 110.0));',
      '  vec3 hc = mix(vec3(0.05, 0.06, 0.09), vec3(0.34, 0.33, 0.47), smoothstep(hill - 0.3, hill, uv.y) * (0.35 + 0.65 * tex) + tex * 0.15);',
      '  col = mix(col, hc, hm);',
      '  float hill2 = 0.40 + 0.03 * fbm(vec2(uv.x * 4.0 + 9.0, 3.0)) + 0.05 * smoothstep(0.75, 1.0, uv.x);',
      '  float hm2 = smoothstep(hill2 + 0.003, hill2 - 0.003, uv.y) * (1.0 - hm);',
      '  col = mix(col, vec3(0.13, 0.15, 0.22) + 0.04 * tex, hm2 * 0.85);',
      '  col *= 1.0 - 0.35 * pow(length((uv - 0.5) * vec2(1.0, 1.2)), 2.0);',
      '  col += (h(gl_FragCoord.xy + fract(t)) - 0.5) * 0.025;',
      '  gl_FragColor = vec4(col, 1.0);',
      '}'
    ].join('\n');
    var sv = sg.createShader(sg.VERTEX_SHADER); sg.shaderSource(sv, 'attribute vec2 p; void main(){ gl_Position = vec4(p, 0.0, 1.0); }'); sg.compileShader(sv);
    var sf = sg.createShader(sg.FRAGMENT_SHADER); sg.shaderSource(sf, sfs); sg.compileShader(sf);
    var sp = sg.createProgram(); sg.attachShader(sp, sv); sg.attachShader(sp, sf); sg.linkProgram(sp); sg.useProgram(sp);
    sg.bindBuffer(sg.ARRAY_BUFFER, sg.createBuffer()); sg.bufferData(sg.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), sg.STATIC_DRAW);
    sg.enableVertexAttribArray(0); sg.vertexAttribPointer(0, 2, sg.FLOAT, false, 0, 0);
    var sres = sg.getUniformLocation(sp, 'res'), st = sg.getUniformLocation(sp, 't');
    var sresize = function () {
      var dpr = Math.min(window.devicePixelRatio || 1, 1.5);
      scene.width = Math.round(scene.clientWidth * dpr); scene.height = Math.round(scene.clientHeight * dpr); sg.viewport(0, 0, scene.width, scene.height);
    };
    window.addEventListener('resize', sresize); sresize();
    var s0 = performance.now() - 40000;
    var sframe = function (now) {
      // only draw while the opening can be seen
      if (staged ? stageAt < 1 : scrollY < innerHeight * 1.2) {
        sg.uniform2f(sres, scene.width, scene.height); sg.uniform1f(st, (now - s0) / 1000); sg.drawArrays(sg.TRIANGLES, 0, 3);
      }
      if (!reduced) requestAnimationFrame(sframe);
    };
    requestAnimationFrame(sframe);
  }
  };
  if (o && !o.classList.contains('look-photo')) window.startScene();

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

  var disk = document.getElementById('disk');
  once(disk, 0.4, function () { setTimeout(function () { disk.classList.add('lit'); }, reduced ? 0 : 1100); });

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
