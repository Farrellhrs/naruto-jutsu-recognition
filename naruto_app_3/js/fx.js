// Canvas particle engine. Effects anchor to real hand landmark positions
// (normalized 0..1, already mirrored to match the on-screen preview).

function rand(min, max) { return min + Math.random() * (max - min); }

class Particle {
  constructor(opts) {
    Object.assign(this, {
      x: 0, y: 0, vx: 0, vy: 0, ax: 0, ay: 0,
      life: 1, maxLife: 1, size: 4, color: "#fff",
      shape: "circle", drag: 1, glow: 0, spin: 0, angle: 0,
    }, opts);
    this.maxLife = this.life;
  }
  step(dt) {
    this.vx = this.vx * this.drag + this.ax * dt;
    this.vy = this.vy * this.drag + this.ay * dt;
    this.x += this.vx * dt;
    this.y += this.vy * dt;
    this.angle += this.spin * dt;
    this.life -= dt;
    return this.life > 0;
  }
  draw(g) {
    const t = Math.max(0, this.life / this.maxLife);
    g.save();
    g.globalAlpha = t;
    if (this.glow) {
      g.shadowBlur = this.glow;
      g.shadowColor = this.color;
    }
    g.fillStyle = this.color;
    g.translate(this.x, this.y);
    g.rotate(this.angle);
    const s = this.size * (0.4 + 0.6 * t);
    if (this.shape === "spark") {
      g.fillRect(-s * 1.6, -s * 0.25, s * 3.2, s * 0.5);
    } else {
      g.beginPath();
      g.arc(0, 0, s, 0, Math.PI * 2);
      g.fill();
    }
    g.restore();
  }
}

export class FXEngine {
  constructor(canvas) {
    this.canvas = canvas;
    this.g = canvas.getContext("2d");
    this.particles = [];
    this.bolts = [];       // lightning polylines
    this.flash = null;     // {color, life}
    this.shake = 0;
    this.emitters = [];    // continuous effects tied to hand position
  }

  resize(width, height) {
    this.canvas.width = width;
    this.canvas.height = height;
  }

  // p is normalized {x, y}; converts to pixels.
  _px(p) { return { x: p.x * this.canvas.width, y: p.y * this.canvas.height }; }

  screenFlash(color, strength = 0.35) {
    this.flash = { color, life: 0.3, maxLife: 0.3, strength };
  }

  addShake(amount = 10) { this.shake = Math.max(this.shake, amount); }

  burst(point, color, count = 26, speed = 260) {
    const { x, y } = this._px(point);
    for (let i = 0; i < count; i++) {
      const angle = rand(0, Math.PI * 2);
      const v = rand(speed * 0.3, speed);
      this.particles.push(new Particle({
        x, y,
        vx: Math.cos(angle) * v, vy: Math.sin(angle) * v,
        life: rand(0.35, 0.8), size: rand(2, 6),
        color, glow: 14, drag: 0.96,
      }));
    }
  }

  // --- jutsu-specific effects -------------------------------------------

  fireball(from) {
    const { x, y } = this._px(from);
    const dir = x < this.canvas.width / 2 ? 1 : -1;
    for (let i = 0; i < 70; i++) {
      this.particles.push(new Particle({
        x: x + rand(-8, 8), y: y + rand(-8, 8),
        vx: dir * rand(180, 560), vy: rand(-70, 70),
        life: rand(0.5, 1.1), size: rand(4, 12),
        color: ["#ffdf8a", "#ff9d3f", "#ff5a1f", "#d63515"][i % 4],
        glow: 22, drag: 0.985, ay: rand(-30, 10),
      }));
    }
    this.screenFlash("#ff7a2f", 0.4);
    this.addShake(8);
  }

  ember(from) {
    const { x, y } = this._px(from);
    for (let i = 0; i < 46; i++) {
      this.particles.push(new Particle({
        x: x + rand(-30, 30), y: y + rand(-16, 16),
        vx: rand(-90, 90), vy: rand(-240, -60),
        life: rand(0.8, 1.6), size: rand(2, 5),
        color: ["#ffb35a", "#ff7a2f", "#8a8a8a"][i % 3],
        glow: 12, drag: 0.985, ay: 60,
      }));
    }
    this.screenFlash("#ff9d4d", 0.22);
  }

  chidori(at) {
    const { x, y } = this._px(at);
    for (let i = 0; i < 7; i++) this._bolt(x, y, rand(60, 150));
    for (let i = 0; i < 26; i++) {
      this.particles.push(new Particle({
        x, y,
        vx: rand(-320, 320), vy: rand(-320, 320),
        life: rand(0.12, 0.4), size: rand(1.5, 3.5),
        shape: "spark", angle: rand(0, Math.PI * 2),
        color: "#bfe0ff", glow: 18, drag: 0.9,
      }));
    }
    this.screenFlash("#7fb7ff", 0.3);
    this.addShake(6);
  }

  _bolt(x, y, reach) {
    const segments = [{ x, y }];
    let angle = rand(0, Math.PI * 2);
    let px = x, py = y;
    const steps = 6;
    for (let i = 0; i < steps; i++) {
      angle += rand(-0.9, 0.9);
      px += Math.cos(angle) * (reach / steps);
      py += Math.sin(angle) * (reach / steps);
      segments.push({ x: px, y: py });
    }
    this.bolts.push({ segments, life: rand(0.1, 0.26), maxLife: 0.26, color: "#cfe6ff" });
  }

  rasengan(at) {
    const p = this._px(at);
    this.emitters.push({
      kind: "rasengan", x: p.x, y: p.y, life: 1.6,
      update: (e, dt, g) => {
        for (let i = 0; i < 6; i++) {
          const angle = rand(0, Math.PI * 2);
          const radius = rand(6, 42);
          this.particles.push(new Particle({
            x: e.x + Math.cos(angle) * radius,
            y: e.y + Math.sin(angle) * radius,
            vx: -Math.sin(angle) * 240, vy: Math.cos(angle) * 240,
            life: rand(0.15, 0.4), size: rand(2, 5),
            color: ["#aef", "#59d7ff", "#e8fbff"][i % 3],
            glow: 16, drag: 0.92,
          }));
        }
        g.save();
        g.globalAlpha = Math.min(1, e.life);
        g.shadowBlur = 34; g.shadowColor = "#59d7ff";
        const grad = g.createRadialGradient(e.x, e.y, 4, e.x, e.y, 40);
        grad.addColorStop(0, "rgba(240,252,255,0.95)");
        grad.addColorStop(0.6, "rgba(89,215,255,0.65)");
        grad.addColorStop(1, "rgba(89,215,255,0)");
        g.fillStyle = grad;
        g.beginPath(); g.arc(e.x, e.y, 42, 0, Math.PI * 2); g.fill();
        g.restore();
      },
    });
    this.screenFlash("#59d7ff", 0.25);
  }

  waterDragon(from) {
    const { x, y } = this._px(from);
    const dir = x < this.canvas.width / 2 ? 1 : -1;
    for (let i = 0; i < 90; i++) {
      const phase = i / 90;
      this.particles.push(new Particle({
        x, y: y + Math.sin(phase * Math.PI * 4) * 34,
        vx: dir * rand(260, 520),
        vy: Math.cos(phase * Math.PI * 4) * 160,
        life: rand(0.6, 1.3), size: rand(3, 9),
        color: ["#bfe2ff", "#3f8dff", "#0f5fd6"][i % 3],
        glow: 16, drag: 0.99,
      }));
    }
    this.screenFlash("#3f8dff", 0.35);
    this.addShake(9);
  }

  earthWall(at) {
    const { x } = this._px(at);
    for (let i = 0; i < 50; i++) {
      this.particles.push(new Particle({
        x: x + rand(-90, 90), y: this.canvas.height + 10,
        vx: rand(-30, 30), vy: rand(-560, -260),
        life: rand(0.5, 1.0), size: rand(4, 11),
        color: ["#c8a35f", "#8a6a34", "#5d4621"][i % 3],
        glow: 4, drag: 0.97, ay: 900,
      }));
    }
    this.addShake(12);
    this.screenFlash("#c8a35f", 0.2);
  }

  shadowClone(at) {
    const { x, y } = this._px(at);
    for (let i = 0; i < 60; i++) {
      const angle = rand(0, Math.PI * 2);
      this.particles.push(new Particle({
        x: x + Math.cos(angle) * rand(0, 60),
        y: y + Math.sin(angle) * rand(0, 60),
        vx: rand(-60, 60), vy: rand(-120, -20),
        life: rand(0.5, 1.2), size: rand(6, 16),
        color: ["#e8e2ff", "#c9b6ff", "#9f86ff"][i % 3],
        glow: 10, drag: 0.95,
      }));
    }
    this.screenFlash("#c9b6ff", 0.3);
  }

  summoning(at) {
    const { x, y } = this._px(at);
    // smoke pillar
    for (let i = 0; i < 110; i++) {
      this.particles.push(new Particle({
        x: x + rand(-70, 70), y: y + rand(-10, 40),
        vx: rand(-50, 50), vy: rand(-260, -60),
        life: rand(0.9, 2.0), size: rand(8, 22),
        color: ["#efe7d8", "#cfc4ae", "#a99f8a"][i % 3],
        glow: 6, drag: 0.985,
      }));
    }
    this.screenFlash("#ffd66b", 0.45);
    this.addShake(16);
  }

  castEffect(jutsuId, anchor) {
    const point = anchor ?? { x: 0.5, y: 0.55 };
    switch (jutsuId) {
      case "fireball": this.fireball(point); break;
      case "phoenixFlower": this.ember(point); break;
      case "chidori": this.chidori(point); break;
      case "rasengan": this.rasengan(point); break;
      case "waterDragon": this.waterDragon(point); break;
      case "earthWall": this.earthWall(point); break;
      case "shadowClone": this.shadowClone(point); break;
      case "summoning": this.summoning(point); break;
      default: this.burst(point, "#ffffff");
    }
  }

  // --- hand skeleton overlay --------------------------------------------

  drawHands(hands, color = "rgba(255,255,255,0.55)") {
    const EDGES = [
      [0, 1], [1, 2], [2, 3], [3, 4],
      [0, 5], [5, 6], [6, 7], [7, 8],
      [5, 9], [9, 10], [10, 11], [11, 12],
      [9, 13], [13, 14], [14, 15], [15, 16],
      [13, 17], [17, 18], [18, 19], [19, 20], [0, 17],
    ];
    const g = this.g;
    g.save();
    g.strokeStyle = color;
    g.lineWidth = 2;
    for (const hand of hands) {
      for (const [a, b] of EDGES) {
        const pa = this._px(hand[a]);
        const pb = this._px(hand[b]);
        g.beginPath();
        g.moveTo(pa.x, pa.y);
        g.lineTo(pb.x, pb.y);
        g.stroke();
      }
      for (const lm of hand) {
        const p = this._px(lm);
        g.beginPath();
        g.arc(p.x, p.y, 3, 0, Math.PI * 2);
        g.fillStyle = color;
        g.fill();
      }
    }
    g.restore();
  }

  // --- frame ------------------------------------------------------------

  render(dt) {
    const g = this.g;

    if (this.shake > 0.2) {
      g.save();
      g.translate(rand(-this.shake, this.shake), rand(-this.shake, this.shake));
      this.shake *= 0.85;
    } else {
      g.save();
      this.shake = 0;
    }

    this.particles = this.particles.filter((p) => p.step(dt));
    for (const p of this.particles) p.draw(g);

    this.bolts = this.bolts.filter((b) => (b.life -= dt) > 0);
    for (const bolt of this.bolts) {
      g.save();
      g.globalAlpha = bolt.life / bolt.maxLife;
      g.strokeStyle = bolt.color;
      g.lineWidth = 2.5;
      g.shadowBlur = 16;
      g.shadowColor = bolt.color;
      g.beginPath();
      g.moveTo(bolt.segments[0].x, bolt.segments[0].y);
      for (const s of bolt.segments.slice(1)) g.lineTo(s.x, s.y);
      g.stroke();
      g.restore();
    }

    this.emitters = this.emitters.filter((e) => (e.life -= dt) > 0);
    for (const e of this.emitters) e.update(e, dt, g);

    g.restore();

    if (this.flash) {
      this.flash.life -= dt;
      if (this.flash.life <= 0) this.flash = null;
      else {
        g.save();
        g.globalAlpha = (this.flash.life / this.flash.maxLife) * this.flash.strength;
        g.fillStyle = this.flash.color;
        g.fillRect(0, 0, this.canvas.width, this.canvas.height);
        g.restore();
      }
    }
  }

  clear() {
    this.g.clearRect(0, 0, this.canvas.width, this.canvas.height);
  }
}
