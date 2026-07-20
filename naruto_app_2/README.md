# Sign Weaver (naruto_app_2) — Ground-Up Rebuild

A from-scratch rewrite of the hand-sign jutsu app: **same trained model, entirely new app**. No code, architecture, or visual assets were carried over from `naruto_app/` — only the CoreML classifier and the sound effects.

## What's different from v1

| | v1 (`naruto_app/`) | v2 (`naruto_app_2/`) |
|---|---|---|
| Hand tracking | MediaPipe (CocoaPods dependency) | **Apple Vision** (`VNDetectHumanHandPoseRequest`) — zero dependencies, builds with plain `xcodebuild` |
| State | `ObservableObject` + Combine view models | **`@Observable`** session facade (`ShinobiSession`) |
| Sequence engine | Mode-switch state machine | **`SignSequencer`** — a pure value type: stability gate with visible 0→1 hold progress, longest-match-first resolution, built-in overlap deferral |
| Effects | CAEmitterLayer inside a 3,900-line view | **SpriteKit scene** (`JutsuScene`) with fully code-generated particle textures — fire bursts, procedural lightning bolt paths, water arcs, rotating wind vortex, expanding summoning seal ring |
| Visual identity | Dark teal HUD | **Ink-and-scroll theme**: paper blacks, crimson/gold, falling ink petals, serif brush titles, chakra-blue hand constellation overlay |
| Modes | Free / Tutorial / Speed / Battle / Versus | Focused trio: **Dojo** (free practice), **Academy** (master all 12 seals with freshly written how-to text — no reference images needed), **Trials** (timed runs with S/A/B/C grades and persistent best times) |

## Architecture

```
naruto_app_2/
├── Core/
│   ├── Jutsu.swift                — HandSign + ChakraNature + Jutsu catalog (single source of truth)
│   ├── CameraFeed.swift           — AVFoundation front-camera wrapper
│   ├── SignRecognitionEngine.swift— Vision hand pose → wrist-centered scale-normalized
│   │                                126 features → CoreML RandomForest
│   ├── SignSequencer.swift        — noisy readings → committed signs → casts (pure struct, unit-testable)
│   ├── ShinobiSession.swift       — @Observable facade: camera + engine + sequencer → UI state
│   └── SoundFX.swift              — AVAudioPlayer cache
├── UI/
│   ├── Components.swift           — theme tokens, camera surface, hand constellation,
│   │                                sign chips, hold ring, cast callout
│   └── JutsuEffectsView.swift     — SpriteKit particle overlay (all textures generated in code)
├── Screens/
│   ├── VillageGateScreen.swift    — home
│   ├── DojoScreen.swift           — free practice
│   ├── AcademyScreen.swift        — per-seal mastery with live match meter
│   └── TrialsScreen.swift         — timed challenges + records
└── Resources/                     — hand_gesture_rf_unified.mlmodel + reused SFX
```

## Recognition notes

- The classifier is the v2 model from `hand_gesture_model/` (97.47% held-out test accuracy). Features are built identically to training: MediaPipe 21-landmark ordering, wrist-centered, max-2D-norm scaled, left|right 126-vector with zero-padding.
- Vision provides no z-coordinate, so z features are 0 at runtime (the model was trained with MediaPipe z). This is the same trade-off as v1's Vision fallback path — expect slightly lower confidence than the MediaPipe runtime; the `minimumConfidence` gate in `ShinobiSession` is tuned accordingly. Adding MediaPipe via CocoaPods remains an optional upgrade.
- The `SignSequencer` overlap logic (wind-inside-summoning deferral) is verified by a standalone assertion suite.

## Sound credits

Jutsu SFX reused from v1 with permission of the author (me). For future free replacements: [Pixabay SFX](https://pixabay.com/sound-effects/), [Mixkit](https://mixkit.co/free-sound-effects/), [ZapSplat CC0](https://www.zapsplat.com/license-type/cc0-1-0-universal/).

## Build

Open `naruto_app_2.xcodeproj` and run on a device (camera required) — no pods, no packages, no setup.
