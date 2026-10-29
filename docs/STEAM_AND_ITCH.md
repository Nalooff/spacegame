# Releasing on Steam and itch.io

The game runs the same everywhere. Steam is an **optional layer**: when the Steam add-ons are present and the Steam client is running,
lobbies, joining and networking go through Steam (no port forwarding, no UPnP, friends can use "Join game"). Otherwise the game falls
back to LAN discovery + the internet board (see README, "Multiplayer").

| | itch.io build | Steam build |
|---|---|---|
| Add-ons | none | GodotSteam (GDExtension) + GodotSteam MultiplayerPeer |
| Lobby list | LAN + internet board (ntfy) | Steam lobbies (+ LAN / board as a fallback list) |
| Connection | direct ENet, host needs UPnP / port 24565 UDP | Steam relay (SteamNetworkingSockets), no port forwarding |
| Friends | share the lobby name | Steam friends list, "Join game", rich presence |

## What is in the project
* `scripts/net/steam_backend.gd` (`SteamBackend`): the ONLY file that talks to the add-ons. Every call is written as a string
  (`api.call("createLobby", ...)`), so the project compiles with or without them. If an add-on changes a name, fix it there.
* `scripts/autoload/net.gd`: `Net.steam`, `Net.steam_active()`, `Net.host_steam()`, `Net.join_steam()`; Steam lobbies appear in
  `Net.all_lobbies()` with `source = "steam"`. The roster, ship transfer, passwords and crew all run unchanged on top of the Steam peer.
* `scripts/ui/lobby_browser.gd`: hosts through Steam when it is active, shows "(Steam)" in the list, handles a friend's invite.
* `Data.USE_STEAM` (`scripts/autoload/data.gd`): set it to `false` to never use Steam even when installed.
* `tests/test_steam.tscn`: runs our side against a FAKE Steam (call order, lobby data, list parsing, join flow, invites).

## Steam setup, step by step
1. **Steamworks**: create the app (you get an App ID). While developing you can use App ID **480** (Spacewar, Valve's test app).
2. **Add-ons**: install the *GodotSteam GDExtension* for Godot 4.4 and the *GodotSteam MultiplayerPeer* into `res://addons/`.
   **Where to get them: the GitHub repository `GodotSteam/GodotSteam` is only a signpost now** (its readme says the project moved to
   **Codeberg**: https://codeberg.org/godotsteam/godotsteam, releases there; docs and downloads also at https://godotsteam.com).
   The Godot Asset Library has both add-ons too (search "GodotSteam"). The MultiplayerPeer source is still on GitHub
   (`GodotSteam/multiplayerpeer`); its prebuilt files are in the releases next to the GDExtension. Take the build that matches Godot 4.4. Restart the editor. In the editor, `Engine.has_singleton("Steam")` and
   `ClassDB.class_exists("SteamMultiplayerPeer")` must both be true (that is exactly what `SteamBackend.is_available()` checks).
3. **steam_appid.txt**: a text file containing only your App ID, next to the editor / the exported .exe, for testing outside Steam. Do not ship it
   in the final Steam build (Steam supplies the ID). It is not committed to the repo.
4. Start the Steam client, log in, run the game. The Play screen says `Steam: <your name>`. Create a lobby: it is listed as "(Steam)".
   A second PC with another Steam account (or a friend) sees it and joins.
5. **Depot / build**: use Steamworks' SteamPipe (`steamcmd` with a `.vdf` build script) to upload the exported folder. Include the add-on's
   Steam redistributable library next to the executable (the add-on's documentation lists the exact files for Windows / Linux / macOS).
6. Optional later: achievements, cloud saves for `user://ships/`, Steam Workshop for ships (ships are single `.json` / `.ship` files, which
   suits it). None of this is started yet.

## What could NOT be verified here
The real add-ons and a real Steam client are not available in the development sandbox. What was tested: the game without the add-ons
(unchanged behaviour), and our whole Steam flow against a fake Steam object. What is NOT tested: the actual GodotSteam call names/signatures
at your version, lobby listing and relay connections against real Steam, friend invites. The calls used are
`steamInitEx`, `run_callbacks`, `createLobby`, `setLobbyData`/`getLobbyData`, `addRequestLobbyList*Filter`, `requestLobbyList`,
`joinLobby`, `leaveLobby`, `getLobbyOwner`, `setRichPresence`, the signals `lobby_created`, `lobby_match_list`, `lobby_joined`,
`join_requested`, and `SteamMultiplayerPeer.create_host(0)` / `create_client(owner_steam_id, 0)`. If something differs in your version, the
error will point at `steam_backend.gd`.

## itch.io
1. **Export**: Project -> Export. `export_presets.cfg` has a Windows preset (embed PCK). Add Linux and macOS presets the same way if wanted.
   The export path in the preset points to a folder outside the repo: change it. Do not include the Steam add-on files in the itch build.
2. **Upload** with [butler](https://itch.io/docs/butler/): `butler push "Export/windows" yourname/vertex-ships:windows`.
3. **Multiplayer on itch**: players host with UPnP or by forwarding **UDP 24565**. The lobby list is the free ntfy message board:
   change `Data.BOARD_TOPIC` to your own unique string before release. The README explains the limits.
4. A game page should say: needs a router with UPnP (or a forwarded port) to HOST; joining needs nothing; LAN play always works.
