import type { Rng } from '../core/Rng';

/**
 * Paints the procedural ground texture: cracked asphalt, sidewalks along the
 * buildings, a cobblestone plaza around the fountain, faded road markings,
 * oil and blood stains. Coordinates are world metres mapped onto the canvas.
 */
export function drawGroundTexture(canvas: HTMLCanvasElement, worldHalf: number, arenaHalf: number, rng: Rng): void {
  const g = canvas.getContext('2d');
  if (!g) throw new Error('2D canvas unavailable');
  const size = canvas.width;
  const ppm = size / (worldHalf * 2); // pixels per metre
  const px = (x: number): number => (x + worldHalf) * ppm;

  // Asphalt base with speckle noise.
  g.fillStyle = '#3b3d40';
  g.fillRect(0, 0, size, size);
  const speckles = Math.floor(size * size * 0.02);
  for (let i = 0; i < speckles; i++) {
    const l = rng.int(40, 80);
    g.fillStyle = `rgba(${l},${l},${l + 3},${rng.range(0.15, 0.5)})`;
    g.fillRect(rng.next() * size, rng.next() * size, ppm * 0.12, ppm * 0.12);
  }
  // Large tonal patches so the asphalt doesn't read as flat.
  for (let i = 0; i < 70; i++) {
    const x = rng.next() * size;
    const y = rng.next() * size;
    const r = rng.range(3, 9) * ppm;
    const grad = g.createRadialGradient(x, y, 0, x, y, r);
    const dark = rng.chance(0.5);
    grad.addColorStop(0, dark ? 'rgba(20,20,22,0.25)' : 'rgba(110,110,105,0.12)');
    grad.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = grad;
    g.fillRect(x - r, y - r, r * 2, r * 2);
  }

  // Sidewalks along the building rows (north, east, west) with paving seams.
  const sw = 3;
  const A = arenaHalf;
  const paving = (x0: number, z0: number, x1: number, z1: number): void => {
    g.fillStyle = '#6b6862';
    g.fillRect(px(x0), px(z0), (x1 - x0) * ppm, (z1 - z0) * ppm);
    g.strokeStyle = 'rgba(40,38,35,0.55)';
    g.lineWidth = Math.max(1, ppm * 0.05);
    for (let x = Math.ceil(x0); x <= x1; x += 1.5) {
      g.beginPath();
      g.moveTo(px(x), px(z0));
      g.lineTo(px(x), px(z1));
      g.stroke();
    }
    for (let z = Math.ceil(z0); z <= z1; z += 1.5) {
      g.beginPath();
      g.moveTo(px(x0), px(z));
      g.lineTo(px(x1), px(z));
      g.stroke();
    }
    // Kerb.
    g.fillStyle = '#8f8b84';
  };
  paving(-A, -A, A, -A + sw);
  g.fillRect(px(-A), px(-A + sw) - ppm * 0.2, 2 * A * ppm, ppm * 0.25);
  paving(A - sw, -A, A, A);
  g.fillRect(px(A - sw), px(-A), ppm * 0.25, 2 * A * ppm);
  paving(-A, -A, -A + sw, A);
  g.fillRect(px(-A + sw) - ppm * 0.25, px(-A), ppm * 0.25, 2 * A * ppm);

  // Faded lane markings: a loop road around the plaza.
  g.strokeStyle = 'rgba(200,180,90,0.35)';
  g.lineWidth = ppm * 0.18;
  g.setLineDash([ppm * 2, ppm * 1.6]);
  g.strokeRect(px(-22), px(-22), 44 * ppm, 44 * ppm);
  g.setLineDash([]);
  g.strokeStyle = 'rgba(220,220,210,0.22)';
  g.lineWidth = ppm * 0.12;
  g.strokeRect(px(-27), px(-27), 54 * ppm, 54 * ppm);
  // Crosswalk stripes near two alleys.
  g.fillStyle = 'rgba(225,225,215,0.28)';
  for (let i = 0; i < 6; i++) {
    g.fillRect(px(-16 + i * 0.7), px(-31), ppm * 0.4, ppm * 4);
    g.fillRect(px(14 + i * 0.7), px(-31), ppm * 0.4, ppm * 4);
  }
  // Parking bays along the south side.
  g.strokeStyle = 'rgba(230,230,220,0.25)';
  g.lineWidth = ppm * 0.12;
  for (let x = -8; x <= 8; x += 2.8) {
    g.beginPath();
    g.moveTo(px(x), px(30));
    g.lineTo(px(x), px(35));
    g.stroke();
  }

  // Cobblestone plaza.
  const R = 14;
  g.save();
  g.beginPath();
  g.arc(px(0), px(0), R * ppm, 0, Math.PI * 2);
  g.clip();
  g.fillStyle = '#6f6a63';
  g.fillRect(px(-R), px(-R), 2 * R * ppm, 2 * R * ppm);
  const stone = 0.55;
  for (let ring = 0; ring * stone < R; ring++) {
    const rr = ring * stone + stone * 0.5;
    const count = Math.max(6, Math.floor((2 * Math.PI * rr) / stone));
    for (let k = 0; k < count; k++) {
      const a = (k / count) * Math.PI * 2 + ring * 0.37;
      const l = rng.int(92, 128);
      g.fillStyle = `rgb(${l},${l - 6},${l - 12})`;
      const cx = px(Math.cos(a) * rr);
      const cy = px(Math.sin(a) * rr);
      g.save();
      g.translate(cx, cy);
      g.rotate(a);
      g.fillRect(-stone * ppm * 0.42, -stone * ppm * 0.42, stone * ppm * 0.84, stone * ppm * 0.84);
      g.restore();
    }
  }
  g.restore();
  g.strokeStyle = '#8f8a83';
  g.lineWidth = ppm * 0.45;
  g.beginPath();
  g.arc(px(0), px(0), R * ppm, 0, Math.PI * 2);
  g.stroke();

  // Cracks.
  g.strokeStyle = 'rgba(15,15,16,0.6)';
  for (let i = 0; i < 60; i++) {
    let x = rng.range(-worldHalf, worldHalf);
    let z = rng.range(-worldHalf, worldHalf);
    let a = rng.range(0, Math.PI * 2);
    g.lineWidth = rng.range(0.6, 1.6) * (ppm / 20);
    g.beginPath();
    g.moveTo(px(x), px(z));
    const segs = rng.int(4, 10);
    for (let s = 0; s < segs; s++) {
      a += rng.range(-0.8, 0.8);
      const len = rng.range(0.4, 1.4);
      x += Math.cos(a) * len;
      z += Math.sin(a) * len;
      g.lineTo(px(x), px(z));
    }
    g.stroke();
  }

  // Oil stains and old blood.
  for (let i = 0; i < 28; i++) {
    const x = px(rng.range(-A, A));
    const y = px(rng.range(-A, A));
    const r = rng.range(0.6, 2.2) * ppm;
    const blood = rng.chance(0.4);
    const grad = g.createRadialGradient(x, y, 0, x, y, r);
    grad.addColorStop(0, blood ? 'rgba(70,10,8,0.55)' : 'rgba(12,12,14,0.55)');
    grad.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = grad;
    g.beginPath();
    g.ellipse(x, y, r, r * rng.range(0.5, 1), rng.range(0, Math.PI), 0, Math.PI * 2);
    g.fill();
  }

  // Manhole covers.
  for (const [x, z] of [[-18, 6], [20, -18], [8, 26]] as const) {
    g.fillStyle = '#2c2d2f';
    g.beginPath();
    g.arc(px(x), px(z), ppm * 0.6, 0, Math.PI * 2);
    g.fill();
    g.strokeStyle = '#4a4b4e';
    g.lineWidth = ppm * 0.08;
    g.stroke();
  }

  // South vacant lot: dirt and gravel.
  g.fillStyle = 'rgba(85,72,55,0.55)';
  g.fillRect(px(-worldHalf), px(A + 0.6), worldHalf * 2 * ppm, (worldHalf - A) * ppm);
  for (let i = 0; i < size * 6; i++) {
    const l = rng.int(60, 110);
    g.fillStyle = `rgba(${l},${l - 10},${l - 25},0.5)`;
    g.fillRect(rng.next() * size, px(rng.range(A + 0.6, worldHalf)), ppm * 0.15, ppm * 0.15);
  }
}
