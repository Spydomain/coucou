# Coucou desktop companion

This repository contains a personal Linux setup of Coucou, with a top-edge capsule, Mochi animations, media controls, and OpenCode chat. The code also contains macOS, iOS and Windows projects; this guide covers the Linux setup script and does not claim to publish installers for those platforms.

The capsule opens on hover. It shows media and agent activity, plays charging/unplugging and low-battery reactions, and gives occasional time-of-day and long-use reminders. Reminders stay inside the expanded capsule. OpenCode is the configured chat provider; no Llama installation is needed.

## Linux setup

Supported package managers: `pacman` (Arch-based) or `apt-get` (Debian/Ubuntu-based). A graphical desktop session and `sudo` access are required to install missing system packages. The script installs build dependencies, Rust, OpenCode v2 if needed, the Tauri app, its OpenCode hook, a 30-day **Coucou chat session** cleanup timer, and autostart. It preserves an existing checkout and existing valid settings rather than resetting Git history.

```bash
git clone https://github.com/Spydomain/coucou.git
cd coucou
./coucou-full-setup.sh --check      # inspect missing system packages; no changes
./coucou-full-setup.sh              # install, build, configure, and launch
```

The first build can take a while and downloads dependencies from the distribution package manager, npm, Rust, and (if missing) OpenCode's official installer. Review this repository and those sources before running a setup script. Running the script again rebuilds and restarts the app without a `git reset` or pull. `--no-launch` installs everything without starting Coucou immediately.

On Niri, the installer enables `coucou-app.service` for the graphical session. On other Linux desktops it writes an XDG autostart entry. It retires old same-binary XDG entries on Niri as recoverable `*.disabled-by-coucou-setup.*` files, to prevent duplicate launches after a reboot. Settings are stored at `~/.config/coucou/settings.json` (mode `0600`); the app and hook are built in `windows/target/release/` and installed to stable paths under `~/.local/share/coucou/bin/`. OpenCode must be installed and available for chat; the installer checks that its v2 service starts.

To inspect the running app on Niri:

```bash
systemctl --user status coucou-app.service
journalctl --user -u coucou-app.service -n 100 --no-pager
systemctl --user status coucou-opencode-cleanup.timer
```

For other desktops, check the autostart entry in `~/.config/autostart/coucou.desktop` and Coucou's log in `~/.local/share/coucou/coucou.log`. Move the pointer to the top-center edge of the screen to open the capsule; select a media player for play/pause, previous and next. If a player does not support a command, its own media service may not expose it.

## Privacy and security

Coucou's local agent hook uses a private same-user Unix socket on Linux, rather than an Internet listener. Chat is sent to the selected OpenCode provider; enabling an optional service integration sends its requests to that service. Leave integrations disabled when they are not needed, and use HTTPS for remote n8n endpoints. Logs and settings are local; do not share them if they include project names, session text, or tokens. The app cannot guarantee privacy of an external OpenCode provider or third-party integration.

## Other platforms and development

The Windows/Linux Tauri source is in [`windows/`](windows/README.md). From `windows/`, use `npm ci`, `npm test`, and `npm run build` for frontend development; Rust tests run with `cargo test` in `windows/src-tauri/`. macOS and iOS code is in `NotchBuddy/` and `Coucou-iOS/`.

## Licenses

Source code is MIT-licensed; retain the copyright notice in [`LICENSE`](LICENSE). The Coucou/Mochi names, character, sounds, and artwork have separate restrictions in [`LICENSE-ASSETS.md`](LICENSE-ASSETS.md). This repository's standalone GitHub status does not change those rights. Obtain permission or replace the restricted assets and branding before redistributing a build.
