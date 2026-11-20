//! A second sign-in, to the public RustDesk server's account service. The public
//! server only lets signed-in users connect, and the main sign-in belongs to the
//! private server, so this token is sent only when connecting through the public
//! server. The main sign-in is left untouched.

use hbb_common::config::LocalConfig;

#[cfg(feature = "flutter")]
const API_SERVER: &str = "https://admin.rustdesk.com";
const OPTION_TOKEN: &str = "public-server-access-token";
#[cfg(feature = "flutter")]
const OPTION_USER: &str = "public-server-user";
// `OidcSession`'s state once the account service has answered.
#[cfg(feature = "flutter")]
const LOGIN_DONE: &str = "Login account auth";

fn access_token() -> String {
    LocalConfig::get_option(OPTION_TOKEN)
}

/// The token a connection through `other_server` (`(id, server, key)`) sends:
/// the public sign-in for the public server, none for any other server.
pub fn token_for(other_server: Option<&(String, String, String)>) -> String {
    match other_server {
        Some((_, server, _)) if server == crate::rendezvous_targets::PUBLIC_SERVER => {
            access_token()
        }
        _ => String::new(),
    }
}

/// The signed-in user's name, or empty when signed out.
#[cfg(feature = "flutter")]
pub fn user() -> String {
    if access_token().is_empty() {
        return String::new();
    }
    LocalConfig::get_option(OPTION_USER)
}

/// Starts a third-party sign-in (`op`: google, github, microsoft) against the
/// public account service, without storing anything as the main sign-in.
#[cfg(feature = "flutter")]
pub fn auth(op: String) {
    crate::hbbs_http::account::OidcSession::account_auth(
        API_SERVER.to_owned(),
        op,
        crate::ui_interface::get_id(),
        crate::ui_interface::get_uuid(),
        false,
    );
}

/// Progress of `auth` as JSON: `state` is waiting, failed or signed-in, with the
/// browser `url` to open while waiting. The token stays on the Rust side.
#[cfg(feature = "flutter")]
pub fn auth_result() -> String {
    let result = crate::hbbs_http::account::OidcSession::get_result();
    if result.state_msg == LOGIN_DONE {
        let Some(body) = result
            .auth_body
            .as_ref()
            .filter(|b| b.r#type == "access_token" && !b.access_token.is_empty())
        else {
            return serde_json::json!({ "state": "failed", "error": "Login failed" }).to_string();
        };
        if access_token() != body.access_token {
            let name = body
                .user
                .display_name
                .clone()
                .filter(|s| !s.is_empty())
                .unwrap_or_else(|| body.user.name.clone());
            LocalConfig::set_option(OPTION_USER.to_owned(), name);
            LocalConfig::set_option(OPTION_TOKEN.to_owned(), body.access_token.clone());
        }
        return serde_json::json!({ "state": "signed-in", "user": user() }).to_string();
    }
    let state = if result.failed_msg.is_empty() {
        "waiting"
    } else {
        "failed"
    };
    serde_json::json!({ "state": state, "url": result.url, "error": result.failed_msg })
        .to_string()
}

#[cfg(feature = "flutter")]
pub fn logout() {
    LocalConfig::set_option(OPTION_TOKEN.to_owned(), String::new());
    LocalConfig::set_option(OPTION_USER.to_owned(), String::new());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_public_server_gets_the_public_sign_in() {
        let via = |server: &str| ("123".to_owned(), server.to_owned(), String::new());
        assert_eq!(token_for(None), "");
        assert_eq!(token_for(Some(&via("backup.example.com:21116"))), "");
        assert_eq!(token_for(Some(&via("public"))), access_token());
    }
}
