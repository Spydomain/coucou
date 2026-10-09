#!/usr/bin/env bash
# Install Coucou and its build/runtime dependencies on a Linux desktop.
# Run from a checkout, or pipe this file to bash to clone a fresh checkout.
set -euo pipefail

REPO_URL="https://github.com/Louis-CFM/coucou.git"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/windows/package-lock.json" ]]; then
  COUCOU_DIR="$SCRIPT_DIR"
else
  COUCOU_DIR="${COUCOU_DIR:-$HOME/coucou}"
fi
WINDOWS_DIR="$COUCOU_DIR/windows"
BINARY="$WINDOWS_DIR/target/release/coucou"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DESKTOP_FILE="$DATA_HOME/applications/coucou.desktop"
AUTOSTART_FILE="$CONFIG_HOME/autostart/coucou.desktop"
ICON_FILE="$DATA_HOME/icons/hicolor/128x128/apps/coucou.png"
SETTINGS_FILE="$CONFIG_HOME/coucou/settings.json"
PLUGIN_FILE="$CONFIG_HOME/opencode/plugins/coucou.js"
HOOK_FILE="$DATA_HOME/coucou/bin/coucou-hook"
NO_LAUNCH=0
CHECK_ONLY=0
CHECK_MISSING=0

for arg in "$@"; do
  case "$arg" in
    --no-launch) NO_LAUNCH=1 ;;
    --check) CHECK_ONLY=1 ;;
    --build) ;; # Older quickstart entry point accepted this; setup always builds.
    *) printf 'Unknown option: %s\nUsage: %s [--check] [--no-launch] [--build]\n' "$arg" "$0" >&2; exit 2 ;;
  esac
done

log() { printf '[coucou] %s\n' "$*"; }
die() { printf '[coucou] ERROR: %s\n' "$*" >&2; exit 1; }

missing_packages() {
  local package
  for package in "$@"; do
    if command -v pacman >/dev/null 2>&1; then
      pacman -Qq "$package" >/dev/null 2>&1 || printf '%s\n' "$package"
    else
      dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q '^install ok installed$' || printf '%s\n' "$package"
    fi
  done
}

install_system_dependencies() {
  local -a packages missing
  if command -v pacman >/dev/null 2>&1; then
    packages=(base-devel git curl file pkgconf nodejs npm gtk3 webkit2gtk-4.1
      gtk-layer-shell libayatana-appindicator librsvg openssl dbus xdotool playerctl
      gst-plugins-base gst-plugins-good gst-plugins-bad)
  elif command -v apt-get >/dev/null 2>&1; then
    packages=(build-essential git curl file pkg-config nodejs npm libgtk-3-dev
      libwebkit2gtk-4.1-dev libgtk-layer-shell-dev libayatana-appindicator3-dev
      librsvg2-dev libssl-dev libdbus-1-dev libxdo-dev patchelf playerctl
      gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad)
  else
    die 'Supported package managers: pacman or apt-get.'
  fi
  mapfile -t missing < <(missing_packages "${packages[@]}")
  if ((${#missing[@]} == 0)); then
    log 'System dependencies are installed.'
    return
  fi
  log "Missing system packages: ${missing[*]}"
  if ((CHECK_ONLY)); then
    CHECK_MISSING=1
    return
  fi
  if command -v pacman >/dev/null 2>&1; then
    sudo pacman -Syu --needed --noconfirm "${missing[@]}"
  else
    sudo apt-get update
    sudo apt-get install -y "${missing[@]}"
  fi
}

ensure_checkout() {
  if [[ -f "$WINDOWS_DIR/package-lock.json" ]]; then
    log "Using existing checkout: $COUCOU_DIR (no git reset or pull)."
    return
  fi
  [[ ! -e "$COUCOU_DIR" ]] || die "Directory exists but is not a Coucou checkout: $COUCOU_DIR"
  git clone --recursive "$REPO_URL" "$COUCOU_DIR"
}

ensure_rust() {
  if ! command -v rustup >/dev/null 2>&1; then
    log 'Installing Rust using rustup.'
    curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal
    export PATH="$HOME/.cargo/bin:$PATH"
  fi
  rustup toolchain list | grep -q '^stable-' || rustup toolchain install stable --profile minimal
  export RUSTUP_TOOLCHAIN=stable
  # Some distributions put an incompatible system rustc before rustup on PATH.
  local stable_rustc
  stable_rustc="$(rustup which rustc --toolchain stable)"
  export RUSTC="$stable_rustc"
  export PATH="$(dirname "$stable_rustc"):$HOME/.cargo/bin:$PATH"
  rustc --version
}

ensure_opencode() {
  if ! command -v opencode >/dev/null 2>&1 || [[ "$(opencode --version 2>/dev/null || true)" != *'v2.'* ]]; then
    log 'Installing OpenCode v2 from its official installer.'
    curl -fsSL https://opencode.ai/v2/install | bash
    export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"
  fi
  command -v opencode >/dev/null 2>&1 || die 'OpenCode installation did not provide an opencode command.'
  [[ "$(opencode --version)" == *'v2.'* ]] || die 'OpenCode v2 is required.'
  log "OpenCode: $(opencode --version)"
}

build_app() {
  log 'Installing JavaScript dependencies and building release app.'
  (cd "$WINDOWS_DIR" && npm ci && ./node_modules/.bin/tauri build --no-bundle)
  [[ -x "$BINARY" && -x "$WINDOWS_DIR/target/release/coucou-hook" ]] || die 'Release app or relay is missing.'
}

install_files() {
  mkdir -p "$(dirname "$DESKTOP_FILE")" "$(dirname "$AUTOSTART_FILE")" "$(dirname "$ICON_FILE")" "$(dirname "$SETTINGS_FILE")" "$(dirname "$PLUGIN_FILE")" "$(dirname "$HOOK_FILE")"
  install -m 755 "$WINDOWS_DIR/target/release/coucou-hook" "$HOOK_FILE"
  install -m 644 "$WINDOWS_DIR/src-tauri/icons/128x128.png" "$ICON_FILE"
  if [[ ! -e "$SETTINGS_FILE" ]]; then
    printf '{"chatProvider":"opencode","chatModels":{"opencode":"opencode/nemotron-3-ultra-free"},"language":"en"}\n' > "$SETTINGS_FILE"
    log 'Created English/OpenCode defaults.'
  else
    log 'Preserved existing settings.'
  fi
  if [[ ! -e "$PLUGIN_FILE" ]] || grep -q 'generated by Coucou' "$PLUGIN_FILE"; then
    node -e 'const fs=require("node:fs"); const [src,dst,hook]=process.argv.slice(1); const js=fs.readFileSync(src,"utf8").replace("{HOOK}",JSON.stringify(hook)); fs.writeFileSync(dst,js,{mode:0o600});' \
      "$WINDOWS_DIR/scripts/coucou-opencode.js" "$PLUGIN_FILE" "$HOOK_FILE"
    log 'Installed the OpenCode v2 plugin.'
  else
    log "Preserved custom OpenCode plugin: $PLUGIN_FILE"
  fi
  printf '[Desktop Entry]\nType=Application\nName=Coucou\nComment=Desktop companion and media controls\nExec="%s"\nIcon=coucou\nTerminal=false\nCategories=Utility;\n' "$BINARY" > "$DESKTOP_FILE"
  printf '[Desktop Entry]\nType=Application\nName=Coucou\nExec="%s"\nHidden=false\nX-GNOME-Autostart-enabled=true\n' "$BINARY" > "$AUTOSTART_FILE"
  log 'Created application menu and autostart entries.'
}

start_app() {
  local pid path
  while read -r pid; do
    [[ -n "$pid" ]] || continue
    path="$(readlink "/proc/$pid/exe" 2>/dev/null || true)"
    case "$path" in
      "$BINARY"|"$BINARY (deleted)")
        kill -TERM "$pid"
        for _ in {1..40}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
        kill -0 "$pid" 2>/dev/null && die "Old Coucou process $pid did not stop."
        ;;
      *) die "Another Coucou is running at $path; close it before launching this build." ;;
    esac
  done < <(pgrep -x coucou || true)
  nohup "$BINARY" >/dev/null 2>&1 </dev/null &
  pid=$!
  sleep 2
  kill -0 "$pid" 2>/dev/null || die "Coucou failed to start; check $DATA_HOME/coucou/coucou.log"
  log "Coucou running (PID $pid)."
}

install_system_dependencies
if ((CHECK_ONLY)); then
  log 'Dependency check complete; no changes made.'
  exit "$CHECK_MISSING"
fi
ensure_checkout
ensure_rust
ensure_opencode
build_app
install_files
opencode service start >/dev/null || die 'Could not start the OpenCode background service.'
if ((NO_LAUNCH)); then
  log 'Setup complete. Launch skipped (--no-launch).'
else
  start_app
  log 'Setup complete.'
fi
