// story.html: the shimmer sky that gathers into the big number, and each chapter's
// arrival (reveals, the count, the disk lighting up, the chat typing itself out).
(function () {
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  function clamp(v) { return Math.min(1, Math.max(0, v)); }
  function ease(t) { return 1 - Math.pow(1 - t, 3); }

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
      // 0 at the top of the page, 1 when the number chapter fills the screen
      var p = ease(clamp(scrollY / Math.max(1, number.offsetTop)));
      var out = clamp((scrollY - number.offsetTop) / (innerHeight * 0.55));
      var n = narrow(), cy = (n ? 0.83 : 0.74) - (n ? 0.33 : 0.24) * p - 0.1 * out;
      var sx = (n ? 0.42 : 0.26) - (n ? 0.24 : 0.14) * p, sy = (n ? 0.12 : 0.2) - 0.06 * p;
      gl.uniform2f(U.res, canvas.width, canvas.height); gl.uniform1f(U.t, (now - t0) / 1000);
      gl.uniform2f(U.centre, 0.5, cy); gl.uniform2f(U.size, sx, sy); gl.uniform1f(U.fade, (1 - out) * (0.9 + 0.3 * p));
      gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT);
      if (out < 1) gl.drawArrays(gl.TRIANGLES, 0, 3);
      if (!reduced) requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
    if (reduced) window.addEventListener('scroll', function () { requestAnimationFrame(frame); }, { passive: true });
  }

  // ---- chapter arrivals ----
  function once(el, threshold, fn) {
    if (!el) return;
    if (reduced) { fn(); return; }
    new IntersectionObserver(function (es, io) { if (es[0].isIntersecting) { io.disconnect(); fn(); } }, { threshold: threshold }).observe(el);
  }
  document.querySelectorAll('.chapter').forEach(function (c) { once(c, 0.25, function () { c.classList.add('in'); }); });

  var count = document.getElementById('count');
  once(number, 0.5, function () {
    if (reduced) { count.textContent = '38.6'; return; }
    var s = performance.now();
    (function step(now) { var t = clamp((now - s) / 1800); count.textContent = (38.6 * ease(t)).toFixed(1); if (t < 1) requestAnimationFrame(step); })(s);
  });

  var disk = document.getElementById('disk');
  once(disk, 0.4, function () { setTimeout(function () { disk.classList.add('lit'); }, reduced ? 0 : 1100); });

  var ask = document.getElementById('ask'), typed = document.getElementById('typed');
  once(ask, 0.4, function () {
    var q = 'What’s taking up space on my Mac?', steps = ask.querySelectorAll('.step');
    function reveal() { steps.forEach(function (s, i) { setTimeout(function () { s.classList.add('on'); }, reduced ? 0 : 500 + i * 380); }); }
    if (reduced) { typed.textContent = q; reveal(); return; }
    var i = 0;
    (function type() { typed.textContent = q.slice(0, ++i); if (i < q.length) setTimeout(type, 38); else setTimeout(reveal, 250); })();
  });
})();
