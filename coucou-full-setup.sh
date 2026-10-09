#!/usr/bin/env bash
# coucou-full-setup.sh — Complete automated setup for new devices
# Run once: curl -fsSL <url> | bash  OR  ./coucou-full-setup.sh

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────────
REPO_URL="https://github.com/Louis-CFM/coucou.git"
COUCOU_DIR="$HOME/coucou"
WINDOWS_DIR="$COUCOU_DIR/windows"
BINARY="$WINDOWS_DIR/target/release/coucou"
DESKTOP_FILE="$HOME/.local/share/applications/coucou.desktop"
AUTOSTART_FILE="$HOME/.config/autostart/coucou.desktop"
SETTINGS_FILE="$HOME/.config/coucou/settings.json"

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR]${NC} $*" >&2; }

# ── Helper: install packages (Arch/CachyOS) ────────────────────────────────────
install_packages() {
  log "Installing system dependencies…"
  if command -v pacman >/dev/null; then
    sudo pacman -S --needed --noconfirm \
      base-devel git nodejs npm rustup \
      gtk3 webkit2gtk libayatana-appindicator \
      gst-plugins-good gst-plugins-base gst-plugins-bad \
      libsoup3 dbus playerctl \
      2>/dev/null || true
    # For Wayland/niri
    sudo pacman -S --needed --noconfirm gtk-layer-shell 2>/dev/null || true
  elif command -v apt >/dev/null; then
    sudo apt update && sudo apt install -y \
      build-essential git nodejs npm curl \
      libgtk-3-dev libwebkit2gtk-4.1-dev libayatana-appindicator3-dev \
      gstreamer1.0-plugins-good gstreamer1.0-plugins-base gstreamer1.0-plugins-bad \
      libsoup-3.0-dev libdbus-1-dev playerctl \
      2>/dev/null || true
  else
    warn "Unknown package manager — please install dependencies manually"
  fi
}

# ── Helper: setup Rust ─────────────────────────────────────────────────────────
setup_rust() {
  log "Setting up Rust toolchain…"
  if ! command -v rustc >/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
  else
    source "$HOME/.cargo/env" 2>/dev/null || true
  fi
  rustup default stable
  rustup update stable
}

# ── Helper: clone or update repo ───────────────────────────────────────────────
clone_repo() {
  log "Cloning/updating Coucou repository…"
  if [[ -d "$COUCOU_DIR/.git" ]]; then
    cd "$COUCOU_DIR"
    git fetch origin
    git reset --hard origin/main
    git submodule update --init --recursive
  else
    git clone --recursive "$REPO_URL" "$COUCOU_DIR"
  fi
}

# ── Helper: install Node deps ──────────────────────────────────────────────────
install_node_deps() {
  log "Installing Node.js dependencies…"
  cd "$WINDOWS_DIR"
  npm ci
}

# ── Helper: build release binary ───────────────────────────────────────────────
build_release() {
  log "Building release binary (this takes a minute)…"
  cd "$WINDOWS_DIR"
  npm run tauri build -- --no-bundle
  ok "Built: $BINARY"
}

# ── Helper: create .desktop files ──────────────────────────────────────────────
create_desktop_files() {
  log "Creating desktop/autostart entries…"
  mkdir -p "$(dirname "$DESKTOP_FILE")" "$(dirname "$AUTOSTART_FILE")"

  cat > "$DESKTOP_FILE" <<'EOF'
[Desktop Entry]
Name=Coucou
Comment=AI agent companion — system monitor, media controls, agent hooks
Exec=/home/spydomain/coucou/windows/target/release/coucou
Icon=coucou
Terminal=false
Type=Application
Categories=Utility;Development;
StartupNotify=false
EOF

  cat > "$AUTOSTART_FILE" <<'EOF'
[Desktop Entry]
Type=Application
Name=Coucou
Exec=/home/spydomain/coucou/windows/target/release/coucou
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

  chmod +x "$BINARY" 2>/dev/null || true
  ok "Desktop entries created"
}

# ── Helper: write default settings ─────────────────────────────────────────────
write_settings() {
  log "Writing default settings…"
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  cat > "$SETTINGS_FILE" <<'EOF'
{
  "soundEnabled": true,
  "soundVolume": 0.2,
  "autoCloseInterval": 15.0,
  "openOnHover": false,
  "absenceInterval": 180.0,
  "activeIntegrations": [
    "integration_system",
    "integration_media",
    "integration_github"
  ],
  "mainPill": "agent_codex",
  "screen": "primary",
  "islandX": null,
  "islandY": null,
  "autostart": true,
  "hooksInstalled": false,
  "model": "claude-opus-5",
  "showPlanInNotch": true,
  "planRelayInstalled": false,
  "showCodexPlanInNotch": true,
  "chatProvider": "opencode",
  "chatModels": {
    "opencode": "opencode/nemotron-3-ultra"
  },
  "ollamaUrl": "",
  "lmstudioUrl": "",
  "opencodeUrl": "http://127.0.0.1:11434",
  "customUrl": "",
  "shortcuts": {
    "toggleIsland": {
      "keys": "Ctrl+Alt+N",
      "enabled": false
    }
  },
  "mochiOutfit": "auto",
  "pillColors": {},
  "language": "",
  "desktopMochi": {
    "onDesktop": false,
    "spot": null
  }
}
EOF
  ok "Settings written to $SETTINGS_FILE"
}

# ── Helper: setup OpenCode hook (optional) ─────────────────────────────────────
setup_opencode_hook() {
  log "Setting up OpenCode hook…"
  mkdir -p "$HOME/.config/opencode/plugins"
  cat > "$HOME/.config/opencode/plugins/coucou.js" <<'EOF'
// Coucou plugin for OpenCode — generated by coucou-full-setup.sh
import { spawn } from 'node:child_process';

const HOOK = "/home/spydomain/.local/share/coucou/bin/coucou-hook";
const EVENT_MAP = {
  'session.created': 'SessionStart',
  'session.idle': 'Stop',
  'session.error': 'StopFailure',
  'session.deleted': 'SessionEnd',
};

function forward(hook_event_name, payload) {
  try {
    const p = spawn(HOOK, ['--agent', 'opencode'], {
      stdio: ['pipe', 'ignore', 'ignore'],
      detached: process.platform !== 'win32',
      windowsHide: true,
    });
    p.on('error', () => {});
    p.stdin.on('error', () => {});
    p.stdin.end(JSON.stringify({ hook_event_name, ...payload }) + '\n');
    p.unref();
  } catch {}
}

export const CoucouPlugin = async ({ directory } = {}) => ({
  event: async ({ event }) => {
    const hook_event_name = EVENT_MAP[event?.type];
    if (!hook_event_name) return;
    const props = event.properties || {};
    forward(hook_event_name, {
      session_id: props.sessionID || props.info?.id || '',
      cwd: directory || '',
    });
  },
  'tool.execute.before': async (input, output) => {
    forward('PreToolUse', {
      session_id: input?.sessionID || '',
      cwd: directory || '',
      tool_name: typeof input?.tool === 'string' ? input.tool : '',
      tool_input: output?.args ?? null,
    });
  },
  'tool.execute.after': async (input) => {
    forward('PostToolUse', {
      session_id: input?.sessionID || '',
      cwd: directory || '',
      tool_name: typeof input?.tool === 'string' ? input.tool : '',
    });
  },
});
EOF
  ok "OpenCode plugin installed"
}

# ── Helper: launch app ─────────────────────────────────────────────────────────
launch_app() {
  log "Launching Coucou…"
  if pgrep -x coucou >/dev/null; then
    pkill -x coucou
    sleep 1
  fi
  nohup "$BINARY" >/dev/null 2>&1 &
  sleep 2
  if pgrep -x coucou >/dev/null; then
    ok "Coucou running (PID $(pgrep -x coucou))"
  else
    err "Failed to start — check ~/.local/share/coucou/coucou.log"
    exit 1
  fi
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
  echo
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║           Coucou Full Automated Setup                        ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo

  install_packages
  setup_rust
  clone_repo
  install_node_deps
  build_release
  create_desktop_files
  write_settings
  setup_opencode_hook
  launch_app

  echo
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  🎉 Setup Complete!                                           ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo
  echo "Coucou is running and will auto-start on graphical login."
  echo
  echo "Key files:"
  echo "  Binary:      $BINARY"
  echo "  Settings:    $SETTINGS_FILE"
  echo "  Logs:        ~/.local/share/coucou/coucou.log"
  echo "  OpenCode hook: ~/.config/opencode/plugins/coucou.js"
  echo
  echo "Next steps:"
  echo "  1. Start your OpenCode server (OpenAI-compatible) on port 11434"
  echo "     Example: opencode serve --port 11434"
  echo "  2. Open Coucou chat → provider picker → select 'OpenCode'"
  echo "  3. Press Ctrl+Alt+N to toggle the island"
  echo "  4. Drag the top wake strip to reposition the island"
  echo
}

# Run
main "$@"