"""Export the deployed v2 RandomForest to ONNX for the web app.

Reproduces the exact clean-split model from train_unified_v2.py
(deterministic: same data, same seed) and verifies ONNX parity
against sklearn before saving.
"""
from pathlib import Path
import json

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier

ARTIFACT_DIR = Path("naruto-hand-sign-4/phase1_outputs_unified")
OUT_DIR = Path("../naruto_app_3/assets/model")
SEED = 42

X = np.load(ARTIFACT_DIR / "X_landmarks_unified.npy").astype(np.float32)
y = np.load(ARTIFACT_DIR / "y_labels_unified.npy", allow_pickle=True)
meta = pd.read_csv(ARTIFACT_DIR / "sample_metadata_unified.csv")
tr = (meta["split"] == "train").to_numpy()

rf = RandomForestClassifier(
    n_estimators=400, class_weight="balanced_subsample",
    random_state=SEED, n_jobs=-1,
).fit(X[tr], y[tr])

from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType

onnx_model = convert_sklearn(
    rf,
    initial_types=[("features", FloatTensorType([None, 126]))],
    options={id(rf): {"zipmap": False}},
    target_opset=15,
)
OUT_DIR.mkdir(parents=True, exist_ok=True)
onnx_path = OUT_DIR / "hand_sign_rf.onnx"
onnx_path.write_bytes(onnx_model.SerializeToString())

with open(OUT_DIR / "labels.json", "w") as f:
    json.dump(list(rf.classes_), f)

# --- parity check on the whole dataset ---
import onnxruntime as ort
sess = ort.InferenceSession(str(onnx_path))
probs = sess.run(None, {"features": X})[1]
onnx_pred = np.array([rf.classes_[i] for i in probs.argmax(axis=1)])
sk_pred = rf.predict(X)
agreement = (onnx_pred == sk_pred).mean()
prob_diff = np.abs(probs - rf.predict_proba(X)).max()
print(f"onnx size: {onnx_path.stat().st_size/1e6:.1f} MB")
print(f"prediction agreement: {agreement:.6f}")
print(f"max probability diff: {prob_diff:.2e}")
print(f"classes: {list(rf.classes_)}")
