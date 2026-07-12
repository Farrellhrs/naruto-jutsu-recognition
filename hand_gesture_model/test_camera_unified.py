#!/usr/bin/env python3
"""Real-time camera test for unified one/two-hand CoreML model (126 features).

Usage:
    python test_camera_unified.py
    python test_camera_unified.py --model naruto-hand-sign-4/phase1_outputs_unified/hand_gesture_rf_unified.mlmodel --camera-index 0
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

import coremltools as ct
import cv2
import mediapipe as mp
import numpy as np

SCORE_SCALE = 1


def normalize_landmarks(landmarks_xyz: np.ndarray) -> np.ndarray:
    lm = landmarks_xyz.reshape(21, 3).astype(np.float32)
    wrist = lm[0].copy()
    lm = lm - wrist

    scale = np.max(np.linalg.norm(lm[:, :2], axis=1))
    if scale < 1e-6:
        scale = 1.0
    lm = lm / scale
    return lm.flatten()


def parse_feature_index(name: str) -> int:
    if not name.startswith("f_"):
        raise ValueError(f"Unexpected input feature name: {name}")
    return int(name.split("_", 1)[1])


def get_model_input_names(mlmodel: ct.models.MLModel) -> list[str]:
    spec = mlmodel.get_spec()
    names = [inp.name for inp in spec.description.input]
    return sorted(names, key=parse_feature_index)


def assign_hands_to_left_right(result) -> tuple[np.ndarray, np.ndarray, int]:
    left_feat = np.zeros(63, dtype=np.float32)
    right_feat = np.zeros(63, dtype=np.float32)

    if not result.multi_hand_landmarks:
        return left_feat, right_feat, 0

    handedness_list = result.multi_handedness or []
    fallback = []

    for idx, hand_lm in enumerate(result.multi_hand_landmarks):
        pts = np.array([(lm.x, lm.y, lm.z) for lm in hand_lm.landmark], dtype=np.float32)
        feat = normalize_landmarks(pts)

        hand_label = None
        if idx < len(handedness_list):
            hand_label = handedness_list[idx].classification[0].label

        if hand_label == "Left":
            left_feat = feat
        elif hand_label == "Right":
            right_feat = feat
        else:
            x_center = float(np.mean([lm.x for lm in hand_lm.landmark]))
            fallback.append((x_center, feat))

    for _, feat in sorted(fallback, key=lambda t: t[0]):
        if np.all(left_feat == 0):
            left_feat = feat
        elif np.all(right_feat == 0):
            right_feat = feat

    return left_feat, right_feat, len(result.multi_hand_landmarks)


def extract_unified_features(result) -> tuple[np.ndarray | None, int]:
    left_feat, right_feat, hand_count = assign_hands_to_left_right(result)
    if hand_count == 0:
        return None, 0

    merged = np.concatenate([left_feat, right_feat], axis=0).astype(np.float32)
    return merged, hand_count


def features_to_input_dict(features: np.ndarray, input_names: list[str]) -> dict[str, float]:
    if len(features) != len(input_names):
        raise ValueError(f"Feature length mismatch: got {len(features)}, expected {len(input_names)}")
    return {name: float(features[i]) for i, name in enumerate(input_names)}


def predict_gesture(mlmodel: ct.models.MLModel, features: np.ndarray, input_names: list[str]) -> tuple[str, float]:
    input_dict = features_to_input_dict(features, input_names)
    out: dict[str, Any] = mlmodel.predict(input_dict)

    label = str(out.get("classLabel", "unknown"))
    probs = out.get("classProbability", {})

    confidence = 0.0
    if isinstance(probs, dict) and label in probs:
        try:
            confidence = float(probs[label])
        except Exception:
            confidence = 0.0

    return label, confidence


def draw_status(frame: np.ndarray, status: str) -> None:
    cv2.rectangle(frame, (8, 8), (900, 64), (0, 0, 0), thickness=-1)
    cv2.putText(frame, status, (16, 44), cv2.FONT_HERSHEY_SIMPLEX, 0.75, (0, 255, 0), 2, cv2.LINE_AA)


def draw_handedness(frame: np.ndarray, result, mp_hands, mp_draw) -> None:
    if not result.multi_hand_landmarks:
        return

    handedness_list = result.multi_handedness or []
    h, w = frame.shape[:2]

    for idx, hand_lm in enumerate(result.multi_hand_landmarks):
        mp_draw.draw_landmarks(frame, hand_lm, mp_hands.HAND_CONNECTIONS)

        label = "Hand"
        if idx < len(handedness_list):
            label = handedness_list[idx].classification[0].label

        wrist = hand_lm.landmark[0]
        x = int(wrist.x * w)
        y = max(20, int(wrist.y * h) - 12)
        cv2.putText(frame, label, (x, y), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 220, 0), 2, cv2.LINE_AA)


def main() -> None:
    parser = argparse.ArgumentParser(description="Unified camera test for one-hand + two-hand gestures")
    parser.add_argument(
        "--model",
        type=Path,
        default=Path("naruto-hand-sign-4/phase1_outputs_unified/hand_gesture_rf_unified.mlmodel"),
        help="Path to unified .mlmodel",
    )
    parser.add_argument("--camera-index", type=int, default=0, help="OpenCV camera index")
    parser.add_argument(
        "--score-threshold",
        type=float,
        default=100.0,
        help="Minimum score to accept classification (score = probability * 1000)",
    )
    args = parser.parse_args()

    model_path = args.model.expanduser().resolve()
    if not model_path.exists():
        raise FileNotFoundError(f"Model not found: {model_path}")

    mlmodel = ct.models.MLModel(str(model_path))
    input_names = get_model_input_names(mlmodel)
    if len(input_names) != 126:
        raise RuntimeError(f"Unified model must have 126 input features, got {len(input_names)}")

    print(f"Loaded unified model: {model_path}")
    print(f"Score threshold: {args.score_threshold:.1f} (score = prob * {int(SCORE_SCALE)})")

    cap = cv2.VideoCapture(args.camera_index)
    if not cap.isOpened():
        raise RuntimeError(f"Failed to open camera index {args.camera_index}")

    mp_hands = mp.solutions.hands
    mp_draw = mp.solutions.drawing_utils

    with mp_hands.Hands(
        static_image_mode=False,
        max_num_hands=2,
        min_detection_confidence=0.3,
        min_tracking_confidence=0.5,
        model_complexity=1,
    ) as hands:
        print("Press 'q' to quit")
        while True:
            ok, frame = cap.read()
            if not ok:
                print("Failed to read camera frame")
                break

            frame = cv2.flip(frame, 1)
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            result = hands.process(rgb)

            draw_handedness(frame, result, mp_hands, mp_draw)

            features, hand_count = extract_unified_features(result)
            if features is None:
                status = "No hand detected"
            else:
                label, conf = predict_gesture(mlmodel, features, input_names)
                mode = "two-hand" if hand_count >= 2 else "one-hand + zero-pad"
                score = conf * SCORE_SCALE
                if score >= args.score_threshold:
                    status = f"Mode: {mode} | Prediction: {label} | Score: {score:.1f}"
                else:
                    status = f"Mode: {mode} | No confident gesture | Score: {score:.1f}"

            draw_status(frame, status)
            cv2.imshow("Unified Hand Gesture Camera Test", frame)

            key = cv2.waitKey(1) & 0xFF
            if key == ord("q"):
                break

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
