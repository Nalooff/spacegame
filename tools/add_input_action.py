"""Adds input actions to project.godot:  python3 tools/add_input_action.py scoreboard=4194306 move_order=71 ...
(physical keycodes, see Godot's Key enum). Existing actions are left alone."""
import sys, os
path = os.path.join(os.path.dirname(__file__), "..", "project.godot")
s = open(path).read()
for spec in sys.argv[1:]:
    name, code = spec.split("=")
    if f"\n{name}=" in s:
        print("exists", name); continue
    block = (f'{name}={{\n"deadzone": 0.5,\n"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,'
             f'"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":{code},'
             f'"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)\n]\n}}\n')
    s = s.replace("\n[physics]", "\n" + block + "\n[physics]", 1) if "\n[physics]" in s else s + "\n" + block
    print("added", name)
open(path, "w").write(s)
