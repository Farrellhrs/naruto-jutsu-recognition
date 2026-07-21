# Shinobi Trainer — Hand-Sign Jutsu in the Browser

A ground-up web remake of the Naruto hand-sign recognition game. Same trained model, entirely new app: no installs, no App Store — open a URL, allow the camera, and weave signs.

**Why the web?** MediaPipe's Hand Landmarker runs officially in-browser (WASM/GPU), the trained RandomForest converts losslessly to ONNX for `onnxruntime-web`, and a static page deploys anywhere. The result is the same on-device pipeline as the iOS app with zero install friction.

```
getUserMedia camera ──► MediaPipe HandLandmarker (WASM, 2 hands × 21 landmarks)
                              │
                              ▼
             126-feature vector (wrist-centered, scale-normalized,
             left|right slots, zero-padded — exact training parity)
                              │
                              ▼
        RandomForest via onnxruntime-web ── 100% parity with the
        trained sklearn model (verified in export_onnx.py)
                              │
                              ▼
        SignEngine: 300ms hold-to-commit · sequence tail matching ·
        deferred triggers for overlapping sequences · wrong-sign grace
                              │
                              ▼
        Canvas particle FX (anchored to real hand positions) + WebAudio
```

## Modes

| Mode | 漢字 | What it is |
|---|---|---|
| **Dojo** | 道場 | Freeform practice — chain any sequence, cast all 8 jutsu; scroll shows every recipe |
| **Trial** | 試練 | Pick a jutsu, perform its full sequence against the clock (Summoning has an 8 s limit) |
| **Duel** | 決闘 | Fight a shadow-clone AI that telegraphs attacks — block by casting the counter element before it lands |

The elemental counter wheel (fire < water < earth < lightning < wind < fire) drives blocking in the Duel.

## Running

```bash
cd naruto_app_3
python3 -m http.server 8123
# open http://localhost:8123  (camera needs localhost or https)
```

**No camera? Demo mode:** `http://localhost:8123/?demo=1` — perform signs with keyboard keys (on-screen key map). This is also how the game logic is tested headlessly.

## Structure

```
├── index.html / styles.css       # single-page app, ink & ember theme
├── js/
│   ├── main.js                   # screens, game loop (rAF + timeout fallback), HUD
│   ├── vision.js                 # MediaPipe HandLandmarker wrapper
│   ├── features.js               # 126-dim feature builder (training parity)
│   ├── classifier.js             # ONNX RandomForest inference
│   ├── signEngine.js             # hold-to-commit + sequences + deferral
│   ├── jutsu.js                  # 8 jutsu: sequences, elements, damage, colors
│   ├── fx.js                     # canvas particles: fire, lightning, water, smoke…
│   ├── audio.js                  # WebAudio-synthesized SFX + licensed mp3 clips
│   └── ai.js                     # shadow-clone duel opponent
└── assets/
    ├── model/hand_sign_rf.onnx   # exported from the trained RF (17.9 MB, 100% parity)
    ├── model/hand_landmarker.task
    └── audio/                    # signature-jutsu clips reused from the original project
```

## Model

The classifier is the same RandomForest trained in `../hand_gesture_model/` (97.5% held-out test accuracy, 12 sign classes), exported to ONNX by `../hand_gesture_model/export_onnx.py` with verified 100% prediction agreement and max probability deviation of 6e-7. Feature extraction in `features.js` mirrors the training code exactly: wrist-centering, max-2D-norm scaling, left/right hand slots with zero padding.

Average in-browser pipeline latency (landmarks → features → ONNX) is logged to the console every 120 frames.

*A non-commercial fan/educational project. Naruto is a trademark of its respective owners.*
