// Jutsu definitions: sequences, elements, combat stats, FX styling.
// The 12 recognizable signs: bird, boar, dog, dragon, hare, horse,
// monkey, ox, ram, rat, snake, tiger.

export const SIGNS = [
  "bird", "boar", "dog", "dragon", "hare", "horse",
  "monkey", "ox", "ram", "rat", "snake", "tiger",
];

export const JUTSU = {
  fireball: {
    id: "fireball",
    name: "Fire Style: Fireball",
    kanji: "火遁・豪火球",
    element: "fire",
    sequence: ["horse", "snake", "monkey", "boar", "horse"],
    damage: 26,
    color: "#ff7a2f",
    sfx: "fireball",
  },
  phoenixFlower: {
    id: "phoenixFlower",
    name: "Fire Style: Phoenix Flower",
    kanji: "火遁・鳳仙火",
    element: "fire",
    sequence: ["rat", "tiger", "dog"],
    damage: 16,
    color: "#ff9d4d",
    sfx: "ember",
  },
  chidori: {
    id: "chidori",
    name: "Chidori",
    kanji: "千鳥",
    element: "lightning",
    sequence: ["ox", "hare", "monkey"],
    damage: 24,
    color: "#7fb7ff",
    sfx: "chidori",
  },
  rasengan: {
    id: "rasengan",
    name: "Rasengan",
    kanji: "螺旋丸",
    element: "wind",
    sequence: ["monkey", "bird"],
    damage: 18,
    color: "#59d7ff",
    sfx: "rasengan",
  },
  waterDragon: {
    id: "waterDragon",
    name: "Water Style: Water Dragon",
    kanji: "水遁・水龍弾",
    element: "water",
    sequence: ["ox", "monkey", "hare", "rat", "boar", "bird"],
    damage: 32,
    color: "#3f8dff",
    sfx: "water",
  },
  earthWall: {
    id: "earthWall",
    name: "Earth Style: Mud Wall",
    kanji: "土遁・土流壁",
    element: "earth",
    sequence: ["tiger", "dog", "ox"],
    damage: 12,
    color: "#c8a35f",
    sfx: "earth",
  },
  shadowClone: {
    id: "shadowClone",
    name: "Shadow Clone Jutsu",
    kanji: "影分身の術",
    element: "chakra",
    sequence: ["ram", "snake", "tiger"],
    damage: 14,
    color: "#c9b6ff",
    sfx: "clone",
  },
  summoning: {
    id: "summoning",
    name: "Summoning Jutsu",
    kanji: "口寄せの術",
    element: "chakra",
    sequence: ["boar", "dog", "bird", "monkey", "ram"],
    damage: 30,
    color: "#ffd66b",
    sfx: "summon",
    timeLimitSec: 8, // trial mode only
  },
};

export const JUTSU_LIST = Object.values(JUTSU);

// Elemental counter wheel: what blocks what.
// fire < water, water < earth, earth < lightning, lightning < wind, wind < fire
const COUNTER_BY_ELEMENT = {
  fire: "water",
  water: "earth",
  earth: "lightning",
  lightning: "wind",
  wind: "fire",
  chakra: "chakra",
};

export function countersFor(jutsu) {
  const blockingElement = COUNTER_BY_ELEMENT[jutsu.element];
  return JUTSU_LIST.filter((j) => j.element === blockingElement);
}

export function isCounter(defense, attack) {
  return defense.element === COUNTER_BY_ELEMENT[attack.element];
}

// The model emits "hare"; canon uses hare/rabbit interchangeably.
export function normalizeSign(raw) {
  const s = String(raw).trim().toLowerCase();
  return s === "rabbit" ? "hare" : s;
}
