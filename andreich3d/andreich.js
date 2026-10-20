// Андреич — киберенот в реальном времени (three.js).
// Мех — оболочки (shell fur) одним instanced-вызовом на часть, плащ — ткань на verlet,
// хвост — пружинная цепочка, все позы — процедурная анимация с плавным переходом.
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

const COL = {
  tiffany: new THREE.Color(0x0abab5),
  glow: new THREE.Color(0x63fff2),
  red: new THREE.Color(0xd8101a),
  furGray: new THREE.Color(0x8c8a90),
  furLight: new THREE.Color(0xe6e4e6),
  furDark: new THREE.Color(0x2a272b),
  furBrown: new THREE.Color(0x6b5f57),
  jacket: new THREE.Color(0x15161b),
  metal: new THREE.Color(0xb4bcc6),
};
const KEY_DIR = new THREE.Vector3(0.45, 0.8, 0.55).normalize();
const RIM = new THREE.Color(0x7fe9e2);

/// Вторая расцветка — под oaiweb.ru: неон не бирюзовый, а фирменный красный.
export function applyTheme(name) {
  if (name === 'oaiweb') {
    COL.tiffany.setHex(0xe1251b); COL.glow.setHex(0xff6a56); RIM.setHex(0xffb3a6);
    // ребрендинг под сайт: кремовый зверь, чёрная маска, тёплые лапы
    COL.furGray.setHex(0xe3dccb); COL.furLight.setHex(0xf6f1e4);
    COL.furDark.setHex(0x1d1715); COL.furBrown.setHex(0x9c8468);
  }
}

// ───────────────────────── мех ─────────────────────────
const FUR_VS = /* glsl */`
  uniform float uLen; uniform float uLayers; uniform vec3 uDroop;
  varying vec3 vN; varying vec3 vW; varying vec3 vObj; varying float vH;
  void main() {
    float h = float(gl_InstanceID) / uLayers;
    vec3 p = position + normal * uLen * h + uDroop * (h * h) * uLen;
    vH = h; vObj = position;
    vec4 w = modelMatrix * vec4(p, 1.0);
    vW = w.xyz;
    vN = normalize(mat3(modelMatrix) * normal);
    gl_Position = projectionMatrix * viewMatrix * w;
  }`;
const FUR_FS = /* glsl */`
  layout(location = 0) out highp vec4 pc_fragColor;
  #define gl_FragColor pc_fragColor
  uniform vec3 uKey; uniform vec3 uRim; uniform float uDensity; uniform int uPart; uniform float uHard;
  uniform vec3 cGray; uniform vec3 cLight; uniform vec3 cDark; uniform vec3 cBrown; uniform vec3 cBase;
  varying vec3 vN; varying vec3 vW; varying vec3 vObj; varying float vH;
  float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
  vec3 headColor(vec3 o) {
    // лицо смотрит в +z; маска «бандита», светлые брови, морда и щёки
    vec3 c = cGray;
    float front = smoothstep(0.15, 0.55, o.z);
    vec3 a3 = vec3(abs(o.x), o.y, o.z);
    vec2 dm = (a3.xy - vec2(0.38, 0.1)) * vec2(0.72, 1.2);
    dm.y += (a3.x - 0.38) * 0.45;
    float mask = smoothstep(0.02, 0.32, o.z) * (1.0 - smoothstep(0.3, 0.42, length(dm)));
    float cheekDrop = front * smoothstep(0.18, 0.05, abs(o.x) - 0.42) * smoothstep(0.1, -0.15, o.y) * smoothstep(-0.55, -0.3, o.y);
    float brow = smoothstep(0.17, 0.10, distance(vec3(abs(o.x), o.y, o.z), vec3(0.34, 0.42, 0.80)));
    float muzzle = smoothstep(-0.12, -0.3, o.y) * smoothstep(0.5, 0.78, o.z);
    float stripe = front * smoothstep(0.1, 0.05, abs(o.x)) * smoothstep(0.02, 0.2, o.y) * smoothstep(0.7, 0.5, o.y);
    float topLight = smoothstep(0.55, 0.95, o.y) * 0.25;
    c = mix(c, cLight, topLight);
    c = mix(c, cLight, max(muzzle, brow));
    c = mix(c, cDark * 0.28, max(mask, max(stripe * 0.95, cheekDrop * 0.7)));
    return c;
  }
  void main() {
    vec3 g = vObj * uDensity;
    vec3 cell = floor(g);
    float strand = hash(cell);
    vec3 f = fract(g) - 0.5;
    float alpha = 1.0;
    if (vH > 0.02) {
      float r0 = mix(0.66, 0.1, vH);
      alpha = step(vH * 0.93, strand) * (1.0 - smoothstep(r0 - 0.12, r0 + 0.06, length(f)));
      if (uPart == 0) {   // мех вокруг глаз короче, чтобы глаза не тонули
        vec3 ao3 = vec3(abs(vObj.x), vObj.y, vObj.z);
        float eyeHole = 1.0 - smoothstep(0.16, 0.24, distance(ao3, vec3(0.36, 0.14, 0.92)));
        alpha *= 1.0 - eyeHole * step(0.12, vH);
      }
      if (uHard > 0.5) { if (alpha < 0.45) discard; alpha = 1.0; }
      else if (alpha < 0.03) discard;
    }
    vec3 base = uPart == 0 ? headColor(vObj) : cBase;
    base *= 0.88 + 0.24 * hash(cell + 7.0);
    vec3 N = normalize(vN);
    vec3 V = normalize(cameraPosition - vW);
    float diff = max(dot(N, uKey), 0.0);
    float wrap = max(dot(N, uKey) * 0.5 + 0.5, 0.0);
    float ao = mix(0.35, 1.0, vH * vH * 0.6 + vH * 0.4);
    float rim = pow(1.0 - max(dot(N, V), 0.0), 2.5);
    vec3 col = base * (0.28 + 0.55 * wrap + 0.45 * diff) * ao;
    col += uRim * rim * (0.35 + 0.65 * vH) * 0.55;
    col += cBase * 0.0;
    gl_FragColor = vec4(col, alpha);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }`;

export const QUALITY = { layers: 1 };
function furMaterial(part, base, { len = 0.07, layers = 22, density = 70, droop = [0, -0.6, 0] } = {}) {
  layers = Math.max(6, Math.round(layers * QUALITY.layers));
  return new THREE.ShaderMaterial({
    glslVersion: THREE.GLSL3,
    vertexShader: FUR_VS,
    fragmentShader: FUR_FS,
    uniforms: {
      uLen: { value: len }, uLayers: { value: layers }, uDroop: { value: new THREE.Vector3(...droop) },
      uKey: { value: KEY_DIR }, uRim: { value: RIM.clone() }, uDensity: { value: density }, uPart: { value: part }, uHard: { value: 0 },
      cGray: { value: COL.furGray }, cLight: { value: COL.furLight }, cDark: { value: COL.furDark }, cBrown: { value: COL.furBrown },
      cBase: { value: base.clone() },
    },
    alphaToCoverage: true,
  });
}

function furMesh(geo, mat) {
  const layers = mat.uniforms.uLayers.value;
  const m = new THREE.InstancedMesh(geo, mat, layers + 1);
  m.frustumCulled = false;
  return m;
}

// ───────────────────────── свечение ─────────────────────────
let glowTex;
function glowTexture() {
  if (glowTex) return glowTex;
  const c = document.createElement('canvas'); c.width = c.height = 128;
  const g = c.getContext('2d');
  const gr = g.createRadialGradient(64, 64, 0, 64, 64, 64);
  gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.25, 'rgba(255,255,255,0.55)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
  glowTex = new THREE.CanvasTexture(c);
  return glowTex;
}
function glowSprite(size, color = COL.glow, opacity = 0.75) {
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTexture(), color, transparent: true, opacity, blending: THREE.AdditiveBlending, depthWrite: false }));
  s.scale.set(size, size, 1);
  return s;
}
const neon = (c = COL.glow) => new THREE.MeshBasicMaterial({ color: c, toneMapped: false });

// ───────────────────────── знак OAI WEB ─────────────────────────
let logoTex;
function logoTexture() {
  if (logoTex) return logoTex;
  const c = document.createElement('canvas'); c.width = c.height = 128; const g = c.getContext('2d');
  g.fillStyle = '#151010'; roundRect(g, 4, 4, 120, 120, 22); g.fill();
  g.strokeStyle = '#0abab5'; g.lineWidth = 5; roundRect(g, 4, 4, 120, 120, 22); g.stroke();
  g.fillStyle = '#e5121b'; g.beginPath(); g.moveTo(14, 112); g.lineTo(76, 18); g.lineTo(100, 18); g.lineTo(38, 112); g.closePath(); g.fill();
  g.fillStyle = '#ece5d6'; g.beginPath(); g.arc(92, 34, 9, 0, Math.PI * 2); g.fill();
  logoTex = new THREE.CanvasTexture(c); logoTex.colorSpace = THREE.SRGBColorSpace;
  return logoTex;
}

// ───────────────────────── эмблема на плаще ─────────────────────────
function capeTexture() {
  const c = document.createElement('canvas'); c.width = 512; c.height = 512;
  const g = c.getContext('2d');
  g.fillStyle = '#c8101a'; g.fillRect(0, 0, 512, 512);
  for (let i = 0; i < 2600; i++) { g.fillStyle = `rgba(0,0,0,${Math.random() * 0.06})`; g.fillRect(Math.random() * 512, Math.random() * 512, 2, 2); }
  // знак OAI WEB: тёмный скруглённый квадрат, красная диагональ, кремовая точка
  g.save(); g.translate(256, 190);
  g.fillStyle = '#151010'; roundRect(g, -78, -78, 156, 156, 26); g.fill();
  g.fillStyle = '#e5121b'; g.beginPath(); g.moveTo(-72, 72); g.lineTo(18, -66); g.lineTo(58, -66); g.lineTo(-32, 72); g.closePath(); g.fill();
  g.fillStyle = '#ece5d6'; g.beginPath(); g.arc(42, -40, 13, 0, Math.PI * 2); g.fill();
  g.restore();
  g.fillStyle = '#f4efe6'; g.font = '900 64px "Helvetica Neue", Arial, sans-serif'; g.textAlign = 'center';
  g.fillText('OAI WEB', 256, 352);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
  return t;
}
function roundRect(g, x, y, w, h, r) { g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r); g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath(); }

// ───────────────────────── плащ: ткань на verlet ─────────────────────────
class Cape {
  constructor(material, { W = 12, H = 14, width = 1.22, length = 1.2 } = {}) {
    this.W = W; this.H = H; this.width = width; this.length = length;
    const n = this.W * this.H;
    this.p = new Float32Array(n * 3); this.q = new Float32Array(n * 3);
    this.geo = new THREE.PlaneGeometry(this.width, this.length, this.W - 1, this.H - 1);
    this.mesh = new THREE.Mesh(this.geo, material);
    this.mesh.frustumCulled = false;
    this.ready = false;
    this.rest = this.width / (this.W - 1); this.restV = this.length / (this.H - 1);
  }
  // anchors: точки крепления в мировых координатах (верхний ряд)
  step(dt, anchors, colliders, wind) {
    const { W, H, p, q } = this;
    if (!this.ready) {
      for (let j = 0; j < H; j++) for (let i = 0; i < W; i++) {
        const a = anchors[i], k = (j * W + i) * 3;
        p[k] = a.x; p[k + 1] = a.y - j * this.restV; p[k + 2] = a.z - 0.05 - j * 0.02;
        q[k] = p[k]; q[k + 1] = p[k + 1]; q[k + 2] = p[k + 2];
      }
      this.ready = true;
    }
    const d2 = dt * dt, damp = 0.985;
    for (let j = 1; j < H; j++) for (let i = 0; i < W; i++) {
      const k = (j * W + i) * 3;
      const flutter = Math.sin(performance.now() * 0.004 + i * 0.7 + j * 0.45) * 0.35;
      for (let c = 0; c < 3; c++) {
        const acc = (c === 1 ? -9.8 : 0) + wind[c] * (0.6 + 0.4 * j / H) + (c === 0 ? flutter * Math.abs(wind[2]) * 0.2 : 0) + (c === 2 ? flutter * 0.6 : 0);
        const v = (p[k + c] - q[k + c]) * damp;
        q[k + c] = p[k + c];
        p[k + c] += v + acc * d2;
      }
    }
    for (let i = 0; i < W; i++) { const k = i * 3, a = anchors[i]; p[k] = a.x; p[k + 1] = a.y; p[k + 2] = a.z; q[k] = a.x; q[k + 1] = a.y; q[k + 2] = a.z; }
    for (let it = 0; it < 14; it++) {
      for (let j = 0; j < H; j++) for (let i = 0; i < W; i++) {
        if (i + 1 < W) this.solve(j * W + i, j * W + i + 1, this.rest);
        if (j + 1 < H) this.solve(j * W + i, (j + 1) * W + i, this.restV);
        if (i + 1 < W && j + 1 < H) this.solve(j * W + i, (j + 1) * W + i + 1, Math.hypot(this.rest, this.restV));
        if (i + 1 < W && j + 1 < H) this.solve(j * W + i + 1, (j + 1) * W + i, Math.hypot(this.rest, this.restV));
        if (i + 2 < W) this.solve(j * W + i, j * W + i + 2, this.rest * 2);
        if (j + 2 < H) this.solve(j * W + i, (j + 2) * W + i, this.restV * 2);
      }
      for (let k = W * 3; k < p.length; k += 3) for (const s of colliders) {
        const dx = p[k] - s.c.x, dy = p[k + 1] - s.c.y, dz = p[k + 2] - s.c.z, d = Math.hypot(dx, dy, dz);
        if (d < s.r) { const f = (s.r - d) / (d || 1e-5); p[k] += dx * f; p[k + 1] += dy * f; p[k + 2] += dz * f; }
      }
    }
    const pos = this.geo.attributes.position;
    for (let j = 0; j < H; j++) for (let i = 0; i < W; i++) {
      const k = (j * W + i) * 3; pos.setXYZ(j * W + i, p[k], p[k + 1], p[k + 2]);
    }
    pos.needsUpdate = true; this.geo.computeVertexNormals();
  }
  solve(a, b, rest) {
    const p = this.p, ka = a * 3, kb = b * 3;
    const dx = p[kb] - p[ka], dy = p[kb + 1] - p[ka + 1], dz = p[kb + 2] - p[ka + 2];
    const d = Math.hypot(dx, dy, dz) || 1e-5, diff = (d - rest) / d * 0.5;
    const pinA = a < this.W, pinB = b < this.W;
    const wa = pinA ? 0 : (pinB ? 1 : 0.5) * 2, wb = pinB ? 0 : (pinA ? 1 : 0.5) * 2;
    p[ka] += dx * diff * wa; p[ka + 1] += dy * diff * wa; p[ka + 2] += dz * diff * wa;
    p[kb] -= dx * diff * wb; p[kb + 1] -= dy * diff * wb; p[kb + 2] -= dz * diff * wb;
  }
}

// ───────────────────────── сам Андреич ─────────────────────────
export class Andreich {
  constructor(scene) {
    this.scene = scene;
    this.state = 'idle';
    this.facing = 0;          // -1 влево, 0 к зрителю, 1 вправо
    this.t = 0; this.phase = 0;
    this.look = new THREE.Vector2(); this.lookTarget = new THREE.Vector2(); this.nextLook = 2;
    this.blinkT = 3;
    this.cur = {};
    this.build();
  }

  build() {
    const root = this.root = new THREE.Group(); this.scene.add(root);
    const hips = this.hips = new THREE.Group(); hips.position.y = 0.68; root.add(hips);

    const leather = new THREE.MeshPhysicalMaterial({ color: COL.jacket, roughness: 0.42, metalness: 0.0, clearcoat: 0.55, clearcoatRoughness: 0.35, sheen: 0.3, sheenColor: new THREE.Color(0x334455) });
    const metal = new THREE.MeshPhysicalMaterial({ color: COL.metal, metalness: 1, roughness: 0.22, clearcoat: 0.6 });
    const darkMetal = new THREE.MeshPhysicalMaterial({ color: 0x2b2f36, metalness: 0.9, roughness: 0.3 });
    const bootMat = new THREE.MeshPhysicalMaterial({ color: 0x0b0b0e, roughness: 0.35, clearcoat: 0.8, clearcoatRoughness: 0.2 });

    // ── таз и низ из шерсти
    const pelvisFur = furMesh(new THREE.SphereGeometry(0.4, 40, 28), furMaterial(1, COL.furBrown, { len: 0.06, layers: 16, density: 85 }));
    pelvisFur.scale.set(1.0, 0.76, 0.92); pelvisFur.position.y = 0.0; hips.add(pelvisFur);

    // ── туловище-куртка (токарный профиль)
    const torso = this.torso = new THREE.Group(); torso.position.y = 0.1; hips.add(torso);
    const prof = [[0, -0.06], [0.37, -0.04], [0.44, 0.06], [0.49, 0.2], [0.52, 0.34], [0.47, 0.48], [0.28, 0.56], [0, 0.58]].map(([x, y]) => new THREE.Vector2(x, y));
    const jacket = new THREE.Mesh(new THREE.LatheGeometry(prof, 48), leather);
    jacket.scale.set(1.04, 1, 0.9); torso.add(jacket);
    // карманы, ремни, воротник
    const pocketGeo = new RoundedBoxGeometry(0.19, 0.13, 0.06, 3, 0.025);
    for (const sx of [-1, 1]) {
      const pk = new THREE.Mesh(pocketGeo, leather); pk.position.set(0.21 * sx, 0.26, 0.44); pk.rotation.y = 0.25 * sx; torso.add(pk);
      const strap = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.4, 0.02), darkMetal); strap.position.set(0.28 * sx, 0.28, 0.45); strap.rotation.z = 0.12 * sx; strap.rotation.y = 0.3 * sx; torso.add(strap);
    }
    const collar = new THREE.Mesh(new THREE.TorusGeometry(0.3, 0.085, 14, 36), leather); collar.rotation.x = Math.PI / 2; collar.position.y = 0.53; collar.scale.set(1, 0.85, 1); torso.add(collar);
    // нашивка со знаком OAI WEB на груди
    {
      const c = document.createElement('canvas'); c.width = c.height = 128; const g = c.getContext('2d');
      g.fillStyle = '#151010'; roundRect(g, 4, 4, 120, 120, 22); g.fill();
      g.strokeStyle = '#0abab5'; g.lineWidth = 5; roundRect(g, 4, 4, 120, 120, 22); g.stroke();
      g.fillStyle = '#e5121b'; g.beginPath(); g.moveTo(14, 112); g.lineTo(76, 18); g.lineTo(100, 18); g.lineTo(38, 112); g.closePath(); g.fill();
      g.fillStyle = '#ece5d6'; g.beginPath(); g.arc(92, 34, 9, 0, Math.PI * 2); g.fill();
      const tex = new THREE.CanvasTexture(c); tex.colorSpace = THREE.SRGBColorSpace;
      const patch = new THREE.Mesh(new THREE.PlaneGeometry(0.17, 0.17), new THREE.MeshStandardMaterial({ map: tex, roughness: 0.6, transparent: true }));
      patch.position.set(-0.25, 0.37, 0.47); patch.rotation.y = -0.32; torso.add(patch);
    }
    // бирюзовые канты: молния, подол, плечи
    const zipCurve = new THREE.CatmullRomCurve3([new THREE.Vector3(0, 0.53, 0.36), new THREE.Vector3(0.02, 0.36, 0.46), new THREE.Vector3(0, 0.16, 0.45), new THREE.Vector3(0, -0.01, 0.4)]);
    torso.add(new THREE.Mesh(new THREE.TubeGeometry(zipCurve, 40, 0.012, 6), neon()));
    const hem = new THREE.Mesh(new THREE.TorusGeometry(0.4, 0.012, 6, 64), neon()); hem.rotation.x = Math.PI / 2; hem.position.y = -0.02; hem.scale.set(1.04, 0.9, 1); torso.add(hem);
    for (const sx of [-1, 1]) {
      const c = new THREE.CatmullRomCurve3([new THREE.Vector3(0.2 * sx, 0.54, 0.32), new THREE.Vector3(0.45 * sx, 0.49, 0.22), new THREE.Vector3(0.57 * sx, 0.36, 0.0)]);
      torso.add(new THREE.Mesh(new THREE.TubeGeometry(c, 20, 0.01, 6), neon()));
    }

    // ── голова
    const neck = this.neck = new THREE.Group(); neck.position.y = 0.56; torso.add(neck);
    const head = this.head = new THREE.Group(); head.position.y = 0.37; head.scale.setScalar(1.24); neck.add(head);
    const skull = furMesh(new THREE.SphereGeometry(1, 64, 48), furMaterial(0, COL.furGray, { len: 0.08, layers: 32, density: 58, droop: [0, -0.45, 0] }));
    skull.scale.set(0.54, 0.48, 0.5); head.add(skull);
    // щёки-пучки по бокам (силуэт енота)
    for (const sx of [-1, 1]) {
      const ch = furMesh(new THREE.SphereGeometry(1, 32, 24), furMaterial(1, COL.furLight, { len: 0.07, layers: 20, density: 48, droop: [0.7 * sx, -0.5, 0] }));
      ch.scale.set(0.26, 0.2, 0.24); ch.position.set(0.4 * sx, -0.17, 0.1); head.add(ch);
    }
    // морда
    const snout = furMesh(new THREE.SphereGeometry(1, 40, 28), furMaterial(1, COL.furLight, { len: 0.035, layers: 12, density: 60 }));
    snout.scale.set(0.22, 0.16, 0.24); snout.position.set(0, -0.12, 0.42); head.add(snout);
    const nose = new THREE.Mesh(new THREE.SphereGeometry(0.065, 24, 16), new THREE.MeshPhysicalMaterial({ color: 0x09090b, roughness: 0.25, clearcoat: 1 }));
    nose.scale.set(1.3, 0.9, 1); nose.position.set(0, -0.06, 0.66); head.add(nose);
    const mouth = this.mouth = new THREE.Mesh(new THREE.TorusGeometry(0.06, 0.012, 8, 20, Math.PI), new THREE.MeshBasicMaterial({ color: 0x1a1214 }));
    mouth.rotation.z = Math.PI; mouth.position.set(0, -0.21, 0.6); head.add(mouth);
    // глаза
    this.eyes = [];
    for (const sx of [-1, 1]) {
      const eye = new THREE.Group(); eye.position.set(0.19 * sx, 0.07, 0.445); head.add(eye);
      const ball = new THREE.Mesh(new THREE.SphereGeometry(0.088, 28, 20), new THREE.MeshPhysicalMaterial({ color: 0x1a120c, roughness: 0.05, clearcoat: 1 }));
      ball.scale.z = 0.55; eye.add(ball);
      const iris = new THREE.Mesh(new THREE.CircleGeometry(0.062, 32), new THREE.MeshBasicMaterial({ color: 0xc7781e, toneMapped: false }));
      iris.position.z = 0.05; eye.add(iris);
      const pupil = new THREE.Mesh(new THREE.CircleGeometry(0.032, 24), new THREE.MeshBasicMaterial({ color: 0x050505 }));
      pupil.position.z = 0.052; eye.add(pupil);
      const hl = new THREE.Mesh(new THREE.CircleGeometry(0.016, 12), new THREE.MeshBasicMaterial({ color: 0xffffff, toneMapped: false })); hl.position.set(0.022, 0.026, 0.054); eye.add(hl);
      const hl2 = new THREE.Mesh(new THREE.CircleGeometry(0.008, 10), new THREE.MeshBasicMaterial({ color: 0xffffff, toneMapped: false })); hl2.position.set(-0.02, -0.02, 0.054); eye.add(hl2);
      this.eyes.push(eye);
    }
    // уши
    this.ears = [];
    for (const sx of [-1, 1]) {
      const ear = new THREE.Group(); ear.position.set(0.34 * sx, 0.46, -0.05); ear.rotation.z = -0.36 * sx; ear.scale.setScalar(1.3); head.add(ear);
      const rimEar = furMesh(new THREE.ConeGeometry(0.21, 0.33, 28, 6), furMaterial(1, COL.furLight, { len: 0.035, layers: 12, density: 80 }));
      rimEar.scale.set(1, 1, 0.42); rimEar.position.z = -0.02; ear.add(rimEar);
      const outer = furMesh(new THREE.ConeGeometry(0.17, 0.28, 28, 6), furMaterial(1, COL.furDark, { len: 0.03, layers: 10, density: 80 }));
      outer.scale.set(1, 1, 0.45); outer.position.set(0, -0.03, 0.005); ear.add(outer);
      const inner = new THREE.Mesh(new THREE.ConeGeometry(0.1, 0.18, 20), new THREE.MeshStandardMaterial({ color: 0xd9c4c6, roughness: 0.9 }));
      inner.position.set(0, -0.05, 0.06); inner.scale.z = 0.3; ear.add(inner);
      this.ears.push(ear);
    }
    // наушники: дуга, чашки с бирюзовыми кольцами, микрофон
    const band = new THREE.Mesh(new THREE.TorusGeometry(0.57, 0.035, 12, 48, Math.PI), darkMetal); band.position.y = 0.0; band.position.z = -0.04; head.add(band);
    this.cupGlows = [];
    for (const sx of [-1, 1]) {
      const cup = new THREE.Group(); cup.position.set(0.57 * sx, -0.02, -0.04); cup.rotation.z = Math.PI / 2; head.add(cup);
      cup.add(new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.16, 0.11, 32), darkMetal));
      const ring = new THREE.Mesh(new THREE.TorusGeometry(0.115, 0.02, 10, 40), neon()); ring.rotation.x = Math.PI / 2; ring.position.y = 0.058 * sx; cup.add(ring);
      const g = glowSprite(0.5); g.position.set(0.64 * sx, -0.02, -0.04); head.add(g); this.cupGlows.push(g);
    }
    const boom = new THREE.CatmullRomCurve3([new THREE.Vector3(-0.57, -0.12, 0.02), new THREE.Vector3(-0.47, -0.32, 0.32), new THREE.Vector3(-0.17, -0.3, 0.56)]);
    head.add(new THREE.Mesh(new THREE.TubeGeometry(boom, 20, 0.012, 6), darkMetal));
    const micTip = new THREE.Mesh(new THREE.SphereGeometry(0.03, 12, 10), neon(COL.tiffany)); micTip.position.set(-0.17, -0.3, 0.56); head.add(micTip);
    // визор на правом глазу (для зрителя слева)
    const visor = this.visor = new THREE.Group(); visor.position.set(-0.19, 0.08, 0.5); head.add(visor);
    const lens = new THREE.Mesh(new RoundedBoxGeometry(0.3, 0.17, 0.03, 4, 0.04),
      new THREE.MeshPhysicalMaterial({ color: 0x0abab5, emissive: 0x0abab5, emissiveIntensity: 0.9, transparent: true, opacity: 0.62, roughness: 0.05, clearcoat: 1 }));
    visor.add(lens);
    const frame = new THREE.Mesh(new THREE.TorusGeometry(0.11, 0.012, 6, 32), darkMetal); frame.scale.set(1.45, 0.85, 1); visor.add(frame);
    const vg = this.visorGlow = glowSprite(0.55, COL.glow, 0.55); vg.position.z = 0.03; visor.add(vg);
    const arm = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.02, 0.02), darkMetal); arm.position.set(-0.22, 0.02, -0.14); arm.rotation.y = 0.9; visor.add(arm);

    // ── руки
    this.arms = {};
    for (const [name, sx] of [['L', 1], ['R', -1]]) {
      const sh = new THREE.Group(); sh.position.set(0.5 * sx, 0.44, 0.01); torso.add(sh);
      const upper = new THREE.Mesh(new THREE.CapsuleGeometry(0.15, 0.19, 6, 16), leather); upper.position.y = -0.15; sh.add(upper);
      const elbow = new THREE.Group(); elbow.position.y = -0.32; sh.add(elbow);
      let hand;
      if (name === 'R') {   // кибер-предплечье
        const fore = new THREE.Mesh(new THREE.CapsuleGeometry(0.125, 0.19, 6, 16), metal); fore.position.y = -0.15; elbow.add(fore);
        for (const a of [0.0, Math.PI]) {
          const strip = new THREE.Mesh(new THREE.BoxGeometry(0.02, 0.19, 0.02), neon()); strip.position.set(Math.sin(a) * 0.115, -0.15, Math.cos(a) * 0.115); elbow.add(strip);
        }
        const g = glowSprite(0.35, COL.glow, 0.4); g.position.set(0, -0.15, 0.13); elbow.add(g);
        hand = new THREE.Mesh(new RoundedBoxGeometry(0.2, 0.18, 0.18, 3, 0.055), darkMetal);
      } else {
        const fore = new THREE.Mesh(new THREE.CapsuleGeometry(0.135, 0.18, 6, 16), leather); fore.position.y = -0.15; elbow.add(fore);
        hand = furMesh(new THREE.SphereGeometry(0.125, 24, 18), furMaterial(1, COL.furDark, { len: 0.03, layers: 8, density: 90 }));
      }
      hand.position.y = -0.33; elbow.add(hand);
      this.arms[name] = { sh, elbow, sx };
    }

    // ── ноги
    this.legs = {};
    for (const [name, sx] of [['L', 1], ['R', -1]]) {
      const hip = new THREE.Group(); hip.position.set(0.21 * sx, -0.08, 0); hips.add(hip);
      const thigh = furMesh(new THREE.CapsuleGeometry(0.175, 0.09, 6, 16), furMaterial(1, COL.furBrown, { len: 0.05, layers: 12, density: 80 }));
      thigh.position.y = -0.11; hip.add(thigh);
      const knee = new THREE.Group(); knee.position.y = -0.27; hip.add(knee);
      const shin = furMesh(new THREE.CapsuleGeometry(0.15, 0.05, 6, 16), furMaterial(1, COL.furBrown, { len: 0.04, layers: 10, density: 85 }));
      shin.position.y = -0.08; knee.add(shin);
      const boot = new THREE.Mesh(new RoundedBoxGeometry(0.3, 0.19, 0.38, 4, 0.08), bootMat); boot.position.set(0, -0.22, 0.06); knee.add(boot);
      const sole = new THREE.Mesh(new THREE.BoxGeometry(0.31, 0.045, 0.39), new THREE.MeshStandardMaterial({ color: 0x1f2126, roughness: 0.9 })); sole.position.set(0, -0.31, 0.06); knee.add(sole);
      const stripe = new THREE.Mesh(new THREE.BoxGeometry(0.315, 0.013, 0.392), neon()); stripe.position.set(0, -0.285, 0.06); knee.add(stripe);
      this.legs[name] = { hip, knee, sx };
    }

    // ── хвост: пружинная цепочка сегментов
    this.tail = [];
    const tailBase = this.tailBase = new THREE.Object3D(); tailBase.position.set(0, -0.04, -0.42); hips.add(tailBase);
    const N = 9;
    for (let i = 0; i < N; i++) {
      const u = i / (N - 1);
      const r = 0.275 * (1 - u * 0.42) * (i === N - 1 ? 0.8 : 1);
      const dark = i % 2 === 0;
      const seg = furMesh(new THREE.SphereGeometry(r, 24, 18), furMaterial(1, dark ? COL.furDark : new THREE.Color(0xb3b1b6), { len: 0.07, layers: 16, density: 60 }));
      seg.scale.set(1, 1, 1.25);
      this.scene.add(seg);
      let ring = null;
      if (!dark && i < N - 1) {
        ring = new THREE.Mesh(new THREE.TorusGeometry(r * 1.05, 0.02, 8, 32), neon());
        const g = glowSprite(r * 3.2, COL.glow, 0.45); ring.add(g);
        this.scene.add(ring);
      }
      this.tail.push({ seg, ring, pos: new THREE.Vector3(), prev: new THREE.Vector3(), len: r * 1.25, init: false });
    }

    // ── плащ
    const capeMat = new THREE.MeshPhysicalMaterial({ map: capeTexture(), color: 0xffffff, roughness: 0.55, sheen: 1, sheenColor: new THREE.Color(0xff5a5a), sheenRoughness: 0.45, side: THREE.DoubleSide });
    this.cape = new Cape(capeMat);
    this.scene.add(this.cape.mesh);
    this.capeAnchorsLocal = [];
    for (let i = 0; i < this.cape.W; i++) {
      const u = i / (this.cape.W - 1);
      const x = THREE.MathUtils.lerp(-0.47, 0.47, u);
      const z = -0.3 - 0.1 * Math.cos((u - 0.5) * Math.PI) + 0.12 * Math.abs(u - 0.5) * 2;
      this.capeAnchorsLocal.push(new THREE.Vector3(x, 0.52 - 0.05 * Math.abs(u - 0.5) * 2, z));
    }

    // ── голограмма для «работает» и волны для «слушает»
    const holoC = document.createElement('canvas'); holoC.width = 256; holoC.height = 160;
    this.holoCtx = holoC.getContext('2d'); this.holoTex = new THREE.CanvasTexture(holoC);
    this.holo = new THREE.Mesh(new THREE.PlaneGeometry(0.64, 0.4), new THREE.MeshBasicMaterial({ map: this.holoTex, transparent: true, opacity: 0.9, toneMapped: false, side: THREE.DoubleSide, depthWrite: false, blending: THREE.AdditiveBlending }));
    this.holo.position.set(0, 0.34, 0.68); this.holo.rotation.x = -0.35; torso.add(this.holo);
    this.waves = [];
    for (let i = 0; i < 3; i++) {
      const w = new THREE.Mesh(new THREE.TorusGeometry(0.2, 0.012, 6, 48, Math.PI * 0.7), neon());
      w.material = w.material.clone(); w.material.transparent = true;
      w.rotation.y = Math.PI / 2; w.rotation.z = Math.PI * 0.65; w.position.set(-0.66, -0.02, -0.04);
      head.add(w); this.waves.push(w);
    }
    // искры для радости и «z» для сна
    this.fx = new THREE.Group(); root.add(this.fx);
    this.sparks = [];
    for (let i = 0; i < 14; i++) { const s = glowSprite(0.18, i % 3 === 0 ? COL.red : COL.glow, 0.9); this.fx.add(s); this.sparks.push({ s, a: Math.random() * 6.28, r: 0.5 + Math.random() * 0.6, y: 0.9 + Math.random() * 1.2, sp: 0.6 + Math.random() }); }
    this.zs = [];
    for (let i = 0; i < 3; i++) {
      const c = document.createElement('canvas'); c.width = c.height = 64; const g = c.getContext('2d');
      g.fillStyle = '#e8fffd'; g.font = '900 52px Arial'; g.textAlign = 'center'; g.fillText('z', 32, 48);
      const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(c), transparent: true, depthWrite: false }));
      s.scale.set(0.28, 0.28, 1); this.fx.add(s); this.zs.push(s);
    }
    // тень на полу
    const shC = document.createElement('canvas'); shC.width = shC.height = 128; const sg = shC.getContext('2d');
    const grd = sg.createRadialGradient(64, 64, 0, 64, 64, 64); grd.addColorStop(0, 'rgba(0,0,0,0.55)'); grd.addColorStop(1, 'rgba(0,0,0,0)'); sg.fillStyle = grd; sg.fillRect(0, 0, 128, 128);
    this.shadow = new THREE.Mesh(new THREE.PlaneGeometry(1.3, 0.58), new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(shC), transparent: true, depthWrite: false }));
    this.shadow.rotation.x = -Math.PI / 2; this.shadow.position.y = 0.002; this.scene.add(this.shadow);
  }

  setState(s) { this.state = s; }
  setLite(on) {
    if (this.lite === on) return;
    this.lite = on;
    this.cape.mesh.visible = !on; this.shadow.visible = !on;
    for (const s of this.tail) { s.seg.visible = !on; if (s.ring) s.ring.visible = !on; }
    this.scene.traverse((o) => {
      if (o.isInstancedMesh) {
        const full = o.material.uniforms.uLayers.value + 1;
        o.count = on ? Math.max(4, Math.ceil(full * 0.5)) : full;
      }
    });
  }
  setFacing(f) { this.facing = f; }

  /// Спрятать/показать целиком — для переключения кругляш/полный.
  setHidden(hide) {
    this.root.visible = !hide;
    this.cape.mesh.visible = !hide && !this.lite;
    this.shadow.visible = !hide && !this.lite;
    for (const s of this.tail) { s.seg.visible = !hide && !this.lite; if (s.ring) s.ring.visible = !hide && !this.lite; }
  }

  // целевые углы суставов для каждой позы
  target(dt) {
    const t = this.t, s = this.state, T = {
      rootY: 0, rotY: 0, hipsY: 0.68, lean: 0, twist: 0, breathe: 1,
      headX: 0, headY: 0, headZ: 0,
      shL: [0, 0.18], shR: [0, -0.18], elL: 0.35, elR: 0.35,
      hipL: 0, hipR: 0, knL: 0, knR: 0,
      wind: [0, 0, -1.2], holo: 0, waves: 0, sparks: 0, sleep: 0, eyes: 1, mouthOpen: 0, tailCurl: 0,
    };
    const facingY = this.facing === 0 ? 0.42 : this.facing * (Math.PI / 2 - 0.42);
    T.rotY = facingY + this.look.x * 0.15;
    T.headY = this.look.x * 0.45; T.headX = this.look.y * 0.25;
    const br = Math.sin(t * 2.1);
    switch (s) {
      case 'walk': {
        this.phase += dt * 10.5;
        const p = this.phase, sp = Math.sin(p), cp = Math.cos(p);
        T.hipL = 0.75 * sp; T.hipR = -0.75 * sp;
        T.knL = 0.18 + 1.1 * Math.max(0, cp); T.knR = 0.18 + 1.1 * Math.max(0, -cp);
        T.hipsY = 0.665 + 0.05 * Math.abs(Math.cos(p));
        T.lean = 0.16; T.twist = 0.12 * sp;
        T.shL = [-0.7 * sp, 0.12]; T.shR = [0.7 * sp, -0.12]; T.elL = 0.7; T.elR = 0.7;
        T.headX = -0.05; T.headY = 0;
        T.wind = [0, -2.2, -2.0]; break;
      }
      case 'idle':
        T.breathe = 1 + 0.012 * br; T.shL = [0.05, 0.2 + 0.02 * br]; T.shR = [0.05, -0.2 - 0.02 * br]; T.elL = 0.3; T.elR = 0.3;
        T.wind = [0.3 * Math.sin(t * 0.7), 0, -1.6]; break;
      case 'listen':
        T.headZ = -0.2; T.headY = -0.15; T.waves = 1;
        T.shR = [0.35, -1.55]; T.elR = 2.75;
        T.shL = [0.05, 0.22]; T.elL = 0.35; T.wind = [0, 0, -1.4]; break;
      case 'wave':
        T.shL = [0.2, 2.6]; T.elL = 0.5 + 0.55 * Math.sin(t * 9); T.mouthOpen = 0.6; T.headZ = 0.1; break;
      case 'work':
        T.holo = 1; T.headX = 0.32; T.lean = 0.05;
        T.shL = [-1.05, 0.25]; T.shR = [-1.05, -0.25]; T.elL = 0.9 + 0.2 * Math.sin(t * 13); T.elR = 0.9 + 0.2 * Math.sin(t * 13 + 2); break;
      case 'cheer': {
        const j = Math.abs(Math.sin(t * 6.5));
        T.rootY = 0.42 * j; T.shL = [0, 2.75]; T.shR = [0, -2.75]; T.elL = 0.2; T.elR = 0.2;
        T.knL = 0.9 * j; T.knR = 0.9 * j; T.hipL = -0.6 * j; T.hipR = -0.6 * j; T.sparks = 1; T.mouthOpen = 1; T.eyes = 0.5;
        T.wind = [0, -4 + 9 * Math.cos(t * 6.5), -3]; T.rotY = facingY + Math.sin(t * 3) * 0.35; break;
      }
      case 'sit':
      case 'sleep': {
        const sleep = s === 'sleep';
        T.hipsY = 0.4; T.hipL = -1.5; T.hipR = -1.5; T.knL = 1.55; T.knR = 1.55; T.lean = sleep ? 0.38 : 0.08;
        T.headX = sleep ? 0.55 : 0.05; T.headZ = sleep ? 0.18 : 0;
        T.shL = sleep ? [-0.6, 0.45] : [-0.2, 0.25]; T.shR = sleep ? [-0.6, -0.45] : [-0.2, -0.25]; T.elL = sleep ? 1.6 : 0.6; T.elR = sleep ? 1.6 : 0.6;
        T.sleep = sleep ? 1 : 0; T.eyes = sleep ? 0.06 : 1; T.tailCurl = 1; T.wind = [0, 0, -0.6]; T.breathe = 1 + 0.02 * Math.sin(t * 1.4); break;
      }
    }
    if (typeof window !== 'undefined' && window.__tune && window.__tune[s]) Object.assign(T, window.__tune[s]);   // отладка поз
    return T;
  }

  update(dt) {
    this.t += dt; const t = this.t;
    // взгляд по сторонам
    this.nextLook -= dt;
    if (this.nextLook < 0) { this.lookTarget.set((Math.random() - 0.5) * 1.2, (Math.random() - 0.5) * 0.6); this.nextLook = 1.5 + Math.random() * 3; }
    this.look.lerp(this.lookTarget, 1 - Math.exp(-dt * 3));
    const T = this.target(dt);
    const k = 1 - Math.exp(-dt * 9), C = this.cur;
    for (const key in T) {
      const v = T[key];
      if (Array.isArray(v)) { C[key] = C[key] || v.slice(); for (let i = 0; i < v.length; i++) C[key][i] += (v[i] - C[key][i]) * k; }
      else { C[key] = C[key] === undefined ? v : C[key] + (v - C[key]) * k; }
    }
    // корпус
    this.root.position.y = C.rootY;
    this.root.rotation.y = C.rotY;
    this.hips.position.y = C.hipsY;
    this.torso.rotation.x = C.lean; this.torso.rotation.y = C.twist;
    this.torso.scale.set(1 / Math.sqrt(C.breathe), C.breathe, 1 / Math.sqrt(C.breathe));
    this.head.rotation.set(C.headX - C.lean * 0.6, C.headY - C.twist, C.headZ);
    // руки: [вперёд-назад, в сторону], локоть сгибает вперёд
    for (const [n, sw, el] of [['L', C.shL, C.elL], ['R', C.shR, C.elR]]) {
      const a = this.arms[n]; a.sh.rotation.set(-sw[0], 0, sw[1]); a.elbow.rotation.x = -el;
    }
    // ноги: бедро вперёд, колено назад
    this.legs.L.hip.rotation.x = -C.hipL; this.legs.R.hip.rotation.x = -C.hipR;
    this.legs.L.knee.rotation.x = C.knL; this.legs.R.knee.rotation.x = C.knR;
    // моргание
    this.blinkT -= dt;
    let blink = 1; if (this.blinkT < 0) { blink = 0.1; if (this.blinkT < -0.12) this.blinkT = 2.5 + Math.random() * 3; }
    for (const e of this.eyes) e.scale.y = Math.min(C.eyes, blink);
    this.mouth.scale.set(1, 1 + C.mouthOpen * 1.5, 1);
    // уши подёргиваются
    this.ears[0].rotation.x = Math.sin(t * 1.3) * 0.05 + (Math.sin(t * 0.5) > 0.97 ? 0.3 : 0);
    this.ears[1].rotation.x = Math.sin(t * 1.1 + 1) * 0.05;
    // свечение
    const pulse = 0.75 + 0.25 * Math.sin(t * 3);
    for (const g of this.cupGlows) g.material.opacity = 0.45 * pulse;
    this.visorGlow.material.opacity = 0.4 + 0.2 * Math.sin(t * 4.3);
    // голограмма
    this.holo.visible = C.holo > 0.05; this.holo.material.opacity = C.holo * 0.9;
    if (this.holo.visible) this.drawHolo(t);
    // волны
    this.waves.forEach((w, i) => { const p = (t * 0.9 + i / 3) % 1; w.visible = C.waves > 0.05; w.scale.setScalar(1 + p * 1.8); w.material.opacity = (1 - p) * C.waves; });
    // искры
    this.sparks.forEach((sp) => { sp.s.visible = C.sparks > 0.05; const a = sp.a + t * sp.sp; sp.s.position.set(Math.cos(a) * sp.r, sp.y + Math.sin(t * 3 + sp.a) * 0.2, Math.sin(a) * sp.r * 0.6); sp.s.material.opacity = C.sparks * (0.5 + 0.5 * Math.sin(t * 8 + sp.a)); });
    this.zs.forEach((z, i) => { const p = (t * 0.35 + i / 3) % 1; z.visible = C.sleep > 0.05; z.position.set(0.5 + p * 0.45, 1.7 + p * 0.8, 0.2); z.material.opacity = (1 - p) * C.sleep; z.scale.setScalar(0.2 + 0.12 * i + p * 0.1); });
    this.shadow.scale.setScalar(1 - Math.min(0.5, C.rootY * 0.6));

    this.root.updateMatrixWorld(true);
    if (!this.lite) { this.updateTail(dt, C); this.updateCape(dt, C); }
  }

  updateTail(dt, C) {
    const base = new THREE.Vector3(); this.tailBase.getWorldPosition(base);
    const q = new THREE.Quaternion(); this.tailBase.getWorldQuaternion(q);
    const back = new THREE.Vector3(0, 0, -1).applyQuaternion(q);
    const up = new THREE.Vector3(0, 1, 0);
    const side = new THREE.Vector3(1, 0, 0).applyQuaternion(q);
    let prev = base, prevDir = back.clone().multiplyScalar(0.8).addScaledVector(up, 0.25).normalize();
    const t = this.t;
    this.tail.forEach((s, i) => {
      const u = i / (this.tail.length - 1);
      // желаемое направление: назад и вверх (S-образно), во сне закручен вокруг
      const desired = back.clone().multiplyScalar(0.7 - 0.5 * u * (1 - C.tailCurl))
        .addScaledVector(up, 0.25 + 0.75 * u * (1 - C.tailCurl * 0.8))
        .addScaledVector(side, Math.sin(t * 2.2 - u * 3.2) * 0.35 * u + C.tailCurl * (0.9 * u))
        .normalize();
      const dir = prevDir.clone().lerp(desired, 0.55).normalize();
      const targetPos = prev.clone().addScaledVector(dir, s.len);
      if (!s.init) { s.pos.copy(targetPos); s.init = true; }
      s.pos.lerp(targetPos, 1 - Math.exp(-dt * (22 - u * 12)));
      // держим длину звена
      const d = s.pos.clone().sub(prev); d.setLength(s.len); s.pos.copy(prev).add(d);
      s.seg.position.copy(s.pos);
      s.seg.lookAt(prev);
      if (s.ring) { s.ring.position.copy(prev).lerp(s.pos, 0.5); s.ring.lookAt(s.pos); }
      prevDir = d.normalize(); prev = s.pos;
    });
  }

  updateCape(dt, C) {
    const anchors = this.capeAnchorsLocal.map((v) => this.torso.localToWorld(v.clone()));
    const chest = new THREE.Vector3(0, 0.3, -0.04); this.torso.localToWorld(chest);
    const pelvis = new THREE.Vector3(0, 0.0, -0.05); this.hips.localToWorld(pelvis);
    const headP = new THREE.Vector3(); this.head.getWorldPosition(headP);
    const colliders = [{ c: chest, r: 0.6 }, { c: pelvis, r: 0.54 }, { c: headP, r: 0.66 }];
    // ветер в системе персонажа → в мировую
    const w = new THREE.Vector3(...C.wind).applyQuaternion(this.root.quaternion);
    const sub = 2, h = Math.min(dt, 1 / 30) / sub;
    for (let i = 0; i < sub; i++) this.cape.step(h, anchors, colliders, [w.x, w.y, w.z]);
  }

  drawHolo(t) {
    const g = this.holoCtx, W = 256, H = 160;
    g.clearRect(0, 0, W, H);
    g.strokeStyle = 'rgba(99,255,242,0.95)'; g.lineWidth = 4; roundRect(g, 6, 6, W - 12, H - 12, 14); g.stroke();
    for (let i = 0; i < 7; i++) { const h = 20 + 80 * Math.abs(Math.sin(t * 2.4 + i * 0.9)); g.fillStyle = `rgba(99,255,242,${0.55 + 0.4 * (i % 2)})`; g.fillRect(24 + i * 31, H - 22 - h, 18, h); }
    g.fillStyle = 'rgba(255,255,255,0.8)'; g.fillRect(24, 22, 120 + 60 * Math.sin(t * 1.7), 6);
    this.holoTex.needsUpdate = true;
  }
}


// ───────────────────────── Андреич-кругляш ─────────────────────────
// Вторая форма: одна пушистая голова на лапках-шариках, круглые ручки,
// хвостик-помпон и маленький плащ. Детская схема в чистом виде.
export class MiniAndreich {
  constructor(scene) {
    this.scene = scene;
    this.state = 'idle'; this.facing = 0; this.lite = false;
    this.t = 0; this.phase = 0; this.cur = {}; this.blinkT = 3;
    this.look = new THREE.Vector2(); this.lookTarget = new THREE.Vector2(); this.nextLook = 2;
    this.build();
  }

  build() {
    const root = this.root = new THREE.Group(); this.scene.add(root);
    const body = this.body = this.head = new THREE.Group(); body.position.y = 0.8; root.add(body);
    const darkMetal = new THREE.MeshPhysicalMaterial({ color: 0x2b2f36, metalness: 0.9, roughness: 0.3 });

    // шар-тело: тот же череп с маской енота
    const skull = furMesh(new THREE.SphereGeometry(1, 64, 48), furMaterial(0, COL.furGray, { len: 0.06, layers: 26, density: 74, droop: [0, -0.3, 0] }));
    skull.scale.set(0.62, 0.58, 0.6); body.add(skull);
    for (const sx of [-1, 1]) {
      const ch = furMesh(new THREE.SphereGeometry(1, 32, 24), furMaterial(1, COL.furLight, { len: 0.055, layers: 16, density: 58, droop: [0.6 * sx, -0.5, 0] }));
      ch.scale.set(0.25, 0.19, 0.23); ch.position.set(0.43 * sx, -0.25, 0.17); body.add(ch);
    }
    const snout = furMesh(new THREE.SphereGeometry(1, 40, 28), furMaterial(1, COL.furLight, { len: 0.032, layers: 12, density: 64 }));
    snout.scale.set(0.25, 0.18, 0.26); snout.position.set(0, -0.17, 0.5); body.add(snout);
    const nose = new THREE.Mesh(new THREE.SphereGeometry(0.075, 24, 16), new THREE.MeshPhysicalMaterial({ color: 0x09090b, roughness: 0.25, clearcoat: 1 }));
    nose.scale.set(1.3, 0.9, 1); nose.position.set(0, -0.08, 0.77); body.add(nose);
    const mouth = this.mouth = new THREE.Mesh(new THREE.TorusGeometry(0.07, 0.014, 8, 20, Math.PI), new THREE.MeshBasicMaterial({ color: 0x1a1214 }));
    mouth.rotation.z = Math.PI; mouth.position.set(0, -0.26, 0.7); body.add(mouth);
    this.eyes = [];
    for (const sx of [-1, 1]) {
      const eye = new THREE.Group(); eye.position.set(0.22 * sx, 0.08, 0.52); body.add(eye);
      const ball = new THREE.Mesh(new THREE.SphereGeometry(0.105, 28, 20), new THREE.MeshPhysicalMaterial({ color: 0x1a120c, roughness: 0.05, clearcoat: 1 }));
      ball.scale.z = 0.55; eye.add(ball);
      const iris = new THREE.Mesh(new THREE.CircleGeometry(0.075, 32), new THREE.MeshBasicMaterial({ color: 0xc7781e, toneMapped: false }));
      iris.position.z = 0.059; eye.add(iris);
      const pupil = new THREE.Mesh(new THREE.CircleGeometry(0.04, 24), new THREE.MeshBasicMaterial({ color: 0x050505 }));
      pupil.position.z = 0.061; eye.add(pupil);
      const hl = new THREE.Mesh(new THREE.CircleGeometry(0.02, 12), new THREE.MeshBasicMaterial({ color: 0xffffff, toneMapped: false })); hl.position.set(0.026, 0.03, 0.063); eye.add(hl);
      this.eyes.push(eye);
    }
    this.ears = [];
    for (const sx of [-1, 1]) {
      const ear = new THREE.Group(); ear.position.set(0.36 * sx, 0.5, -0.05); ear.rotation.z = -0.34 * sx; ear.scale.setScalar(1.18); body.add(ear);
      const rimEar = furMesh(new THREE.ConeGeometry(0.21, 0.33, 28, 6), furMaterial(1, COL.furLight, { len: 0.03, layers: 12, density: 85 }));
      rimEar.scale.set(1, 1, 0.42); rimEar.position.z = -0.02; ear.add(rimEar);
      const outer = furMesh(new THREE.ConeGeometry(0.17, 0.28, 28, 6), furMaterial(1, COL.furDark, { len: 0.035, layers: 10, density: 80 }));
      outer.scale.set(1, 1, 0.45); outer.position.set(0, -0.03, 0.005); ear.add(outer);
      const inner = new THREE.Mesh(new THREE.ConeGeometry(0.1, 0.18, 20), new THREE.MeshStandardMaterial({ color: 0xd9c4c6, roughness: 0.9 }));
      inner.position.set(0, -0.05, 0.06); inner.scale.z = 0.3; ear.add(inner);
      this.ears.push(ear);
    }
    // наушники, микрофон, визор
    const band = new THREE.Mesh(new THREE.TorusGeometry(0.64, 0.04, 12, 48, Math.PI), darkMetal); band.position.z = -0.04; body.add(band);
    this.cupGlows = [];
    for (const sx of [-1, 1]) {
      const cup = new THREE.Group(); cup.position.set(0.63 * sx, -0.02, -0.04); cup.rotation.z = Math.PI / 2; body.add(cup);
      cup.add(new THREE.Mesh(new THREE.CylinderGeometry(0.18, 0.18, 0.12, 32), darkMetal));
      const ring = new THREE.Mesh(new THREE.TorusGeometry(0.13, 0.022, 10, 40), neon()); ring.rotation.x = Math.PI / 2; ring.position.y = 0.063 * sx; cup.add(ring);
      const g = glowSprite(0.55); g.position.set(0.71 * sx, -0.02, -0.04); body.add(g); this.cupGlows.push(g);
    }
    for (const sx of [-1, 1]) {   // знак OAI WEB на чашках наушников
      const badge = new THREE.Mesh(new THREE.PlaneGeometry(0.17, 0.17),
        new THREE.MeshBasicMaterial({ map: logoTexture(), transparent: true, toneMapped: false }));
      badge.position.set(sx * 0.705, -0.02, -0.04); badge.rotation.y = sx * Math.PI / 2; body.add(badge);
    }
    this.visorGlow = glowSprite(0.0, COL.glow, 0);   // визора у кругляша нет
    // застёжка плаща: знак-брошь по центру груди
    const clasp = new THREE.Mesh(new THREE.PlaneGeometry(0.23, 0.23),
      new THREE.MeshBasicMaterial({ map: logoTexture(), transparent: true, toneMapped: false }));
    clasp.position.set(0, -0.47, 0.44); clasp.rotation.x = -0.7; body.add(clasp);

    // ручки-шарики
    this.hands = [];
    for (const sx of [-1, 1]) {
      const h = furMesh(new THREE.SphereGeometry(0.125, 24, 18), furMaterial(1, COL.furBrown, { len: 0.045, layers: 10, density: 80 }));
      h.position.set(0.5 * sx, -0.4, 0.22); body.add(h); this.hands.push(h);
    }
    // ножки-шарики, без всяких ботинок
    this.feet = [];
    for (const sx of [-1, 1]) {
      const f = furMesh(new THREE.SphereGeometry(0.17, 24, 18), furMaterial(1, COL.furBrown, { len: 0.055, layers: 10, density: 75 }));
      f.scale.set(1, 0.74, 1.25); f.position.set(0.24 * sx, 0.13, 0.08); root.add(f); this.feet.push(f);
    }
    // хвостик-помпон: три шарика дугой, одно неоновое колечко
    this.tailSegs = [];
    const tailCols = [COL.furDark, new THREE.Color(0xb3b1b6), COL.furDark];
    const tailR = [0.17, 0.14, 0.11];
    for (let i = 0; i < 3; i++) {
      const seg = furMesh(new THREE.SphereGeometry(tailR[i], 22, 16), furMaterial(1, tailCols[i], { len: 0.06, layers: 12, density: 70 }));
      body.add(seg); this.tailSegs.push(seg);
    }
    this.tailRing = new THREE.Mesh(new THREE.TorusGeometry(0.135, 0.018, 8, 28), neon()); body.add(this.tailRing);

    // маленький плащ с эмблемой
    const capeMat = new THREE.MeshPhysicalMaterial({ map: capeTexture(), color: 0xffffff, roughness: 0.55, sheen: 1, sheenColor: new THREE.Color(0xff5a5a), sheenRoughness: 0.45, side: THREE.DoubleSide });
    this.cape = new Cape(capeMat, { W: 10, H: 8, width: 0.85, length: 0.55 });
    this.scene.add(this.cape.mesh);
    this.capeAnchorsLocal = [];
    for (let i = 0; i < this.cape.W; i++) {
      const u = i / (this.cape.W - 1);
      const x = THREE.MathUtils.lerp(-0.32, 0.32, u);
      const z = -0.44 - 0.08 * Math.cos((u - 0.5) * Math.PI);
      this.capeAnchorsLocal.push(new THREE.Vector3(x, 0.34 - 0.05 * Math.abs(u - 0.5) * 2, z));
    }

    // эффекты: голограмма, волны, искры, «z», тень
    const holoC = document.createElement('canvas'); holoC.width = 256; holoC.height = 160;
    this.holoCtx = holoC.getContext('2d'); this.holoTex = new THREE.CanvasTexture(holoC);
    this.holo = new THREE.Mesh(new THREE.PlaneGeometry(0.56, 0.35), new THREE.MeshBasicMaterial({ map: this.holoTex, transparent: true, opacity: 0.9, toneMapped: false, side: THREE.DoubleSide, depthWrite: false, blending: THREE.AdditiveBlending }));
    this.holo.position.set(0, -0.1, 0.9); this.holo.rotation.x = -0.3; body.add(this.holo);
    this.waves = [];
    for (let i = 0; i < 3; i++) {
      const w = new THREE.Mesh(new THREE.TorusGeometry(0.22, 0.013, 6, 48, Math.PI * 0.7), neon());
      w.material = w.material.clone(); w.material.transparent = true;
      w.rotation.y = Math.PI / 2; w.rotation.z = Math.PI * 0.65; w.position.set(-0.72, -0.02, -0.04);
      body.add(w); this.waves.push(w);
    }
    this.fx = new THREE.Group(); root.add(this.fx);
    this.sparks = [];
    for (let i = 0; i < 10; i++) { const s = glowSprite(0.16, i % 3 === 0 ? COL.red : COL.glow, 0.9); this.fx.add(s); this.sparks.push({ s, a: Math.random() * 6.28, r: 0.5 + Math.random() * 0.5, y: 0.8 + Math.random() * 0.8, sp: 0.6 + Math.random() }); }
    this.zs = [];
    for (let i = 0; i < 3; i++) {
      const c = document.createElement('canvas'); c.width = c.height = 64; const g = c.getContext('2d');
      g.fillStyle = '#e8fffd'; g.font = '900 52px Arial'; g.textAlign = 'center'; g.fillText('z', 32, 48);
      const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(c), transparent: true, depthWrite: false }));
      sp.scale.set(0.24, 0.24, 1); this.fx.add(sp); this.zs.push(sp);
    }
    const shC = document.createElement('canvas'); shC.width = shC.height = 128; const sg = shC.getContext('2d');
    const grd = sg.createRadialGradient(64, 64, 0, 64, 64, 64); grd.addColorStop(0, 'rgba(0,0,0,0.5)'); grd.addColorStop(1, 'rgba(0,0,0,0)'); sg.fillStyle = grd; sg.fillRect(0, 0, 128, 128);
    this.shadow = new THREE.Mesh(new THREE.PlaneGeometry(1.05, 0.5), new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(shC), transparent: true, depthWrite: false }));
    this.shadow.rotation.x = -Math.PI / 2; this.shadow.position.y = 0.002; this.scene.add(this.shadow);
  }

  setState(s) { this.state = s; }
  setFacing(f) { this.facing = f; }
  setLite(on) {
    if (this.lite === on) return;
    this.lite = on;
    this.cape.mesh.visible = !on; this.shadow.visible = !on;
  }
  setHidden(hide) {
    this.root.visible = !hide;
    this.cape.mesh.visible = !hide && !this.lite;
    this.shadow.visible = !hide && !this.lite;
  }

  target(dt) {
    const t = this.t, s = this.state, T = {
      rootY: 0, rotY: 0, bodyY: 0.8, lean: 0, squash: 1, breathe: 1,
      handY: -0.32, handLY: -0.32, waveArm: 0, step: 0,
      wag: 0.35, eyes: 1, mouthOpen: 0, holo: 0, waves: 0, sparks: 0, sleep: 0,
      wind: [0, -0.6, -1.2],
    };
    const facingY = this.facing === 0 ? 0.3 : this.facing * (Math.PI / 2 - 0.35);
    T.rotY = facingY + this.look.x * 0.15;
    const br = Math.sin(t * 2.1);
    switch (s) {
      case 'walk': {
        this.phase += dt * 9;
        T.rootY = Math.abs(Math.sin(this.phase)) * 0.09;
        T.step = 1; T.lean = 0.14; T.wag = 1.2;
        T.wind = [0, -1.8, -2.2]; break;
      }
      case 'idle':
        T.breathe = 1 + 0.018 * br; T.bodyY = 0.8 + 0.012 * br; break;
      case 'listen':
        T.lean = -0.05; T.waves = 1; T.handY = 0.05; T.wag = 0.6; break;
      case 'wave':
        T.waveArm = 1; T.mouthOpen = 0.6; T.wag = 1; break;
      case 'work':
        T.holo = 1; T.lean = 0.12; T.handY = -0.12; T.handLY = -0.12; break;
      case 'cheer': {
        const j = Math.abs(Math.sin(t * 6.5));
        T.rootY = 0.3 * j; T.handY = 0.25; T.handLY = 0.25; T.sparks = 1; T.mouthOpen = 1; T.eyes = 0.5;
        T.wag = 1.6; T.wind = [0, -3 + 7 * Math.cos(t * 6.5), -2.4]; break;
      }
      case 'sit':
        T.squash = 0.93; T.bodyY = 0.72; T.wag = 0.25; break;
      case 'sleep':
        T.squash = 0.88; T.bodyY = 0.66; T.sleep = 1; T.eyes = 0.06; T.lean = 0.12;
        T.wag = 0.05; T.breathe = 1 + 0.03 * Math.sin(t * 1.4); T.wind = [0, -0.4, -0.5]; break;
    }
    if (typeof window !== 'undefined' && window.__tuneMini && window.__tuneMini[s]) Object.assign(T, window.__tuneMini[s]);
    return T;
  }

  update(dt) {
    this.t += dt; const t = this.t;
    this.nextLook -= dt;
    if (this.nextLook < 0) { this.lookTarget.set((Math.random() - 0.5) * 1.2, (Math.random() - 0.5) * 0.6); this.nextLook = 1.5 + Math.random() * 3; }
    this.look.lerp(this.lookTarget, 1 - Math.exp(-dt * 3));
    const T = this.target(dt);
    const k = 1 - Math.exp(-dt * 9), C = this.cur;
    for (const key in T) {
      const v = T[key];
      if (Array.isArray(v)) { C[key] = C[key] || v.slice(); for (let i = 0; i < v.length; i++) C[key][i] += (v[i] - C[key][i]) * k; }
      else { C[key] = C[key] === undefined ? v : C[key] + (v - C[key]) * k; }
    }
    this.root.position.y = C.rootY;
    this.root.rotation.y = C.rotY;
    this.body.position.y = C.bodyY;
    const sq = C.squash * C.breathe;
    this.body.scale.set(1 / Math.sqrt(sq), sq, 1 / Math.sqrt(sq));
    this.body.rotation.x = C.lean + this.look.y * 0.15;
    this.body.rotation.z = Math.sin(t * 1.1) * 0.02;
    // ножки: на месте стоят, в шаге семенят
    const p = this.phase;
    this.feet[0].position.z = 0.08 + C.step * Math.sin(p) * 0.2;
    this.feet[1].position.z = 0.08 - C.step * Math.sin(p) * 0.2;
    this.feet[0].position.y = 0.13 + C.step * Math.max(0, Math.sin(p)) * 0.07;
    this.feet[1].position.y = 0.13 + C.step * Math.max(0, -Math.sin(p)) * 0.07;
    // ручки
    const wave = C.waveArm * (0.25 + 0.1 * Math.sin(t * 9));
    this.hands[0].position.set(0.5, C.handLY - 0.08 + C.step * Math.sin(p + Math.PI) * 0.07, 0.22);
    this.hands[1].position.set(-0.5, C.handY - 0.08 + wave + C.step * Math.sin(p) * 0.07, 0.22 + C.waveArm * 0.1);
    // хвостик виляет
    const wag = Math.sin(t * 4.2) * 0.14 * C.wag;
    this.tailSegs[0].position.set(wag * 0.4, -0.42, -0.5);
    this.tailSegs[1].position.set(wag, -0.38, -0.72);
    this.tailSegs[2].position.set(wag * 1.7, -0.22, -0.88);
    this.tailRing.position.copy(this.tailSegs[1].position);
    this.tailRing.lookAt(this.tailSegs[2].getWorldPosition(new THREE.Vector3()));
    // моргание
    this.blinkT -= dt;
    let blink = 1; if (this.blinkT < 0) { blink = 0.1; if (this.blinkT < -0.12) this.blinkT = 2.5 + Math.random() * 3; }
    for (const e of this.eyes) e.scale.y = Math.min(C.eyes, blink);
    this.mouth.scale.set(1, 1 + C.mouthOpen * 1.5, 1);
    this.ears[0].rotation.x = Math.sin(t * 1.3) * 0.06 + (Math.sin(t * 0.5) > 0.97 ? 0.3 : 0);
    this.ears[1].rotation.x = Math.sin(t * 1.1 + 1) * 0.06;
    const pulse = 0.75 + 0.25 * Math.sin(t * 3);
    for (const g of this.cupGlows) g.material.opacity = 0.45 * pulse;
    this.visorGlow.material.opacity = 0.4 + 0.2 * Math.sin(t * 4.3);
    this.holo.visible = C.holo > 0.05; this.holo.material.opacity = C.holo * 0.9;
    if (this.holo.visible) this.drawHolo(t);
    this.waves.forEach((w, i) => { const q = (t * 0.9 + i / 3) % 1; w.visible = C.waves > 0.05; w.scale.setScalar(1 + q * 1.8); w.material.opacity = (1 - q) * C.waves; });
    this.sparks.forEach((sp) => { sp.s.visible = C.sparks > 0.05; const a = sp.a + t * sp.sp; sp.s.position.set(Math.cos(a) * sp.r, sp.y + Math.sin(t * 3 + sp.a) * 0.15, Math.sin(a) * sp.r * 0.6); sp.s.material.opacity = C.sparks * (0.5 + 0.5 * Math.sin(t * 8 + sp.a)); });
    this.zs.forEach((z, i) => { const q = (t * 0.35 + i / 3) % 1; z.visible = C.sleep > 0.05; z.position.set(0.45 + q * 0.4, 1.45 + q * 0.7, 0.2); z.material.opacity = (1 - q) * C.sleep; z.scale.setScalar(0.16 + 0.1 * i + q * 0.08); });
    this.shadow.scale.setScalar(1 - Math.min(0.4, C.rootY * 0.8));
    this.root.updateMatrixWorld(true);
    if (!this.lite) {
      const anchors = this.capeAnchorsLocal.map((v) => this.body.localToWorld(v.clone()));
      const center = new THREE.Vector3(0, 0, 0); this.body.localToWorld(center);
      const w = new THREE.Vector3(...C.wind).applyQuaternion(this.root.quaternion);
      const sub = 2, h = Math.min(dt, 1 / 30) / sub;
      for (let i = 0; i < sub; i++) this.cape.step(h, anchors, [{ c: center, r: 0.68 }], [w.x, w.y, w.z]);
    }
  }

  drawHolo(t) {
    const g = this.holoCtx, W = 256, H = 160;
    g.clearRect(0, 0, W, H);
    g.strokeStyle = 'rgba(99,255,242,0.95)'; g.lineWidth = 4; roundRect(g, 6, 6, W - 12, H - 12, 14); g.stroke();
    for (let i = 0; i < 7; i++) { const h = 20 + 80 * Math.abs(Math.sin(t * 2.4 + i * 0.9)); g.fillStyle = `rgba(99,255,242,${0.55 + 0.4 * (i % 2)})`; g.fillRect(24 + i * 31, H - 22 - h, 18, h); }
    g.fillStyle = 'rgba(255,255,255,0.8)'; g.fillRect(24, 22, 120 + 60 * Math.sin(t * 1.7), 6);
    this.holoTex.needsUpdate = true;
  }
}


// ───────────────────────── Андреич-конструктивист ─────────────────────────
// Версия для oaiweb.ru: собран из прямоугольных плашек, как и сам сайт.
// Плоские заливки в четыре краски, жёсткий чёрный контур, никакого меха.
export class BlockAndreich {
  constructor(scene) {
    this.scene = scene;
    this.state = 'idle'; this.facing = 0; this.lite = false;
    this.t = 0; this.phase = 0; this.cur = {}; this.blinkT = 3;
    this.build();
  }

  build() {
    const INK = 0x151010, PAPER = 0xf0ede6, RED = 0xe1251b, AMBER = 0xf0a43c;
    const grad = (() => {   // двухступенчатый свет: плакат, не пластик
      const c = document.createElement('canvas'); c.width = 4; c.height = 1;
      const g = c.getContext('2d');
      g.fillStyle = '#9a927f'; g.fillRect(0, 0, 2, 1);
      g.fillStyle = '#ffffff'; g.fillRect(2, 0, 2, 1);
      const t = new THREE.CanvasTexture(c); t.minFilter = t.magFilter = THREE.NearestFilter;
      return t;
    })();
    const mat = (color) => new THREE.MeshToonMaterial({ color, gradientMap: grad });
    const ink = new THREE.MeshBasicMaterial({ color: INK });
    const red = new THREE.MeshBasicMaterial({ color: RED, toneMapped: false });
    const outlineMat = new THREE.MeshBasicMaterial({ color: INK, side: THREE.BackSide });
    const box = (w, h, d, m, outline = true) => {
      const g = new THREE.Group();
      const core = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m);
      g.add(core);
      if (outline) {
        const o = new THREE.Mesh(core.geometry, outlineMat);
        o.scale.setScalar(1.0).multiplyScalar(1);
        o.scale.set((w + 0.07) / w, (h + 0.07) / h, (d + 0.07) / d);
        g.add(o);
      }
      return g;
    };

    const root = this.root = new THREE.Group(); this.scene.add(root);
    const body = this.body = this.head = new THREE.Group(); body.position.y = 0.85; root.add(body);

    // голова-плашка
    body.add(box(1.14, 1.0, 0.94, mat(PAPER)));
    // маска — чёрная лента поперёк, как плашка с заголовком
    const mask = box(1.18, 0.34, 0.97, ink, false); mask.position.y = 0.12; body.add(mask);
    // глаза: квадратные, янтарные, на маске
    this.eyes = [];
    for (const sx of [-1, 1]) {
      const eye = new THREE.Mesh(new THREE.PlaneGeometry(0.2, 0.2), new THREE.MeshBasicMaterial({ color: AMBER, toneMapped: false }));
      eye.position.set(0.26 * sx, 0.12, 0.492); body.add(eye);
      const pupil = new THREE.Mesh(new THREE.PlaneGeometry(0.09, 0.09), new THREE.MeshBasicMaterial({ color: INK }));
      pupil.position.set(0.26 * sx - 0.02 * sx, 0.1, 0.494); body.add(pupil);
      this.eyes.push(eye);
    }
    // нос и рот
    const nose = box(0.16, 0.12, 0.1, ink, false); nose.position.set(0, -0.16, 0.5); body.add(nose);
    const mouth = this.mouth = new THREE.Mesh(new THREE.PlaneGeometry(0.3, 0.05), red);
    mouth.position.set(0, -0.34, 0.493); body.add(mouth);
    // уши: чёрные квадраты углом, как флажки
    this.ears = [];
    for (const sx of [-1, 1]) {
      const ear = box(0.34, 0.34, 0.1, ink, false);
      ear.position.set(0.44 * sx, 0.62, 0); ear.rotation.z = sx * Math.PI / 4;
      body.add(ear); this.ears.push(ear);
    }
    // наушники: плашки по бокам со знаком OAI WEB
    for (const sx of [-1, 1]) {
      const cup = box(0.14, 0.44, 0.44, ink, false); cup.position.set(0.63 * sx, 0.06, 0); body.add(cup);
      const badge = new THREE.Mesh(new THREE.PlaneGeometry(0.3, 0.3),
        new THREE.MeshBasicMaterial({ map: logoTexture(), transparent: true, toneMapped: false }));
      badge.position.set(0.705 * sx, 0.06, 0); badge.rotation.y = sx * Math.PI / 2; body.add(badge);
    }
    const band = box(1.4, 0.1, 0.12, ink, false); band.position.y = 0.6; body.add(band);
    // лапки и ножки — кубики
    this.hands = [];
    for (const sx of [-1, 1]) {
      const h = box(0.22, 0.22, 0.22, mat(PAPER)); h.position.set(0.56 * sx, -0.62, 0.2); body.add(h); this.hands.push(h);
    }
    this.feet = [];
    for (const sx of [-1, 1]) {
      const f = box(0.3, 0.18, 0.4, ink, false); f.position.set(0.26 * sx, 0.1, 0.06); root.add(f); this.feet.push(f);
    }
    // хвост: три плашки лесенкой, чёрная-кремовая-красная
    this.tail = new THREE.Group(); this.tail.position.set(0, -0.3, -0.56); body.add(this.tail);
    const tcols = [ink, mat(PAPER), red];
    for (let i = 0; i < 3; i++) {
      const seg = box(0.26 - i * 0.05, 0.26 - i * 0.05, 0.16, tcols[i], i === 1);
      seg.position.set(0, i * 0.16, -0.14 - i * 0.14); this.tail.add(seg);
    }
    // флаг-плащ: жёсткий красный прямоугольник
    const flagTex = capeTexture();
    this.flag = new THREE.Mesh(new THREE.PlaneGeometry(0.9, 0.62, 12, 1),
      new THREE.MeshBasicMaterial({ map: flagTex, side: THREE.DoubleSide, toneMapped: false }));
    this.flag.position.set(0, 0.1, -0.62); body.add(this.flag);
    this.flagBase = this.flag.geometry.attributes.position.array.slice();
    // «z», волны и искры — как у кругляша
    this.fx = new THREE.Group(); root.add(this.fx);
    this.zs = [];
    for (let i = 0; i < 3; i++) {
      const c = document.createElement('canvas'); c.width = c.height = 64; const g = c.getContext('2d');
      g.fillStyle = '#151010'; g.font = '900 52px Arial'; g.textAlign = 'center'; g.fillText('z', 32, 48);
      const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(c), transparent: true, depthWrite: false }));
      sp.scale.set(0.24, 0.24, 1); this.fx.add(sp); this.zs.push(sp);
    }
    this.waves = [];
    for (let i = 0; i < 3; i++) {
      const w = new THREE.Mesh(new THREE.PlaneGeometry(0.1, 0.26), red.clone());
      w.material.transparent = true;
      w.position.set(-0.85 - i * 0.16, 0.06, 0); body.add(w); this.waves.push(w);
    }
    this.shadow = new THREE.Mesh(new THREE.PlaneGeometry(1.2, 0.4),
      new THREE.MeshBasicMaterial({ color: INK, transparent: true, opacity: 0.18, depthWrite: false }));
    this.shadow.rotation.x = -Math.PI / 2; this.shadow.position.y = 0.002; this.scene.add(this.shadow);
  }

  setState(s) { this.state = s; }
  setFacing(f) { this.facing = f; }
  setLite(on) { this.lite = on; this.shadow.visible = !on; }
  setHidden(hide) { this.root.visible = !hide; this.shadow.visible = !hide && !this.lite; }

  target() {
    const t = this.t, s = this.state, T = {
      rootY: 0, rotY: 0, bodyY: 0.85, lean: 0, squash: 1, step: 0, wag: 0.3,
      eyes: 1, mouthW: 1, waves: 0, sleep: 0, handY: -0.62, waveArm: 0,
    };
    const facingY = this.facing === 0 ? 0.26 : this.facing * (Math.PI / 2 - 0.3);
    T.rotY = facingY;
    switch (s) {
      case 'walk': this.phase += 0.14; T.rootY = Math.abs(Math.sin(this.phase)) * 0.08; T.step = 1; T.lean = 0.12; T.wag = 1.2; break;
      case 'idle': T.bodyY = 0.85 + 0.02 * Math.sin(t * 2.1); break;
      case 'listen': T.waves = 1; T.lean = -0.04; T.wag = 0.6; break;
      case 'wave': T.waveArm = 1; T.wag = 1; break;
      case 'work': T.lean = 0.1; T.handY = -0.4; break;
      case 'cheer': { const j = Math.abs(Math.sin(t * 6.5)); T.rootY = 0.26 * j; T.handY = -0.1; T.wag = 1.6; T.mouthW = 1.6; break; }
      case 'sit': T.squash = 0.94; T.bodyY = 0.78; break;
      case 'sleep': T.squash = 0.9; T.bodyY = 0.72; T.sleep = 1; T.eyes = 0.12; T.lean = 0.1; T.wag = 0.05; break;
    }
    return T;
  }

  update(dt) {
    this.t += dt; const t = this.t;
    const T = this.target();
    const k = 1 - Math.exp(-dt * 9), C = this.cur;
    for (const key in T) { const v = T[key]; C[key] = C[key] === undefined ? v : C[key] + (v - C[key]) * k; }
    this.root.position.y = C.rootY;
    this.root.rotation.y = C.rotY;
    this.body.position.y = C.bodyY;
    this.body.scale.set(1 / Math.sqrt(C.squash), C.squash, 1 / Math.sqrt(C.squash));
    this.body.rotation.x = C.lean;
    this.body.rotation.z = Math.sin(t * 1.3) * 0.015;
    const p = this.phase;
    this.feet[0].position.z = 0.06 + C.step * Math.sin(p) * 0.2;
    this.feet[1].position.z = 0.06 - C.step * Math.sin(p) * 0.2;
    const wave = C.waveArm * (0.3 + 0.12 * Math.sin(t * 9));
    this.hands[0].position.y = C.handY + C.step * Math.sin(p + Math.PI) * 0.06;
    this.hands[1].position.y = C.handY + wave + C.step * Math.sin(p) * 0.06;
    this.tail.rotation.y = Math.sin(t * 4.2) * 0.4 * C.wag;
    this.blinkT -= dt;
    let blink = 1; if (this.blinkT < 0) { blink = 0.08; if (this.blinkT < -0.1) this.blinkT = 2.5 + Math.random() * 3; }
    for (const e of this.eyes) e.scale.y = Math.min(C.eyes, blink);
    this.mouth.scale.x = C.mouthW;
    this.ears[0].rotation.z = Math.PI / 4 * -1 + Math.sin(t * 1.3) * 0.06;
    this.ears[1].rotation.z = Math.PI / 4 + Math.sin(t * 1.1 + 1) * 0.06;
    // флаг: жёсткая волна по синусу — печатный, не тряпичный
    const pos = this.flag.geometry.attributes.position, base = this.flagBase;
    for (let i = 0; i < pos.count; i++) {
      const x = base[i * 3];
      pos.setZ(i, Math.sin(t * 3 + x * 4) * 0.05 * (0.5 - x / 0.9) * (C.step + 0.4));
    }
    pos.needsUpdate = true;
    this.waves.forEach((w, i) => { const q = (t * 0.9 + i / 3) % 1; w.visible = C.waves > 0.05; w.material.opacity = (1 - q) * C.waves; });
    this.zs.forEach((z, i) => { const q = (t * 0.35 + i / 3) % 1; z.visible = C.sleep > 0.05; z.position.set(0.5 + q * 0.4, 1.5 + q * 0.7, 0.2); z.material.opacity = (1 - q) * C.sleep; });
    this.shadow.scale.setScalar(1 - Math.min(0.4, C.rootY * 0.8));
    this.root.updateMatrixWorld(true);
  }
}

// ───────────────────────── сцена и цикл ─────────────────────────
export function boot(canvas, { transparent = true, head = false, quality = 'full', variant = 'full', theme = '', bg = 0x101114, fit = 1, hardFur = false, pixelate = 0 } = {}) {
  if (quality === 'app') QUALITY.layers = 0.6;
  if (theme) applyTheme(theme);
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: transparent, premultipliedAlpha: true });
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.3;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  if (transparent) renderer.setClearColor(0x000000, 0); else renderer.setClearColor(bg, 1);
  const scene = new THREE.Scene();
  const pm = new THREE.PMREMGenerator(renderer);
  scene.environment = pm.fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = 0.65;
  scene.add(new THREE.HemisphereLight(0xcfe7ff, 0x221a18, 0.9));
  const key = new THREE.DirectionalLight(0xfff1e0, 2.4); key.position.copy(KEY_DIR).multiplyScalar(8); scene.add(key);
  const rim = new THREE.DirectionalLight(0x63fff2, 2.4); rim.position.set(-4, 3, -5); scene.add(rim);
  const fill = new THREE.DirectionalLight(0xffffff, 0.9); fill.position.set(-2, 1.5, 8); scene.add(fill);
  const rim2 = new THREE.DirectionalLight(0xff4a4a, 0.8); rim2.position.set(5, 2, -4); scene.add(rim2);

  const camera = new THREE.PerspectiveCamera(27, 1, 0.1, 60);
  const andreich = new Andreich(scene);
  const mini = new MiniAndreich(scene);
  const block = new BlockAndreich(scene);
  let shape = variant;                       // 'full' | 'mini' (кругляш) | 'block' (конструктивист)
  const active = () => (shape === 'mini' ? mini : shape === 'block' ? block : andreich);
  const applyShape = () => { andreich.setHidden(shape !== 'full'); mini.setHidden(shape !== 'mini'); block.setHidden(shape !== 'block'); };
  applyShape();
  let viewMode = head ? 'head' : 'full';
  const headPos = new THREE.Vector3(), camTarget = new THREE.Vector3(0, 1.08, 0), camPos = new THREE.Vector3(0, 1.3, 7.9);
  const frame = (snap) => {
    const miniNow = shape !== 'full';
    let tp, cp;
    if (viewMode === 'head') {
      active().head.getWorldPosition(headPos);
      camera.fov = 19;
      tp = headPos.clone().add(new THREE.Vector3(0, miniNow ? 0.02 : 0.05, 0));
      cp = headPos.clone().add(new THREE.Vector3(0, miniNow ? 0.08 : 0.12, miniNow ? 4.6 : 5.1));
    } else {
      camera.fov = 27;
      tp = miniNow ? new THREE.Vector3(0, 0.78, 0) : new THREE.Vector3(0, 1.08, 0);
      cp = miniNow ? new THREE.Vector3(0, 0.9, 6.6 / fit) : new THREE.Vector3(0, 1.3, 7.9 / fit);
    }
    if (snap) { camTarget.copy(tp); camPos.copy(cp); } else { camTarget.lerp(tp, 0.2); camPos.lerp(cp, 0.2); }
    camera.position.copy(camPos); camera.lookAt(camTarget); camera.updateProjectionMatrix();
  };
  if (hardFur) scene.traverse((o) => { if (o.isInstancedMesh && o.material.uniforms && o.material.uniforms.uHard) o.material.uniforms.uHard.value = 1; });

  // Пиксельный оттиск: лоу-рез буфер + квантизация в печатную палитру сайта.
  let post = null;
  if (pixelate > 0) {
    renderer.setPixelRatio(1);
    const pal = ['#151010', '#3a2f2a', '#9c8468', '#e3dccb', '#f6f1e4', '#e1251b', '#f0a43c']
      .map((c) => new THREE.Color(c));
    const rt = new THREE.WebGLRenderTarget(64, 64, { depthBuffer: true, samples: 0 });
    rt.texture.minFilter = THREE.NearestFilter; rt.texture.magFilter = THREE.NearestFilter;
    const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), new THREE.ShaderMaterial({
      glslVersion: THREE.GLSL3,
      uniforms: { uTex: { value: rt.texture }, uPal: { value: pal } },
      vertexShader: 'out vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }',
      fragmentShader: `layout(location = 0) out highp vec4 pc_fragColor;
        uniform sampler2D uTex; uniform vec3 uPal[7]; in vec2 vUv;
        void main(){
          vec4 t = texture(uTex, vUv);
          if (t.a < 0.5) discard;
          vec3 c = pow(max(t.rgb, 0.0), vec3(0.4545));
          vec3 best = uPal[0]; float bd = 1e9;
          for (int i = 0; i < 7; i++) { float d = distance(c, uPal[i]); if (d < bd) { bd = d; best = uPal[i]; } }
          pc_fragColor = vec4(best, 1.0);
        }`,
      transparent: true, depthTest: false, depthWrite: false,
    }));
    const pScene = new THREE.Scene(); pScene.add(quad);
    const pCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    post = { rt, scene: pScene, cam: pCam, px: pixelate };
  }
  andreich.update(0.016); mini.update(0.016); block.update(0.016); frame(true);
  const resize = () => {
    const w = canvas.clientWidth, h = canvas.clientHeight;
    renderer.setSize(w, h, false); camera.aspect = w / h; camera.updateProjectionMatrix();
    if (post) post.rt.setSize(Math.max(24, Math.round(w / post.px)), Math.max(24, Math.round(h / post.px)));
  };
  resize(); new ResizeObserver(resize).observe(canvas);

  let last = performance.now(), fps = 60, acc = 0;
  const xf = { rot: 0, scale: 1 };
  const applyXf = () => { canvas.style.transform = `rotate(${xf.rot}deg) scale(${xf.scale})`; };
  const api = {
    andreich, mini, block, renderer,
    setState: (s) => { andreich.setState(s); mini.setState(s); block.setState(s); },
    setFacing: (f) => { andreich.setFacing(f); mini.setFacing(f); block.setFacing(f); },
    setFPS: (f) => { fps = f; },
    setRotation: (deg) => { xf.rot = deg; applyXf(); },
    setScale: (k) => { xf.scale = k; applyXf(); },
    setView: (m) => { viewMode = m; andreich.setLite(m === 'head'); mini.setLite(m === 'head'); block.setLite(m === 'head'); applyShape(); frame(true); },
    setVariant: (v) => { if (v !== shape) { shape = v; applyShape(); frame(true); } },
  };
  const loop = (now) => {
    requestAnimationFrame(loop);
    const dt = Math.min(0.05, (now - last) / 1000); last = now; acc += dt;
    if (acc < 1 / fps - 0.002) return;
    active().update(acc); acc = 0;
    frame(false);
    if (post) {
      renderer.setRenderTarget(post.rt);
      renderer.render(scene, camera);
      renderer.setRenderTarget(null);
      renderer.render(post.scene, post.cam);
    } else {
      renderer.render(scene, camera);
    }
  };
  requestAnimationFrame(loop);
  return api;
}
