use base::config::keys::{OPTION_EXTRA_RENDEZVOUS_OUTGOING, OPTION_EXTRA_RENDEZVOUS_SERVERS};
use hbb_common::{
    config::{Config, REG_INTERVAL, RENDEZVOUS_PORT, RENDEZVOUS_SERVERS, RS_PUB_KEY},
    log,
};
use std::{sync::Mutex, time::Instant};

pub const PUBLIC_SERVER: &str = "public";
/// Shown by the Flutter session as a toast rather than a dialog.
#[cfg(feature = "flutter")]
pub const MSGTYPE_EXTRA_SERVER_TOAST: &str = "custom-info-extra-server";

// `lang::translate` reads the system locale and exists on desktop only; mobile
// falls back to the app's own language setting.
#[cfg(feature = "flutter")]
pub fn translate(name: String) -> String {
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    return crate::lang::translate(name);
    #[cfg(any(target_os = "android", target_os = "ios"))]
    return crate::lang::translate_locale(name, "");
}

#[derive(Clone, Debug, PartialEq)]
pub struct RendezvousTarget {
    pub host: String,
    pub key: String,
    pub primary: bool,
}

/// The primary server(s), then every extra server from `extra-rendezvous-servers`
/// that is not already a primary. A primary's `key` is empty: it keeps reading the
/// configured key live through `get_key()`.
pub fn get_rendezvous_targets() -> Vec<RendezvousTarget> {
    let mut out: Vec<RendezvousTarget> = Config::get_rendezvous_servers()
        .into_iter()
        .map(|host| RendezvousTarget {
            host,
            key: String::new(),
            primary: true,
        })
        .collect();
    out.extend(
        parse_extra_rendezvous_servers()
            .into_iter()
            .map(|(server, key)| RendezvousTarget {
                host: server_host(&server),
                key,
                primary: false,
            }),
    );
    out
}

/// `(server, key)` pairs for the extra servers, with `public` kept literal so the
/// viewer can hand it to `other_server` unchanged.
fn parse_extra_rendezvous_servers() -> Vec<(String, String)> {
    parse(
        &Config::get_option(OPTION_EXTRA_RENDEZVOUS_SERVERS),
        &Config::get_rendezvous_servers(),
    )
}

/// The servers the viewer falls back to: `extra-rendezvous-outgoing` when set,
/// none for `none`, else the same list the device registers on.
pub fn parse_outgoing_rendezvous_servers() -> Vec<(String, String)> {
    parse(
        outgoing_option(
            &Config::get_option(OPTION_EXTRA_RENDEZVOUS_OUTGOING),
            &Config::get_option(OPTION_EXTRA_RENDEZVOUS_SERVERS),
        ),
        &Config::get_rendezvous_servers(),
    )
}

fn outgoing_option<'a>(outgoing: &'a str, extra: &'a str) -> &'a str {
    match outgoing.trim() {
        "" => extra,
        s if s.eq_ignore_ascii_case("none") => "",
        _ => outgoing,
    }
}

/// Server settings baked in at build time (from CI secrets), used as defaults:
/// anything set in the app or with `--option` still wins.
const BUILD_DEFAULTS: &[(&str, Option<&str>)] = &[
    (
        "custom-rendezvous-server",
        option_env!("DEFAULT_RENDEZVOUS_SERVER"),
    ),
    ("key", option_env!("DEFAULT_RS_PUB_KEY")),
    ("relay-server", option_env!("DEFAULT_RELAY_SERVER")),
    ("api-server", option_env!("DEFAULT_API_SERVER")),
    (
        OPTION_EXTRA_RENDEZVOUS_SERVERS,
        option_env!("DEFAULT_EXTRA_RENDEZVOUS_SERVERS"),
    ),
];

pub fn apply_build_defaults() {
    apply_defaults(BUILD_DEFAULTS);
}

fn apply_defaults(defaults: &[(&str, Option<&str>)]) {
    let mut settings = hbb_common::config::DEFAULT_SETTINGS.write().unwrap();
    for (k, v) in defaults {
        if let Some(v) = v.map(str::trim).filter(|v| !v.is_empty()) {
            settings
                .entry(k.to_string())
                .or_insert_with(|| v.to_owned());
        }
    }
}

pub fn server_host(server: &str) -> String {
    if server.eq_ignore_ascii_case(PUBLIC_SERVER) {
        RENDEZVOUS_SERVERS[0].to_owned()
    } else {
        server.to_owned()
    }
}

fn parse(option: &str, primaries: &[String]) -> Vec<(String, String)> {
    let norm = |host: &str| crate::check_port(host, RENDEZVOUS_PORT).to_lowercase();
    let mut seen: Vec<String> = primaries.iter().map(|h| norm(h)).collect();
    let mut out = Vec::new();
    for entry in option.split(',').map(str::trim).filter(|s| !s.is_empty()) {
        let (server, key) = if entry.eq_ignore_ascii_case(PUBLIC_SERVER) {
            (PUBLIC_SERVER.to_owned(), RS_PUB_KEY.to_owned())
        } else {
            let mut it = entry.splitn(2, '?');
            let host = it.next().unwrap_or_default().trim().to_owned();
            let key = it
                .next()
                .unwrap_or_default()
                .split('&')
                .find_map(|kv| kv.strip_prefix("key="))
                .unwrap_or_default()
                .to_owned();
            (host, key)
        };
        if server.is_empty() {
            log::trace!("ignoring invalid {OPTION_EXTRA_RENDEZVOUS_SERVERS} entry: {entry}");
            continue;
        }
        let host = norm(&server_host(&server));
        if seen.contains(&host) {
            continue;
        }
        seen.push(host);
        out.push((server, key));
    }
    out
}

pub const STATE_CONNECTING: &str = "connecting";
pub const STATE_ONLINE: &str = "online";
pub const STATE_ID_TAKEN: &str = "id-taken";
pub const STATE_NOT_DEPLOYED: &str = "not-deployed";
pub const STATE_ERROR: &str = "error";

struct ExtraStatus {
    host: String,
    state: &'static str,
    error: String,
    // UDP registration has no connection to lose, so "online" expires when the
    // server stops answering; `None` for TCP, where an error ends the session.
    online_until: Option<Instant>,
}

lazy_static::lazy_static! {
    static ref EXTRA_STATUS: Mutex<Vec<ExtraStatus>> = Default::default();
}

fn norm_host(host: &str) -> String {
    crate::check_port(host, RENDEZVOUS_PORT).to_lowercase()
}

/// Called by the mediator each time it (re)starts all servers.
pub fn reset_extra_status(targets: &[RendezvousTarget]) {
    *EXTRA_STATUS.lock().unwrap() = targets
        .iter()
        .filter(|t| !t.primary)
        .map(|t| ExtraStatus {
            host: norm_host(&t.host),
            state: STATE_CONNECTING,
            error: String::new(),
            online_until: None,
        })
        .collect();
}

pub fn set_extra_status(host: &str, state: &'static str, error: String) {
    let host = norm_host(host);
    if let Some(s) = EXTRA_STATUS
        .lock()
        .unwrap()
        .iter_mut()
        .find(|s| s.host == host)
    {
        s.state = state;
        s.error = error;
        s.online_until = None;
    }
}

pub fn set_extra_online(host: &str, udp: bool) {
    let host = norm_host(host);
    if let Some(s) = EXTRA_STATUS
        .lock()
        .unwrap()
        .iter_mut()
        .find(|s| s.host == host)
    {
        s.state = STATE_ONLINE;
        s.error.clear();
        s.online_until =
            udp.then(|| Instant::now() + std::time::Duration::from_millis(3 * REG_INTERVAL as u64));
    }
}

/// `[{"server": host, "public": bool, "state": ..., "error": ...}]` for the UI.
pub fn extra_status_json() -> String {
    let public = norm_host(RENDEZVOUS_SERVERS[0]);
    let list: Vec<_> = EXTRA_STATUS
        .lock()
        .unwrap()
        .iter()
        .map(|s| {
            let expired = s.online_until.map(|t| Instant::now() > t).unwrap_or(false);
            let state = if s.state == STATE_ONLINE && expired {
                STATE_CONNECTING
            } else {
                s.state
            };
            serde_json::json!({
                "server": s.host,
                "public": s.host == public,
                "state": state,
                "error": s.error,
            })
        })
        .collect();
    serde_json::Value::Array(list).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn public_and_keyed_servers_are_parsed() {
        let got = parse(
            " public , backup.example.com:21116?key=AbC= ,",
            &["my.server".to_owned()],
        );
        assert_eq!(
            got,
            vec![
                (PUBLIC_SERVER.to_owned(), RS_PUB_KEY.to_owned()),
                ("backup.example.com:21116".to_owned(), "AbC=".to_owned()),
            ]
        );
    }

    #[test]
    fn primaries_and_duplicates_are_dropped() {
        let got = parse(
            "public,my.server?key=x,MY.SERVER:21116,rs-ny.rustdesk.com",
            &["my.server".to_owned()],
        );
        assert_eq!(got, vec![(PUBLIC_SERVER.to_owned(), RS_PUB_KEY.to_owned())]);
        let got = parse("public", &[RENDEZVOUS_SERVERS[0].to_owned()]);
        assert!(got.is_empty());
    }

    #[test]
    fn extra_status_is_reported_per_server() {
        reset_extra_status(&[
            RendezvousTarget {
                host: "my.server".to_owned(),
                key: String::new(),
                primary: true,
            },
            RendezvousTarget {
                host: RENDEZVOUS_SERVERS[0].to_owned(),
                key: String::new(),
                primary: false,
            },
        ]);
        set_extra_status(RENDEZVOUS_SERVERS[0], STATE_ID_TAKEN, String::new());
        let v: serde_json::Value = serde_json::from_str(&extra_status_json()).unwrap();
        let list = v.as_array().unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0]["public"], true);
        assert_eq!(list[0]["state"], STATE_ID_TAKEN);
        set_extra_online(RENDEZVOUS_SERVERS[0], false);
        let v: serde_json::Value = serde_json::from_str(&extra_status_json()).unwrap();
        assert_eq!(v[0]["state"], STATE_ONLINE);
    }

    #[test]
    fn build_defaults_skip_empty_values_and_keep_existing_ones() {
        hbb_common::config::DEFAULT_SETTINGS
            .write()
            .unwrap()
            .insert("relay-server".to_owned(), "from-custom-client".to_owned());
        apply_defaults(&[
            ("test-build-default", Some(" my.server ")),
            ("test-build-empty", Some("")),
            ("test-build-unset", None),
            ("relay-server", Some("from-build")),
        ]);
        let d = hbb_common::config::DEFAULT_SETTINGS.read().unwrap();
        assert_eq!(
            d.get("test-build-default").map(String::as_str),
            Some("my.server")
        );
        assert!(!d.contains_key("test-build-empty"));
        assert!(!d.contains_key("test-build-unset"));
        assert_eq!(
            d.get("relay-server").map(String::as_str),
            Some("from-custom-client")
        );
    }

    #[test]
    fn outgoing_list_defaults_to_extra_and_can_be_turned_off() {
        assert_eq!(outgoing_option("", "public"), "public");
        assert_eq!(outgoing_option(" NONE ", "public"), "");
        assert_eq!(
            outgoing_option("b.example.com?key=k", ""),
            "b.example.com?key=k"
        );
    }
}
