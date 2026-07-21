// RandomForest hand-sign classifier via onnxruntime-web.
// The ONNX model was exported from the trained sklearn RF with verified
// 100% prediction parity (see hand_gesture_model/export_onnx.py).

/* global ort */

let session = null;
let labels = [];

export async function initClassifier() {
  ort.env.wasm.numThreads = 1; // keeps it simple; RF inference is ~ms anyway
  const [modelResponse, labelsResponse] = await Promise.all([
    fetch("assets/model/hand_sign_rf.onnx"),
    fetch("assets/model/labels.json"),
  ]);
  const modelBytes = new Uint8Array(await modelResponse.arrayBuffer());
  labels = await labelsResponse.json();
  session = await ort.InferenceSession.create(modelBytes, {
    executionProviders: ["wasm"],
  });
}

/**
 * @param {Float32Array} features 126-dim vector
 * @returns {Promise<{label: string, confidence: number, top: Array}>}
 */
export async function classify(features) {
  if (!session) return null;
  const tensor = new ort.Tensor("float32", features, [1, 126]);
  const output = await session.run({ features: tensor });

  // zipmap disabled at export: probabilities come back as a flat tensor.
  const probs = output.probabilities.data;
  let bestIdx = 0;
  for (let i = 1; i < probs.length; i++) {
    if (probs[i] > probs[bestIdx]) bestIdx = i;
  }

  const ranked = Array.from(probs)
    .map((p, i) => ({ label: labels[i], p }))
    .sort((a, b) => b.p - a.p)
    .slice(0, 3);

  return { label: labels[bestIdx], confidence: probs[bestIdx], top: ranked };
}
