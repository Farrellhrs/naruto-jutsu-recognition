// 126-feature builder — exact parity with the training pipeline:
// per hand: subtract wrist (landmark 0), scale by max 2D norm, flatten
// 21 landmarks x (x,y,z); left-hand block first, right-hand block second,
// zero-padded when a hand is missing.

const LANDMARKS = 21;
const BLOCK = LANDMARKS * 3; // 63

function normalizeHand(landmarks) {
  const out = new Float32Array(BLOCK);
  const wx = landmarks[0].x, wy = landmarks[0].y, wz = landmarks[0].z;

  let scale = 0;
  for (let i = 0; i < LANDMARKS; i++) {
    const dx = landmarks[i].x - wx;
    const dy = landmarks[i].y - wy;
    const norm = Math.hypot(dx, dy);
    if (norm > scale) scale = norm;
  }
  if (scale < 1e-6) scale = 1;

  for (let i = 0; i < LANDMARKS; i++) {
    out[i * 3] = (landmarks[i].x - wx) / scale;
    out[i * 3 + 1] = (landmarks[i].y - wy) / scale;
    out[i * 3 + 2] = (landmarks[i].z - wz) / scale;
  }
  return out;
}

/**
 * @param {Array<{landmarks: Array, handedness: string|null}>} hands
 *   Hands with canonical (unmirrored) landmark coordinates.
 * @returns {Float32Array|null} 126-dim feature vector, or null if no hands.
 */
export function buildFeatureVector(hands) {
  if (!hands.length) return null;

  const features = new Float32Array(BLOCK * 2);
  let left = null;
  let right = null;
  const fallback = [];

  for (const hand of hands.slice(0, 2)) {
    if (hand.landmarks.length !== LANDMARKS) continue;
    const normalized = normalizeHand(hand.landmarks);
    const label = hand.handedness ? hand.handedness.toLowerCase() : null;

    if (label === "left" && !left) left = normalized;
    else if (label === "right" && !right) right = normalized;
    else {
      const meanX = hand.landmarks.reduce((s, p) => s + p.x, 0) / LANDMARKS;
      fallback.push({ meanX, normalized });
    }
  }

  fallback.sort((a, b) => a.meanX - b.meanX);
  for (const hand of fallback) {
    if (!left) left = hand.normalized;
    else if (!right) right = hand.normalized;
  }

  if (!left && !right) return null;
  if (left) features.set(left, 0);
  if (right) features.set(right, BLOCK);
  return features;
}
