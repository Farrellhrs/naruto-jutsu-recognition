# Jutsu Master — Real-Time Naruto Hand-Sign Recognition on iOS

An end-to-end, fully **on-device** computer-vision game: perform Naruto hand signs in front of your iPhone camera, and the app recognizes them in real time, tracks sign *sequences*, and unleashes jutsu effects (Fireball, Chidori, Rasengan, Kuchiyose…) with particle visuals, face-direction-aware targeting, and synchronized audio.

Built at **Apple Developer Academy @ Tangerang**. Full technical write-up in [`pdf documentation/main.pdf`](pdf%20documentation/main.pdf).

## How It Works

```
Camera (AVFoundation)
   │  CVPixelBuffer, per frame
   ▼
MediaPipe Hand Landmarker (.task, on-device)          MediaPipe Face Landmarker
   │  up to 2 hands × 21 landmarks × (x,y,z)             │  mouth point + face direction
   ▼                                                     │
Feature vector: fixed 126 floats                         │
   (left hand 63 | right hand 63,                        │
    zero-padded when a hand is missing)                  │
   ▼                                                     ▼
CoreML RandomForest (12 classes) ──► JutsuManager (sequence engine) ──► SwiftUI effects
   97.47% held-out test accuracy         hold-to-commit (300 ms),           CAEmitterLayer particles,
                                        wrong-sign reset (2 s),            direction-aware fireballs,
                                        sequence time limits               sound effects
```

The key design decision is the **unified 126-feature representation**: one-hand and two-hand signs share a single model. A detected hand is assigned to its left/right slot and the missing slot is zero-padded, so the classifier operates seamlessly as hands enter and leave the frame — no separate one-hand/two-hand model switching at runtime.

## Repository Layout

```
├── naruto_app/                      # iOS app (SwiftUI, MVVM)
│   └── naruto_app/
│       ├── Managers/                # Core pipeline
│       │   ├── CameraManager.swift          # AVFoundation capture
│       │   ├── HandLandmarkDetector.swift   # MediaPipe hand landmarks
│       │   ├── FaceDirectionEstimator.swift # Face landmarks → aim vector + mouth state
│       │   ├── GestureRecognizer.swift      # 126-feature build + CoreML inference
│       │   └── JutsuManager.swift           # Sign-sequence state machine
│       ├── ViewModels/              # GameViewModel, BattleModeViewModel
│       ├── Views/                   # Home, ModeSetup, CameraGame, BattleGame
│       │   └── Components/          # CameraView, JutsuEffectView, OverlayView
│       ├── Model/                   # CoreML models + MediaPipe .task bundles
│       └── (assets)                 # hand-sign reference images, SFX, soundtrack
├── hand_gesture_model/              # Python training pipeline
│   ├── download_dataset.ipynb       # Pull dataset from Roboflow
│   ├── train2.ipynb                 # v1 pipeline: landmarks → unified RF → CoreML
│   ├── train_unified_v2.py          # ★ v2: leak-free split + augmentation study
│   ├── train3.ipynb                 # YOLOv8 detector experiment (comparison)
│   ├── test_camera_unified.py       # Live webcam sanity-check of the exported model
│   └── naruto-hand-sign-4/
│       ├── data.yaml                # 12 classes (dataset images git-ignored, see below)
│       └── phase1_outputs_unified/  # Exported artifacts: .mlmodel, dataset CSVs,
│                                    # confusion matrix, class distribution, metrics
├── naruto_app_2/                    # ★ v2 ground-up rebuild: Vision-only (no pods),
│                                    #   @Observable + SpriteKit effects, Dojo/Academy/Trials
├── swift_tests/                     # SwiftPM harness: 21 unit tests for JutsuManager
│                                    #   (cd swift_tests && swift test)
└── pdf documentation/main.pdf       # 28-page technical documentation (LaTeX)
```

## ML Pipeline (hand_gesture_model/)

1. **Dataset** — [Naruto Hand Sign v4](https://universe.roboflow.com/adityas-workshop-kr2u8/naruto-hand-sign-cyq8u/dataset/4) from Roboflow Universe (CC BY 4.0), 6,146 images with YOLO-format bounding boxes over 12 classes: `bird, boar, dog, dragon, hare, horse, monkey, ox, ram, rat, snake, tiger`. Images are git-ignored — re-download with `download_dataset.ipynb`.
2. **Feature extraction** (`train2.ipynb`) — for every image, MediaPipe Hands extracts 21 landmarks per hand; hands are assigned to left/right slots to form a fixed 126-dim vector (zero-padded when one hand is absent). 3,961 usable samples survive quality filtering (3,289 one-hand, 672 two-hand); 2,177 images are skipped where MediaPipe finds no hands.
3. **Training** — RandomForest (`n_estimators=400`, `class_weight=balanced_subsample`). The v2 pipeline (`train_unified_v2.py`) honors the dataset's original train/valid/test split (no random re-split, so no near-duplicate frame leakage) → **97.47% test accuracy / 0.971 macro-F1** on the held-out test split. A landmark-space augmentation study (mirror, rotation+jitter) is included; neither variant helped — mirroring *hurts* because hand signs are chirality-sensitive — so the deployed model uses the clean training set. Per-class metrics and the confusion matrix are exported alongside the model.
4. **Export** — `coremltools` converts the RF to `hand_gesture_rf_unified.mlmodel`, which is bundled into the iOS app.
5. **Verification** — `test_camera_unified.py` runs the exact same feature pipeline on a live webcam for parity checking before deployment; `train3.ipynb` documents a YOLOv8 detection alternative evaluated for comparison.

## iOS Runtime (naruto_app/)

- **Recognition loop** — every frame: MediaPipe hand + face landmarkers → 126-feature vector → CoreML → top-label + confidence. Multiple candidate left/right assignments are scored and the best prediction wins.
- **Sequence engine** (`JutsuManager`) — a sign must be *held* ~300 ms to commit; committed signs advance the current jutsu sequence. Wrong signs held ≥2 s reset progress; Kuchiyose enforces a 4.5 s time limit for its full sequence. When a short jutsu completes while the history is still a live prefix of a longer one (wind inside kuchiyose), the short trigger is *deferred* for a 1.8 s grace window — it fires if you stop, and yields if the longer jutsu completes. This temporal-validation layer is what makes noisy per-frame predictions playable.
- **Effects** — jutsu trigger particle systems (`CAEmitterLayer`/`CAShapeLayer`): fireballs launch along the estimated 3D face direction and require an open mouth (Fireball jutsu, like in the show), Chidori crackles at the hand position, with per-jutsu sound effects.
- **Game modes** — Free (sandbox), Tutorial (guided sign-by-sign, no time pressure), Speed (against the clock), **Versus** (two players share one camera — the frame is split in half, up to 4 hands tracked, each side gets independent CoreML predictions, and completed jutsu fly at the opponent unless countered by the right element), and Battle: a real-time duel where enemy projectiles deal chip damage unless you counter in time, fast counters score Perfect Blocks (+chakra), chained attacks build combo multipliers (up to 1.6×), and difficulty scales each round — with haptics, screen shake, impact bursts, and hit-flash feedback throughout.

## Running

### iOS app

```bash
cd naruto_app
pod install                       # installs MediaPipeTasksVision
open naruto_app.xcworkspace       # build & run on a real device (camera required)
```

Requires iOS 15+, Xcode with CocoaPods. The Podfile patches MediaPipe's xcconfig to link the tasks frameworks correctly.

### Training

```bash
cd hand_gesture_model
# 1. download the dataset (Roboflow API key needed) — download_dataset.ipynb
# 2. run train2.ipynb once to extract landmark features, then:
python train_unified_v2.py   # →  phase1_outputs_unified_v2/hand_gesture_rf_unified.mlmodel
# 3. sanity check live:
python test_camera_unified.py
# 4. copy the .mlmodel into naruto_app/naruto_app/Model/
```

Python deps: `mediapipe==0.10.14`, `coremltools`, `scikit-learn`, `opencv-python`, `pandas`, `numpy`, `pyyaml` (+ `ultralytics` for the YOLO experiment).

## Results

| Metric | Value |
|---|---|
| Usable training samples | 3,961 (3,289 one-hand / 672 two-hand) |
| Feature dimension | 126 (2 × 21 landmarks × 3 coords) |
| Test accuracy (v2, leak-free Roboflow split) | **97.47%** |
| Test macro-F1 (v2) | 0.9709 |
| v1 reference (pooled random 80/20 split) | 96.85% |
| Runtime | Real-time on-device (no network, no server); pipeline latency logged every 120 frames |

Confusion matrix, class distribution, and per-class breakdowns: `hand_gesture_model/naruto-hand-sign-4/phase1_outputs_unified/`.

## Credits

- Dataset: [Aditya's Workshop — Naruto Hand Sign](https://universe.roboflow.com/adityas-workshop-kr2u8/naruto-hand-sign-cyq8u) (CC BY 4.0)
- Hand/face landmarks: [MediaPipe Tasks](https://developers.google.com/mediapipe) (Google)
- Naruto is a trademark of its respective owners; this is a non-commercial fan/educational project.

**Farrell Habibie Putra Haris** — [GitHub](https://github.com/Farrellhrs) · farrellhrs@gmail.com
