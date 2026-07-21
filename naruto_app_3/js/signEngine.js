// Sign engine: turns noisy per-frame predictions into committed signs and
// jutsu triggers.
//
// Core rules:
// - a sign must be held HOLD_MS before it commits (kills classifier flicker)
// - committed signs join a rolling history; a jutsu fires when its full
//   sequence matches the tail of the history
// - overlapping sequences: if a completed short jutsu is also a live prefix
//   of a longer one, the short trigger is deferred for a grace window —
//   it fires if the caster stops, and yields if the longer jutsu completes
// - target mode (trial/duel-defense): progress is tracked against one
//   sequence, with a grace period for briefly-held wrong signs

import { JUTSU_LIST, normalizeSign } from "./jutsu.js";

const HOLD_MS = 300;
const DEBOUNCE_MS = 350;
const WRONG_SIGN_RESET_MS = 2000;
const DEFER_GRACE_MS = 1800;

const MAX_HISTORY = Math.max(...JUTSU_LIST.map((j) => j.sequence.length));

export class SignEngine {
  constructor({ targetJutsu = null, enforceTimeLimit = false } = {}) {
    this.targetJutsu = targetJutsu;
    this.enforceTimeLimit = enforceTimeLimit;
    this.reset();
  }

  reset() {
    this.history = [];
    this.historyTimes = [];
    this.pendingLabel = null;
    this.pendingSince = 0;
    this.pendingCommitted = false;
    this.lastCommitLabel = null;
    this.lastCommitAt = -Infinity;
    this.wrongLabel = null;
    this.wrongSince = 0;
    this.targetProgress = 0;
    this.targetStartedAt = null;
    this.deferred = null; // {jutsu, expiresAt}
  }

  /** Call every frame, even without a confident label (pass null). */
  update(rawLabel, now = performance.now()) {
    const events = [];

    // Deferred short-jutsu fires once its grace window expires.
    if (this.deferred && now >= this.deferred.expiresAt) {
      const jutsu = this.deferred.jutsu;
      this.deferred = null;
      this._clearAfterTrigger();
      events.push({ type: "trigger", jutsu });
    }

    if (rawLabel == null) {
      this.pendingLabel = null;
      this.pendingCommitted = false;
      return { events, status: "", holdProgress: 0 };
    }

    const label = normalizeSign(rawLabel);

    if (label !== this.pendingLabel) {
      this.pendingLabel = label;
      this.pendingSince = now;
      this.pendingCommitted = false;
      return { events, status: `hold ${label}…`, holdProgress: 0 };
    }

    const held = now - this.pendingSince;
    if (!this.pendingCommitted && held >= HOLD_MS) {
      this.pendingCommitted = true;
      events.push(...this._commit(label, now));
      return { events, status: "", holdProgress: 1 };
    }

    if (this.pendingCommitted && this.targetJutsu) {
      const wrongStatus = this._checkPersistentWrongSign(label, now);
      if (wrongStatus) return { events, status: wrongStatus, holdProgress: 1 };
    }

    return {
      events,
      status: "",
      holdProgress: Math.min(1, held / HOLD_MS),
    };
  }

  _commit(label, now) {
    if (label === this.lastCommitLabel && now - this.lastCommitAt < DEBOUNCE_MS) {
      return [];
    }
    this.lastCommitLabel = label;
    this.lastCommitAt = now;

    if (this.targetJutsu) return this._commitTargeted(label, now);
    return this._commitFreeform(label, now);
  }

  // --- freeform: any jutsu can fire off the rolling history -------------

  _commitFreeform(label, now) {
    const events = [{ type: "sign", sign: label }];

    this.history.push(label);
    this.historyTimes.push(now);
    if (this.history.length > MAX_HISTORY) {
      this.history.shift();
      this.historyTimes.shift();
    }

    const matched = this._matchTail();
    const overlapLen = this._longestLivePrefixOverlap(now);

    if (matched) {
      if (overlapLen > matched.sequence.length) {
        // A longer jutsu is still in progress: park the short one.
        this.deferred = { jutsu: matched, expiresAt: now + DEFER_GRACE_MS };
        events.push({ type: "charging", jutsu: matched });
        return events;
      }
      this.deferred = null;
      this._clearAfterTrigger();
      events.push({ type: "trigger", jutsu: matched });
      return events;
    }

    if (this.deferred) {
      if (overlapLen > this.deferred.jutsu.sequence.length) {
        this.deferred.expiresAt = now + DEFER_GRACE_MS; // still on track
      } else {
        this.deferred = null; // chain broke
      }
    }
    return events;
  }

  _matchTail() {
    // Longest sequence wins when several match the tail.
    let best = null;
    for (const jutsu of JUTSU_LIST) {
      const seq = jutsu.sequence;
      if (this.history.length < seq.length) continue;
      const tail = this.history.slice(-seq.length);
      if (seq.every((s, i) => s === tail[i])) {
        if (!best || seq.length > best.sequence.length) best = jutsu;
      }
    }
    return best;
  }

  _longestLivePrefixOverlap() {
    let best = 0;
    for (const jutsu of JUTSU_LIST) {
      const seq = jutsu.sequence;
      const maxL = Math.min(this.history.length, seq.length - 1);
      for (let L = maxL; L >= 2; L--) {
        const tail = this.history.slice(-L);
        if (seq.slice(0, L).every((s, i) => s === tail[i])) {
          if (L > best) best = L;
          break;
        }
      }
    }
    return best;
  }

  _clearAfterTrigger() {
    this.history = [];
    this.historyTimes = [];
    this.targetProgress = 0;
    this.targetStartedAt = null;
    this.wrongLabel = null;
  }

  // --- targeted: progress along one required sequence -------------------

  _commitTargeted(label, now) {
    const seq = this.targetJutsu.sequence;
    const limitMs = (this.targetJutsu.timeLimitSec ?? 0) * 1000;

    if (
      this.enforceTimeLimit && limitMs > 0 && this.targetStartedAt != null &&
      now - this.targetStartedAt > limitMs
    ) {
      this.targetProgress = 0;
      this.targetStartedAt = null;
      if (label === seq[0]) {
        this.targetProgress = 1;
        this.targetStartedAt = now;
        return [{ type: "sign", sign: label }, { type: "progress", progress: 1, total: seq.length }];
      }
      return [{ type: "timeout" }];
    }

    if (this.targetProgress < seq.length && label === seq[this.targetProgress]) {
      if (this.targetProgress === 0) this.targetStartedAt = now;
      this.targetProgress += 1;
      this.wrongLabel = null;
      const events = [
        { type: "sign", sign: label },
        { type: "progress", progress: this.targetProgress, total: seq.length },
      ];
      if (this.targetProgress === seq.length) {
        const jutsu = this.targetJutsu;
        this._clearAfterTrigger();
        events.push({ type: "trigger", jutsu });
      }
      return events;
    }

    // Wrong sign: start the grace clock instead of resetting immediately.
    this.wrongLabel = label;
    this.wrongSince = now;
    return [{ type: "wrong", sign: label }];
  }

  _checkPersistentWrongSign(label, now) {
    if (label !== this.wrongLabel) return null;
    const elapsed = now - this.wrongSince;
    if (elapsed >= WRONG_SIGN_RESET_MS) {
      this.targetProgress = 0;
      this.targetStartedAt = null;
      this.wrongLabel = null;
      return "wrong sign held — sequence reset";
    }
    return `wrong sign (reset in ${Math.ceil((WRONG_SIGN_RESET_MS - elapsed) / 1000)}s)`;
  }
}
