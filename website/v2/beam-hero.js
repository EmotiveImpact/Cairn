/* Cairn website: light-beam hero.
   Beam shader from React Bits "Light Rays" by David Haz (reactbits.dev), MIT + Commons Clause,
   ported from React to plain WebGL2. Sparks and dust are drawn on a 2D canvas. */
// ---- Light beam ----
// Shader from React Bits "Light Rays" by David Haz (reactbits.dev, MIT + Commons Clause),
// ported from the React component to plain WebGL2 and aimed straight down at the app window.
(function () {
  var fx = document.getElementById('fx');
  var raysCanvas = document.getElementById('rays');
  var sparkCanvas = document.getElementById('spark');
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var narrow = window.matchMedia('(max-width:760px)');
  if (!fx) return;
  function hitFraction() { var h = narrow.matches ? 0.88 : 0.78; return (0.12 + h) / 1.24; }
  function placeCore() { fx.style.setProperty('--hitx', (hitFraction() * 100).toFixed(2) + '%'); }
  placeCore();

  var VERTEX = `#version 300 es
const vec2 corners[3] = vec2[3](vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0));
void main() {
  gl_Position = vec4(corners[gl_VertexID], 0.0, 1.0);
}`;
  var FRAGMENT = `#version 300 es
precision highp float;
uniform vec2 uResolution;
uniform float uScale;
uniform float uTime;
uniform vec2 uSource;
uniform vec2 uAim;
uniform float uReach;
uniform vec3 uColor;
uniform float uSpread;
uniform float uLength;
uniform float uFade;
uniform float uSaturation;
uniform float uPulsating;
uniform float uNoise;
uniform float uDistortion;
uniform float uDensity;
uniform float uSharpness;
uniform float uGlow;
uniform float uHaze;
uniform float uAtmosphere;
uniform float uIntensity;
uniform vec4 uShadow;
uniform vec4 uPulses[4];
uniform vec2 uIntro;
uniform float uLight;
uniform float uOpacity;
out vec4 fragColor;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float valueNoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = p - i;
  vec2 w = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), w.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), w.x), w.y);
}

float shape(float strength, float width) {
  float edge = max(mix(0.5, 0.08, uSharpness), width);
  return mix(strength, smoothstep(0.62 - edge, 0.62 + edge, strength), uSharpness);
}

void main() {
  vec2 coord = vec2(gl_FragCoord.x, uResolution.y - gl_FragCoord.y) / uScale;
  vec2 delta = coord - uSource;
  float distance = length(delta);
  vec2 dir = delta / max(distance, 1e-4);
  float cosAngle = dot(dir, uAim);
  float angle = cosAngle + uDistortion * sin(uTime * 2.0 + distance * 0.02) * 0.2;
  float slope = fwidth(angle);
  float depth = distance / uReach;

  float source = exp(-depth * depth * 9.0) * 0.9 + exp(-depth * 3.2) * 0.25;
  float glowLight = uGlow * source * smoothstep(-0.2, 0.6, cosAngle);
  float spread = pow(max(angle, 0.0), 1.0 / uSpread);
  float lengthFalloff = clamp(1.0 - distance / (uReach * uLength), 0.0, 1.0);
  float fadeFalloff = clamp(1.0 - distance / (uReach * uFade), 0.5, 1.0);
  float envelope = spread * lengthFalloff * fadeFalloff;
  float reveal = uIntensity * uIntro.y * (1.0 - smoothstep(uIntro.x - 0.35, uIntro.x, depth));
  if ((envelope * 1.6 + glowLight) * reveal < 0.0015) {
    fragColor = vec4(0.0);
    return;
  }

  float phaseA = angle * 36.2214 * uDensity + uTime * 1.5;
  float phaseB = -angle * 21.11349 * uDensity + uTime * 1.5;
  float phaseC = angle * 22.3991 * uDensity + uTime * 1.1;
  float phaseD = -angle * 18.0234 * uDensity + uTime * 1.1;
  float strengthA = clamp(0.75 + 0.15 * sin(phaseA) + 0.2 * cos(phaseB), 0.0, 1.0);
  float strengthB = clamp(0.75 + 0.15 * sin(phaseC) + 0.2 * cos(phaseD), 0.0, 1.0);
  float widthA = abs(0.15 * 36.2214 * cos(phaseA) + 0.2 * 21.11349 * sin(phaseB)) * uDensity * slope;
  float widthB = abs(0.15 * 22.3991 * cos(phaseC) + 0.2 * 18.0234 * sin(phaseD)) * uDensity * slope;
  float pulseA = uPulsating > 0.5 ? 0.8 + 0.2 * sin(uTime * 4.5) : 1.0;
  float pulseB = uPulsating > 0.5 ? 0.8 + 0.2 * sin(uTime * 3.3) : 1.0;
  float rayLight = envelope * (0.5 * shape(strengthA, widthA) * pulseA + 0.4 * shape(strengthB, widthB) * pulseB);

  if (uHaze > 0.0) {
    float around = atan(uAim.x * dir.y - uAim.y * dir.x, cosAngle);
    vec2 drift = vec2(around * 2.2 + uTime * 0.035, depth * 2.6 - uTime * 0.11);
    float fog = 0.65 * valueNoise(drift * vec2(3.0, 1.0)) + 0.35 * valueNoise(drift * vec2(7.0, 2.3) + 4.1);
    rayLight *= mix(1.0, 0.25 + 1.2 * fog, uHaze);
  }

  if (uShadow.z > 0.0) {
    vec2 toCursor = uShadow.xy - uSource;
    float cursorDistance = length(toCursor);
    float along = dot(delta, toCursor) / max(cursorDistance * cursorDistance, 1e-4);
    float side = abs(delta.x * toCursor.y - delta.y * toCursor.x) / max(cursorDistance, 1e-4);
    float trail = max(along - 1.0, 0.0);
    float width = uShadow.w * along + 0.22 * trail * cursorDistance;
    float behind = smoothstep(0.97, 1.25, along) * exp(-trail * 1.1);
    float shade = (1.0 - smoothstep(width * 0.3, width * 1.6, side)) * behind;
    rayLight *= 1.0 - uShadow.z * 0.62 * shade;
  }

  float boost = 0.0;
  for (int i = 0; i < 4; i++) {
    vec4 wave = uPulses[i];
    if (wave.z <= 0.0) continue;
    float x = (depth - wave.x) / wave.y;
    boost += wave.z * exp(-x * x);
  }
  float light = (rayLight * (1.0 + boost) + glowLight) * reveal;

  if (uNoise > 0.0) {
    float n = fract(sin(dot(coord * 0.02 + uTime * 0.1, vec2(12.9898, 78.233))) * 43758.5453123);
    light *= 1.0 - uNoise + uNoise * n;
  }

  float near = clamp(1.2 - distance / (uResolution.y / uScale), 0.0, 1.0);
  vec3 tint = mix(vec3(0.9), vec3(0.1, 0.3, 0.5) + near * vec3(0.8, 0.6, 0.5), uAtmosphere);
  float gray = dot(tint, vec3(0.299, 0.587, 0.114));
  vec3 hue = max(mix(vec3(gray), tint, uSaturation), 0.0) * uColor;

  float grain = (fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715)))) - 0.5) / 255.0;
  if (uLight > 0.5) {
    vec3 color = hue * light;
    float energy = max(color.r, max(color.g, color.b));
    vec3 tone = clamp(1.0 - (1.0 - hue / max(max(hue.r, max(hue.g, hue.b)), 1e-4)) * 1.8, 0.0, 1.0);
    float warm = clamp((min(tone.r, tone.g) - tone.b) * 2.0, 0.0, 1.0);
    vec3 ink = tone * (mix(0.66, 0.94, warm) - 0.1 * smoothstep(0.4, 1.2, energy));
    float density = clamp(0.82 * (1.0 - exp(-1.5 * energy * energy)) * uOpacity + grain, 0.0, 1.0);
    fragColor = vec4(ink * density, density);
    return;
  }
  float level = light < 0.75 ? light : 0.75 + 0.25 * (1.0 - exp(-(light - 0.75) / 0.25));
  float top = max(hue.r, max(hue.g, hue.b));
  hue = mix(hue, vec3(top), smoothstep(0.8, 1.0, level) * 0.45);
  vec3 shown = clamp(hue * level, 0.0, 1.0) * level;
  fragColor = vec4(clamp(shown + grain, 0.0, level) * uOpacity, level * uOpacity);
}`;

  var cfg = { color: [0.55, 0.77, 1.0], spread: 0.03, length: 1.15, fade: 1.0, density: 1.3, sharpness: 0.55,
              glow: 0.9, haze: 0.45, atmosphere: 0.55, intensity: 1.25, saturation: 1.0, influence: 0.035 };

  var gl = raysCanvas.getContext('webgl2', { alpha: true, premultipliedAlpha: true, antialias: false, depth: false, stencil: false });
  var prog = null, u = {};
  function compile(type, src) { var sh = gl.createShader(type); gl.shaderSource(sh, src); gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) { console.error(gl.getShaderInfoLog(sh)); return null; } return sh; }
  if (gl) {
    var vs = compile(gl.VERTEX_SHADER, VERTEX), fs = compile(gl.FRAGMENT_SHADER, FRAGMENT);
    if (vs && fs) { prog = gl.createProgram(); gl.attachShader(prog, vs); gl.attachShader(prog, fs); gl.linkProgram(prog);
      if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) prog = null; }
    if (prog) { var n = gl.getProgramParameter(prog, gl.ACTIVE_UNIFORMS);
      for (var i = 0; i < n; i++) { var info = gl.getActiveUniform(prog, i); u[info.name.replace(/\[0\]$/, '')] = gl.getUniformLocation(prog, info.name); } }
    var vao = gl.createVertexArray();
  }

  var sctx = sparkCanvas.getContext('2d');
  var W = 1, H = 1, ratio = 1;
  function resize() {
    var r = fx.getBoundingClientRect(); W = Math.max(1, r.width); H = Math.max(1, r.height);
    ratio = Math.min(window.devicePixelRatio || 1, 2, Math.sqrt(2.4e6 / (W * H)));
    raysCanvas.width = Math.round(W * ratio); raysCanvas.height = Math.round(H * ratio);
    sparkCanvas.width = Math.round(W * Math.min(window.devicePixelRatio || 1, 2)); sparkCanvas.height = Math.round(H * Math.min(window.devicePixelRatio || 1, 2));
    sctx.setTransform(sparkCanvas.width / W, 0, 0, sparkCanvas.height / H, 0, 0);
    placeCore();
  }
  new ResizeObserver(resize).observe(fx); resize();

  // pointer gently steers the beam, click sends a pulse down it (as in the original component)
  var pointer = { x: 0.5, seen: false }, aimX = 0, pulses = [], pulseData = new Float32Array(16);
  window.addEventListener('pointermove', function (e) { var r = fx.getBoundingClientRect(); pointer.x = (e.clientX - r.left) / r.width; pointer.seen = true; }, { passive: true });
  window.addEventListener('pointerdown', function () { if (!reduced) { pulses.push({ age: 0 }); if (pulses.length > 4) pulses.shift(); } }, { passive: true });

  // sparks: dust falling down the shaft, and a spray where it hits the window
  var motes = [], sparks = [];
  function newMote(top) { return { x: (Math.random() - 0.5) * (Math.random() * 26), y: top ? 0 : Math.random() * H, v: 30 + Math.random() * 90, r: 0.4 + Math.random() * 1.1, a: 0.25 + Math.random() * 0.6 }; }
  for (var m = 0; m < 110; m++) motes.push(newMote(false));
  function spawnSpark() {
    var dir = Math.random() < 0.5 ? -1 : 1, speed = 40 + Math.random() * 260;
    sparks.push({ x: 0, y: 0, vx: dir * speed * (0.4 + Math.random() * 0.6), vy: -(10 + Math.random() * 120), life: 0, max: 0.6 + Math.random() * 1.6, r: 0.5 + Math.random() * 1.3 });
  }

  var time = 0, last = performance.now(), opening = reduced ? 1 : 0;
  function smoother(t) { t = Math.min(1, Math.max(0, t)); return t * t * t * (t * (t * 6 - 15) + 10); }
  function frame(now) {
    var dt = Math.min(0.05, Math.max(0, (now - last) / 1000)); last = now;
    time += dt * (reduced ? 0.3 : 1);
    if (opening < 1) opening = Math.min(1, opening + dt / 1.8);
    var hx = hitFraction();

    if (prog) {
      var target = pointer.seen ? (pointer.x - hx) : 0;
      aimX += (target * cfg.influence - aimX) * (1 - Math.exp(-dt / 0.25));
      var dl = Math.hypot(aimX, 1);
      for (var p = pulses.length - 1; p >= 0; p--) { pulses[p].age += dt; if (pulses[p].age >= 2) pulses.splice(p, 1); }
      pulseData.fill(0);
      pulses.forEach(function (q, k) { var t = q.age; pulseData[k * 4] = 0.05 + t * 1.05; pulseData[k * 4 + 1] = 0.14 + t * 0.14; pulseData[k * 4 + 2] = 0.9 * smoother(t / 0.15) * (1 - smoother(t / 2)); });
      var eased = 1 - Math.pow(1 - opening, 3);
      gl.viewport(0, 0, raysCanvas.width, raysCanvas.height); gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT);
      gl.useProgram(prog); gl.bindVertexArray(vao);
      gl.uniform2f(u.uResolution, raysCanvas.width, raysCanvas.height); gl.uniform1f(u.uScale, raysCanvas.width / W);
      gl.uniform1f(u.uTime, time); gl.uniform2f(u.uSource, hx * W, -0.12 * H); gl.uniform2f(u.uAim, aimX / dl, 1 / dl);
      gl.uniform1f(u.uReach, Math.max(W, H)); gl.uniform3f(u.uColor, cfg.color[0], cfg.color[1], cfg.color[2]);
      gl.uniform1f(u.uSpread, cfg.spread); gl.uniform1f(u.uLength, cfg.length); gl.uniform1f(u.uFade, cfg.fade);
      gl.uniform1f(u.uSaturation, cfg.saturation); gl.uniform1f(u.uPulsating, 0); gl.uniform1f(u.uNoise, 0); gl.uniform1f(u.uDistortion, 0);
      gl.uniform1f(u.uDensity, cfg.density); gl.uniform1f(u.uSharpness, cfg.sharpness); gl.uniform1f(u.uGlow, cfg.glow);
      gl.uniform1f(u.uHaze, cfg.haze); gl.uniform1f(u.uAtmosphere, cfg.atmosphere); gl.uniform1f(u.uIntensity, cfg.intensity);
      gl.uniform4f(u.uShadow, 0, 0, 0, 16); gl.uniform4fv(u.uPulses, pulseData);
      gl.uniform2f(u.uIntro, eased * 2.6, smoother(opening / 0.5)); gl.uniform1f(u.uLight, 0); gl.uniform1f(u.uOpacity, 1);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    // sparks layer
    var cx = hx * W;
    sctx.clearRect(0, 0, W, H);
    sctx.globalCompositeOperation = 'lighter';
    var flicker = 0.85 + 0.15 * Math.sin(time * 7.3) * Math.sin(time * 3.1);
    var g = sctx.createRadialGradient(cx, H, 0, cx, H, 230);
    g.addColorStop(0, 'rgba(235,246,255,' + (0.9 * flicker * opening) + ')');
    g.addColorStop(0.08, 'rgba(160,210,255,' + (0.55 * flicker * opening) + ')');
    g.addColorStop(0.35, 'rgba(60,140,240,' + (0.18 * opening) + ')');
    g.addColorStop(1, 'rgba(47,127,224,0)');
    sctx.save(); sctx.translate(cx, H); sctx.scale(1.9, 0.55); sctx.translate(-cx, -H);
    sctx.fillStyle = g; sctx.fillRect(cx - 240, H - 240, 480, 480); sctx.restore();
    if (!reduced) {
      for (var s2 = 0; s2 < 5; s2++) if (sparks.length < 240) spawnSpark();
    }
    for (var i2 = sparks.length - 1; i2 >= 0; i2--) {
      var k = sparks[i2]; k.life += dt;
      if (k.life > k.max) { sparks.splice(i2, 1); continue; }
      k.vx *= 1 - dt * 1.4; k.vy += 90 * dt; k.x += k.vx * dt; k.y = Math.min(0, k.y + k.vy * dt);
      var fade = 1 - k.life / k.max;
      sctx.fillStyle = 'rgba(215,236,255,' + Math.min(1, fade * 1.3 * opening) + ')';
      sctx.beginPath(); sctx.arc(cx + k.x, H - 1 + k.y, k.r, 0, 6.283); sctx.fill();
    }
    for (var j = 0; j < motes.length; j++) {
      var mo = motes[j];
      if (!reduced) { mo.y += mo.v * dt; if (mo.y > H) motes[j] = mo = newMote(true); }
      var depth = mo.y / H;
      sctx.fillStyle = 'rgba(190,225,255,' + (mo.a * depth * depth * opening) + ')';
      sctx.beginPath(); sctx.arc(cx + mo.x * (0.3 + depth), mo.y, mo.r, 0, 6.283); sctx.fill();
    }
    sctx.globalCompositeOperation = 'source-over';
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();
