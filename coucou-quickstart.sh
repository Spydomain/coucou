#!/usr/bin/env bash
# Coucou quick-start — configures autostart and launches.
# Builds ONLY if binary is missing or source changed.
# Usage: coucou-quickstart [--build]

set -euo pipefail

COUCOU_DIR="/home/spydomain/coucou/windows"
BINARY="$COUCOU_DIR/target/release/coucou"
DESKTOP_FILE="$HOME/.local/share/applications/coucou.desktop"
AUTOSTART_FILE="$HOME/.config/autostart/coucou.desktop"
BUILD_FLAG="${1:-}"

# ── Fast path: if binary exists and no --build flag, just ensure autostart + launch ───
if [[ ! -f "$BINARY" ]] || [[ "$BUILD_FLAG" == "--build" ]]; then
  echo "🔨 Building Coucou (release, embedded assets)…"
  cd "$COUCOU_DIR"
  npm run tauri build -- --no-bundle
  echo "✅ Build complete"
else
  echo "⚡ Binary exists — skipping build (use --build to force)"
fi

# ── .desktop entry (for app menus) ───────────────────────────────────────────────
mkdir -p "$(dirname "$DESKTOP_FILE")"
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

# ── Autostart entry (launches on graphical login) ─────────────────────────────────
mkdir -p "$(dirname "$AUTOSTART_FILE")"
cat > "$AUTOSTART_FILE" <<'EOF'
[Desktop Entry]
Type=Application
Name=Coucou
Exec=/home/spydomain/coucou/windows/target/release/coucou
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

chmod +x "$BINARY"

# ── Launch if not running ─────────────────────────────────────────────────────────
if pgrep -x coucou >/dev/null; then
  echo "✅ Coucou already running (PID $(pgrep -x coucou))"
else
  echo "🚀 Launching Coucou…"
  nohup "$BINARY" >/dev/null 2>&1 &
  sleep 1
  if pgrep -x coucou >/dev/null; then
    echo "✅ Coucou started (PID $(pgrep -x coucou))"
  else
    echo "⚠️  Failed to start — check ~/.local/share/coucou/coucou.log"
    exit 1
  fi
fi

echo
echo "🎉 Ready. Coucou auto-starts on graphical login."
echo "   Logs: ~/.local/share/coucou/coucou.log"
echo "   Settings: ~/.config/coucou/settings.json"