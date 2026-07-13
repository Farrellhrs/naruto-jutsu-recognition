"""Unified hand-sign classifier v2 — leak-free split + landmark-space augmentation.

Improvements over train2.ipynb:
1. Honors the Roboflow train/valid/test split (no random re-split, so no
   near-duplicate frame leakage between train and test).
2. Landmark-space augmentation on the training split only:
   - horizontal mirror (swap left/right hand blocks, negate x)
   - rotation of (x, y) around the wrist by ±15 degrees
   - small Gaussian jitter
3. Reports per-class precision/recall/F1 and macro-F1 on valid and test,
   plus the old leaky-random-split accuracy for comparison.
4. Exports the best model to CoreML with the same f_000..f_125 interface
   the iOS app already uses.

Run:  python train_unified_v2.py            (in the yolo-env conda env)
"""

from pathlib import Path
import json
import warnings

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (accuracy_score, classification_report,
                             confusion_matrix, f1_score)
from sklearn.model_selection import train_test_split

warnings.filterwarnings("ignore")

PROJECT_DIR = Path(__file__).resolve().parent
ARTIFACT_DIR = PROJECT_DIR / "naruto-hand-sign-4" / "phase1_outputs_unified"
OUTPUT_DIR = PROJECT_DIR / "naruto-hand-sign-4" / "phase1_outputs_unified_v2"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

SEED = 42
N_LANDMARKS = 21
BLOCK = N_LANDMARKS * 3  # 63 features per hand
rng = np.random.default_rng(SEED)


# ---------------------------------------------------------------- data
X = np.load(ARTIFACT_DIR / "X_landmarks_unified.npy").astype(np.float32)
y = np.load(ARTIFACT_DIR / "y_labels_unified.npy", allow_pickle=True)
meta = pd.read_csv(ARTIFACT_DIR / "sample_metadata_unified.csv")
assert len(X) == len(meta) == len(y)

split = meta["split"].to_numpy()
tr, va, te = split == "train", split == "valid", split == "test"
print(f"samples  train={tr.sum()}  valid={va.sum()}  test={te.sum()}")


# ---------------------------------------------------- augmentation ops
def _blocks(vec):
    """Return (left, right) hand blocks as (21, 3) arrays (copies)."""
    return (vec[:BLOCK].reshape(N_LANDMARKS, 3).copy(),
            vec[BLOCK:].reshape(N_LANDMARKS, 3).copy())


def _merge(left, right):
    return np.concatenate([left.reshape(-1), right.reshape(-1)])


def _present(block):
    return not np.allclose(block, 0.0)


def mirror(vec):
    """Horizontal flip: negate x and swap hand roles (left <-> right)."""
    left, right = _blocks(vec)
    for b in (left, right):
        if _present(b):
            b[:, 0] = -b[:, 0]
    return _merge(right, left)


def rotate(vec, degrees):
    """Rotate (x, y) around the wrist (origin after normalization)."""
    theta = np.deg2rad(degrees)
    c, s = np.cos(theta), np.sin(theta)
    rot = np.array([[c, -s], [s, c]], dtype=np.float32)
    left, right = _blocks(vec)
    for b in (left, right):
        if _present(b):
            b[:, :2] = b[:, :2] @ rot.T
    return _merge(left, right)


def jitter(vec, sigma=0.01):
    left, right = _blocks(vec)
    for b in (left, right):
        if _present(b):
            b += rng.normal(0.0, sigma, size=b.shape).astype(np.float32)
    return _merge(left, right)


def augment_mirror(X_in, y_in):
    """Original + mirrored copy = 2x data (hand signs are chirality-symmetric
    to a first approximation; rotation is deliberately NOT applied because
    several signs are orientation-sensitive)."""
    return (np.concatenate([X_in, np.stack([mirror(v) for v in X_in])]),
            np.concatenate([y_in, y_in]))


def augment_full(X_in, y_in):
    """Original + mirror + two rotations (with light jitter) = 4x data."""
    out_X, out_y = [X_in], [y_in]
    out_X.append(np.stack([mirror(v) for v in X_in]))
    out_y.append(y_in)
    for lo, hi in ((-15.0, -5.0), (5.0, 15.0)):
        degs = rng.uniform(lo, hi, size=len(X_in))
        out_X.append(np.stack([jitter(rotate(v, d)) for v, d in zip(X_in, degs)]))
        out_y.append(y_in)
    return np.concatenate(out_X), np.concatenate(out_y)


# ------------------------------------------------------------- training
def make_rf():
    return RandomForestClassifier(
        n_estimators=400,
        class_weight="balanced_subsample",
        random_state=SEED,
        n_jobs=-1,
    )


def evaluate(model, X_eval, y_eval, name):
    pred = model.predict(X_eval)
    acc = accuracy_score(y_eval, pred)
    macro = f1_score(y_eval, pred, average="macro")
    print(f"  {name}: accuracy={acc:.4f}  macro-F1={macro:.4f}")
    return pred, acc, macro


print("\n[1/4] OLD methodology (random 80/20 on pooled splits — leaky, for comparison)")
X_tr_old, X_te_old, y_tr_old, y_te_old = train_test_split(
    X, y, test_size=0.2, random_state=SEED, stratify=y)
rf_old = make_rf().fit(X_tr_old, y_tr_old)
_, acc_leaky, macro_leaky = evaluate(rf_old, X_te_old, y_te_old, "leaky random test")

print("\n[2/4] Clean split, no augmentation")
rf_clean = make_rf().fit(X[tr], y[tr])
_, acc_va_clean, f1_va_clean = evaluate(rf_clean, X[va], y[va], "valid")
_, acc_te_clean, f1_te_clean = evaluate(rf_clean, X[te], y[te], "test ")

print("\n[3/4] Clean split + augmentation variants")
X_mir, y_mir = augment_mirror(X[tr], y[tr])
print(f"  mirror-only train size: {len(X_mir)}")
rf_mir = make_rf().fit(X_mir, y_mir)
_, acc_va_mir, f1_va_mir = evaluate(rf_mir, X[va], y[va], "valid (mirror)")
_, acc_te_mir, f1_te_mir = evaluate(rf_mir, X[te], y[te], "test  (mirror)")

X_aug, y_aug = augment_full(X[tr], y[tr])
print(f"  full-aug train size: {len(X_aug)}")
rf_aug = make_rf().fit(X_aug, y_aug)
_, acc_va_aug, f1_va_aug = evaluate(rf_aug, X[va], y[va], "valid (full)  ")
_, acc_te_aug, f1_te_aug = evaluate(rf_aug, X[te], y[te], "test  (full)  ")

# Select on validation macro-F1; an augmentation variant must beat the plain
# model by a meaningful margin (0.005) to justify the added train-time cost
# and distribution shift.
MARGIN = 0.005
candidates = [("clean", rf_clean, f1_va_clean),
              ("mirror-augmented", rf_mir, f1_va_mir),
              ("full-augmented", rf_aug, f1_va_aug)]
best_name, best_model, best_f1 = candidates[0]
for name, model, f1 in candidates[1:]:
    if f1 > best_f1 + MARGIN:
        best_name, best_model, best_f1 = name, model, f1
print(f"\nselected model: {best_name} (validation macro-F1 {best_f1:.4f}, margin rule {MARGIN})")

pred_test = best_model.predict(X[te])
report = classification_report(y[te], pred_test, digits=4)
print("\nPer-class report (held-out Roboflow test split):\n" + report)

labels_sorted = sorted(set(y))
cm = confusion_matrix(y[te], pred_test, labels=labels_sorted)
pd.DataFrame(cm, index=labels_sorted, columns=labels_sorted).to_csv(
    OUTPUT_DIR / "confusion_matrix_v2.csv")
with open(OUTPUT_DIR / "classification_report_v2.txt", "w") as f:
    f.write(report)

summary = {
    "train_samples": int(tr.sum()),
    "valid_samples": int(va.sum()),
    "test_samples": int(te.sum()),
    "augmented_train_samples": int(len(X_aug)),
    "leaky_random_split_accuracy": round(float(acc_leaky), 4),
    "clean_split_test_accuracy_no_aug": round(float(acc_te_clean), 4),
    "clean_split_test_macro_f1_no_aug": round(float(f1_te_clean), 4),
    "clean_split_test_accuracy_mirror_aug": round(float(acc_te_mir), 4),
    "clean_split_test_macro_f1_mirror_aug": round(float(f1_te_mir), 4),
    "clean_split_test_accuracy_full_aug": round(float(acc_te_aug), 4),
    "clean_split_test_macro_f1_full_aug": round(float(f1_te_aug), 4),
    "selected_model": best_name,
    "seed": SEED,
}
with open(OUTPUT_DIR / "training_summary_v2.json", "w") as f:
    json.dump(summary, f, indent=2)
print("\nsummary:", json.dumps(summary, indent=2))

# ------------------------------------------------------------- export
print("\n[4/4] CoreML export")
import coremltools as ct  # noqa: E402

input_features = [f"f_{i:03d}" for i in range(X.shape[1])]
coreml_model = ct.converters.sklearn.convert(
    best_model, input_features, "classLabel")
coreml_model.author = "Farrell Habibie Putra Haris"
coreml_model.short_description = (
    "Unified 126-feature Naruto hand-sign classifier v2 "
    "(leak-free split + landmark augmentation)")
coreml_path = OUTPUT_DIR / "hand_gesture_rf_unified.mlmodel"
coreml_model.save(str(coreml_path))
print(f"saved {coreml_path}")
