// story.html: the shimmer sky that gathers into the big number, and each chapter's
// arrival (reveals, the count, the disk lighting up, the chat typing itself out).
(function () {
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  document.body.classList.add('story-page');
  function clamp(v) { return Math.min(1, Math.max(0, v)); }
  function ease(t) { return 1 - Math.pow(1 - t, 3); }

  // ---- the stack: chapters hold still and dissolve into one another ----
  var track = document.querySelector('.stage-track');
  var layers = track ? [].slice.call(track.querySelectorAll('.stage > .chapter')) : [];
  var staged = !!track && !reduced && innerWidth >= 760 && innerHeight >= 600;
  var stageAt = 0;            // 0 = opening, 1 = number, 2 = disk, 3 = ask
  var arrive = [];            // callbacks per chapter, run the first time it settles
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
    });
  }
  if (staged) { window.addEventListener('scroll', stage, { passive: true }); window.addEventListener('resize', stage); stage(); }

  // ---- shimmer sky: thin vertical light streaks, one WebGL fragment shader ----
  var canvas = document.getElementById('sky');
  var gl = canvas && canvas.getContext('webgl', { alpha: true, premultipliedAlpha: false });
  var open = document.getElementById('open'), number = document.getElementById('number');
  if (gl && open && number) {
    var FS = [
      'precision highp float;',
      'uniform vec2 res; uniform float t; uniform vec2 centre; uniform vec2 size; uniform float fade;',
      'float h(float n){ return fract(sin(n * 127.1) * 43758.5453); }',
      'float n1(float x){ float i = floor(x), f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(h(i), h(i + 1.0), f); }',
      'vec3 layer(vec2 uv, float cols, float seed, float speed){',
      '  float x = uv.x * cols; float c = floor(x) + seed; float lx = fract(x) - 0.5;',
      '  float a = h(c), b = h(c + 3.1), d = h(c + 7.7), e = h(c + 11.3);',
      '  float w = 0.04 + 0.1 * a;',
      '  float line = exp(-abs(lx) / w * 2.2) + 0.18 * exp(-abs(lx) * 3.0);',
      '  float cy = centre.y + (b - 0.5) * size.y * 0.9 + 0.03 * sin(t * 0.4 * speed + a * 6.28);',
      '  float len = size.y * (0.25 + 0.75 * d);',
      '  float seg = smoothstep(len, 0.0, abs(uv.y - cy));',
      '  float spark = pow(n1(uv.y * (30.0 + 40.0 * e) - t * speed * (0.6 + a) + c * 4.0), 2.5);',
      '  float flick = 0.45 + 0.55 * sin(t * (0.8 + 2.4 * e) + a * 20.0);',
      '  float boost = 0.4 + 2.6 * pow(h(c + 19.7), 4.0);',
      '  float v = line * seg * (0.3 + 1.8 * spark) * flick * boost;',
      '  vec3 col = mix(vec3(0.35, 0.55, 1.0), vec3(0.3, 0.85, 1.0), step(0.6, e));',
      '  col = mix(col, vec3(0.3, 1.0, 0.55), step(0.88, b) * 0.85);',
      '  return col * v;',
      '}',
      'void main(){',
      '  vec2 uv = gl_FragCoord.xy / res; uv.y = 1.0 - uv.y;',
      '  float ar = res.x / res.y; vec2 q = (uv - centre) / size; q.x *= 1.0;',
      '  float mask = exp(-(q.x * q.x * 2.2 + q.y * q.y * 3.0));',
      '  float core = exp(-(q.x * q.x * 6.0 + q.y * q.y * 6.0));',
      '  vec2 st = vec2((uv.x - centre.x) * min(1.0, 0.26 / size.x) + centre.x, uv.y);',
      '  vec3 col = layer(st, 70.0, 1.0, 1.0) + 0.8 * layer(st, 130.0, 50.0, 1.4) + 0.5 * layer(st, 210.0, 90.0, 1.9);',
      '  col *= (mask + core * 1.5) * 7.0;',
      '  col += mask * mask * vec3(0.05, 0.12, 0.3) * 1.6;',
      '  col = (1.0 - exp(-col * 1.2)) * fade;',
      '  gl_FragColor = vec4(col, clamp(max(col.r, max(col.g, col.b)) * 1.4, 0.0, 1.0));',
      '}'].join('\n');
    var VS = 'attribute vec2 p; void main(){ gl_Position = vec4(p, 0.0, 1.0); }';
    var sh = function (type, src) { var s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); return s; };
    var prog = gl.createProgram(); gl.attachShader(prog, sh(gl.VERTEX_SHADER, VS)); gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, FS)); gl.linkProgram(prog); gl.useProgram(prog);
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer()); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    var loc = gl.getAttribLocation(prog, 'p'); gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    var U = {}; ['res', 't', 'centre', 'size', 'fade'].forEach(function (n) { U[n] = gl.getUniformLocation(prog, n); });
    var resize = function () {
      var dpr = Math.min(window.devicePixelRatio || 1, 1.5);
      canvas.width = Math.round(innerWidth * dpr); canvas.height = Math.round(innerHeight * dpr); gl.viewport(0, 0, canvas.width, canvas.height);
    };
    window.addEventListener('resize', resize); resize();
    var t0 = performance.now(), narrow = function () { return innerWidth < 760; };
    var frame = function (now) {
      // 0 at the top of the page, 1 when the number chapter fills the screen; the streaks only show on the number
      var p = staged ? ease(clamp(stageAt)) : ease(clamp(scrollY / Math.max(1, number.offsetTop)));
      var out = staged ? clamp((stageAt - 1.15) / 0.4) : clamp((scrollY - number.offsetTop) / (innerHeight * 0.55));
      var n = narrow(), cy = (n ? 0.4 : 0.42) + (n ? 0.1 : 0.08) * p - 0.1 * out;
      var sx = (n ? 0.5 : 0.36) - (n ? 0.3 : 0.24) * p, sy = (n ? 0.24 : 0.3) - (n ? 0.1 : 0.16) * p;
      gl.uniform2f(U.res, canvas.width, canvas.height); gl.uniform1f(U.t, (now - t0) / 1000);
      gl.uniform2f(U.centre, 0.5, cy); gl.uniform2f(U.size, sx, sy); var inn = clamp((p - 0.3) / 0.6); gl.uniform1f(U.fade, (1 - out) * inn * inn * 1.2);
      gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT);
      if (out < 1 && inn > 0) gl.drawArrays(gl.TRIANGLES, 0, 3);
      if (!reduced) requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
    if (reduced) window.addEventListener('scroll', function () { requestAnimationFrame(frame); }, { passive: true });
  }


  // ---- opening scene: a dusk sky with a slow swirl of light over dark hills ----
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

  // ---- chapter arrivals ----
  function once(el, threshold, fn) {
    if (!el) return;
    if (reduced) { fn(); return; }
    var k = layers.indexOf(el);
    if (staged && k >= 0) { (arrive[k] = arrive[k] || []).push(fn); setTimeout(stage); return; }
    new IntersectionObserver(function (es, io) { if (es[0].isIntersecting) { io.disconnect(); fn(); } }, { threshold: threshold }).observe(el);
  }
  document.querySelectorAll('.chapter').forEach(function (c) { once(c, 0.25, function () { c.classList.add('in'); }); });

  var count = document.getElementById('count');
  once(number, 0.5, function () {
    if (reduced) { count.textContent = '38.6'; number.classList.add('done'); return; }
    var s = performance.now();
    (function step(now) { var t = clamp((now - s) / 1800); count.textContent = (38.6 * ease(t)).toFixed(1); if (t < 1) requestAnimationFrame(step); else number.classList.add('done'); })(s);
  });

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
