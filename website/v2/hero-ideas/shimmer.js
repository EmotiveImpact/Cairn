// Shimmer: a cluster of thin vertical light streaks that flicker and drift,
// tinted ice blue with touches of cyan and green. One WebGL fragment shader.
(function () {
  var canvas = document.getElementById('shimmer');
  if (!canvas) return;
  var gl = canvas.getContext('webgl', { premultipliedAlpha: false, alpha: true });
  if (!gl) return;
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var VS = 'attribute vec2 p; void main(){ gl_Position = vec4(p, 0.0, 1.0); }';
  var FS = [
    'precision highp float;',
    'uniform vec2 res; uniform float t; uniform vec2 centre; uniform vec2 size;',
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
    '  vec3 blue = vec3(0.35, 0.55, 1.0), cyan = vec3(0.3, 0.85, 1.0), green = vec3(0.3, 1.0, 0.55);',
    '  vec3 col = mix(blue, cyan, step(0.6, e));',
    '  col = mix(col, green, step(0.88, b) * 0.85);',
    '  return col * v;',
    '}',
    'void main(){',
    '  vec2 uv = gl_FragCoord.xy / res; uv.y = 1.0 - uv.y;',
    '  vec2 q = (uv - centre) / size;',
    '  float mask = exp(-(q.x * q.x * 2.2 + q.y * q.y * 3.0));',
    '  vec3 col = layer(uv, 70.0, 1.0, 1.0) + 0.8 * layer(uv, 130.0, 50.0, 1.4) + 0.5 * layer(uv, 210.0, 90.0, 1.9);',
    '  float core = exp(-(q.x * q.x * 6.0 + q.y * q.y * 6.0));',
    '  col *= (mask + core * 1.5) * 7.0;',
    '  col += mask * mask * vec3(0.05, 0.12, 0.3) * 1.6;',
    '  col = 1.0 - exp(-col * 1.2);',
    '  float a = clamp(max(col.r, max(col.g, col.b)) * 1.4, 0.0, 1.0);',
    '  gl_FragColor = vec4(col, a);',
    '}'].join('\n');
  function sh(type, src) { var s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) console.error(gl.getShaderInfoLog(s)); return s; }
  var prog = gl.createProgram(); gl.attachShader(prog, sh(gl.VERTEX_SHADER, VS)); gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, FS)); gl.linkProgram(prog); gl.useProgram(prog);
  var buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  var loc = gl.getAttribLocation(prog, 'p'); gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
  var uRes = gl.getUniformLocation(prog, 'res'), uT = gl.getUniformLocation(prog, 't'), uC = gl.getUniformLocation(prog, 'centre'), uS = gl.getUniformLocation(prog, 'size');
  function resize() {
    var r = canvas.getBoundingClientRect(), dpr = Math.min(window.devicePixelRatio || 1, 1.5);
    canvas.width = Math.max(1, Math.round(r.width * dpr)); canvas.height = Math.max(1, Math.round(r.height * dpr));
    gl.viewport(0, 0, canvas.width, canvas.height);
  }
  function cfg() {
    var cs = getComputedStyle(canvas);
    var cx = parseFloat(cs.getPropertyValue('--cx')) || 0.5, cy = parseFloat(cs.getPropertyValue('--cy')) || 0.5;
    var sx = parseFloat(cs.getPropertyValue('--sx')) || 0.28, sy = parseFloat(cs.getPropertyValue('--sy')) || 0.3;
    return [cx, cy, sx, sy];
  }
  var t0 = performance.now(), c = cfg();
  function frame(now) {
    gl.uniform2f(uRes, canvas.width, canvas.height); gl.uniform1f(uT, (now - t0) / 1000);
    gl.uniform2f(uC, c[0], c[1]); gl.uniform2f(uS, c[2], c[3]);
    gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT); gl.drawArrays(gl.TRIANGLES, 0, 3);
    if (!reduced) requestAnimationFrame(frame);
  }
  new ResizeObserver(function () { resize(); c = cfg(); }).observe(canvas);
  resize(); requestAnimationFrame(frame);
})();
