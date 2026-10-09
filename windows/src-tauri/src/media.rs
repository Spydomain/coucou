// The Media pill — all MPRIS players on the session bus (Linux).
//
// Spotify has its own, richer pill (spotify.rs): artwork, seek, volume. This one
// enumerates every MPRIS player — browser videos, VLC, mpv, etc. — lets you pick
// which one the controls drive, and shows each one's track info.

#[cfg(target_os = "linux")]
pub use linux::{control, sample, set_active_player, ActivePlayer};

/// Without a session bus there is no player to show or drive.
#[cfg(not(target_os = "linux"))]
pub fn sample() -> serde_json::Value {
    serde_json::json!({})
}

#[cfg(not(target_os = "linux"))]
pub fn control(_action: &str) -> bool {
    false
}

#[cfg(not(target_os = "linux"))]
pub fn set_active_player(_bus: &str) {}

#[cfg(not(target_os = "linux"))]
#[derive(Clone, Debug, serde::Serialize)]
pub struct ActivePlayer {
    pub bus: String,
    pub name: String,
}

#[cfg(target_os = "linux")]
mod linux {
    use serde_json::{json, Value};
    use std::sync::{LazyLock, Mutex};
    use std::time::Duration;

    use dbus::arg::PropMap;
    use dbus::blocking::stdintf::org_freedesktop_dbus::Properties;
    use dbus::blocking::Connection;

    use crate::spotify::{linux::props_of, parse_metadata};

    const PATH: &str = "/org/mpris/MediaPlayer2";
    const PLAYER: &str = "org.mpris.MediaPlayer2.Player";
    const DBUS: &str = "org.freedesktop.DBus";
    /// No player call may hold the poller up for longer than this.
    const CALL: Duration = Duration::from_millis(1200);

    static CONN: LazyLock<Mutex<Option<Connection>>> = LazyLock::new(|| Mutex::new(None));
    /// The bus name of the player whose controls are active.
    static ACTIVE_BUS: LazyLock<Mutex<Option<String>>> = LazyLock::new(|| Mutex::new(None));

    /// Runs `f` on a kept session connection, remaking it if it dropped.
    fn with_conn<R>(f: impl FnOnce(&Connection) -> Option<R>) -> Option<R> {
        let mut slot = CONN.lock().unwrap();
        if slot.as_ref().is_none_or(|c| !c.channel().is_connected()) {
            *slot = Connection::new_session().ok();
        }
        let conn = slot.as_ref()?;
        f(conn)
    }

    /// Every MPRIS player the bus knows about, in the order the bus lists them.
    fn players(conn: &Connection) -> Vec<String> {
        let proxy = conn.with_proxy(DBUS, "/org/freedesktop/DBus", CALL);
        let Ok((names,)): Result<(Vec<String>,), _> = proxy.method_call(DBUS, "ListNames", ()) else {
            return Vec::new();
        };
        names
            .into_iter()
            .filter(|n| n.starts_with("org.mpris.MediaPlayer2."))
            .filter(|n| !n.contains("playerctld"))
            .collect()
    }

    fn status(map: &PropMap) -> String {
        map.get("PlaybackStatus")
            .and_then(|v| v.0.as_str())
            .unwrap_or("")
            .to_string()
    }

    /// Snapshot of one player for the card.
    #[derive(Clone, Debug, serde::Serialize)]
    pub struct PlayerInfo {
        pub bus: String,
        pub name: String,
        pub title: String,
        pub artist: String,
        pub album: String,
        pub genre: String,
        pub bpm: Option<f64>,
        pub duration: f64,
        pub playing: bool,
    }

    /// Keep a valid explicit selection; otherwise prefer what is playing.
    pub(super) fn chosen_bus(players: &[PlayerInfo], selected: Option<String>) -> Option<String> {
        selected
            .filter(|bus| players.iter().any(|p| &p.bus == bus))
            .or_else(|| {
                players
                    .iter()
                    .find(|p| p.playing)
                    .map(|p| p.bus.clone())
                    .or_else(|| players.first().map(|p| p.bus.clone()))
            })
    }

    /// The currently active player (for the frontend).
    #[derive(Clone, Debug, serde::Serialize)]
    pub struct ActivePlayer {
        pub bus: String,
        pub name: String,
    }

    /// "org.mpris.MediaPlayer2.brave.instance4311" → "Brave".
    fn friendly(bus: &str) -> String {
        let base = bus
            .trim_start_matches("org.mpris.MediaPlayer2.")
            .split('.')
            .next()
            .unwrap_or("");
        let mut chars = base.chars();
        match chars.next() {
            Some(c) => c.to_uppercase().collect::<String>() + chars.as_str(),
            None => String::new(),
        }
    }

    fn read_one(conn: &Connection, bus: &str) -> Option<PlayerInfo> {
        let proxy = conn.with_proxy(bus, PATH, CALL);
        let Ok(map) = proxy.get_all(PLAYER) else { return None };
        let props = props_of(&map);
        let metadata = props.iter().find_map(|(k, v)| match (k.as_str(), v) {
            ("Metadata", crate::spotify::Value::Map(m)) => Some(m.as_slice()),
            _ => None,
        });
        let track = metadata.and_then(parse_metadata);
        Some(PlayerInfo {
            bus: bus.to_string(),
            name: friendly(bus),
            title: track.as_ref().map(|t| t.title.clone()).unwrap_or_default(),
            artist: track.as_ref().map(|t| t.artist.clone()).unwrap_or_default(),
            album: track.as_ref().map(|t| t.album.clone()).unwrap_or_default(),
            genre: track.as_ref().map(|t| t.genre.clone()).unwrap_or_default(),
            bpm: track.as_ref().and_then(|t| t.bpm),
            duration: track.as_ref().map(|t| t.duration).unwrap_or(0.0),
            playing: status(&map) == "Playing",
        })
    }

    /// Returns all players + the currently selected one.
    pub fn sample() -> Value {
        with_conn(|conn| {
            let list = players(conn);
            let mut all = Vec::new();
            for bus in list {
                if let Some(info) = read_one(conn, &bus) {
                    all.push(info);
                }
            }
            // Keep the backend's control target in sync with the player shown
            // by the card. Previously this was only computed for the JSON
            // response, so the card displayed a player while every transport
            // command failed because ACTIVE_BUS was still unset.
            let selected = ACTIVE_BUS.lock().unwrap().clone();
            // If no active set (or the old player disappeared), pick the
            // playing one, else the first player.
            let active = chosen_bus(&all, selected);
            *ACTIVE_BUS.lock().unwrap() = active.clone();
            Some(json!({
                "players": all,
                "activeBus": active,
            }))
        })
        .unwrap_or_else(|| json!({"players": [], "activeBus": null}))
    }

    /// Set which player receives transport controls.
    pub fn set_active_player(bus: &str) {
        *ACTIVE_BUS.lock().unwrap() = Some(bus.to_string());
    }

    /// The currently active player's bus name (for the frontend).
    pub fn active_player() -> Option<ActivePlayer> {
        let bus = ACTIVE_BUS.lock().unwrap().clone()?;
        Some(ActivePlayer { name: friendly(&bus), bus })
    }

    pub fn control(action: &str) -> bool {
        let method = match action {
            "playPause" => "PlayPause",
            "play" => "Play",
            "pause" => "Pause",
            "next" => "Next",
            "previous" => "Previous",
            _ => return false,
        };
        let Some(bus) = ACTIVE_BUS.lock().unwrap().clone() else { return false };
        with_conn(|conn| {
            conn.with_proxy(&bus, PATH, CALL).method_call::<(), _, _, _>(PLAYER, method, ()).ok()
        })
        .is_some()
    }
}

#[cfg(test)]
mod tests {
    #[cfg(target_os = "linux")]
    #[test]
    fn sample_lists_players() {
        let v = super::sample();
        assert!(v.is_object());
        println!("media sample: {v}");
        let players = v.get("players").and_then(|p| p.as_array());
        assert!(players.is_some());
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn active_player_falls_back_and_stays_valid() {
        use super::linux::{chosen_bus, PlayerInfo};
        let players = vec![
            PlayerInfo { bus: "brave".into(), name: "Brave".into(), title: String::new(), artist: String::new(), album: String::new(), genre: String::new(), bpm: None, duration: 0.0, playing: false },
            PlayerInfo { bus: "vlc".into(), name: "VLC".into(), title: String::new(), artist: String::new(), album: String::new(), genre: String::new(), bpm: None, duration: 0.0, playing: true },
        ];
        assert_eq!(chosen_bus(&players, None).as_deref(), Some("vlc"));
        assert_eq!(chosen_bus(&players, Some("brave".into())).as_deref(), Some("brave"));
        assert_eq!(chosen_bus(&players, Some("gone".into())).as_deref(), Some("vlc"));
    }
}
