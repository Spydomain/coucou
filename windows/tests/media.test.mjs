// The generic Media card is backed by Linux MPRIS. Keep its compact custom
// picker and all transport commands covered: a native <select> previously grew
// tall enough to hide the buttons, while the backend had no selected target.

import { beforeEach, test } from "node:test";
import assert from "node:assert/strict";
import { calls, sent } from "./tauri.mjs";
import { installFakeDom } from "./fakedom.mjs";
import { renderIntegrationCard } from "../src/views/integrations.ts";
import { DEFAULT_SETTINGS, State } from "../src/core/state.ts";
import { IDLE_SPOTIFY, Spotify } from "../src/core/spotify.ts";

installFakeDom();

const task = {
  id: "integration_media", name: "Media", color: "#F5A524", state: "idle", stepIndex: 0, steps: [],
  source: "n8n", isIntegration: true,
};

const hooks = { detailOpen: false, openDetail() {}, closeDetail() {}, openSettings() {} };

beforeEach(() => {
  calls.length = 0;
  State.os = "linux";
  State.settings = { ...DEFAULT_SETTINGS, activeIntegrations: ["integration_media"] };
  State.integrations = {
    integration_media: {
      loaded: true, configured: true, error: null,
      data: {
        activeBus: "org.mpris.MediaPlayer2.brave.instance1",
        players: [
          { bus: "org.mpris.MediaPlayer2.brave.instance1", name: "Brave", title: "Afreen Afreen", artist: "Rahat", album: "Topic", playing: true },
          { bus: "org.mpris.MediaPlayer2.vlc", name: "VLC", title: "Other track", artist: "", album: "", playing: false },
        ],
      },
    },
  };
  Spotify.state = { ...IDLE_SPOTIFY };
});

test("Media has a compact picker and sends every transport action to its selected player", () => {
  const card = renderIntegrationCard(task, hooks);
  assert.ok(card.classList.contains("media-card"));
  assert.match(card.textContent, /Afreen Afreen.*Rahat.*Topic.*Brave/);

  const [picker, brave, vlc, previous, playPause, next] = card.find("BUTTON");
  picker.fire("click");
  assert.ok(card.querySelector("media-picker-menu").classList.contains("open"));
  vlc.fire("click");
  previous.fire("click");
  playPause.fire("click");
  next.fire("click");

  assert.deepEqual(sent("media_set_player"), [{ bus: "org.mpris.MediaPlayer2.vlc" }]);
  assert.deepEqual(sent("media_control"), [
    { action: "previous" },
    { action: "playPause" },
    { action: "next" },
  ]);
  assert.equal(brave.textContent, "Brave ▶");
});

test("Media playback joins Spotify in Mochi's dance state only when the pill is declared", () => {
  assert.ok(State.mediaPlaying);
  assert.ok(State.musicPlaying);
  State.settings.activeIntegrations = [];
  assert.ok(!State.mediaPlaying);
  assert.ok(!State.musicPlaying);
});
