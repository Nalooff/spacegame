# Making a module: a special thruster and a special weapon

Screenshots are in `docs/img/` and are produced by `tests/shot_module_demo.gd` (run it to redo them after UI changes).

## A special thruster (a long, cold "hot ion" nozzle)
1. **Create tab -> Module.** Click the *Thruster* type. Pick a **preset** (here *Ion drive*: weak for its size, almost no heat). `1_thruster_choose_type_and_preset.png`
2. Pick the **shape** (a cone: the nozzle) and its **half-size**. The shape IS the engine: volume = thrust, nozzle size and length = the heat cone. `2_thruster_shape_and_size.png`
3. **Add module at the view centre.** Move it (G) next to the hull. Thrusters need no corridor. `3_thruster_added.png`
4. **Properties tab:** change the ONE main number (*Thrust per m3*). The other numbers (electricity per newton, heat per newton) re-derive with the trade-offs in `ModulePresets.set_main`. `4_thruster_tuned.png`
5. Type a name and **save as preset** to reuse it (stored in `user://presets.json`). `5_thruster_saved_as_preset.png`

## A special weapon (a long railgun barrel)
1. **Create -> Module -> Barrel**, preset *Railgun*, shape *cylinder*, thin and long (half-size 0.12 x 0.12 x 1.6). `6_weapon_choose.png`
2. Add it. Damage grows with its VOLUME; Properties shows damage per m3, time between shots, muzzle speed, spread, electricity and heat. `7_weapon_added_and_stats.png`
3. Select the turret base and the barrel and press **L** (Link). A barrel only swivels if it touches its turret base.

Where to change the rules: numbers per preset in `scripts/data/module_presets.gd` (`PRESETS`), trade-offs in `set_main`, new module types in `scripts/data/module_catalog.gd` plus an icon in `scripts/builder/builder_icons.gd` (`type_<name>`).


## Your own preset from scratch (any module type)
Main menu -> **Module presets** (`docs/img/8_preset_creator.png`). Pick the type, press **New preset from this one**, type a name and every number, choose the kind (projectile or beam
for a weapon) and its **damage type** (kinetic / energy / piercing / explosive), then **Save preset**. The summary line shows shots per second and damage per second per m3 of barrel.
It appears in the builder's preset list for that module type. Armor and hull presets set toughness and weight; thruster presets set thrust per m3, electricity and heat.
Code: `ModulePresets.save_definition`, damage types in `scripts/damage/` (`DamageRegistry.WEAPON_TYPES`).

## The engine room
Add the *Engine room* type (a room: min. 1.9 m thick, needs a corridor). With one on the ship, thrusters obey only while an engine room works.
