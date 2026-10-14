// three-lite.js: a tiny flat-shaded 3D renderer for canvas 2D, pure functions of their inputs.
// Meshes are built once (at module load) from convex parts; draw3d() transforms, lights
// (Lambert + Blinn specular, depth fog), culls back faces, sorts and fills, and can stroke
// edges in a hairline colour for the engraved look.

export const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
export const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
export const mul = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
export const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
export const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
export const len = (a) => Math.hypot(a[0], a[1], a[2]);
export const norm = (a) => { const l = len(a) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };

export function rotX(p, a) { const c = Math.cos(a), s = Math.sin(a); return [p[0], p[1] * c - p[2] * s, p[1] * s + p[2] * c]; }
export function rotY(p, a) { const c = Math.cos(a), s = Math.sin(a); return [p[0] * c + p[2] * s, p[1], -p[0] * s + p[2] * c]; }
export function rotZ(p, a) { const c = Math.cos(a), s = Math.sin(a); return [p[0] * c - p[1] * s, p[0] * s + p[1] * c, p[2]]; }

export function camera({ pos, target, up = [0, 1, 0], fov = 50, W, H, roll = 0 }) {
  const f = norm(sub(target, pos));
  let r = norm(cross(up, f));     // +x is screen-right when looking down +z with +y up
  let u = cross(f, r);
  if (roll) {
    const c = Math.cos(roll), s = Math.sin(roll);
    const r2 = add(mul(r, c), mul(u, s)), u2 = add(mul(u, c), mul(r, -s));
    r = r2; u = u2;
  }
  const focal = (H / 2) / Math.tan((fov * Math.PI) / 360);
  return {
    pos, f, r, u, focal, cx: W / 2, cy: H / 2, near: 0.5,
    toCam(p) { const d = sub(p, pos); return [dot(d, r), dot(d, u), dot(d, f)]; },
    project(p) {
      const c = this.toCam(p);
      if (c[2] < this.near) return null;
      return [this.cx + (c[0] * focal) / c[2], this.cy - (c[1] * focal) / c[2], c[2]];
    },
  };
}

// A part: { v: [[x,y,z]...], f: [[i,j,k,...]...], c: [r,g,b] (0..1), spec?, edge?, emissive? }
// Faces are re-wound at build time so their normals point away from the part's centroid
// (parts are convex), which makes back-face culling reliable.
export function part(v, f, opts = {}) {
  const cen = v.reduce((a, p) => add(a, p), [0, 0, 0]).map((x) => x / v.length);
  const faces = f.map((idx) => {
    const a = v[idx[0]], b = v[idx[1]], c = v[idx[2]];
    const n = cross(sub(b, a), sub(c, a));
    const fc = idx.reduce((s, i) => add(s, v[i]), [0, 0, 0]).map((x) => x / idx.length);
    return dot(n, sub(fc, cen)) < 0 ? idx.slice().reverse() : idx;
  });
  return { v, f: faces, c: opts.c || [0.5, 0.5, 0.5], spec: opts.spec ?? 0.2, shin: opts.shin ?? 24,
    edge: opts.edge ?? null, emissive: opts.emissive ?? 0, twoSided: !!opts.twoSided, faceColors: opts.faceColors || null };
}

// Extrude a 2D polygon (x, y) along z, centred. Convex polygons only (use triangulated parts otherwise).
export function extrude(poly, depth, opts) {
  const n = poly.length, h = depth / 2;
  const v = [...poly.map(([x, y]) => [x, y, h]), ...poly.map(([x, y]) => [x, y, -h])];
  const f = [poly.map((_, i) => i), poly.map((_, i) => n + i)];
  for (let i = 0; i < n; i++) { const j = (i + 1) % n; f.push([i, j, n + j, n + i]); }
  return part(v, f, opts);
}

// Star of `points` points as a set of convex wedges (each a kite), extruded with a bevel ridge.
export function starParts(points, R, r, depth, opts) {
  const parts = [];
  for (let k = 0; k < points; k++) {
    const a = (k / points) * Math.PI * 2 - Math.PI / 2;
    const a0 = a - Math.PI / points, a1 = a + Math.PI / points;
    const tip = [Math.cos(a) * R, Math.sin(a) * R];
    const l = [Math.cos(a0) * r, Math.sin(a0) * r], rr = [Math.cos(a1) * r, Math.sin(a1) * r];
    const h = depth / 2;
    // two bevelled halves: centre ridge raised, edges low
    for (const side of [l, rr]) {
      const v = [[0, 0, h * 1.6], [tip[0], tip[1], 0], [side[0], side[1], 0], [0, 0, -h * 1.6]];
      parts.push(part(v, [[0, 1, 2], [3, 2, 1], [0, 2, 3], [0, 3, 1]], opts));
    }
  }
  return parts;
}

export function lathe(profile, segs, opts) {
  // profile: [[radius, y], ...] bottom to top
  const v = [];
  for (let s = 0; s < segs; s++) {
    const a = (s / segs) * Math.PI * 2;
    for (const [r, y] of profile) v.push([Math.cos(a) * r, y, Math.sin(a) * r]);
  }
  const P = profile.length, parts = [];
  // one convex quad strip per segment, as separate parts so winding fixes stay local
  for (let s = 0; s < segs; s++) {
    const s2 = (s + 1) % segs;
    for (let k = 0; k < P - 1; k++) {
      const q = [v[s * P + k], v[s2 * P + k], v[s2 * P + k + 1], v[s * P + k + 1]];
      // outward = away from the axis
      const mid = q.reduce((a, p) => add(a, p), [0, 0, 0]).map((x) => x / 4);
      const n = cross(sub(q[1], q[0]), sub(q[2], q[0]));
      const out = [mid[0], 0, mid[2]];
      const idx = dot(n, out) < 0 ? [3, 2, 1, 0] : [0, 1, 2, 3];
      parts.push({ v: q, f: [idx], c: opts.c, spec: opts.spec ?? 0.2, shin: opts.shin ?? 24, edge: opts.edge ?? null,
        emissive: opts.emissive ?? 0, twoSided: !!opts.twoSided, faceColors: null });
    }
  }
  return parts;
}

export function box(w, h, d, opts, at = [0, 0, 0]) {
  const x = w / 2, y = h / 2, z = d / 2;
  const v = [[-x, -y, -z], [x, -y, -z], [x, y, -z], [-x, y, -z], [-x, -y, z], [x, -y, z], [x, y, z], [-x, y, z]]
    .map((p) => add(p, at));
  return part(v, [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [0, 3, 7, 4]], opts);
}

// Tapered prism along z: cross-section polygon at z0 scaled by s0, at z1 scaled by s1.
export function taper(section, z0, z1, s0, s1, opts, off = [0, 0, 0]) {
  const n = section.length;
  const v = [...section.map(([x, y]) => [x * s0 + off[0], y * s0 + off[1], z0 + off[2]]),
    ...section.map(([x, y]) => [x * s1 + off[0], y * s1 + off[1], z1 + off[2]])];
  const f = [section.map((_, i) => i), section.map((_, i) => n + i)];
  for (let i = 0; i < n; i++) { const j = (i + 1) % n; f.push([i, j, n + j, n + i]); }
  return part(v, f, opts);
}

function shadeColor(c, k, spec, fogT, fog) {
  let r = c[0] * k + spec, g = c[1] * k + spec * 0.92, b = c[2] * k + spec * 0.7;
  if (fog && fogT > 0) { r += (fog[0] - r) * fogT; g += (fog[1] - g) * fogT; b += (fog[2] - b) * fogT; }
  return `rgb(${Math.round(Math.min(1, r) * 255)},${Math.round(Math.min(1, g) * 255)},${Math.round(Math.min(1, b) * 255)})`;
}

// objects: [{ parts, pos, rot: [rx, ry, rz], scale, tint?, emissiveBoost? }]
// light: { dir, ambient, diffuse, fog: [r,g,b], fogNear, fogFar, edgeAlpha }
export function draw3d(ctx, cam, objects, light = {}) {
  const L = norm(light.dir || [0.4, 0.8, -0.5]);
  const amb = light.ambient ?? 0.32, dif = light.diffuse ?? 0.8;
  const fog = light.fog || null, fn = light.fogNear ?? 50, ff = light.fogFar ?? 400;
  const polys = [];
  for (const o of objects) {
    const s = o.scale ?? 1, [rx, ry, rz] = o.rot || [0, 0, 0];
    for (const p of o.parts) {
      const wv = p.v.map((q) => {
        let w = [q[0] * s, q[1] * s, q[2] * s];
        if (rz) w = rotZ(w, rz);
        if (rx) w = rotX(w, rx);
        if (ry) w = rotY(w, ry);
        if (o.rot2) w = rotY(rotX(w, o.rot2[0]), o.rot2[1]);
        return add(w, o.pos || [0, 0, 0]);
      });
      p.f.forEach((idx, fi) => {
        const a = wv[idx[0]], b = wv[idx[1]], c = wv[idx[2]];
        let n = norm(cross(sub(b, a), sub(c, a)));
        const cen = idx.reduce((acc, i) => add(acc, wv[i]), [0, 0, 0]).map((x) => x / idx.length);
        const view = norm(sub(cam.pos, cen));
        if (dot(n, view) < 0) { if (!p.twoSided) return; n = mul(n, -1); }
        const pts = [];
        for (const i of idx) { const pr = cam.project(wv[i]); if (!pr) return; pts.push(pr); }
        const lam = Math.max(0, dot(n, L));
        const hv = norm(add(L, view));
        const sp = p.spec * Math.pow(Math.max(0, dot(n, hv)), p.shin);
        const depth = pts.reduce((acc, q) => acc + q[2], 0) / pts.length;
        const fogT = fog ? Math.min(1, Math.max(0, (depth - fn) / (ff - fn))) : 0;
        const base = p.faceColors ? p.faceColors[fi] : (o.tint || p.c);
        const k = amb + dif * lam + p.emissive + (o.emissiveBoost || 0);
        polys.push({ pts, depth, col: shadeColor(base, k, sp, fogT, fog), edge: p.edge, fogT });
      });
    }
  }
  polys.sort((a, b) => b.depth - a.depth);
  const ea = light.edgeAlpha ?? 0.8;
  for (const q of polys) {
    ctx.beginPath();
    ctx.moveTo(q.pts[0][0], q.pts[0][1]);
    for (let i = 1; i < q.pts.length; i++) ctx.lineTo(q.pts[i][0], q.pts[i][1]);
    ctx.closePath();
    ctx.fillStyle = q.col;
    ctx.fill();
    // a hairline in the fill colour hides anti-aliasing seams between faces
    ctx.strokeStyle = q.col; ctx.lineWidth = 0.8; ctx.stroke();
    if (q.edge && ea > 0) {
      ctx.globalAlpha = ea * (1 - q.fogT);
      ctx.strokeStyle = q.edge; ctx.lineWidth = Math.max(0.6, Math.min(2.2, 900 / q.depth));
      ctx.stroke();
      ctx.globalAlpha = 1;
    }
  }
  return polys.length;
}
