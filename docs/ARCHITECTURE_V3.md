# Presets, radar and detection, weapons, control modes

(Part 3. Part 2 is ARCHITECTURE_V2.md: structure, splitting, seats, plugin.)

## 1. Modules are made from PRESETS with stats PER m3

You no longer add a "base thruster" or "base turret". In the builder's **Add** tab you pick a type, then a **preset**
(`ModulePresets`, `scripts/data/module_presets.gd`), a shape and a size. The preset only gives numbers **per cubic
metre**; what the module really does comes from its shape (`ShipDesign.module_volume`):

| type | main stat (what you edit) | what the shape decides |
|---|---|---|
| thruster (chemical / ion / plasma) | thrust per m3 (N/m3) | thrust = per_m3 x volume; electricity and heat = per newton x thrust; the no-go zone is the outline of the nozzle pushed straight back, as long as the heat |
| turret base (light / heavy mount) | turn speed (deg/s) | precision and servo power follow (fast = loose) |
| barrel: cannon / railgun | damage per shot per m3 | shot damage = per_m3 x volume; cooldown, speed, spread follow |
| barrel: **beam** | beam dps per m3 | less damage, but goes through `penetration` metres of modules |
| commander (bridge / cockpit / war room) | volume per seat | seats = floor(volume / seat_volume) |
| radar (electronic / thermal) | range per metre of size | range = range_per_m x cbrt(volume) |

Changing the main stat re-derives the others with trade-offs (`ModulePresets.set_main`): e.g. thrust per m3 x4 costs
roughly x1.5 electricity per newton and x2.1 heat per newton, a beam with more damage loses penetration. The tuning
exponents are in that one function. The resolved numbers are COPIED into the module (`modules[i]["cfg"]["stats"]`), so
saved ships do not depend on the preset list. **Selection tab > Preset & stats** edits them and **Save as preset** keeps
them in `user://presets.json` (they then show up in the preset lists).

`cfg` = `{preset, kind, stats, barrels: [module ids] (turret base), links: [turret bases] + pilot: bool (commander)}`. Old ship files are
converted on load (`ShipDesign._migrate`: thruster `power` -> thrust per m3, commander `crew` -> seat volume, single `barrel`).

**Minimum size** (`ModuleCatalog.MIN_EXTENT`): hull, commander >= 1.9 m on every side, turret base >= 1.2 m, because people
walk inside. `validate()` refuses to save a smaller one. The premade ships were rebuilt at human scale (x2.6).

## 2. Detection (internal module) and Radar (external module)

* `Ship/Systems/Detection` (`ShipDetection`) scans every 0.25 s. **No radar:** it works by VIEW: other ships within
  `Data.VIEW_RANGE` (1200 m) are contacts and rendered; farther ones are not even drawn (`Ship.set_rendered`), and ships
  beyond `Data.NET_RANGE` (6 km) are not even sent any data (`Ship._net_filter`, a MultiplayerSynchronizer visibility filter).
* **Radar modules** (type `radar`) are used by Detection: **electronic** sees `Ship.sig_elec` (watts of electricity in use),
  **thermal** sees `Ship.sig_heat` (thrusters, firing weapons...). Range = radar range x clamp(sqrt(signature / reference), 0.25, 3).
  A ship using a lot of electricity or running hot is seen farther. Both signatures are smoothed, rounded and replicated.
* Every contact has a `precision` (the radar's, falling with distance): the position and velocity we know are the true ones
  plus a slow error of (1 - precision).
* **Friend or enemy**: lobby team picker (`Net.submit_team`; team 0 = on my own, 1-4 = shared). `Net.are_friends`.
* HUD (`scripts/ui/contact_markers.gd`): green / red brackets, list of contacts with how they were detected, **R** locks the
  next enemy, the lead reticle shows where the guns really aim.
* Electricity (`ShipElectricity`) now counts per-thruster watts, weapons and a passive load (commanders and radars, per m3).

## 3. Weapons

* Per barrel (`ShipTurrets.Rig`): damage, cooldown, muzzle speed, spread (barrel + (1 - turret precision) x `Data.TURRET_SPREAD_DEG`),
  electricity and heat while firing. A base can have several barrels; a barrel that does not touch its base is stuck (forward only).
* **Lead** (`Ballistics.intercept`): with a locked target the guns aim at the intercept point computed from the contact's
  (imprecise) position and relative velocity, and the barrel's muzzle speed.
* Aim tolerance is `Data.TURRET_AIM_TOLERANCE_DEG` = 1.5 deg; bullets are long glowing tracers (`ProjectilePool`).
* **Beam**: every `Data.BEAM_TICK` the shooter sends a beam message; every peer traces the ray through several modules
  (`ProjectilePool.fire_beam`); each module costs `Data.BEAM_MODULE_COST x (1 + hardness/100)` metres of penetration and
  takes less damage as it is used up; only the owner of the hit ship applies damage.

## 4. Control modes and stations (`ShipStations`, `Ship/Stations`)

* **V** switches mode. **Commander**: third-person camera, you give orders (autopilot panel). Radar, lock-on and gunnery
  are automatic (nearest enemy, lead, fire within `Data.AUTO_FIRE_RANGE`, the autopilot closes in unless you typed a destination).
* **Crew**: you are the pilot, first person (`StationCamera`), standing in ONE station: a **commander module** = pilot seat
  (fly the ship) or a **turret base** = gun station (aim with the mouse, fire its barrels). **F** walks to the next station
  at 2.5 m/s; you can do nothing on the way. A turret linked to a commander in the editor (select both, **T**) can be fired
  from the pilot seat, so you do not have to walk. Esc releases the mouse.
* Crew members who join your ship in the lobby still work all the turrets with the mouse, as before.

## 5. Ship plan, dead modules, corridors and communications

**Module states** (`Ship.module_hp`, still one replicated array): `hp > 0` working, `hp == 0` **DEAD** (a wreck: still there, solid,
heavy, drawn charred, cannot be entered or used), `hp < 0` **GONE** (cut off, hidden, no collision). Nothing is destroyed any
more. A dent that flattens a module (volume under `Data.CRUSH_VOLUME_FRACTION`, thinnest side under `ModuleCatalog.MIN_EXTENT`,
or pushed through a neighbour) makes it DEAD. `HullDeformer` already caps pushes so a module never goes through its own middle.
After every dent `ModuleGraph.refresh` re-tests the CONTACT links of the dented module (shared-vertex links never break).
`Ship._check_structure` cuts a group only when no link to a working commander is left: its modules become GONE; several groups
with commanders still split into ships.

**The plan** (`ShipPlan`, generated, never stored): rooms = commander, turret, thruster, radar, antenna modules; hull and armor are
the spaces that hold the corridors (a hub in each, a joint where two modules touch, a door in each room). Corridor pieces
(`edges`) know the module they lie in. The player only edits the corridors (`ShipDesign.plan` = removed pieces, free bend nodes,
added pieces, saved in the ship file and remapped when modules are removed or extracted). The builder refuses ships with a room
no corridor leads to (`ShipDesign.unwalkable_rooms`).

**Live state** (`PlanState`, `Ship.plan_state`, replicated `Ship.corridor_hp` per piece): a piece can be walked when its health
is above 0 and the module it lies in works. **Damage lines**: every hit (`DamageHit.direction/reach`, bullets, beams, rams)
runs a line from the impact into the ship; pieces near it lose `hp_damage / Data.CORRIDOR_HP`.

**Working rule**: a room works when `hp > 0` and (communications are online OR a working commander can walk to it over open
corridors). Commanders and antennas work alone. `Ship.is_working(mi)` / `working_mask()` is what turrets, detection, stations,
thrusters and electricity use; mass uses all present modules (`alive_mask`).

**Communications** (`ShipComms`, `Systems/Communications`, external ANTENNA modules): online while the working antennas add up to
`Data.COMMS_MIN_STRENGTH`. Online = every order is instant. Offline = `PlanState.order_delay(room)` = corridor length from the
commander / 2.5 m/s: thrusters obey the command the pilot gave that many seconds ago (`Ship._delayed_throttles`), guns start
firing only after the fire order has been held that long (`ShipWeapons.try_fire`). No open corridor = the room is cut off.

**Plan view** (`scenes/plan_view.tscn`, `PlanView` + `PlanCanvas`): top / side / front. Builder: **Plan** button, draw / erase
corridors, reset to automatic (undoable). In game: **P** shows live colours (working, dead cross, gone outline, corridor health,
order delay seconds).

**Decks**: the plan view shows ONE floor (`Data.DECK_HEIGHT` = 2.4 m) at a time as cross-sections of the modules at mid-floor, so
nothing overlaps; pieces joining two floors are stairs (cyan); corridors are drawn with square corners. Side / Front are profile views.

**Look of the plan**: white ink on dark paper. Only the hull's OUTSIDE layer (the merged outline of all hull / armor sections) and an
inside layer are drawn, not every compartment; rooms carry a three-letter code (ENG, GUN, CMD, RDR, ANT); corridors are tubes.
Colour appears only as damage the commander KNOWS about: white, yellow, orange, red, black (dead). The theorised damage spheres are
also drawn on the 3D ship (`Ship/ReportSpheres`, pulsing, own ship only). The separate hull health bar was removed from the HUD.

**Damage reports** (`ShipReports`, own ship only): damage is simulated at once, but the commander only KNOWS it when the report
arrives: instantly with communications, else after walking from the damaged spot to a working commander (`PlanState.delay_at`).
Until then the plan shows an orange "?" sphere (offset, `Data.REPORT_UNCERTAINTY` radius) and the old state; the visible dent of
the own hull (`hull.rebuild`) is held back the same time (the collision and the numbers are already real).

Not done / simplifications: a corridor module has ONE hub (tall hulls get stairs, not a corridor per deck); corridor health of a part that splits off starts at full; corridors keep their original positions
when the hull is dented; communications power draw is passive (no brown-out turns antennas off); order delay does not model
the person actually walking (only the path length); balance numbers are first guesses.

## 6. What is not covered

* No automated test drives the real keyboard / mouse input of the first-person camera; it was checked by screenshot only.
* Crew members from the lobby do not get stations; only the pilot does.
* Balance numbers (presets, signature references, ranges) are first guesses: tune them in `ModulePresets` and `Data`.


## 6. Commander links, seats and the plan view
* **A ship starts in commander view** (`ShipStations.mode = "commander"`); V switches to crew view.
* **Commander links.** A commander module controls only what is linked to it: `cfg.links` (turret bases; select commander + base, **T**
  toggles) and `cfg.pilot` (flight controls, a checkbox in the builder). If no commander has any link, every commander does everything.
  `ShipDesign.controls()/controls_flight()`, `Ship.my_commander()/bases_of_seat()/i_fly()`. Old files with one `link` are converted.
* **Seats.** Crew pick a bridge with `Net.submit_join_crew`; the owner of a locked ship picks theirs with `Net.submit_set_seat`
  (lobby button "Choose my bridge", same seat picker). `Net.seat_of(peer)` decides what each player controls.
* **Stations / guns.** In crew view you only reach your own bridge and the turrets it controls. `ShipTurrets` keeps per-base aim
  (`base_aim`) so two commanders can aim different turrets at once. Crew fire / aim RPCs only move the turrets of the sender's bridge.
* **Flying.** If the owner sits at a gunner-only bridge, a crew member at a pilot bridge flies (`Ship.request_flight`).
  The autopilot panel, radar and antenna are still shared by everybody aboard.
* **Plan canvas.** One white outline per deck (hull not drawn), rooms and corridors inside, doorway funnels, stairs icons. Decks come
  from stacking: every extra module overlapping a footprint along y adds a deck.

## Ship editor layout (v3.2)

* **Left panel** – one *mode dropdown* (Object / Vertex / Edge / Face, keys 1-4, each with an icon + tooltip). Under it
  the **context tools** for that mode (Edge: Bevel, Subdivide, Dissolve, Collapse, Align…), then the **common tools**
  at the bottom (Transform, Select grow/invert/linked/box, Adjust last operation F9, Frame, Delete).
  Buttons are built at runtime from the tables in `scripts/builder/builder_tools.gd`; add a tool by adding a table row
  and, for adjustable ones, an `_op_<name>(params)` function in `ship_builder.gd`.
* **Viewport bar** – Shading (Solid / X-ray / Wireframe), View (perspective/ortho, standard views, hide/isolate) and
  Overlays. In *Solid* shading vertices/edges behind surfaces are not drawn or pickable; X-ray shows and picks everything.
* **Adjustable operations** (bevel, extrude, inset, subdivide, mirror, array…) open the operator panel
  (`operator_panel.gd`): change the numbers, the result is recomputed from a snapshot, Apply keeps, Cancel/Esc restores.
  F9 reopens the last one until the next undo checkpoint. Not a persistent modifier stack.
* **Create tab** – Ship | Module toggle, so ship creation and module creation are separate.
* Icons are inline SVG in `builder_icons.gd`; colours in `builder_theme.gd`.

## Plan view, layers and the new module rules (v3.3)
* `PlanCanvas` draws a STACK OF LAYERS (`layers`, `register_layer(id, label, draw_fn, iso_fn)`). Built in: "structure" (hull,
  outside parts) and "rooms" (rooms, corridors, doors, damage). PlanView lists a check box for each. To add e.g. an
  electricity layer, register one: it draws with the canvas helpers, and an optional `iso` callable draws it in the exploded view.
* Views: Decks, Side, Front, **Sheet** (all decks on one sheet), **Exploded 3D** (isometric, drag = turn, wheel = zoom, hover a
  module: it grows and the others are pushed away; Explode slider). White/dark paper switch. Live ships also get STATUS and LOGS tabs.
* Corridors: start anywhere inside the hull (no room needed), click to add bends, click a corridor to make a junction, Shift =
  45 degree steps. Damage reports from places with no path to the bridge wait (NO LINK) until comms or a corridor is back.
* **Room or not is a PRESET property** (`kind: "room"`, `ShipDesign.is_room`). Thrusters and the antenna presets Whip / Dish are
  not rooms (no corridor, orders always reach them, the antenna sends a fixed signal). The antenna presets "Relay room" and
  "Long range transmitter" are rooms (they need a corridor) with an adjustable signal strength (lower = less electricity =
  harder to see on electronic radar). Rooms are drawn with their real footprint.
* Flight: `ShipAutopilot` modes GOTO (stops) and DRIVE (thrust 0..1, never stops, can follow a ship), optional turret-facing lock
  (`ShipTurrets.best_facing_axis`). Orders are given on the **tactical map** (M): click = waypoint, height ruler, thrust slider.
  Commander mode: radar locks and aims, guns fire only while LMB is held (or WEAPONS FREE, H); the ship no longer flies itself.
* Turrets aim at the closest direction their arc allows (`_best_reachable`) and keep firing along the barrel when the target is out of arc.

## Plan readability and fuzz tests
- `PlanCanvas` places every text and marker through `_claim()` / `_place_text()`: each one reserves its rectangle, a later one moves
  below / above / beside instead of overlapping. External parts reserve their outline, so deck-change markers and labels stay clear.
- A deck change is a small disc with an up/down triangle and the number of the deck it leads to (`_stairs`).
- Gunnery: automatic / commander fire only when the barrel points at the target (`TURRET_AIM_TOLERANCE_DEG`); a person holding fire
  in crew mode (`manual = true`) fires regardless.
- `tests/test_fuzz.tscn` (random modelling operators, save/load, random damage and comms on the plan, every plan view / paper /
  deck / layer combination, label overlap check) and `tests/test_fuzz_live.tscn` (real ships flying random GOTO / DRIVE / facing /
  brake orders while being damaged and firing). Raise `SEEDS` to run longer.

## Rooms that touch, stairs, legend
- Two rooms that touch are joined by a door in the shared wall only (`ShipPlan.generate` always makes the joint; the canvas draws no corridor, `_joint_kind == "wall"`).
- A joint between modules on different decks is a stair (`"stairs"`): no corridor stub into the room, one small marker inside the room (and straight below / above it on the other deck), seen from both decks.
- The plan legend lists only: stairs, corridor, module (the code in the box says which).

## Decks, shapes, engine room, presets, arrow orders, map (latest)
- **Decks** (`PlanCanvas._compute_layers`): a module's deck = max(its height-gap floor, the footprint-overlap rule), renumbered so there are no empty decks (`MAX_DECKS` 48, `DECK_GAP` 1 m).
- **Shapes** (`ShipBuilder.add_shape`, `axis_basis`): cylinder / cone are built along Y from a base radius and a height, then turned to the chosen axis (0 up, 1 forward = -Z the ship's nose, 2 side). "Add on the selected part" puts it on the selected face pointing along its normal and welds the nearest base vertices (`ShipDesign.weld_pairs`). `ModuleCatalog.DEFAULT_ROUND` holds the defaults per type. Premade ships are generated by `tools/make_premade_ships.py` (`nozzle()` makes a thruster cylinder lying along its thrust).
- **Engine room** (`ModuleCatalog.ENGINE_ROOM`, a room): `PlanState.engine_ok` / `engines_cut()`. `Ship._delayed_throttles` zeroes all thruster commands when the ship has engine rooms and none works; without comms `order_delay` of a thruster is the walk to the nearest working engine room. No engine room on the ship = old behaviour.
- **Presets**: `ModulePresets.save_definition / delete_custom / summary`, `custom_file` is the save path (tests redirect it). Weapon presets and cfg carry `damage_type` (a `DamageRegistry.WEAPON_TYPES` id); `Rig.damage_type` is an index so it travels in the `fire` / `beam` RPCs (`PackedInt32Array`, optional last argument). `WeaponDamage` is one parametrised class (`hardness_share`, `dent_per_damage`, `hp_share`). Armor / hull stats `hp_mult`, `density_mult` are read in `ShipDesign.compute_props` (missing = 1).
- **Arrow orders** (`ShipAutopilot`): `drive_heading(dir, thr)` (fixed world direction), `drive_to(p, thr, follow)` (a ship: aims at `aim_point()` = `intercept_point()`, which iterates "time to cover the distance accelerating from the current speed, where is the target then"), `go_follow(ship)` (GOTO in the frame of the target, holding `follow_distance`).
- **Tactical map** (`TacticalMap`): one orthographic projection (`_proj` / `_unproject`) for both views; 2D = pitch 90 deg. `MapObjects.gather` lists ships (radar estimates), shots (`Data.PROJECTILE_EYE_RANGE` / `PROJECTILE_RADAR_RANGE`) and the world's `Landmarks`.
- **Editor plugin**: `tools/ship_cli.gd` (run as a scene, headless) does new / copy / info / validate / delete; the dock calls it through `OS.execute`. Opening the builder switches `run/window_placement/game_embed_mode` on.
