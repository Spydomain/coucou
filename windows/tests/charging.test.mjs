import { test } from "node:test";
import assert from "node:assert/strict";
import { installFakeDom } from "./fakedom.mjs";

installFakeDom();
const { Island } = await import("../src/island/island.ts");
const { Bridge } = await import("../src/core/bridge.ts");
const { State, DEFAULT_SETTINGS } = await import("../src/core/state.ts");

test("both power transitions start a reaction, but the initial reading does not", async () => {
  const island = Object.create(Island.prototype);
  island.root = document.createElement("div");
  island.charging = null;
  const events = [];
  island.startPowerAnimation = (pluggedIn, level) => events.push(`${pluggedIn ? "plug" : "unplug"}:${level}`);
  const statuses = [false, false, true, true, false].map((pluggedIn) => ({ pluggedIn, level: 63 }));
  const originalPowerStatus = Bridge.powerStatus;
  const originalInterval = window.setInterval;
  let poll;
  let intervalMs;
  Bridge.powerStatus = async () => statuses.shift();
  window.setInterval = (fn, ms) => { poll = fn; intervalMs = ms; return 1; };
  try {
    island.installBatteryMood();
    await Promise.resolve();
    assert.ok(intervalMs <= 2_000, "charging reactions should appear promptly");
    assert.deepEqual(events, []);
    for (let i = 0; i < 4; i++) {
      poll();
      await Promise.resolve();
    }
    assert.deepEqual(events, ["plug:63", "unplug:63"]);
    assert.equal(island.root.classList.contains("charging"), false);
  } finally {
    Bridge.powerStatus = originalPowerStatus;
    window.setInterval = originalInterval;
  }
});

test("plug and unplug open the bar, animate inside it, and end automatically", () => {
  const island = Object.create(Island.prototype);
  island.root = document.createElement("div");
  island.chargePop = document.createElement("div");
  island.chargeCanvas = document.createElement("canvas");
  island.chargeCanvas.getContext = () => null;
  island.chargeLabel = document.createElement("span");
  island.chargeIcon = document.createElement("span");
  island.seasons = { get: () => "none" };
  island.chargeToken = 0;
  island.wasInIsland = true;
  let opened = 0;
  island.fsm = { forceHome: () => { opened++; State.mode = "expanded"; } };
  island.ensureRunning = () => {};
  const frames = [];
  const originalFrame = globalThis.requestAnimationFrame;
  globalThis.requestAnimationFrame = (fn) => frames.push(fn);
  State.settings = { ...DEFAULT_SETTINGS };
  State.mode = "hidden";
  State.paused = false;
  State.pendingApproval = null;
  try {
    island.startPowerAnimation(true, 63);
    assert.equal(opened, 1);
    assert.equal(island.chargeLabel.textContent, "Charging · 63%");
    assert.equal(island.chargeIcon.textContent, "⚡");
    assert.ok(island.chargePop.classList.contains("show"));
    assert.equal(island.powerActive, true);
    assert.equal(frames.length, 1);
    frames.shift()(performance.now() + 5_000);
    assert.ok(!island.chargePop.classList.contains("show"));
    assert.ok(!island.root.classList.contains("charger-pop"));
    assert.equal(island.powerActive, false);

    State.view = "overview";
    island.nightMood = true;
    island.startPowerAnimation(false, 64);
    assert.equal(opened, 2);
    assert.equal(island.chargeLabel.textContent, "On battery · 64%");
    assert.equal(island.chargeIcon.textContent, "🔋");
    assert.equal(island.chargeEngine.state, "sleeping");
    assert.ok(island.chargePop.classList.contains("unplugged"));
    assert.ok(island.root.classList.contains("charger-unplug"));
    assert.ok(island.chargePop.classList.contains("show"));
    island.stopChargingPop();
    frames.shift()(performance.now() + 500);
    assert.ok(!island.chargePop.classList.contains("show"));
    assert.ok(!island.root.classList.contains("charger-unplug"));
    assert.equal(frames.length, 0, "closing cancels the animation loop");
  } finally {
    globalThis.requestAnimationFrame = originalFrame;
  }
});

test("rapid replug replaces the old power reaction", () => {
  const island = Object.create(Island.prototype);
  island.root = document.createElement("div");
  island.chargePop = document.createElement("div");
  island.chargeCanvas = document.createElement("canvas");
  island.chargeCanvas.getContext = () => null;
  island.chargeLabel = document.createElement("span");
  island.chargeIcon = document.createElement("span");
  island.seasons = { get: () => "none" };
  island.chargeToken = 0;
  island.wasInIsland = true;
  island.fsm = { forceHome: () => { State.mode = "expanded"; } };
  island.ensureRunning = () => {};
  const frames = [];
  const originalFrame = globalThis.requestAnimationFrame;
  globalThis.requestAnimationFrame = (fn) => frames.push(fn);
  State.mode = "expanded";
  State.paused = false;
  State.pendingApproval = null;
  try {
    island.startPowerAnimation(false, 52);
    island.startPowerAnimation(true, 53);
    frames.shift()(performance.now() + 100);
    assert.equal(island.chargeLabel.textContent, "Charging · 53%");
    assert.ok(island.chargePop.classList.contains("show"));
    assert.ok(island.root.classList.contains("charger-pop"));
    assert.ok(!island.root.classList.contains("charger-unplug"));
  } finally {
    globalThis.requestAnimationFrame = originalFrame;
  }
});

test("night mood sleeps only when idle and music is stopped", () => {
  const island = Object.create(Island.prototype);
  const states = [];
  const emotes = [];
  island.engine = {
    setState: (state) => states.push(state),
    triggerEmote: (emote) => emotes.push(emote),
  };
  island.desktop = { setNightMood: () => {} };
  island.ensureRunning = () => {};
  State.settings = { ...DEFAULT_SETTINGS, activeIntegrations: [] };
  State.tasks = [];
  State.stateOverride = null;
  State.mode = "compact";
  island.setNightMood(true);
  assert.equal(states.at(-1), "sleeping");
  assert.equal(emotes.at(-1), "yawn");

  State.stateOverride = "working";
  island.setNightMood(false);
  island.setNightMood(true);
  assert.equal(states.at(-1), "working");
  assert.equal(emotes.length, 1, "active tasks should not yawn");
  State.stateOverride = null;
});
