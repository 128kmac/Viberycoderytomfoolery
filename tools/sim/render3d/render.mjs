// Render an exported harness scene (Sim.export_scene JSON) to PNG with three.js in headless Chromium.
// Approximates Roblox's look (materials, neon glow via bloom, dusk lighting, fog); it exists to check
// layout, readability and composition, not to match Roblox pixel-for-pixel.
//
//   node render.mjs scene.json out.png [width] [height] [cameraJSON]
//   cameraJSON: {"pos":[x,y,z],"look":[x,y,z],"fov":70}   (defaults to the scene's camera)
import { createRequire } from 'module';
import fs from 'fs';
import path from 'path';
import url from 'url';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const here = path.dirname(url.fileURLToPath(import.meta.url));
const [, , sceneFile, outFile, w = '1280', h = '720', camArg] = process.argv;
const scene = JSON.parse(fs.readFileSync(sceneFile, 'utf8'));
const cam = camArg ? JSON.parse(camArg) : null;
const threeUrl = url.pathToFileURL(path.join(here, 'node_modules/three/build/three.module.js')).href;
const jsm = url.pathToFileURL(path.join(here, 'node_modules/three/examples/jsm/')).href;

const html = `<!doctype html><html><head><meta charset="utf-8">
<style>html,body{margin:0;background:#000;overflow:hidden}</style>
<script type="importmap">{"imports":{"three":"${threeUrl}","three/addons/":"${jsm}"}}</script>
</head><body><script type="module">
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
window.renderScene = async (S, cam, W, H) => {
  const arr = (x) => Array.isArray(x) ? x : Object.values(x || {});
  S.parts = arr(S.parts); S.beams = arr(S.beams); S.particles = arr(S.particles); S.lights = arr(S.lights);
  const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
  renderer.setSize(W, H);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  document.body.appendChild(renderer.domElement);
  const scene = new THREE.Scene();
  // dusk sky gradient under Proxima
  const sky = document.createElement('canvas'); sky.width = 4; sky.height = 256;
  const g = sky.getContext('2d'); const grad = g.createLinearGradient(0, 0, 0, 256);
  grad.addColorStop(0, '#120c24'); grad.addColorStop(0.45, '#3a1f46'); grad.addColorStop(0.7, '#a2484a'); grad.addColorStop(0.82, '#e0805a'); grad.addColorStop(1, '#3a2234');
  g.fillStyle = grad; g.fillRect(0, 0, 4, 256);
  const skyTex = new THREE.CanvasTexture(sky); skyTex.colorSpace = THREE.SRGBColorSpace;
  scene.background = skyTex;
  scene.fog = new THREE.Fog(0x6b3b4e, 260, 1300);
  const L = S.lighting || {};
  const amb = L.ambient || [0.18, 0.14, 0.24];
  scene.add(new THREE.HemisphereLight(new THREE.Color(0.75, 0.55, 0.6), new THREE.Color(amb[0] * 1.6, amb[1] * 1.6, amb[2] * 1.8), 0.9));
  const sun = new THREE.DirectionalLight(new THREE.Color(1.0, 0.62, 0.46), 2.2);
  sun.position.set(-280, 140, -400);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  const sc = sun.shadow.camera; sc.left = -220; sc.right = 220; sc.top = 220; sc.bottom = -220; sc.near = 10; sc.far = 1200;
  sun.shadow.bias = -0.0006;
  scene.add(sun);
  const matCache = {};
  const ROUGH = { Metal: [0.35, 0.8], DiamondPlate: [0.4, 0.7], Foil: [0.2, 0.9], Marble: [0.25, 0], Glass: [0.05, 0], Ice: [0.1, 0], SmoothPlastic: [0.45, 0], Plastic: [0.6, 0], Neon: [0.4, 0], ForceField: [0.3, 0] };
  function material(p) {
    const key = p.mat + p.color.join(',') + p.t.toFixed(2);
    if (matCache[key]) return matCache[key];
    const c = new THREE.Color(p.color[0], p.color[1], p.color[2]);
    const rm = ROUGH[p.mat] || [0.85, 0];
    const m = new THREE.MeshStandardMaterial({ color: c, roughness: rm[0], metalness: rm[1] });
    let t = p.t;
    if (p.mat === 'Neon') { m.emissive = c.clone(); m.emissiveIntensity = 2.2; }
    if (p.mat === 'ForceField') { t = Math.max(t, 0.55); m.emissive = c.clone(); m.emissiveIntensity = 0.8; m.depthWrite = false; }
    if (p.mat === 'Glass') { t = Math.max(t, 0.25); }
    if (t > 0.01) { m.transparent = true; m.opacity = 1 - t; if (t > 0.4) m.depthWrite = false; }
    matCache[key] = m;
    return m;
  }
  const geoCache = {};
  function wedgeGeo() {
    // Roblox wedge: high edge at +Z (back), low edge at -Z (front); unit cube centred at origin
    const g = new THREE.BufferGeometry();
    const v = [
      -0.5,-0.5,-0.5, 0.5,-0.5,-0.5, 0.5,-0.5,0.5, -0.5,-0.5,0.5,  // bottom
      -0.5,0.5,0.5, 0.5,0.5,0.5 ];                                 // top back edge
    const idx = [0,2,1, 0,3,2,  3,4,5, 3,5,2,  0,1,5, 0,5,4,  0,4,3,  1,2,5];
    g.setAttribute('position', new THREE.Float32BufferAttribute(v, 3));
    g.setIndex(idx); g.computeVertexNormals();
    return g;
  }
  function geometry(shape) {
    if (geoCache[shape]) return geoCache[shape];
    let g;
    if (shape === 'Ball') g = new THREE.SphereGeometry(0.5, 24, 16);
    else if (shape === 'Cylinder') { g = new THREE.CylinderGeometry(0.5, 0.5, 1, 32); g.rotateZ(Math.PI / 2); }
    else if (shape === 'Wedge') g = wedgeGeo();
    else g = new THREE.BoxGeometry(1, 1, 1);
    geoCache[shape] = g;
    return g;
  }
  const m4 = new THREE.Matrix4();
  for (const p of S.parts) {
    if (p.size[0] > 1500) continue;
    const mesh = new THREE.Mesh(geometry(p.shape), material(p));
    const c = p.cf;
    m4.set(c[3], c[4], c[5], c[0], c[6], c[7], c[8], c[1], c[9], c[10], c[11], c[2], 0, 0, 0, 1);
    mesh.matrixAutoUpdate = false;
    mesh.matrix.copy(m4).multiply(new THREE.Matrix4().makeScale(p.size[0], p.size[1], p.size[2]));
    mesh.castShadow = p.t < 0.3 && p.mat !== 'Neon' && p.mat !== 'ForceField';
    mesh.receiveShadow = true;
    scene.add(mesh);
  }
  // beams as glowing tubes
  for (const b of S.beams || []) {
    const a = new THREE.Vector3(...b.p0), z = new THREE.Vector3(...b.p1);
    const len = a.distanceTo(z); if (len < 0.01) continue;
    const r = Math.max(0.05, (b.w0 + b.w1) / 4);
    const geo = new THREE.CylinderGeometry(r, r, len, 8, 1, true);
    const col = new THREE.Color(...b.color);
    const mat = new THREE.MeshBasicMaterial({ color: col.multiplyScalar(b.glow > 0.5 ? 2.5 : 1), transparent: true, opacity: 1 - b.t, blending: b.glow > 0.5 ? THREE.AdditiveBlending : THREE.NormalBlending, depthWrite: false });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.position.copy(a).add(z).multiplyScalar(0.5);
    mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), z.clone().sub(a).normalize());
    scene.add(mesh);
  }
  // particles
  if ((S.particles || []).length) {
    const pos = [], col = [];
    for (const q of S.particles) { pos.push(...q.pos); const k = (1 - q.t) * (q.glow > 0.5 ? 2.2 : 1); col.push(q.color[0] * k, q.color[1] * k, q.color[2] * k); }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    geo.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
    const pm = new THREE.PointsMaterial({ size: 0.9, vertexColors: true, transparent: true, opacity: 0.9, blending: THREE.AdditiveBlending, depthWrite: false });
    scene.add(new THREE.Points(geo, pm));
  }
  // point lights (nearest to the camera, capped for shader cost)
  const camera = new THREE.PerspectiveCamera(cam && cam.fov || (S.camera && S.camera.fov) || 70, W / H, 0.3, 4000);
  if (cam) { camera.position.set(...cam.pos); camera.lookAt(new THREE.Vector3(...cam.look)); }
  else { const c = S.camera.cf; m4.set(c[3], c[4], c[5], c[0], c[6], c[7], c[8], c[1], c[9], c[10], c[11], c[2], 0, 0, 0, 1); camera.matrixAutoUpdate = false; camera.matrix.copy(m4); camera.matrixWorld.copy(m4); camera.matrixWorldInverse.copy(m4).invert(); }
  const lights = (S.lights || []).slice().sort((a, b) => camera.position.distanceTo(new THREE.Vector3(...a.pos)) - camera.position.distanceTo(new THREE.Vector3(...b.pos))).slice(0, 14);
  for (const l of lights) { const pl = new THREE.PointLight(new THREE.Color(...l.color), l.brightness * 18, l.range * 1.6, 1.6); pl.position.set(...l.pos); scene.add(pl); }
  const composer = new EffectComposer(renderer);
  composer.addPass(new RenderPass(scene, camera));
  composer.addPass(new UnrealBloomPass(new THREE.Vector2(W, H), 0.55, 0.5, 0.82));
  composer.addPass(new OutputPass());
  composer.render();
  return renderer.domElement.toDataURL('image/png');
};
window.ready = true;
</script></body></html>`;

const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--allow-file-access-from-files'] });
const page = await browser.newPage({ viewport: { width: +w, height: +h } });
const tmp = path.join(here, '_page.html');
fs.writeFileSync(tmp, html);
page.on('console', (m) => { if (m.type() === 'error') console.error('[page]', m.text()); });
page.on('pageerror', (e) => console.error('[pageerror]', e.message));
await page.goto(url.pathToFileURL(tmp).href);
await page.waitForFunction('window.ready === true', null, { timeout: 30000 });
const data = await page.evaluate(([S, cam, W, H]) => window.renderScene(S, cam, W, H), [scene, cam, +w, +h]);
fs.writeFileSync(outFile, Buffer.from(data.split(',')[1], 'base64'));
await browser.close();
console.log('wrote', outFile);
