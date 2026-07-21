// Shinobi Trainer — app controller.
// Screens: menu → dojo (freeform) | trial (target jutsu) | duel (vs AI).
// Add ?demo=1 to run without a camera: keys perform signs (see on-screen map).

import { JUTSU, JUTSU_LIST, SIGNS, normalizeSign } from "./jutsu.js";
import { buildFeatureVector } from "./features.js";
import { initVision, detectHands } from "./vision.js";
import { initClassifier, classify } from "./classifier.js";
import { SignEngine } from "./signEngine.js";
import { FXEngine } from "./fx.js";
import { sfx, unlockAudio } from "./audio.js";
import { ShadowCloneAI } from "./ai.js";

const CONFIDENCE_THRESHOLD = 0.25;
const DEMO_KEYMAP = {
  1: "bird", 2: "boar", 3: "dog", 4: "dragon", 5: "hare", 6: "horse",
  7: "monkey", 8: "ox", 9: "ram", 0: "rat", q: "snake", w: "tiger",
};

const $ = (id) => document.getElementById(id);

const state = {
  demo: new URLSearchParams(location.search).has("demo"),
  mode: null,               // dojo | trial | duel
  running: false,
  engine: null,
  fx: null,
  ai: null,
  trial: null,              // {jutsu, startedAt, finishedIn}
  demoLabel: null,
  demoLabelUntil: 0,
  lastFrameTime: 0,
  classifierBusy: false,
  lastPrediction: null,     // {label, confidence}
  handsMirrored: [],        // for overlay drawing
  anchor: { x: 0.5, y: 0.55 },
  ready: { vision: false, classifier: false, camera: false },
  latencies: [],
};

// ---------------------------------------------------------------- boot

async function boot() {
  buildMenu();
  buildSignChips();
  wireEvents();

  setLoadStatus("loading sign classifier…");
  try {
    await initClassifier();
    state.ready.classifier = true;
  } catch (err) {
    setLoadStatus(`classifier failed to load: ${err.message}`);
    return;
  }

  if (state.demo) {
    setLoadStatus("demo mode — keyboard controls active");
    $("demo-banner").hidden = false;
    state.ready.vision = true;
    state.ready.camera = true;
    enableMenu();
    return;
  }

  setLoadStatus("loading hand tracker…");
  try {
    await initVision(2);
    state.ready.vision = true;
  } catch (err) {
    setLoadStatus(`hand tracker failed: ${err.message} — try ?demo=1`);
    return;
  }

  setLoadStatus("requesting camera…");
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: "user", width: { ideal: 1280 }, height: { ideal: 720 } },
      audio: false,
    });
    const video = $("camera");
    video.srcObject = stream;
    await video.play();
    state.ready.camera = true;
  } catch (err) {
    setLoadStatus(`camera unavailable: ${err.message} — try ?demo=1`);
    return;
  }

  setLoadStatus("ready");
  enableMenu();
}

function setLoadStatus(text) { $("load-status").textContent = text; }
function enableMenu() {
  document.querySelectorAll(".mode-card").forEach((el) => el.classList.add("enabled"));
}

// ---------------------------------------------------------------- menu

function buildMenu() {
  const trialGrid = $("trial-grid");
  for (const jutsu of JUTSU_LIST) {
    const button = document.createElement("button");
    button.className = "trial-option";
    button.style.setProperty("--accent", jutsu.color);
    button.innerHTML = `<span class="kanji">${jutsu.kanji}</span><span>${jutsu.name}</span><span class="seq">${jutsu.sequence.join(" · ")}</span>`;
    button.addEventListener("click", () => startGame("trial", { jutsu }));
    trialGrid.appendChild(button);
  }
}

function buildSignChips() {
  const container = $("sign-keymap");
  for (const [key, sign] of Object.entries(DEMO_KEYMAP)) {
    const chip = document.createElement("span");
    chip.className = "keychip";
    chip.innerHTML = `<b>${key}</b>${sign}`;
    container.appendChild(chip);
  }
}

function wireEvents() {
  $("btn-dojo").addEventListener("click", () => startGame("dojo"));
  $("btn-duel").addEventListener("click", () => startGame("duel"));
  $("btn-trial").addEventListener("click", () => {
    $("trial-picker").classList.toggle("open");
  });
  $("btn-back").addEventListener("click", exitToMenu);
  $("btn-again").addEventListener("click", () => {
    $("result-overlay").hidden = true;
    startGame(state.mode, state.trial ? { jutsu: state.trial.jutsu } : {});
  });
  $("btn-result-menu").addEventListener("click", () => {
    $("result-overlay").hidden = true;
    exitToMenu();
  });

  window.addEventListener("keydown", (event) => {
    if (!state.demo || !state.running) return;
    const sign = DEMO_KEYMAP[event.key.toLowerCase()];
    if (sign) {
      state.demoLabel = sign;
      state.demoLabelUntil = performance.now() + 2500;
    }
  });

  window.addEventListener("resize", sizeCanvas);
}

// ---------------------------------------------------------------- game

function startGame(mode, options = {}) {
  unlockAudio();
  state.mode = mode;
  state.running = true;
  state.trial = null;
  state.ai = null;
  state.lastPrediction = null;

  $("screen-menu").hidden = true;
  $("screen-game").hidden = false;
  $("result-overlay").hidden = true;
  $("trial-picker").classList.remove("open");
  $("hud-duel").hidden = mode !== "duel";
  $("hud-trial").hidden = mode !== "trial";
  $("dex").hidden = mode !== "dojo";

  if (!state.fx) state.fx = new FXEngine($("fx"));
  sizeCanvas();

  if (mode === "trial") {
    const jutsu = options.jutsu ?? JUTSU.fireball;
    state.trial = { jutsu, startedAt: performance.now(), finishedIn: null };
    state.engine = new SignEngine({ targetJutsu: jutsu, enforceTimeLimit: true });
    $("trial-name").textContent = jutsu.name;
    renderTrialSequence(jutsu, 0);
  } else {
    state.engine = new SignEngine();
  }

  if (mode === "duel") {
    state.ai = new ShadowCloneAI({ hp: 120 });
    state.ai.start(performance.now());
    updateDuelHUD();
    setBanner("A shadow clone appears…", "#c9b6ff");
  } else if (mode === "dojo") {
    renderDex();
    setBanner("Dojo open — perform any sequence", "#ffd66b");
  } else {
    setBanner(`Trial: ${state.trial.jutsu.name}`, state.trial.jutsu.color);
  }

  state.lastFrameTime = performance.now();
  scheduleFrame();
}

// rAF with a timeout fallback: keeps the game loop alive in throttled /
// headless contexts where requestAnimationFrame stops firing.
function scheduleFrame() {
  let done = false;
  const run = () => {
    if (done) return;
    done = true;
    clearTimeout(timer);
    cancelAnimationFrame(raf);
    frame(performance.now());
  };
  const raf = requestAnimationFrame(run);
  const timer = setTimeout(run, 50);
}

function exitToMenu() {
  state.running = false;
  $("screen-game").hidden = true;
  $("screen-menu").hidden = false;
  $("result-overlay").hidden = true;
}

function sizeCanvas() {
  if (!state.fx) return;
  const stage = $("stage");
  state.fx.resize(stage.clientWidth, stage.clientHeight);
}

// ------------------------------------------------------------ main loop

async function frame(now) {
  if (!state.running) return;
  const dt = Math.min(0.05, (now - state.lastFrameTime) / 1000);
  state.lastFrameTime = now;

  await sense(now);

  const label =
    state.lastPrediction && state.lastPrediction.confidence >= CONFIDENCE_THRESHOLD
      ? state.lastPrediction.label
      : null;

  const { events, status, holdProgress } = state.engine.update(label, now);
  updateSignHUD(label, holdProgress, status);
  for (const event of events) handleEngineEvent(event, now);

  if (state.mode === "duel" && state.ai) {
    const aiEvent = state.ai.tick(now);
    if (aiEvent) handleAIEvent(aiEvent, now);
    updateDuelTimer(now);
  }

  state.fx.clear();
  if (state.handsMirrored.length) {
    state.fx.drawHands(state.handsMirrored, "rgba(255,214,107,0.5)");
  }
  state.fx.render(dt);

  scheduleFrame();
}

async function sense(now) {
  if (state.demo) {
    state.handsMirrored = [];
    if (state.demoLabel && now < state.demoLabelUntil) {
      state.lastPrediction = { label: state.demoLabel, confidence: 0.99 };
    } else {
      state.demoLabel = null;
      state.lastPrediction = null;
    }
    return;
  }

  if (state.classifierBusy) return;
  state.classifierBusy = true;
  try {
    const t0 = performance.now();
    const video = $("camera");
    const hands = detectHands(video, Math.round(now));

    // Overlay uses mirrored coords to match the mirrored preview.
    state.handsMirrored = hands.map((h) =>
      h.landmarks.map((lm) => ({ x: 1 - lm.x, y: lm.y }))
    );
    if (hands.length) {
      const mean = state.handsMirrored.flat();
      const cx = mean.reduce((s, p) => s + p.x, 0) / mean.length;
      const cy = mean.reduce((s, p) => s + p.y, 0) / mean.length;
      state.anchor = { x: cx, y: cy };
    }

    const features = buildFeatureVector(hands);
    if (features) {
      const result = await classify(features);
      state.lastPrediction = result;
      trackLatency(performance.now() - t0);
    } else {
      state.lastPrediction = null;
    }
  } finally {
    state.classifierBusy = false;
  }
}

function trackLatency(ms) {
  state.latencies.push(ms);
  if (state.latencies.length >= 120) {
    const avg = state.latencies.reduce((a, b) => a + b, 0) / state.latencies.length;
    console.info(`[shinobi] avg pipeline latency: ${avg.toFixed(1)} ms/frame`);
    state.latencies = [];
  }
}

// ------------------------------------------------------- event handling

function handleEngineEvent(event, now) {
  switch (event.type) {
    case "sign":
      sfx.signCommit();
      pushRecentSign(event.sign);
      break;
    case "charging":
      setBanner(`${event.jutsu.name} charged — keep signing…`, event.jutsu.color);
      break;
    case "progress":
      if (state.trial) renderTrialSequence(state.trial.jutsu, event.progress);
      break;
    case "wrong":
      break;
    case "timeout":
      setBanner("Too slow — summoning fizzled. Again!", "#ff6a5a");
      if (state.trial) renderTrialSequence(state.trial.jutsu, 0);
      break;
    case "trigger":
      castJutsu(event.jutsu, now);
      break;
  }
}

function castJutsu(jutsu, now) {
  state.fx.castEffect(jutsu.id, state.anchor);
  sfx.cast(jutsu.sfx);
  setBanner(`${jutsu.kanji} — ${jutsu.name}!`, jutsu.color);

  if (state.mode === "trial" && state.trial) {
    state.trial.finishedIn = (now - state.trial.startedAt) / 1000;
    setTimeout(() => showResult({
      title: "Trial Complete!",
      subtitle: `${state.trial.jutsu.name} in ${state.trial.finishedIn.toFixed(2)}s`,
      good: true,
    }), 900);
    state.running = state.running && false;
    state.running = true; // keep FX running until overlay shows
  }

  if (state.mode === "duel" && state.ai) {
    const result = state.ai.playerCast(jutsu, now);
    if (!result) return;
    if (result.kind === "block") {
      sfx.block();
      state.fx.burst({ x: 0.5, y: 0.4 }, "#66ff99", 40, 320);
      setBanner(`Blocked ${result.blocked.name}!`, "#66ff99");
    } else if (result.kind === "dodge") {
      setBanner("The clone flickers away — missed!", "#c9b6ff");
    } else if (result.kind === "hit") {
      sfx.hit();
      state.fx.burst({ x: 0.5, y: 0.3 }, jutsu.color, 34, 300);
      setBanner(`${jutsu.name} hits for ${jutsu.damage}!`, jutsu.color);
      if (result.defeated) {
        sfx.victory();
        setTimeout(() => showResult({
          title: "Victory!",
          subtitle: "The shadow clone dispels in smoke.",
          good: true,
        }), 800);
      }
    }
    updateDuelHUD();
  }
}

function handleAIEvent(event, now) {
  if (event.kind === "telegraph") {
    const counters = state.ai.counterHint().map((j) => j.name).join(" or ");
    setBanner(`Incoming ${event.jutsu.name}! Counter with ${counters}`, event.jutsu.color);
    $("incoming").hidden = false;
    $("incoming-name").textContent = event.jutsu.name;
    $("incoming-name").style.color = event.jutsu.color;
  } else if (event.kind === "playerHit") {
    $("incoming").hidden = true;
    sfx.hit();
    state.fx.screenFlash("#ff2f2f", 0.5);
    state.fx.addShake(14);
    setBanner(`${event.jutsu.name} hits you for ${event.jutsu.damage}!`, "#ff6a5a");
    updateDuelHUD();
    if (event.defeated) {
      sfx.defeat();
      setTimeout(() => showResult({
        title: "Defeated…",
        subtitle: "Train in the dojo and challenge the clone again.",
        good: false,
      }), 800);
    }
  }
  if (state.ai.phase !== "telegraph") $("incoming").hidden = true;
}

// ---------------------------------------------------------------- HUD

const recentSigns = [];
function pushRecentSign(sign) {
  recentSigns.push(sign);
  if (recentSigns.length > 5) recentSigns.shift();
  $("recent-signs").innerHTML = recentSigns
    .map((s) => `<span class="sign-chip">${s}</span>`)
    .join("");
}

function updateSignHUD(label, holdProgress, status) {
  const el = $("current-sign");
  if (label) {
    el.textContent = normalizeSign(label);
    el.style.opacity = 1;
    $("hold-ring").style.setProperty("--p", `${Math.round(holdProgress * 100)}`);
  } else {
    el.textContent = state.demo ? "press a key" : "show a sign";
    el.style.opacity = 0.5;
    $("hold-ring").style.setProperty("--p", "0");
  }
  $("engine-status").textContent = status;
}

let bannerTimer = null;
function setBanner(text, color = "#ffd66b") {
  const banner = $("banner");
  banner.textContent = text;
  banner.style.setProperty("--accent", color);
  banner.classList.remove("pop");
  void banner.offsetWidth; // restart animation
  banner.classList.add("pop");
  clearTimeout(bannerTimer);
  bannerTimer = setTimeout(() => banner.classList.remove("pop"), 2600);
}

function renderTrialSequence(jutsu, progress) {
  $("trial-seq").innerHTML = jutsu.sequence
    .map((sign, i) =>
      `<span class="seq-step ${i < progress ? "done" : i === progress ? "next" : ""}">${sign}</span>`)
    .join("<span class='seq-arrow'>➜</span>");
}

function updateDuelHUD() {
  if (!state.ai) return;
  $("hp-player").style.width = `${state.ai.playerHP}%`;
  $("hp-player-num").textContent = state.ai.playerHP;
  $("hp-clone").style.width = `${(state.ai.hp / state.ai.maxHP) * 100}%`;
  $("hp-clone-num").textContent = state.ai.hp;
}

function updateDuelTimer(now) {
  const bar = $("incoming-bar");
  if (state.ai.phase === "telegraph") {
    const total = state.ai.phaseEndsAt - (state.ai.phaseEndsAt - now);
    const remaining = Math.max(0, state.ai.phaseEndsAt - now);
    const windowMs = state.ai.phaseEndsAt - (state.ai.phaseEndsAt - remaining);
    bar.style.width = `${Math.max(0, Math.min(100, (remaining / 7000) * 100))}%`;
  }
}

function renderDex() {
  $("dex-list").innerHTML = JUTSU_LIST
    .map((j) => `
      <div class="dex-row" style="--accent:${j.color}">
        <span class="dex-kanji">${j.kanji}</span>
        <span class="dex-name">${j.name}</span>
        <span class="dex-seq">${j.sequence.join(" · ")}</span>
      </div>`)
    .join("");
}

function showResult({ title, subtitle, good }) {
  $("result-title").textContent = title;
  $("result-title").className = good ? "good" : "bad";
  $("result-subtitle").textContent = subtitle;
  $("result-overlay").hidden = false;
}

window.__shinobi = state; // debug/testing handle
boot();
