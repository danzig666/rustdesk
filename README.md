# RustDesk Dual

A fork of [RustDesk](https://github.com/rustdesk/rustdesk). Differences from upstream:

- **Dual registration** – a device registers its ID on its own ID server and on extra servers (e.g. the public RustDesk server) at the same time, reachable through all of them. Option `extra-rendezvous-servers`: `public` and/or `host:port?key=KEY`, comma-separated.
- **Viewer fallback** – an ID not found on the main server is looked up on the extra servers (option `extra-rendezvous-outgoing`: empty = same list, `none` = off, or its own list). Online status covers them too.
- **Settings UI** – Network → ID/Relay server has an "Extra ID servers" section with live per-server status; the main window shows "Also on: …".
- **Built-in defaults** – ID server, key, relay, API and extra servers can be baked in at build time (`DEFAULT_*` in the build workflow or repository secrets).
- **Updates from this fork only** – never from rustdesk.com; Windows builds update from this repository's signed `fork-build-*` releases.
- **Android** – installs as "RustDesk Dual" next to the official app; two-finger drag scrolls the remote, pinch zooms.
