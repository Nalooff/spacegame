# Structure, splitting, turrets, seats, editor tools and plugin

This document describes the systems added in the "structural integrity" update, where the code lives, and every number you can tune.

## 1. Structural integrity

| Piece | File | What it does |
|---|---|---|
| `ModuleGraph` | `scripts/ship/module_graph.gd` | Which modules are connected. Two modules are connected when they **share a vertex** (covers shared edges and faces) **or touch/overlap** (GJK test on small point sets, margin `CONTACT_MARGIN` = 4 cm). Built once per ship, in the worker thread for big ships. |
| `ConvexOverlap` | `scripts/data/convex_overlap.gd` | GJK boolean test used by the graph, the turrets and the crush rule. |
| `Ship._check_structure()` | `scripts/ship/ship.gd` | Runs on the owner, at most once per physics frame, only after a module was lost. |

Rules, in order:
1. Every group of connected, living modules **without a working Commander** is cut off: all its modules are destroyed.
2. No group with a Commander is left: the ship is lost (`report_death`, respawn after `Data.RESPAWN_DELAY`).
3. Several groups each with a Commander: the ship **splits** (section 3).

Losing modules lowers mass, moves the centre of mass (`center_of_mass` is set; thruster torque arms are taken around it) and removes thrusters/turrets (`ShipDesign.compute_props(alive_mask)`).
Links are decided by the *design* (they are not recomputed after dents: dents only push inward, so touching modules keep touching).

## 2. Deformation and the crush rule

* **Stuck links**: vertices shared between modules are the *same* vertex id, so when a dent moves one, every linked edge/face/module moves with it (`HullDeformer`). The deformer also never pushes a vertex more than 45 % of its distance to the module centre.
* **Crush rule** (`Ship._crush_check`, owner only, after every dent). A module is destroyed instead of clipping when
  * its volume falls under `Data.CRUSH_VOLUME_FRACTION` (35 %) of the original, or turns inside out, or
  * vertices that moved in this dent end up deeper than `Data.CRUSH_PENETRATION` (0.15 m) inside a module it is attached to (e.g. an armor plate driven into the hull behind it). Vertices that were already inside before the dent do not count.
  
  Destroying a module triggers the structure check, so whatever hung on it falls off.

## 3. Multi-commander ships and dynamic splitting

* A Commander's `crew` value = its seats. **Capacity = sum of the living Commanders** (`ShipDesign.seat_slots()`, `crew_capacity()`).
* When the structure check finds two or more groups with a Commander:
  1. The owner picks the group holding the **pilot's seat** as the one that stays (else the biggest).
  2. For every other group the owner sends one small RPC to the host: module ids, their health, the transform and velocity of the moment (`game_world.structure_changed`). The host re-seats people (`Net.srv_structure_changed`) and spawns the new ships with the existing `MultiplayerSpawner`.
  3. **Every peer cuts the same modules out of its own copy of the parent** (`ShipDesign.extract`, deterministic) – no mesh is ever sent. The new ship starts with the parent's damaged health, dents included, a push apart (`Data.SPLIT_PUSH`) and the right velocity (`v + omega x r`).
  4. A crew member seated at one of the torn-off Commanders becomes the **pilot** of the new ship (ship node name = their peer id). If nobody sat there it becomes a derelict (`d<N>`) that just drifts.
* Pilots can only fly the ship they are aboard (`Ship.is_flown_by_me`).

## 4. Seats

Roster entry: `slots` = `{commander module: seats}`, `seat` = commander the player sits at. The host (`Net`) is the referee: `srv_join_crew(captain, commander)`, `occupancy()`, `seats_left()`, `srv_structure_changed()`, `srv_reset_seats()`.
Lobby: "Choose a seat on the selected ship..." opens `scenes/seat_picker.tscn` – a 3D preview (drag to rotate, wheel to zoom) with a floating button `taken/capacity` (`0/2`, `1/1`) over every Commander. Full commanders are red and disabled. The picker fetches the ship from the host when the client does not have it yet (`Net.request_blob`).

## 5. Thrusters: exhaust no-go zone

`ExhaustZone` (`scripts/data/exhaust_zone.gd`): a straight tube behind each thruster (the outline of its rear opening pushed back, not a cone). Its length grows with the heat the thruster makes (`Data.EXHAUST_BASE_LENGTH + EXHAUST_LENGTH_PER_MW x MW`), so the shape you model decides the cone (see ARCHITECTURE_V3). The builder draws it in orange and **refuses to save** while any other module is inside. If it happens anyway (hand edited file) the module burns: `Data.EXHAUST_BURN_DPS` hp/s while the thruster is above 20 % throttle (`Ship._burn_step`).

## 6. Turrets: base + barrel (architecture)

```
TURRET base  (crew station, fixed to the hull, `dir` = mount axis)    TURRET_BARREL (cannon)
        pivot = centroid of the base  <----- swivels ----->  rendered in node  Hull/BarrelPivot<N>
```
* Modules linked in the editor (`cfg.barrels` of the base: a base can have SEVERAL barrels). Per-base settings: `yaw_min/yaw_max`, `pitch_min/pitch_max` (degrees); turn speed and precision are preset stats (`cfg.stats`). A barrel pivots only if it TOUCHES its base, otherwise it is stuck and fires forward.
* `ShipTurrets` (`scripts/ship/turrets.gd`, node `Ship/Turrets`) owns the rigs. The **owner** simulates the aim (`track(dt)`): clamp to the arc, move at most `turn_speed*dt`. Only `turret_angles` (2 floats per turret, on change) is replicated; other peers pose their copy.
* **Self-collision**: (a) a turn that would push the barrel into another module is refused – the barrel stops; (b) a turret does not fire when another module is within `Data.TURRET_BLOCK_RANGE` in front of its muzzle. Both are GJK tests on <= 40 points, AABB-prefiltered.
* Firing (`ShipWeapons.try_fire`): every usable turret that points within `Data.TURRET_AIM_TOLERANCE_DEG` of the aim point and has a free line of fire shoots from **its own muzzle**. Pilot aim = mouse, crew aim is sent at 12 Hz (`request_aim`).
* A turret needs both parts alive. Barrels are not dented (they only take hp damage).

## 7. Editor

New builder tools (keys and buttons): **Create face** `C` (Vertex mode, click vertices in order), **Make module** `N` (Face mode: selected faces -> new module of the type chosen in the Add tab), **Bevel / round** `B` (Edge mode; width and segments in the tool panel; clean on corners where <= 3 faces meet, otherwise the "not closed" check tells you), **Link turret + barrel** `T`.
Validation: loose faces are drawn **pink**, faces next to a hole in their container **amber**, exhaust cones **orange**, turret arc + link **magenta**. Saving is blocked until the Ship tab says "Ready to save" (loose faces, open containers, unreachable modules, exhaust conflicts, bad turret links, missing commander/thruster).

## 8. Godot editor plugin (`addons/vertex_ships/`)

1. Project > Project Settings > Plugins: **Vertex Ships** (already enabled in `project.godot`).
2. A main-screen tab **Ships** appears next to 2D / 3D / Script (top of the editor): list of `res://ships/*`, **Open in builder** (runs the builder with that ship), **New ship**, **Validate all**, **Refresh list**.
3. Only a builder started FROM that tab shows the **Save as PREMADE** button (the plugin writes `user://premade_mode.txt`); playing the game normally, even from the editor, never shows it. The normal *Save* goes to the player folder `user://ships/`.
4. Premade ships are read by the lobby automatically. `tools/make_premade_ships.py` regenerates the four built-in ones.

## 9. Performance notes

* Structure check, crush check, burn and turret blocking only run when something changed or moved; nothing in them scales with vertex count.
* The module graph and exhaust check are built in the existing worker thread and reuse the collision-hull point ids (no extra vertex scan).
* Replication: pose 30 Hz, `throttles` and `turret_angles` only on change, module health on change, no per-frame allocations in the sync path.
* Per-peer cost of a split: one RPC + one `extract` of the torn-off modules.
