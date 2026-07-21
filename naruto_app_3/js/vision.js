// MediaPipe HandLandmarker wrapper (browser WASM build).
// Loads the same hand_landmarker.task bundle used during training.

const MEDIAPIPE_VERSION = "0.10.14";
const WASM_ROOT = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${MEDIAPIPE_VERSION}/wasm`;

let landmarker = null;

export async function initVision(maxHands = 2) {
  const { FilesetResolver, HandLandmarker } = await import(
    `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${MEDIAPIPE_VERSION}/vision_bundle.mjs`
  );
  const fileset = await FilesetResolver.forVisionTasks(WASM_ROOT);
  landmarker = await HandLandmarker.createFromOptions(fileset, {
    baseOptions: {
      modelAssetPath: "assets/model/hand_landmarker.task",
      delegate: "GPU",
    },
    runningMode: "VIDEO",
    numHands: maxHands,
    minHandDetectionConfidence: 0.4,
    minHandPresenceConfidence: 0.4,
    minTrackingConfidence: 0.4,
  });
  return landmarker;
}

/**
 * @returns {Array<{landmarks: Array<{x,y,z}>, handedness: string|null}>}
 */
export function detectHands(video, timestampMs) {
  if (!landmarker) return [];
  const result = landmarker.detectForVideo(video, timestampMs);
  const hands = [];
  const count = result.landmarks ? result.landmarks.length : 0;
  for (let i = 0; i < count; i++) {
    const handednessCategory = result.handednesses?.[i]?.[0];
    hands.push({
      landmarks: result.landmarks[i],
      handedness: handednessCategory ? handednessCategory.categoryName : null,
      score: handednessCategory ? handednessCategory.score : 0,
    });
  }
  return hands;
}
