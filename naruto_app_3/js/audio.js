// Audio: signature jutsu use the licensed mp3 clips (reused with
// permission from the original project); everything else is synthesized
// with WebAudio so the app needs no downloaded third-party assets.

let ctx = null;
const mp3Cache = new Map();

const MP3 = {
  fireball: "assets/audio/Fireball.mp3",
  chidori: "assets/audio/Chidori.mp3",
  rasengan: "assets/audio/Rasengan.mp3",
  ember: "assets/audio/Burning Ash.mp3",
};

function audioContext() {
  if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)();
  if (ctx.state === "suspended") ctx.resume();
  return ctx;
}

async function playMp3(url, volume = 0.8) {
  const ac = audioContext();
  let buffer = mp3Cache.get(url);
  if (!buffer) {
    const response = await fetch(url);
    buffer = await ac.decodeAudioData(await response.arrayBuffer());
    mp3Cache.set(url, buffer);
  }
  const source = ac.createBufferSource();
  const gain = ac.createGain();
  gain.gain.value = volume;
  source.buffer = buffer;
  source.connect(gain).connect(ac.destination);
  source.start();
}

// --- synthesized effects ------------------------------------------------

function noiseBuffer(ac, seconds = 1) {
  const buffer = ac.createBuffer(1, ac.sampleRate * seconds, ac.sampleRate);
  const data = buffer.getChannelData(0);
  for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
  return buffer;
}

function synthWhoosh(ac, { duration = 0.5, from = 400, to = 90, volume = 0.5 }) {
  const source = ac.createBufferSource();
  source.buffer = noiseBuffer(ac, duration);
  const filter = ac.createBiquadFilter();
  filter.type = "bandpass";
  filter.frequency.setValueAtTime(from, ac.currentTime);
  filter.frequency.exponentialRampToValueAtTime(to, ac.currentTime + duration);
  filter.Q.value = 1.2;
  const gain = ac.createGain();
  gain.gain.setValueAtTime(volume, ac.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, ac.currentTime + duration);
  source.connect(filter).connect(gain).connect(ac.destination);
  source.start();
}

function synthZap(ac, { duration = 0.35, volume = 0.35 }) {
  const osc = ac.createOscillator();
  osc.type = "sawtooth";
  osc.frequency.setValueAtTime(1400, ac.currentTime);
  osc.frequency.exponentialRampToValueAtTime(180, ac.currentTime + duration);
  const gain = ac.createGain();
  gain.gain.setValueAtTime(volume, ac.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, ac.currentTime + duration);
  osc.connect(gain).connect(ac.destination);
  osc.start();
  osc.stop(ac.currentTime + duration);
}

function synthThud(ac, { volume = 0.6 }) {
  const osc = ac.createOscillator();
  osc.type = "sine";
  osc.frequency.setValueAtTime(140, ac.currentTime);
  osc.frequency.exponentialRampToValueAtTime(40, ac.currentTime + 0.28);
  const gain = ac.createGain();
  gain.gain.setValueAtTime(volume, ac.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, ac.currentTime + 0.3);
  osc.connect(gain).connect(ac.destination);
  osc.start();
  osc.stop(ac.currentTime + 0.3);
}

function synthChime(ac, { volume = 0.25 }) {
  for (const [i, freq] of [660, 880, 1320].entries()) {
    const osc = ac.createOscillator();
    osc.type = "sine";
    osc.frequency.value = freq;
    const gain = ac.createGain();
    const start = ac.currentTime + i * 0.05;
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(volume, start + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.001, start + 0.5);
    osc.connect(gain).connect(ac.destination);
    osc.start(start);
    osc.stop(start + 0.55);
  }
}

// --- public API ---------------------------------------------------------

export const sfx = {
  signCommit() {
    const ac = audioContext();
    const osc = ac.createOscillator();
    osc.type = "triangle";
    osc.frequency.value = 520;
    const gain = ac.createGain();
    gain.gain.setValueAtTime(0.18, ac.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ac.currentTime + 0.12);
    osc.connect(gain).connect(ac.destination);
    osc.start();
    osc.stop(ac.currentTime + 0.13);
  },

  cast(sfxName) {
    const ac = audioContext();
    if (MP3[sfxName]) {
      playMp3(MP3[sfxName]).catch(() => synthWhoosh(ac, {}));
      return;
    }
    switch (sfxName) {
      case "water": synthWhoosh(ac, { duration: 0.9, from: 700, to: 120, volume: 0.55 }); break;
      case "earth": synthThud(ac, { volume: 0.7 }); break;
      case "clone": synthChime(ac, { volume: 0.3 }); break;
      case "summon": synthThud(ac, { volume: 0.5 }); synthChime(ac, { volume: 0.35 }); break;
      default: synthWhoosh(ac, {});
    }
  },

  hit() { synthThud(audioContext(), { volume: 0.65 }); },
  block() { synthChime(audioContext(), { volume: 0.3 }); },
  zap() { synthZap(audioContext(), {}); },
  victory() {
    const ac = audioContext();
    synthChime(ac, { volume: 0.35 });
    setTimeout(() => synthChime(ac, { volume: 0.3 }), 250);
  },
  defeat() {
    const ac = audioContext();
    synthWhoosh(ac, { duration: 1.2, from: 300, to: 50, volume: 0.5 });
  },
};

// Browsers require a user gesture before audio can play.
export function unlockAudio() {
  audioContext();
}
