//! Updates for this fork: installed copies never ask api.rustdesk.com or take
//! rustdesk/rustdesk releases. They look for `fork-build-<run id>-<platform>-<arch>`
//! releases on the fork's GitHub repository, whose `rustdesk-update.json` must be
//! signed with the fork's own key (built in from `FORK_UPDATE_PUBLIC_KEY`). With
//! no key built in, there are no updates at all.

#[cfg(not(any(target_os = "android", target_os = "ios")))]
use crate::update_metadata::{
    UpdateArtifactQuery, UpdateMetadataRequirements, VerifiedUpdateArtifact,
};
use hbb_common::{bail, log, ResultType};

/// Switches the shared update paths over to this module.
pub const ENABLED: bool = true;
pub const PACKAGE_ID: &str = "rustdesk-dual";
const TAG_PREFIX: &str = "fork-build-";
#[cfg(not(any(target_os = "android", target_os = "ios")))]
const SIDECAR_MAX_BYTES: u64 = 1024 * 1024;

fn repo() -> &'static str {
    option_env!("FORK_UPDATE_REPO")
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or("danzig666/rustdesk")
}

/// The run id of the CI build this binary came from; 0 for local builds.
fn current_build() -> u64 {
    option_env!("FORK_BUILD_ID")
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0)
}

fn public_key() -> Option<[u8; 32]> {
    let encoded = option_env!("FORK_UPDATE_PUBLIC_KEY")?.trim();
    crate::decode64(encoded).ok()?.try_into().ok()
}

// Same values as `updater::current_update_platform/arch` on Windows (Flutter) and
// macOS; spelled out here because the updater is not built on mobile.
fn tag_suffix() -> String {
    format!("-{}-{}", std::env::consts::OS, std::env::consts::ARCH)
}

fn build_of_tag(tag: &str, suffix: &str) -> Option<u64> {
    tag.strip_prefix(TAG_PREFIX)?
        .strip_suffix(suffix)?
        .parse()
        .ok()
}

/// Whether downloads from `github.com/<owner>/<repo>` are this fork's updates.
pub(crate) fn is_update_repo(owner: &str, repo_name: &str) -> bool {
    ENABLED && repo() == format!("{owner}/{repo_name}")
}

fn release_page_prefix() -> String {
    format!("https://github.com/{}/releases/tag/", repo())
}

#[derive(serde::Deserialize)]
struct Release {
    tag_name: String,
    #[serde(default)]
    draft: bool,
}

/// The newest release for this platform built after `current`.
fn newest_update_tag(releases: &[u8], current: u64, suffix: &str) -> ResultType<Option<String>> {
    let releases: Vec<Release> = serde_json::from_slice(releases)?;
    Ok(releases
        .into_iter()
        .filter(|r| !r.draft)
        .filter_map(|r| build_of_tag(&r.tag_name, suffix).map(|n| (n, r.tag_name)))
        .filter(|(n, _)| *n > current)
        .max_by_key(|(n, _)| *n)
        .map(|(_, tag)| tag))
}

/// Replaces the api.rustdesk.com version check: sets `SOFTWARE_UPDATE_URL` to the
/// newest fork release page for this platform, or clears it.
pub async fn check_software_update() -> ResultType<()> {
    let found = find_update().await;
    let url = match &found {
        Ok(Some(tag)) => format!("{}{}", release_page_prefix(), tag),
        _ => String::new(),
    };
    #[cfg(feature = "flutter")]
    if !url.is_empty() {
        let mut m = std::collections::HashMap::new();
        m.insert("name", "check_software_update_finish");
        m.insert("url", &url);
        if let Ok(data) = serde_json::to_string(&m) {
            let _ = crate::flutter::push_global_event(crate::flutter::APP_TYPE_MAIN, data);
        }
    }
    *crate::common::SOFTWARE_UPDATE_URL.lock().unwrap() = url;
    found.map(|_| ())
}

async fn find_update() -> ResultType<Option<String>> {
    if public_key().is_none() {
        log::debug!("No fork update key built in; updates are off");
        return Ok(None);
    }
    let url = format!(
        "https://api.github.com/repos/{}/releases?per_page=50",
        repo()
    );
    let client = crate::hbbs_http::create_http_client_async_with_url_strict(&url).await?;
    let response = client
        .get(&url)
        .header("User-Agent", "rustdesk-fork-updater")
        .header("Accept", "application/vnd.github+json")
        .send()
        .await?;
    if !response.status().is_success() {
        bail!("Fork update check failed: {}", response.status());
    }
    let body = response.bytes().await?;
    newest_update_tag(&body, current_build(), &tag_suffix())
}

/// Replaces the rustdesk/rustdesk release-page verification for fork releases.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub(crate) fn verified_artifact(
    release_page_url: &str,
    query: &UpdateArtifactQuery<'_>,
) -> ResultType<VerifiedUpdateArtifact> {
    let Some(key) = public_key() else {
        bail!("No fork update key built in");
    };
    let Some(tag) = release_page_url.strip_prefix(&release_page_prefix()) else {
        bail!("Not a fork release URL: {}", release_page_url);
    };
    match build_of_tag(tag, &tag_suffix()) {
        Some(n) if n > current_build() => {}
        _ => bail!("Not a newer fork release for this platform: {}", tag),
    }
    let prefix = format!("https://github.com/{}/releases/download/{}/", repo(), tag);
    let metadata = fetch(&format!("{prefix}rustdesk-update.json"))?;
    let signature = fetch(&format!("{prefix}rustdesk-update.json.sig"))?;
    crate::update_metadata::verify_fork_update_metadata(
        &metadata,
        &signature,
        UpdateMetadataRequirements {
            expected_version: tag,
            expected_release_id: tag,
            expected_artifact_url_prefix: &prefix,
            artifact: *query,
        },
        PACKAGE_ID,
        key,
    )
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn fetch(url: &str) -> ResultType<Vec<u8>> {
    use std::io::Read;
    let client = crate::hbbs_http::create_http_client_with_url_strict(url)?;
    let response = client.get(url).send()?;
    if !response.status().is_success() {
        bail!("Failed to download {}: {}", url, response.status());
    }
    let mut data = Vec::new();
    response
        .take(SIDECAR_MAX_BYTES + 1)
        .read_to_end(&mut data)?;
    if data.len() as u64 > SIDECAR_MAX_BYTES {
        bail!("{} is too large", url);
    }
    Ok(data)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SUFFIX: &str = "-windows-x86_64";

    #[test]
    fn picks_the_newest_newer_release_for_this_platform() {
        let releases = br#"[
            {"tag_name": "fork-build-200-windows-x86_64"},
            {"tag_name": "fork-build-300-windows-aarch64"},
            {"tag_name": "fork-build-250-windows-x86_64", "draft": true},
            {"tag_name": "fork-build-150-windows-x86_64"},
            {"tag_name": "dual-server-nightly"},
            {"tag_name": "1.5.2"}
        ]"#;
        assert_eq!(
            newest_update_tag(releases, 100, SUFFIX).unwrap().as_deref(),
            Some("fork-build-200-windows-x86_64")
        );
        assert_eq!(newest_update_tag(releases, 200, SUFFIX).unwrap(), None);
    }

    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    #[test]
    fn update_downloads_from_this_fork_are_accepted() {
        let url = format!(
            "https://github.com/{}/releases/download/fork-build-7{SUFFIX}/rustdesk-1.5.1-x86_64.exe",
            repo()
        );
        assert!(crate::updater::get_update_download_file_from_url(&url).is_some());
        assert!(crate::updater::get_update_download_file_from_url(
            "https://github.com/someone/else/releases/download/fork-build-7-windows-x86_64/rustdesk.exe"
        )
        .is_none());
    }

    #[test]
    fn tags_of_other_platforms_or_shapes_are_ignored() {
        assert_eq!(build_of_tag("fork-build-7-windows-x86_64", SUFFIX), Some(7));
        assert_eq!(build_of_tag("fork-build-7-windows-aarch64", SUFFIX), None);
        assert_eq!(build_of_tag("fork-build-x-windows-x86_64", SUFFIX), None);
        assert_eq!(build_of_tag("v1.5.2", SUFFIX), None);
    }
}
