> Code made with the help of AI

# Vertex Ships — Godot 4.4+ project

Multiplayer spaceship game with **vertex-built modular ships**. Build a ship in the editor, fly it, fight with turrets, ram, and manage
the damage on an emergency deck plan. Open this folder in **Godot 4.4 or newer** (`project.godot` is here), press F5.
Main scene: `scenes/main_menu.tscn`. Version in `project.godot` (`config/version`).

* Playing: see **Controls**. Building ships: see **Ship editor** and `docs/MODULE_CREATION.md` (a walkthrough with screenshots).
* Releasing: **Steam and itch.io** in `docs/STEAM_AND_ITCH.md`.
* Architecture notes: `docs/ARCHITECTURE_V2.md`, `docs/ARCHITECTURE_V3.md`.

## Menus and multiplayer
* **Creation** = ship editor. **Play** = lobby browser (nobody types an IP address).
* **Host**: lobby name, Public / Private (password, checked by the host, only a hash is sent). Hosting alone = single player.
* **Join**: the list merges every source:
  * **Steam** (optional, see below): Steam lobbies, joining through friends ("Join game"), no port forwarding;
  * **LAN**: UDP broadcast (`scripts/net/lobby_directory.gd`);
  * **Internet board**: a free ntfy-style message board (`Data.BOARD_URL`, `Data.BOARD_TOPIC` - **change the topic to your own unique string**).
    Hosts post one small JSON message, browsers read it. The game itself is direct peer-to-peer (ENet); `scripts/net/nat_helper.gd` asks the
    router for UPnP and looks up the public IP. If UPnP is refused the host must forward **UDP 24565**. Players behind CGNAT cannot host.
    Players on the same router as the host are switched to the host's LAN address automatically.
* **Steam** (`scripts/net/steam_backend.gd`): used automatically when the GodotSteam add-ons are installed and the Steam client runs; otherwise
  the game behaves exactly as without it (`Data.USE_STEAM` can switch it off). The roster, ship transfer, passwords and crew work unchanged on top.
  Setup, what was tested (against a fake Steam only) and what was not: **docs/STEAM_AND_ITCH.md**.
* **Pre-game room** (`scenes/lobby.tscn`): pick a ship, **Lock in**. A locked ship can be joined as **crew** while it has free seats
  (seats = `crew` of the ship's Commander module, 1-8, pilot included). A **2:00 timer** (`Data.LOBBY_SECONDS`): the host can START when everyone is locked,
  or FORCE LAUNCH after the timer; players without a ship get a random premade one. Teams decide who is a friend (`Net.are_friends`).
* Tested headless: two-process game (`tests/run_net_test.sh`), 3-process lobby (`tests/run_lobby_test.sh`), the internet board against a local fake ntfy
  (`tests/run_board_test.sh`), the Steam flow against a fake Steam (`tests/test_steam.tscn`). NOT verifiable in the build sandbox: real ntfy.sh, real UPnP, real Steam.

## Playing
Each player flies one ship; other players can be **crew** on it. Two ways to run a ship (switch with **V**):
* **Commander** (default): you give orders. Orders and damage reports travel over the ship's **communications**; the radar locks targets.
  Turrets are **half-automatic**: they track the locked enemy, but fire **only when the barrel actually points at it** (within `Data.TURRET_AIM_TOLERANCE_DEG`)
  and only when you allow it: **hold left mouse** or toggle **H = weapons free**. A turret that cannot reach the target (limited arc) turns to the closest
  direction it can reach and waits.
* **Crew** (take a station with **F**): you control that turret yourself; **as long as you hold fire it fires**, pointing at the target or not.

Flight orders (the commander's autopilot, `scripts/ship/autopilot.gd`):
* **GOTO**: fly to a point and stop there (no speed cap: the fastest speed the ship can still brake from, flip with the gyroscope, retro-burn, RCS finishes).
* **DRIVE**: fly towards a point or a tracked ship with a chosen **thrust** and **never stop** (made for ramming). Only **brake (X)** or cancel ends it.
* **Turret facing lock**: while moving, the ship turns so the most turrets bear on the locked enemy (or the destination) instead of pointing its best thrust axis along the push.
* **Tactical map (M)**: click in space to place waypoints (no typing coordinates), see contacts and your orders.

Damage and information: the damage is simulated at once, but what the **commander knows** depends on communications. With comms online, reports are instant.
Without, someone has to walk the report along the corridors (seconds shown on the plan); damage the commander has not heard about is shown as a dashed
**"?" sphere** ("something happened around here"), and rooms with no open corridor to the bridge are marked **NO LINK** - they cannot be ordered and their
reports wait until comms or a corridor is back. Thrusters and external antennas work without a corridor.

## Controls
| Key | Action |
|---|---|
| W / S, A / D, Space / C | thrust forward-back, strafe, up-down (ship-local; the thruster allocator + RCS solve it) |
| arrows, Q / E | pitch / yaw, roll |
| X | brake · **T** hold attitude (flight assist) · **R** lock the target under the cursor |
| left mouse | fire at the cursor (hold = weapons free in commander mode; crew: fires the station's turret) |
| **H** | weapons free on / off · **M** tactical map · **P** ship plan (live status) |
| **V** | commander / crew mode · **F** next station · Esc autopilot panel |
| right mouse drag, wheel | orbit the camera, zoom |
Any manual flight key cancels the autopilot.

## Ship model
* A ship is a set of **modules**; a module is a set of polygon faces. All modules share ONE vertex pool (`ShipDesign.vertices`): two modules that use the
  same vertex id are linked (Flyout-style), moving it moves both. Start shapes: box, wedge, pyramid, tetra, cylinder, cone, sphere, dome (round ones have adjustable sides).
* **Module types** (`scripts/data/module_catalog.gd`, per-m3 stats in `module_presets.gd`):
  * **Hull / Armor**: the shell and the space that holds the corridors.
  * **Commander** (exactly one is mandatory; if the last dies the ship dies and respawns), **Turret** (base + barrels), **Radar**: **rooms** - people walk in, they need a corridor.
  * **Thruster**: never a room, never needs a corridor, drawn only as an outline on the plan.
  * **Antenna**: ONE module type with **presets**. *Whip* and *Dish* are external (no corridor, fixed signal); *Relay* and *Long range* are **rooms** (need a corridor) with an
    **adjustable signal strength** - a weaker signal is harder for enemy radar to see and costs less electricity.
  * Presets decide the module's `kind` (`"room"` / `"external"`); you can save your own (see `docs/MODULE_CREATION.md`).
* **Internal systems** (no shell, never damaged), under `Ship/Systems`: **Electricity** (powers everything, brown-out scales it down), **Gyroscope** (turning, stabilising,
  cancels torque of off-centre thrusters), **RCS** (always 5 % of the best-direction thrust, from the centre of mass), **Communications** (antennas).
* Thrusters have any position, direction and power; force is applied AT the thruster, so they make torque.

## Ship plan (emergency map)
Generated from the modules (`scripts/data/ship_plan.gd`), drawn by `scripts/ui/plan_canvas.gd`. Open it with **Plan** in the editor (you can edit the corridors) or **P** in game (live status).
* **Rooms** are drawn with their real footprint and a three-letter code in the box (ENG, GUN, CMD, RDR, ANT) with a small icon.
* **Two rooms that touch** need no corridor: just a **door** in the shared wall. **Stairs**: a room on another deck gets one small disc marker with an
  up / down arrow and the number of the deck it leads to, **inside the room** (and straight below / above it on the other deck) - no long corridor to get down.
* **Corridors** can start anywhere in the hull, bend, and split other corridors (a junction); bulkhead **doors** can be placed on them. Corridors never leave the ship.
  While drawing, the thing a click would link to lights up (a room, a junction or a point on a corridor) and the line snaps to it; a click **anywhere inside a room** links to that room.
* The deck view shows the **deck below as a faint ghost** (layer "Deck below"), so you can see what to line up with.
* **Views**: Deck (one deck), Side, Front, **Sheet** (all decks on one page, like a blueprint), **Exploded 3D** (isometric, hover a module and the others push away
  and it grows), white paper / dark paper. **Layers** (Hull, Rooms and corridors; more can be registered, e.g. electricity) can be switched on and off.
* Labels and markers avoid overlapping each other. The legend lists: stairs, corridor, module (the code in the box says which).
* Plan tabs: MAP, STATUS, LOGS (what the commander was told and when).

## Damage and deformation (`scripts/damage/`)
Everything that hurts a ship is a **DamageHit** (what happened) resolved by a **DamageType** (how much HP / how deep a dent) and applied by
`Ship.apply_hit()`. Types now: `KineticDamage` (bullets: `damage*100/(100+hardness)`, no dent) and `RammingDamage` (ship collisions).
* Materials (`scripts/data/material_catalog.gd`): aluminium, bronze, steel, titanium; each module has one (builder -> Selection tab; default by type).
  Harder = takes less damage, dents at a higher speed, but is heavier (`density_mult`).
* Ramming: relative velocity at the contact point (previous physics frame) -> closing speed along the contact normal.
  Threshold = `yield_speed(victim) * sqrt(hardness(victim)/hardness(attacker))`. Below it: **no dent, no damage**, the physics engine just bounces the ships.
  Above it: HP loss from the energy above the threshold and a **vertex-adding dent** (`scripts/damage/hull_deformer.gd`):
  1. **refine** - long edges near the impact get a new middle vertex (the neighbour faces, also of other modules, get it too: no cracks), then
     big faces are cut into smaller ones around a new centre vertex (a quad hit in its middle becomes 4 quads), until faces near the hit are
     about `radius/3` long;
  2. **push** - vertices within the radius move inward with smooth falloff (never past 45 % of the way to the module centre);
  3. **recalculate** - the module's volume / centre / inertia sums are corrected incrementally ("new faces - old faces"), then mass, inertia,
     thruster/turret positions, collision hull and the affected render chunks are refreshed.
  Only (module, point, direction, depth, radius) are sent (`Ship.apply_dent` RPC); every peer runs the same deterministic code, so meshes match.
* **Ramming between players**: each player's PC only simulates their own ship, and sees the other as a copy that is stopped by their copy of them.
  So when A's ship hits B's copy, A also sends B's PC an RPC (`Ship.receive_ram`) with the contact; B applies the same damage/dent rules and the push.
  Tested over real ENet with two processes up to 600 m/s (`tests/net_ram_runner.gd`: `net_test.tscn -- host Dart ram` + `-- client Dart ram`).
* Tune numbers in `Data` (`RAM_ENERGY_TO_DAMAGE`, `DENT_PER_MS`, `DENT_MAX_DEPTH`, `DENT_BASE_RADIUS`) and in the material table.
* **Add a damage type**: copy `kinetic_damage.gd`, change `id` and `resolve()`, register it in `DamageRegistry._register_defaults()`, then create
  `DamageHit`s with that `type_id`. Nothing else changes. Listen to `BusEvent.ship_hit` / `ship_deformed` for effects or HUD.
Mass/centre of mass/inertia ARE recomputed after a dent (cached per-module sums, O(modules)). Module max HP stays as designed.

## Scale (up to about 2 million vertices)
* Faces are stored flat (`FaceSet`), mass data is cached per module, the 2M-vertex file is compressed binary (`.ship`, ~13 MB; small ships stay readable `.json`).
* The hull is drawn by `HullRenderer`: chunks of ~8000 faces, positions+indices only, flat shading in `shaders/hull.gdshader`. A dent rebuilds only the touched chunks.
* Collision per module = convex hull of <= 200 chosen vertices. Ships above 30k vertices build their render/face data in worker threads (the ship is flyable meanwhile).
* Ships travel as hash-verified blobs in chunks (`Net.blobs`); the host sends them before the world loads.
* Builder: above 30k vertices it switches to large-ship mode (no vertex dots/wireframe/vertex-edge-face picking); undo stores compressed snapshots with a 256 MB cap.
* Measured here (headless, 2 CPU cores, `tests/test_scale.tscn -- 580 fine`, 2.03M vertices): Ship `_ready` 0.28 s on the main thread, hull data ready after ~14 s in the background, one dent ~15-40 ms. GPU frame rate for 4M triangles could NOT be measured in the sandbox.

## Autopilot internals
`scripts/ship/autopilot.gd` + `thrust_allocator.gd`: speed profile -> velocity loop -> wanted force -> gyroscope aims the BEST thrust axis (or the turret-facing
axis) -> allocator -> throttles -> RCS tops up -> gyro cancels thruster torque. Prototype: `tools/ship_sim.py`.

## Ship editor ("Creation")
Blender-style: mode dropdown (Object / Vertex / Edge / Face) with contextual tools, **adjustable operators** (change the last operation's numbers afterwards, F9),
shading modes, top bar (name, New / Save / Load, Undo / Redo), right tabs **Create** (Ship | Module) / **Properties** / **Ship**, bottom messages.
| Key | Action |
|---|---|
| 1 / 2 / 3 / 4 | Object / Vertex / Edge / Face (Tab toggles Object <-> last edit mode) |
| click, Shift+click | select / add. Click-drag a selected thing = quick move. A / Alt+A = all / none |
| G / R / S | move / rotate / scale (X, Y, Z lock an axis, type a number, Enter = ok, Esc = cancel) |
| E | extrude face · W add vertex on edge · J connect two vertices · bevel, inset, subdivide, triangulate in the tool panel |
| L / U | link / unlink vertices · M mirror · Shift+D duplicate · X / Del delete |
| F | frame selection · Ctrl+Z / Ctrl+Y undo / redo · Ctrl+S save |
Camera: right mouse orbit, middle mouse or Shift+right pan, wheel zoom. Forward is **-Z**. Ships save to `user://ships/*.json` (readable) or `.ship` (compressed, for huge ships).
Where things are: `ship_builder.gd` state + actions · `builder_ui.gd` buttons · `builder_view.gd` drawing · `transform_tool.gd` G/R/S · `data/mesh_ops.gd` topology · `data/primitives.gd` shapes.
New button = add it in `tools/gen_builder.py`, connect it to a `_on_xxx` in builder_ui.gd, call a ShipBuilder function.

## Autoloads
`Data` (every tunable constant + the local player's choices) · `BusEvent` (signal hub) · `Game` (scene paths, `go_to()`) · `Net` (lobby rules - the host is the referee,
roster, ENet / Steam host and join, `Net.players[id]`).

## Scene tree (everything fixed lives in .tscn files)
```
scenes/main_menu.tscn   scenes/lobby_browser.tscn   scenes/lobby.tscn (room)   scenes/ship_builder.tscn   scenes/hud.tscn   scenes/tactical_map.tscn   scenes/plan_view.tscn
scenes/ship.tscn   Ship(RigidBody3D) HullMesh, Flames(MultiMesh), Systems/{Electricity,Gyroscope,RCS,Communications}, Autopilot, Weapons,
                   TransformSync + StateSync (MultiplayerSynchronizer), Explosion, Nameplate
scenes/game_world.tscn  GameWorld, WorldEnvironment, Sun, Landmarks, SpawnPoints(8 Marker3D), Ships, ShipSpawner(MultiplayerSpawner),
                   ProjectilePool (bullets created in code at start), CameraRig/Pivot/Camera3D, TargetMarker, HUD
```
Most scenes are generated by `tools/gen_scenes.py`, `gen_builder.py`, `gen_lobby.py` (optional - the .tscn files are normal, editable scenes; `plan_view.tscn` is hand-written).

## Networking model
Each peer owns and simulates its own ship; pose is replicated (TransformSync), module HP / throttles / alive (StateSync). Shots are RPCs; each peer simulates
the bullets and only the owner of the hit ship applies damage. The host spawns ships and handles respawn. Ships travel as hash-verified blobs in chunks (`Net.blobs`).

## Layout
`scripts/data` (ModuleCatalog, ModulePresets, ShipDesign, ShipPlan, Primitives, MeshOps) · `scripts/ship` (ship, allocator, autopilot, turrets, weapons, detection, reports, systems) ·
`scripts/builder` · `scripts/damage` · `scripts/net` · `scripts/ui` · `scripts/world` · `scripts/autoload` · `addons/vertex_ships` (editor plugin) · `ships/*.json` premade ·
`tests/` · `tools/`. New `class_name` scripts need a class-cache refresh: `godot --headless --path . --editor --quit-after 20`.

## Tests
Headless, from the project folder (`GODOT` = your binary):
`$GODOT --headless --path . res://tests/test_<name>.tscn` for **structure, combat, builder, damage, graph, scale, plan, scenes, steam, fuzz, fuzz_live**;
`$GODOT --headless --fixed-fps 60 --path . -s res://tests/test_drive.gd -- "Twin Hull"` (DRIVE and facing lock);
`tests/run_net_test.sh`, `run_lobby_test.sh`, `run_board_test.sh`. **fuzz** = random modelling operators, save/load, random damage and comms, every plan view;
**fuzz_live** = real ships flying random orders while damaged. `bash tools/check_warnings.sh` prints nothing when there is no GDScript warning (the project treats them as errors).
Screenshots (needs a virtual display): `tools/shots.sh` with `tests/shot_*.tscn`.

## Releasing
**docs/STEAM_AND_ITCH.md**: itch.io export + butler, Steam add-ons, App ID, SteamPipe. Before release change `Data.BOARD_TOPIC`, the export path in `export_presets.cfg`, and `config/version`.

## Known simplifications
Thrusters respond instantly; RigidBody3D inertia is diagonal only; client-authoritative ships (fine for co-op / friends, not cheat-proof); remote ships use simple
smoothing, no lag compensation. Module links are decided from the design and not recomputed after dents. Doors are drawn on the plan but have no gameplay effect yet.
A ship split uses each peer's copy of the parent, so a ship still building its mesh in the background should not be split in its first seconds. Bevel is clean where up to
3 faces meet at the edge ends. Turret barrels cannot be dented. The seat-picker preview of ships above 30,000 vertices shows one box per module.
