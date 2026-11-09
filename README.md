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
* **GOTO**: fly to a point and stop there (no speed cap: the fastest speed the ship can still brake from, flip with the gyroscope, retro-burn, RCS finishes). Click a **ship** instead and the ship follows it, holding station 40 m away and matching its velocity.
* **DRIVE**: an **arrow**, not a point: the ship pushes along that direction with a chosen **thrust** and never stops (made for ramming). Click an enemy and the arrow follows it, aimed at the **intercept point** (where it will be when you arrive). Only **brake (X)** or cancel ends it.
* **Turret facing lock**: while moving, the ship turns so the most turrets bear on the locked enemy (or the destination) instead of pointing its best thrust axis along the push.
* **Tactical map (M)**: click in space to give orders (no typing coordinates). **2D** is a top-down view with a height ruler; **3D** tilts the camera so you SEE the height (every object stands on a line down to your own height; right-drag turns the view, middle-drag pans, Ctrl+wheel sets the height of the next order). It shows everything known: radar contacts, shots in flight (by eye up to `Data.PROJECTILE_EYE_RANGE`, with a working radar up to `PROJECTILE_RADAR_RANGE`) and the landmarks, each with an arrow in the direction it moves (`scripts/ui/map_objects.gd`).
* **Engine room**: a ship that has one only fires its thrusters while one works (alive, and reachable by corridor unless communications are up). Without comms the pilot's orders are walked to the engine room first. Ships with no engine room behave as before.

Damage and information: the damage is simulated at once, but what the **commander knows** depends on communications. With comms online, reports are instant.
Without, someone has to walk the report along the corridors (seconds shown on the plan); damage the commander has not heard about is shown as a dashed
**"?" sphere** ("something happened around here"), and rooms with no open corridor to the bridge are marked **NO LINK** - they cannot be ordered and their
reports wait until comms or a corridor is back. Thrusters and external antennas work without a corridor.

## Paint and readable ships
**Paint** (builder, Properties tab, or **K** for paint mode): two colours, a pattern (solid, stripes, checker, hazard, two-tone) and a pattern size per module; saved with the ship, shown in the game by `shaders/hull.gdshader` (the builder shows the first colour only). Whatever the paint, thrusters (flame end, orange), barrels (muzzle, red), turret bases (yellow cap) and radars (green) get a **glowing direction mark**, so other players can read where the guns and thrusters point. Test: `test_paint`.

## Crew, penetration, aiming at parts
**Crew** (`ShipCrew`, panel with **Y**): one person per 18 m3 of room volume. They walk the corridors of the ship plan, repair damaged modules they know about (health comes back while somebody works there) and patrol the rooms otherwise. A hit hurts the people in that room, a destroyed room kills them, and **all crew dead = the ship is lost** (counts as a death). Orders: pick a module in the panel and press Repair (go and fix it) or Look (go and see). Without communications an order needs the walking time to reach the person, and a damage **report** only exists once somebody has actually been near the damage and walked it to the bridge (so sometimes nobody passes by: send somebody to look). **Penetration**: a barrel's `pierce` stat (metres of modules; Railgun, Armor-piercing cannon) lets bullets go through modules and damage each one. **Aiming at a part**: J cycles the locked ship's modules, but only while it is close enough to be SEEN (`Data.VIEW_RANGE`); a radar-only contact is aimed at the average point of its heat (thermal radar: burning thrusters, firing turrets) or electricity (electronic radar). Tests: `test_crew`, `test_bullets`.

## Bullet types and aiming
A projectile barrel's preset (**Preset creator**, or the preset list in the builder) now has: bullets per shot (the shot damage is shared between the pellets), bullet size, lifetime (range = speed x lifetime), spread, burst length and gap, explosion radius (flak: hurts the modules around the impact), muzzle speed variation, recoil and tracer colour. Built-in: Cannon, Autocannon (bursts), Scatter gun, Flak cannon, Railgun. **Aiming**: at a gun station the turret follows YOUR mouse; a locked target (R) only gets a **lead circle** (War Thunder style, red when out of the bullets' reach): put the crosshair in the circle. Automatic gunnery (commander mode) works out the lead for every barrel with its own bullet speed, from the radar's position, velocity AND acceleration of the target. Test: `tests/test_bullets.tscn`.

## Barrels: direction, muzzle tube, aiming circles
A barrel has its own **direction** (Properties tab, like a thruster) that is where it fires when the turret is at rest (older ships keep "base to barrel"). In front of the muzzle a **tube the size of the barrel's bullet** (`Data.BARREL_TUBE_LENGTH`, red in the builder) must stay free: a ship with a module in it cannot be saved. The builder draws two circles through the barrel (horizontal = yaw around the mount axis, vertical = pitch); the bright part is the allowed arc, a full bright circle means 360 degrees. Turning the turret turns the vertical circle around the horizontal one. Test: `tests/test_barrel_dir.tscn`.

## Controls and settings
**Flying**: the flight keys, the mouse schemes and the G / EVE orders work in commander mode (full ship control) and at a pilot seat, not at a gun station (there the mouse aims the turret) and not while walking. **Gun-station camera**: the eye is placed on the side of the turret with the clearest view, so an upside-down or buried turret never puts the camera inside the hull (`tests/test_station_cam.tscn`). **3D tactical map**: the plane a click lands on (the chosen order height) is drawn as a cyan grid, the cursor marker and read-out show x, z and height.
**Settings** (main menu, or the Settings button in game) are saved to `user://settings.cfg` (`scripts/autoload/prefs.gd`) and apply at once:
* **Movement scheme** (`scripts/ship/flight_controls.gd`, `scripts/world/order_controls.gd`). All schemes also accept the keyboard and gamepad 0 (left stick strafe/forward, right stick turn, triggers up/down, bumpers roll):
  1. **Classic keyboard**: W/S, A/D, Space/C thrust, arrows pitch/yaw, Q/E roll.
  2. **Mouse flight (Star Wars Outlaws style)**: the cursor's distance from the screen centre steers pitch/yaw (dead zone, strength, invert in settings); W/S thrust, A/D strafe, Q/E roll; hold the right mouse button to look around without turning.
  3. **Mouse flight + throttle lever**: the same, but W/S move a lever that stays put (X = zero; an autopilot order releases it).
  4. **Point and click circle (Nebulous style)**: press **G**, a ring follows the cursor over the plane at the ship's height (x, z); hold **Alt** and move the mouse up/down to change the height (y) instead; click to fly there, Esc / right click cancels. Firing is blocked while the circle is open.
  5. **Click orders (EVE Online style)**: double click in space = align and fly that way (double click a contact = approach it); **Z** approach, **O** orbit (new autopilot mode `ORBIT`), **K** keep at range the locked enemy (R locks, or the closest one); **[ ]** change the distance.
* Other settings: mouse strength, invert, dead zone, lever speed, orbit distance, **every key can be rebound**; camera FOV / start distance / orbit speed / invert; fullscreen, V-sync, 3D render scale, FPS cap, interface scale, FPS counter; master volume; pilot name.

| Key (default) | Action |
|---|---|
| W / S, A / D, Space / C | thrust forward-back, strafe, up-down (ship-local; the thruster allocator + RCS solve it) |
| arrows, Q / E | pitch / yaw, roll |
| X | brake · **T** hold attitude (flight assist) · **R** lock the next enemy |
| left mouse | fire at the cursor (hold = weapons free in commander mode; crew: fires the station's turret) |
| **H** | weapons free on / off · **M** tactical map · **P** exploded 3D plan (live status) |
| **V** | commander / crew mode · **F** next station · Esc autopilot panel |
| **Tab** | scoreboard (hold) · the **Respawn** button counts as a death |
| right mouse drag, wheel | orbit the camera, zoom |
Any manual flight key cancels the autopilot.

## Languages
English, Français, Deutsch, Español, Русский, 简体中文, 日本語. Pick one in **Settings > Player > Language** (default: the operating system's language). The English texts are the keys: scenes and `tr("...")` calls hold English, `translations/<code>.json` maps them to the other languages, anything missing shows English.
* Add or change a text: write it as English in a scene or inside `tr("...")`, run `python3 tools/i18n_extract.py` (rebuilds `translations/keys.json`), add the six translations to a `translations/src/t*.py` file and run `python3 translations/src/build.py` (writes the json files and reports missing texts / wrong `%` placeholders). `tests/test_i18n.tscn` checks every language is complete.
* Chinese and Japanese need a system font with those characters (Windows, macOS and most Linux have one; Godot falls back to it automatically).

## Scoreboard, respawn, joining a running game
* `Net` keeps per-player **kills, deaths, damage dealt, damage taken** (host-authoritative, synced every 0.5 s; the victim's owner reports hits, the host validates). A death is counted when your ship is destroyed or you press **Respawn**; the player who did the **most damage to that ship since it spawned** gets the kill (none if nobody hit it). Crew damage counts for the pilot. Kill feed on the HUD, table on **Tab**.
* **Join in progress**: the host ticks "Allow players to join while the game runs" (lobby, or scoreboard in game). Players can then join a running game (the browser shows "(in progress)"), choose a ship in the lobby and press **JOIN THE GAME**. Until a peer has loaded the world nothing is replicated to it (`Net.world_peers`).

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
Generated from the modules (`scripts/data/ship_plan.gd`), drawn by `scripts/ui/plan_canvas.gd`. Open it with **Plan** in the editor or **P** in game (live status). Only the **exploded 3D view** is offered now (the flat deck / side / front / sheet drawings and the corridor drawing tools were removed from the UI; corridors are generated).
* **Rooms** are boxes with a three-letter code (ENG, GUN, CMD, RDR, ANT); hover a module and the others push away and it grows. Drag to turn, wheel to zoom.
* **Stairs**, **doors** and corridors are drawn between the decks; **Layers** switch hull / rooms and corridors.
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

## Module presets (weapons, thrusters, armor ...)
Main menu -> **Module presets** (`scenes/preset_creator.tscn`, `scripts/ui/preset_creator.gd`): pick a module type, copy a built-in preset with **New preset from this one**,
type every number (a weapon: damage per shot, time between shots = **shots per second**, muzzle speed, spread, electricity, heat; a thruster: thrust per m3 ...) and, for weapons,
the **damage type** (`kinetic`, `energy`, `piercing`, `explosive`, see `scripts/damage/`: armor protects fully against kinetic, half against energy, a little against piercing, and explosive shells also dent the hull).
Presets are saved in `user://presets.json` and show in the builder's preset list. Armor and hull presets set toughness (HP per m3 x) and weight (density x). New types of damage: see `scripts/damage/damage_type.gd`.
Missiles will use the same screen when they exist.

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
**Create -> Module**: pick the type and preset, then the shape: round shapes take a **base radius**, a **height** and the **axis** they point along (up, forward = the way the ship points, side); boxes take width X, height Y, length Z.
**Add at the view centre**, or **Add on the selected part (linked)** which places the new shape on the selected face, pointing away from it, and welds it to that face (selecting several parts shows a warning: it will try to link them all as well as it can).
**Decks** of the ship plan: every height level gets its own deck (up to 48); modules that overlap in footprint also stack.
Camera: right mouse orbit, middle mouse or Shift+right pan, wheel zoom. Forward is **-Z**. Ships save to `user://ships/*.json` (readable) or `.ship` (compressed, for huge ships).
Where things are: `ship_builder.gd` state + actions · `builder_ui.gd` buttons · `builder_view.gd` drawing · `transform_tool.gd` G/R/S · `data/mesh_ops.gd` topology · `data/primitives.gd` shapes.
New button = add it in `tools/gen_builder.py`, connect it to a `_on_xxx` in builder_ui.gd, call a ShipBuilder function.

## Editor plugin (`addons/vertex_ships`)
A **Ships** tab in the Godot editor. New ship, Duplicate, Delete, Info and Validate all run in a background headless Godot (`tools/ship_cli.tscn`), so **no scene is launched**;
they use the real game code. Shaping vertices needs the real game, so **Open in builder** runs the builder scene and switches the editor to its embedded game view (Godot 4.4+, setting
`run/window_placement/game_embed_mode`) so it opens inside the editor window. Note: the vertex builder itself is not a `@tool` script, so it cannot be drawn in the editor viewport itself.

## Autoloads
`Data` (every tunable constant + the local player's choices) · `Prefs` (saved settings) · `BusEvent` (signal hub) · `Game` (scene paths, `go_to()`) · `Net` (lobby rules - the host is the referee,
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
`scripts/builder` · `scripts/damage` · `scripts/net` · `scripts/ui` · `scripts/world` · `scripts/autoload` · `addons/vertex_ships` (editor plugin: manage ships in the editor, see below) · `ships/*.json` premade ·
`tests/` · `tools/`. New `class_name` scripts need a class-cache refresh: `godot --headless --path . --editor --quit-after 20`.

## Tests
Headless, from the project folder (`GODOT` = your binary):
`$GODOT --headless --path . res://tests/test_<name>.tscn` for **structure, combat, builder, damage, graph, scale, plan, scenes, steam, fuzz, fuzz_live**;
`$GODOT --headless --fixed-fps 60 --path . -s res://tests/test_drive.gd -- "Twin Hull"` (DRIVE and facing lock);
`tests/run_net_test.sh`, `run_lobby_test.sh`, `run_board_test.sh`, `run_cli_test.sh` (the ship command line of the editor plugin); also **presets, map, scoreboard, controls**; `-s res://tests/test_orbit.gd` (orbit autopilot); `tests/run_late_test.sh` (join in progress); `-s res://tests/test_heading.gd` (arrow DRIVE, intercept, follow). **fuzz** = random modelling operators, save/load, random damage and comms, every plan view;
**fuzz_live** = real ships flying random orders while damaged. `bash tools/check_warnings.sh` prints nothing when there is no GDScript warning (the project treats them as errors).
Screenshots (needs a virtual display): `tools/shots.sh` with `tests/shot_*.tscn`.

## Releasing
**docs/STEAM_AND_ITCH.md**: itch.io export + butler, Steam add-ons, App ID, SteamPipe. Before release change `Data.BOARD_TOPIC`, the export path in `export_presets.cfg`, and `config/version`.

## Known simplifications
Thrusters respond instantly; RigidBody3D inertia is diagonal only; client-authoritative ships (fine for co-op / friends, not cheat-proof); remote ships use simple
smoothing, no lag compensation. Module links are decided from the design and not recomputed after dents. Doors are drawn on the plan but have no gameplay effect yet.
A ship split uses each peer's copy of the parent, so a ship still building its mesh in the background should not be split in its first seconds. Bevel is clean where up to
3 faces meet at the edge ends. Turret barrels cannot be dented. The seat-picker preview of ships above 30,000 vertices shows one box per module.

## Fire, air, electricity and doors
Damage inside the ship is not only lost health:
- **Fire** starts in modules that were hit hard (engine rooms burn best, armor hardly), grows while there is air, burns the module's health and the people in it, eats the air and jumps through open doors. It dies when the fuel is gone or the air is gone. Crew standing in the room put it out.
- **Air** leaks from hit modules (a *breach*; repairs close it) and flows through open doors. Under about a third of the air, people suffocate. A vented room puts fires out - and kills the crew inside.
- **Electrical faults** can follow a hit: the module does nothing until the fault clears (25 s, much faster with somebody in the room).
- **Doors**: every wall doorway and every corridor door you placed in the builder. In the live plan, click a door: open -> closed -> locked. Closed doors stop fire and air, crew can still walk through them. **Locked** doors stop the crew too. Doors next to a hit, a fire or thin air close **by themselves** and open again when it is safe. Changing doors needs working communications.
- **Roles**: a turret base, radar or engine room with somebody standing in it works 15% better (reload, range, thrust). Nobody is assigned; it is where the crew happens to be (or where you send them).

## License
MIT, see `LICENSE`.

## Ramming, breaches and boarding
- A ram hard enough to dent a hull **lodges** the two ships in each other: a damped grip keeps them together (no bounce) and weakens for about 14 s until it tears - thrusting away tears it sooner. It also opens a **hole** in the hit modules: air leaks out until somebody stands in the room and seals it.
- **Airlock** (new room type): while lodged, your crew can walk out of an airlock within 10 m of the contact and board through a hole (or an airlock) of the enemy near the same spot.
- **Pod bay** (new room type): launches boarding pods (2 people each, a pod per ~10 m3) at the ship you have locked; a pod punches a hole where it lands.
- Both are used from the crew panel (Y): BOARD row, choose how many people go.
- **Boarders** (red dots in the plan) wreck every room nobody defends, may start fires and shorts, and go for the bridge. Defenders in the room fight them. Boarders holding the bridge for 12 s, or killing every defender, take the ship (a kill for them). **Locked doors** stop boarders too - lock them in.

## Game mode: free for all or team deathmatch
The host picks the **game mode** in the lobby (under the team picker): *Free for all* (everyone chooses their own team, or none) or *Team deathmatch* with **2 to 8 teams**. In team deathmatch players are put in the smallest team when they join and can switch. Kills count for the killer's team (killing a friend scores nothing); the scoreboard (Tab) shows team totals on top. A **kill limit** (0 = none) ends the round when a team (or a pilot in free for all) reaches it: the winner is announced and the scores restart.

## Hints and tutorial
- **Tutorial (solo)** on the main menu: a game for one against a target drone. Nine steps: fly, find the drone, lock it, fire, aim at a module, destroy it, ram a second drone (lodging), open the crew panel and the plan. Nothing is advertised on the network.
- **Hint bar** (top centre): emergencies first (boarders, fire, thin air, electrical faults, stuck in an enemy; each comes back after a minute if it is still true), then lessons you have not followed yet (fly, lock, fire, aim at a module, map, crew panel, plan). Each lesson disappears for good once you do it. Switch them off in Settings > Video > Help.

## Dedicated server (optional) and the duel simulator
- `godot --headless --path . -- --server "--name=My server" --password=secret` runs a server with no player of its own; see `docs/SERVER.md` (also: free ways to keep one running). Normal hosting in the menus is unchanged.
- `godot --headless --path . res://tests/duel_sim.tscn -- seconds=40 ranges=150,400,800 types=cannon,railgun` makes identical ships with different bullet types duel and prints win tables: use it when tuning `ModulePresets`.

### Bullet balance (tests/duel_sim.gd, 8 Nov 2026)
Rough damage per second per m3 of barrel now: cannon 450, autocannon 450, railgun 600 (long range, pierces 3), armor-piercing 330 (pierces 2, ignores armor), scatter gun 400 per pellet-volley (best under ~150 m, useless beyond 300 m), flak 290 + one extra helping of splash damage. In 25 s duels at 300 m the types landed 3-9% of the enemy ship's health; the short-range scatter gun wins at 100 m. Re-run the simulator after changing any preset. Performance: hits used to recompute mass and function every time (2 ms each), a blast dented every module around it; both fixed (0.03 ms per hit).

## Paint, details and Auto paint

Paint tab of the builder (key K is the colour brush, **O** the detail brush):

- **Auto paint** (one button): livery colours, plate lines + rivets, window decks, navigation and running lights,
  ship name and hull number, stripes, roundels, docking marks, vents, hatches, tanks, antennas and weathering
  (scorch marks, rust and dirt streaks, scratches). Choose a style (military grey, navy, industrial, stealth, white,
  desert, raider), the amount of detail and the wear. Same seed = same result; it is undoable. Everything it makes is
  flagged *auto*: running it again replaces only its own work, never the details you placed by hand.
- **Finish**: metallic, roughness, gloss coat, wear and dirt, plate lines, rivets, plate size (all in `hull.gdshader`).
- **Details** (a separate layer, independent of modules): 20 kinds (window, porthole, hatch, light, plate, vent, grille,
  stripe, chevron, star, roundel, warning sign, scorch, streak, scratches, docking mark, box, tank, antenna, text).
  Click the hull to place one, click a detail to select it, Shift+click moves it, Delete removes it. Size, rotation,
  two colours, lit / blink / strength, text, mirror (x = 0). Details may sit across modules; they only remember the
  module they were put on so they vanish (and darken) with it.
- **Decals stay on the ship**: every flat detail is shrunk until its whole rectangle lies on the surface under it
  (`DetailFit`), so a name can never hang off the hull. "Fit all to surface" repairs older ships.
- Details are saved in the ship file and sent to other players like everything else (`ShipDesign.details`,
  `ShipDesign.finish`); `DetailRenderer` draws them in a few meshes with `shaders/detail.gdshader`.

## The Dreadnought (2.2 km)

`ships/Dreadnought.ship` is a capital ship 2235 m long (120 modules: armoured spine, bow, stern engine block, command
tower, four main engines, manoeuvring thrusters on every side, 6 twin heavy cannons, 8 twin and 12 single secondary guns,
hangars with airlocks and pod bays) with about 11 000 auto-made details. It is generated by
`godot --headless --path . res://tools/gen_dreadnought.tscn` (add `SAVE=1` to write the file), then
`tests/test_dreadnought.tscn` checks it. Screenshot any ship with `tests/shot_details.tscn` (`SHOT_SHIP`, `SHOT_OUT`).

The Dreadnought has **6 command posts** (commander modules) spread along the spine, so it can lose its bridge and keep fighting.

## Fonts and more decals

`assets/fonts/` holds 14 futuristic fonts (Orbitron, Audiowide, Michroma, Oxanium, Rajdhani, Share Tech Mono, Bruno Ace,
Electrolize, Aldrich, Black Ops One, Saira Stencil One, Stardos Stencil, Zen Dots, Jura), all SIL Open Font License, with
the licence texts in `assets/fonts/licenses/`. `FontCatalog` lists them (append-only so saved ships keep their font);
every TEXT detail has its own font (builder: Detail font). New decals: hazard stripes, checker band, arrow, barcode,
circuit lines, diamond, cross, shield crest.

## Maps

`MapCatalog` defines 8 arenas (classic, Twin Suns, Crimson Nebula, Gas Giant Orbit, Young Star Cluster, Asteroid
Graveyard, Deep Void, Frozen Rim); `WorldBuilder.build` makes the sky (`shaders/space_sky.gdshader`: nebulae, galaxy
band, planets, rings), one directional light per star, tumbling decorative rocks and drifting dust. Arenas are much
larger than before (spawn ring up to 2800 m, camera far plane 30 km) so capital ships fit. The host picks the map in
the lobby game options (synced as `Net.map_id`); a dedicated server takes `--map=<id>`. Rocks are decoration only
(no collision) and planets/stars live in the sky shader (no parallax). Test: `tests/test_maps.tscn`, `tests/test_map_game.tscn`;
screenshot: `tests/shot_map.tscn`.

## Missing-ship fix (9 Nov 2026)

A client could end up in the world with no ship (camera in the void). Cause: a client that finished loading before the host's
world scene existed reported "ready" to nobody, so no ship was ever spawned for it. The host now remembers every
`Net.ready_msec` and spawns waiting peers when its world is built, and a client with no ship 4 / 9 / 16 s after loading
asks the host (`Net.report_ship_missing`) to spawn it again (also covers a lost spawn packet).

## Collision physics (bounce, friction, angle)

Hull-hull hits are now resolved like real rigid bodies (`Ship._integrate_forces`, `_restitution`, `_bounce`):

- **Restitution per material** (`restitution` in `MaterialCatalog`: aluminium 0.30, bronze 0.22, steel 0.45, titanium 0.55; the two hulls' values are averaged). Only the part of the speed *along the contact normal* rebounds, so a head-on hit bounces back and a glancing one barely does - the angle matters automatically.
- **Speed**: below a material pair's dent speed the hit is elastic and rebounds by `e * closing speed`; above it the hull dents and the ships lodge in each other (no rebound), as before.
- **Effective mass**: the rebound impulse is applied at the centre of the whole contact patch and uses both masses and both moments of inertia, so an off-centre hit spins the ships and a face-on-face hit goes straight back. Momentum is conserved (each owner applies its own half; the halves sum to exactly the rebound).
- **Friction** (`Data.HULL_FRICTION` 0.25): a glancing blow scrapes along the hull and keeps its sideways speed instead of sticking.
- Multiplayer: the rammed player's PC receives the restitution in `receive_ram` and adds it to its own push.

Tune in `Data` (`HULL_FRICTION`, `BOUNCE_MAX_SPEED`) and `MaterialCatalog`. Test: `tests/test_bounce.tscn`.

## Collisions: bullets, hulls, and bullets against bullets

- **Bullet vs hull** (`Projectile._hit_module`): the impact angle (from the surface normal) matters. A flat hit does full damage; a slanted one does less (cos) and meets more armour (thickness / cos); a grazing one **ricochets** - it bounces off with 75 % of its sideways speed, does only a scratch (`Data.GLANCE_DAMAGE`) and flies on. Harder hulls turn bullets away earlier, fast and armour-piercing bullets later (`Data.RICOCHET_*`). Explosive shells burst on contact, energy bolts never ricochet (they spread over a slanted hull). Every hit also pushes the ship with the bullet's momentum (bullet mass = recoil / speed). The ricochet dice are reproducible from the position, so every player's copy of a bullet agrees.
- **Hull vs hull** (`Ship._integrate_forces`): besides bounce/friction (above), the *contact patch* sets how sharp the hit is. A corner or edge touching a face is a few points over a tiny area: its dent threshold falls by `sqrt(sharpness)` (up to x2 lower) and the dent goes deeper (`DamageHit.sharpness`, `Data.HULL_*`). A face on a face is blunt and just bounces.
- **Bullet vs bullet** (`ProjectilePool._physics_process`): swept test of nearby bullets of different ships. A heavy shell smashes a light bullet, comparable bullets bounce off each other and are dented, two energy bolts cancel each other, solid bullets and plasma pass through each other. Flak shells (explosive with a splash radius) have a **proximity fuse** and burst near enemy bullets (or at the end of their life), wrecking or deflecting everything inside their radius.
- Tests: `tests/test_bullets_phys.tscn`, `tests/test_bounce.tscn`.
