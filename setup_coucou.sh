#!/usr/bin/env bash
# Coucou setup script — builds, installs, and configures autostart.
# Run once after cloning or pulling updates.

set -euo pipefail

COUCOU_DIR="/home/spydomain/coucou/windows"
BINARY="$COUCOU_DIR/target/release/coucou"
DESKTOP_FILE="$HOME/.local/share/applications/coucou.desktop"
AUTOSTART_FILE="$HOME/.config/autostart/coucou.desktop"

echo "🔨 Building Coucou (release, embedded assets)…"
cd "$COUCOU_DIR"
npm run tauri build -- --no-bundle

echo "✅ Build complete: $BINARY"

# ── .desktop entry (for app menus) ───────────────────────────────────────────
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
echo "📝 Created $DESKTOP_FILE"

# ── Autostart entry (launches on graphical login) ─────────────────────────────
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
echo "📝 Created $AUTOSTART_FILE"

# ── Ensure the binary is executable (it is) ───────────────────────────────────
chmod +x "$BINARY"

# ── Restart only if the binary was rebuilt ──────────────────────────────────────
RESTART=0
if pgrep -x coucou >/dev/null; then
  # Check if running binary is older than the one we just built
  RUNNING_BIN=$(readlink -f /proc/$(pgrep -x coucou)/exe 2>/dev/null || echo "")
  if [[ "$RUNNING_BIN" != "$BINARY" ]] || [[ "$BINARY" -nt "$RUNNING_BIN" ]]; then
    echo "🔄 Binary updated — restarting Coucou…"
    pkill -x coucou
    sleep 1
    RESTART=1
  else
    echo "✅ Coucou already running with current binary (PID $(pgrep -x coucou))"
  fi
else
  RESTART=1
fi

if [[ $RESTART -eq 1 ]]; then
  echo "🚀 Launching Coucou…"
  nohup "$BINARY" >/dev/null 2>&1 &
  sleep 1
fi

if pgrep -x coucou >/dev/null; then
  echo "✅ Coucou is running (PID $(pgrep -x coucou))"
else
  echo "⚠️  Coucou failed to start — check ~/.local/share/coucou/coucou.log"
  exit 1
fi

echo
echo "🎉 Done. Coucou will auto-start on next graphical login."
echo "   Logs: ~/.local/share/coucou/coucou.log"
echo "   Settings: ~/.config/coucou/settings.json"