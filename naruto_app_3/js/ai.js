// Duel opponent: a "shadow clone" that telegraphs attacks and gives the
// player a counter window. Difficulty ramps as its HP drops.

import { JUTSU, JUTSU_LIST, isCounter } from "./jutsu.js";

const ATTACK_POOL = [JUTSU.fireball, JUTSU.chidori, JUTSU.waterDragon, JUTSU.phoenixFlower];

export class ShadowCloneAI {
  constructor({ hp = 120 } = {}) {
    this.maxHP = hp;
    this.hp = hp;
    this.playerHP = 100;
    this.phase = "idle";          // idle | telegraph | resolve | over
    this.incoming = null;          // jutsu being telegraphed
    this.phaseEndsAt = 0;
    this.blockedIncoming = false;
    this.winner = null;
    this.log = [];
  }

  start(now) {
    this.phase = "idle";
    this.phaseEndsAt = now + 2500;
  }

  /** Player finished casting a jutsu. Returns a result descriptor. */
  playerCast(jutsu, now) {
    if (this.phase === "over") return null;

    if (this.phase === "telegraph" && this.incoming && isCounter(jutsu, this.incoming)) {
      this.blockedIncoming = true;
      this.phase = "idle";
      this.phaseEndsAt = now + 1800;
      const blocked = this.incoming;
      this.incoming = null;
      return { kind: "block", blocked, with: jutsu };
    }

    // Clone tries to dodge; harder to hit while it's winding up an attack.
    const dodgeChance = this.phase === "telegraph" ? 0.12 : 0.22;
    if (Math.random() < dodgeChance) {
      return { kind: "dodge", jutsu };
    }

    this.hp = Math.max(0, this.hp - jutsu.damage);
    if (this.hp === 0) {
      this.phase = "over";
      this.winner = "player";
      return { kind: "hit", jutsu, defeated: true };
    }
    return { kind: "hit", jutsu, defeated: false };
  }

  /** Advance the state machine. Returns an event or null. */
  tick(now) {
    if (this.phase === "over" || now < this.phaseEndsAt) return null;

    if (this.phase === "idle") {
      this.incoming = ATTACK_POOL[Math.floor(Math.random() * ATTACK_POOL.length)];
      this.blockedIncoming = false;
      this.phase = "telegraph";
      // Counter window shrinks as the clone weakens (it gets desperate).
      const desperation = 1 - this.hp / this.maxHP;
      const windowMs = Math.max(3800, 7000 - desperation * 2600);
      this.phaseEndsAt = now + windowMs;
      return { kind: "telegraph", jutsu: this.incoming, windowMs };
    }

    if (this.phase === "telegraph") {
      const attack = this.incoming;
      this.incoming = null;
      this.phase = "idle";
      this.phaseEndsAt = now + 2600;

      if (this.blockedIncoming) return null; // already resolved by a block

      this.playerHP = Math.max(0, this.playerHP - attack.damage);
      if (this.playerHP === 0) {
        this.phase = "over";
        this.winner = "clone";
        return { kind: "playerHit", jutsu: attack, defeated: true };
      }
      return { kind: "playerHit", jutsu: attack, defeated: false };
    }

    return null;
  }

  counterHint() {
    if (!this.incoming) return null;
    return JUTSU_LIST.filter((j) => isCounter(j, this.incoming));
  }
}
