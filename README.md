> Code made with the help of AI

# Vertex Ships — Godot 4.4+ project

Multiplayer spaceship game with vertex-built modular ships. Open the folder in **Godot 4.4 or newer**
(project.godot is in this folder), press F5. Main scene: `scenes/main_menu.tscn`.
Validated headless with Godot 4.4.1: scenes load, autopilot, builder ops, ramming/dent test (`tests/test_damage.tscn`), two-process game test
(`tests/run_net_test.sh`) and a 3-process lobby test (`tests/run_lobby_test.sh`: discovery, wrong/right password, lock, crew, force launch, crew firing).

## Menus and lobbies
* **Creation** – ship builder. **Play** – lobby browser (no IP/port typing).
* **Host a lobby**: name, Public/Private, password if private. Hosting alone = single player.
* **Join**: the browser lists every open lobby in the pre-game state (lock icon = private; a password prompt appears). Two sources are merged:
  **LAN** (UDP broadcast, `scripts/net/lobby_directory.gd`) and **Internet** (`scripts/net/lobby_board.gd`, see below). The password is checked by
  the host (sent as a hash, never advertised).
* **Internet play without a server of yours**: the list is a free public ntfy-style "message board" (`Data.BOARD_URL`, default `https://ntfy.sh`,
  topic `Data.BOARD_TOPIC`) - hosts post one small JSON message (name, players, public IP + port, private flag), browsers read the last minutes.
  The game itself is direct peer-to-peer (ENet). On Create, `scripts/net/nat_helper.gd` asks the router to open the UDP port (UPnP) and looks up the
  public IP. If the router refuses UPnP the host must forward the UDP port (24565) by hand - nothing can avoid that without a relay server.
  **Change `Data.BOARD_TOPIC` to your own unique string** (anyone who knows the topic can read/write it); no account is needed.
  Players on the SAME router as the host cannot use the public address; the board entry also carries the host's LAN address and the browser switches to it automatically.
  The host's room shows the internet status (UPnP result, public address) under the timer, so you can see why a friend cannot join. The router mapping is leased and renewed, never deleted.
  Limits: ntfy.sh is a free third-party service (rate limits, can change); players behind strict NAT/CGNAT cannot host.
  NOT verifiable in the build sandbox: real ntfy.sh and real UPnP. Tested against a local fake ntfy (`tests/run_board_test.sh`).
* **Pre-game room** (`scenes/lobby.tscn`): pick a ship, **Lock in**. A locked ship can be joined as **crew** by other players while it
  has free seats. Seats = `crew` value of the ship's **Commander module** (builder -> Selection tab, 1-8, pilot included).
  Unlocking releases the crew. A **2:00 timer** runs (`Data.LOBBY_SECONDS`): the host can START when everyone is locked, or **FORCE LAUNCH**
  after the timer ends; players without a ship then get a random premade one.
* **In game**: the pilot flies; crew members watch from the same ship and **hold left click to fire its turrets** (aim with the mouse).
  If a pilot leaves, their crew get a random ship of their own.

## Ship model
* **External modules** (physical shells, have HP, can be shot): Hull, Armor, Thruster, Turret, **Commander (exactly one, mandatory;
  if destroyed the ship dies and respawns)**. A module is a set of polygon faces. Start shapes (`scripts/data/primitives.gd`):
  box, wedge, pyramid, tetra, **cylinder, cone, sphere, dome** (round ones have an adjustable number of sides).
* **Linking** (Flyout-style): all modules share ONE vertex pool (`ShipDesign.vertices`). Two modules that use the same vertex id are linked; moving
  it moves both. Drop a vertex on another module's vertex (auto-link) or select two (Shift) and press **L**. **U** unlinks.
* **Internal modules** (no shell, never damaged): **Electricity**, **Gyroscope**, **RCS** — nodes under `Ship/Systems`.
  * Electricity: powers thrusters/RCS/gyro/turrets; if demand > supply everything is scaled down (brown-out). Builder slider.
  * Gyroscope: turning + stabilisation + cancels torque from off-centre thrusters. Builder slider.
  * RCS: pushes from the centre of mass (no torque), always **5 % of the ship's best-direction thrust**
    (`ThrustAllocator.best_axis`; e.g. 2×5 N forward + 9 N backward → 10 N → RCS 0.5 N). Not editable, can never rival the main thrusters.
* Thrusters have arbitrary position, direction and power; force is applied AT the thruster (`apply_force(f, offset)`), so they make torque.

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

## Autopilot (HUD, bottom-right)
Type X Y Z → **GO**: accelerate (no speed cap), flip with the gyroscope, retro-burn, RCS finishes the stop. **Brake (X)** stops where it can.
Algorithm = `ship_sim.py` Python prototype, ported to `scripts/ship/autopilot.gd` + `thrust_allocator.gd`.

## Controls (flight)
W/S forward/back, A/D strafe, Space/C up/down (ship-local, solved by the thruster allocator + RCS), arrows pitch/yaw, Q/E roll,
X brake, T flight-assist on/off, LMB fire at cursor, RMB drag orbit camera, wheel zoom. Any manual key cancels the autopilot.

## Builder ("Creation") – Blender-style
Layout: top bar (name, New/Save/Load, Undo/Redo) · left = selection mode + tools · right tabs **Add / Selection / Ship** · bottom = messages.
| Key | Action |
|---|---|
| 1 / 2 / 3 / 4 | select **Object / Vertex / Edge / Face** (Tab toggles Object <-> last edit mode) |
| click, Shift+click | select / add to selection. Click-drag a selected thing = quick move |
| A / Alt+A | select all / none |
| G / R / S | move / rotate / scale selection (X, Y, Z lock an axis, click or Enter = ok, Esc = cancel) |
| E | extrude face · W add vertex on edge · J connect two vertices (new edge) |
| L / U | link / unlink vertices |
| M / Shift+D / X or Del | mirror / duplicate / delete |
| F | frame selection · Ctrl+Z / Ctrl+Y undo / redo · Ctrl+S save |
Camera: RMB orbit, MMB or Shift+RMB pan, wheel zoom. You can also type exact centre coordinates in the Selection tab.
Forward is **-Z**. Ships save to `user://ships/*.json` in a readable format (one vertex / face per line).

## *MODDER* -- 

## Autoloads (global helpers)
* `Data` – every tunable constant (`RCS_FRACTION`, turret damage, pool size...) + the local player's choices.
* `BusEvent` – signal hub (`ship_died`, `local_ship_changed`, `notify`, `builder_design_changed`...). Emit/connect from any script.
* `Game` – scene paths + `go_to()`. `Net` – lobby rules (host is the referee), roster, ENet host/join, `Net.players[id] = {name, ship, locked, crew_of, seats}`.

## Where to change things (builder)
`ship_builder.gd` state + every action (extrude, subdivide...) · `builder_ui.gd` buttons (each calls a builder action) ·
`builder_view.gd` drawing · `transform_tool.gd` G/R/S · `data/mesh_ops.gd` topology edits · `data/primitives.gd` shapes.
New button = add it in `tools/gen_builder.py`, connect to a `_on_xxx` in builder_ui.gd, call a ShipBuilder function.

## Scene tree (everything fixed lives in .tscn files)
```
scenes/main_menu.tscn   scenes/lobby_browser.tscn   scenes/lobby.tscn (room)   scenes/ship_builder.tscn   scenes/hud.tscn
scenes/ship.tscn   Ship(RigidBody3D) HullMesh, Flames(MultiMesh), Systems/{Electricity,Gyroscope,RCS}, Autopilot, Weapons,
                   TransformSync + StateSync (MultiplayerSynchronizer), Explosion, Nameplate
scenes/game_world.tscn  GameWorld, WorldEnvironment, Sun, Landmarks, SpawnPoints(8 Marker3D), Ships, ShipSpawner(MultiplayerSpawner),
                   ProjectilePool (creates its bullets in code at start), CameraRig/Pivot/Camera3D, TargetMarker, HUD
```

## Networking
Each peer owns and simulates its own ship; pose is replicated (TransformSync), module HP / throttles / alive (StateSync).
Shots are replicated as RPCs; each peer simulates the bullets and only the owner of the ship that is hit applies damage.
Host spawns ships and handles respawn. Forward UDP 24565 to host over the internet.

## Layout
`scripts/data` (ModuleCatalog, ShipDesign, Primitives, MeshOps) · `scripts/ship` (ship, allocator, autopilot, systems, weapons) · `scripts/builder`
`scripts/damage` · `scripts/net` · `scripts/ui` · `scripts/world` · `scripts/autoload` (Data, BusEvent, Game, Net) · `ships/*.json` premade · `tests/` headless tests ·
`tools/` Python generators (gen_scenes / gen_builder / gen_lobby) for the .tscn files and premade ships (optional; the .tscn files are normal editable scenes).

## Structure, splitting, turrets, seats, plugin
See **docs/ARCHITECTURE_V2.md** (commander connectivity, crush rule, ship splitting, seat picker, base+barrel turrets, exhaust zones, new editor tools, the Godot plugin and its steps).

## Known simplifications
Thrusters respond instantly; RigidBody3D inertia is diagonal only; client-authoritative ships (fine for co-op/friends, not cheat-proof);
remote ships use simple smoothing, no lag compensation. Module links are decided from the design and not recomputed after dents.
A ship split uses each peer's copy of the parent, so a ship still building its mesh in the background (millions of vertices) should not be split in its first seconds.
Bevel is clean where up to 3 faces meet at the edge ends. Turret barrels cannot be dented. The seat-picker preview of ships above 30,000 vertices shows one box per module.
