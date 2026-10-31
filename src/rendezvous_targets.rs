use base::config::keys::{OPTION_EXTRA_RENDEZVOUS_OUTGOING, OPTION_EXTRA_RENDEZVOUS_SERVERS};
use hbb_common::{
    config::{Config, RENDEZVOUS_PORT, RENDEZVOUS_SERVERS, RS_PUB_KEY},
    log,
};

pub const PUBLIC_SERVER: &str = "public";

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
    fn outgoing_list_defaults_to_extra_and_can_be_turned_off() {
        assert_eq!(outgoing_option("", "public"), "public");
        assert_eq!(outgoing_option(" NONE ", "public"), "");
        assert_eq!(
            outgoing_option("b.example.com?key=k", ""),
            "b.example.com?key=k"
        );
    }
}
