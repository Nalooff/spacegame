extends Node
## Autoload "Data": every tunable number of the game + the local player's choices.
## Want to rebalance something? Change the constant here and nowhere else.
##
##   Data.RCS_FRACTION            -> RCS strength relative to best-direction thrust
##   Data.TURRET_DAMAGE ...       -> weapons
##   Data.player_name             -> chosen in the lobby
##   Data.selected_ship_json      -> design the player will fly (set in the lobby)

# ------------------------------------------------------------------ network
const DEFAULT_PORT := 24565
const MAX_PLAYERS := 16

# ------------------------------------------------------------------ gameplay
const RESPAWN_DELAY := 4.0          # seconds between death and respawn
const RCS_FRACTION := 0.05          # RCS force = this * ship's best-direction thrust
const PROJECTILE_POOL_SIZE := 256    # bullets that can be in flight at once

const TURRET_DAMAGE := 25.0
const TURRET_COOLDOWN := 0.25       # seconds between salvos
const TURRET_PROJECTILE_SPEED := 120.0
const TURRET_POWER_COST := 3000.0   # watts while firing

# ------------------------------------------------------------------ damage / ramming
const RAM_ENERGY_TO_DAMAGE := 0.0012  # hit points per joule of collision energy above the dent threshold
const RAM_COOLDOWN := 0.3             # seconds before the same collider can hurt the same ship again
const DENT_PER_MS := 0.05             # metres of dent per m/s above the threshold (for hardness 50)
const DENT_MAX_DEPTH := 5.0          # a single collision never dents deeper than this (m)
const DENT_DETAIL := 2.0              # new vertices: faces near a dent are cut until their edges are radius / DENT_DETAIL long. LOWER = fewer vertices (2 = few, 3 = default, 5 = many)
const DENT_MIN_EDGE := 0.15           # metres: faces are never cut smaller than this (raise it, e.g. 0.15, to cap the vertex count)
# ------------------------------------------------------------------ structure / thrusters / turrets
## CRUSH RULE, 2nd part: a dented module whose pushed vertices sink deeper than this (metres) into a module it is
## attached to is destroyed instead of clipping through it.
const CRUSH_PENETRATION := 0.15
const CRUSH_VOLUME_FRACTION := 0.35   # a module dented down to less than this share of its volume is crushed (destroyed)
const SPLIT_PUSH := 0.6               # m/s the two halves of a split ship drift apart
const EXHAUST_BASE_LENGTH := 0.8      # exhaust no-go cone: length = base + per_power * thruster power
const EXHAUST_LENGTH_PER_POWER := 0.0006
const EXHAUST_START_RADIUS := 0.18
const EXHAUST_HALF_ANGLE := 14.0      # degrees
const EXHAUST_BURN_DPS := 40.0        # burn damage per second at full throttle for a module inside the cone
const TURRET_AIM_TOLERANCE_DEG := 4.0  # a turret fires once its barrel points this close to the aim point
const TURRET_BLOCK_RANGE := 4.0       # a turret refuses to fire if its own hull is within this distance in front of the muzzle

const DENT_BASE_RADIUS := 0.5         # metres around the impact that get pushed in

# ------------------------------------------------------------------ lobby
const LOBBY_SECONDS := 120.0          # countdown before the host may force-launch
const DISCOVERY_PORT := 24566         # UDP port lobbies are advertised on (LAN)
## INTERNET lobby list = a free public "message board" (ntfy-compatible), so you do not run or pay for a server.
## Hosts post one small message per lobby (name, players, public IP + port - never a password); browsers read the
## last few minutes of messages. Any ntfy server works (the free https://ntfy.sh, or your own later).
## CHANGE BOARD_TOPIC to something unique for your game (anyone who knows the topic can read/write it).
const BOARD_ENABLED := true
var BOARD_URL := "https://ntfy.sh"   # (var, so tests / a settings screen can point it elsewhere)
var BOARD_TOPIC := "vertexships-lobbies-7f3a9c"
const BOARD_HEARTBEAT := 30.0         # seconds between "still open" posts
const BOARD_STALE := 100.0            # a lobby not refreshed for this long is hidden (host crashed / PC off)
var PUBLIC_IP_URLS: Array[String] = ["https://api.ipify.org", "https://icanhazip.com", "https://checkip.amazonaws.com"]

# ------------------------------------------------------------------ files
const PREMADE_SHIP_DIR := "res://ships/"
const SAVED_SHIP_DIR := "user://ships/"

# ------------------------------------------------------------------ local player state
var player_name: String = "Pilot"
## JSON text of the design the local player will fly.
var selected_ship_json: String = ""
## Path the ship builder should open on start ("" = new ship).
var builder_open_path: String = ""
## One-line message shown on the next menu/lobby screen.
var notice: String = ""
## The ship the local player is flying right now (null in menus). Set by the world.
var local_ship: Ship = null


func ship_name_of(json: String) -> String:
	if json == "":
		return "?"
	var parsed: Variant = JSON.parse_string(json)
	if typeof(parsed) == TYPE_DICTIONARY:
		return str((parsed as Dictionary).get("name", "?"))
	return "?"
