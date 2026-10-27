class_name BuilderTools
extends RefCounted
## THE TABLE OF EDITING TOOLS. The left panel of the builder is built from this file, so adding a tool = adding a line here
## (plus the function it calls in ship_builder.gd). Nothing else has to change.
##
## A tool entry:
##   id      unique name (also used by ShipBuilder.tool_available(id) to grey the button out)
##   label   text on the button        icon  name in BuilderIcons.ICONS        key  shortcut shown on the button (text only)
##   tip     what the tooltip says     act   what happens:  "op:NAME"  = open the adjustable operation NAME (see OPERATORS)
##                                                          "NAME"     = call ShipBuilder.NAME()
##                                                          ["NAME", arg] = call ShipBuilder.NAME(arg)
## Other entries:  {"heading": "TEXT"}  a small title,   {"row": [entry, entry, ...]}  icon-only buttons side by side.
##
## OPERATORS are tools with numbers you can change afterwards (the popup "Adjust last operation"):
##   title, mode (0 object, 1 vertex, 2 edge, 3 face: the selection type it needs), params [{key, label, type, min, max, step, value, ...}]
##   type "float" / "int" use min, max, step, value, suffix;  type "option" uses options [..] and value = index of the default.

## Selection types, in the order of ShipBuilder.Mode (OBJECT, VERTEX, EDGE, FACE).
const MODES := [
	{"id": "object", "label": "Object", "icon": "mode_object", "key": "1", "tip": "Object: select whole modules (hull, thruster, turret...)"},
	{"id": "vertex", "label": "Vertex", "icon": "mode_vertex", "key": "2", "tip": "Vertex: select single points"},
	{"id": "edge", "label": "Edge", "icon": "mode_edge", "key": "3", "tip": "Edge: select the lines between two points"},
	{"id": "face", "label": "Face", "icon": "mode_face", "key": "4", "tip": "Face: select the flat sides"},
]

const MODE_TOOLS := {
	0: [
		{"heading": "MODULES"},
		{"id": "duplicate", "label": "Duplicate", "icon": "duplicate", "key": "Shift+D", "act": "duplicate_selection", "tip": "Copy the selected modules, then move the copies"},
		{"id": "mirror", "label": "Mirror", "icon": "mirror", "key": "M", "act": "op:mirror", "tip": "Mirrored copy across the X, Y or Z plane (numbers can be changed afterwards)"},
		{"id": "array", "label": "Array", "icon": "array", "key": "", "act": "op:array", "tip": "Repeat the modules several times along a direction"},
		{"id": "center_origin", "label": "Centre on origin", "icon": "center_origin", "key": "", "act": "center_on_origin", "tip": "Move the selection so its middle is at the world origin"},
		{"heading": "LINKS"},
		{"id": "link_turret", "label": "Link", "icon": "link_turret", "key": "T", "act": "link_turret_barrel", "tip": "Barrels onto a turret base (select the base + barrels), or a commander to a turret base (the bridge controls that turret)"},
		{"heading": "VISIBILITY"},
		{"id": "hide", "label": "Hide", "icon": "hide", "key": "H", "act": "hide_selection", "tip": "Hide the selected modules (they stay in the ship)"},
		{"id": "isolate", "label": "Isolate", "icon": "isolate", "key": "/", "act": "isolate_selection", "tip": "Show only the selected modules. Press again with nothing selected to show all"},
		{"id": "reveal", "label": "Show all", "icon": "reveal", "key": "Alt+H", "act": "reveal_all", "tip": "Show every hidden module"},
	],
	1: [
		{"heading": "VERTEX"},
		{"id": "connect", "label": "Connect", "icon": "connect", "key": "J", "act": "connect_vertices", "tip": "Draw an edge between two vertices of the same face (cuts the face in two)"},
		{"id": "create_face", "label": "Create face", "icon": "create_face", "key": "C", "act": "create_face", "tip": "Click 3 or more vertices in order, then make a face. It is red (loose) until it is part of a module"},
		{"id": "link", "label": "Link", "icon": "link", "key": "L", "act": "link_vertices", "tip": "Make the selected vertices one shared point so they move together (green dots)"},
		{"id": "unlink", "label": "Unlink", "icon": "unlink", "key": "U", "act": "unlink_vertices", "tip": "Detach the vertex from the other modules"},
		{"id": "merge_center", "label": "Merge at centre", "icon": "merge_center", "key": "Alt+M", "act": "merge_at_center", "tip": "Collapse the selected vertices to one vertex in their middle"},
		{"heading": "ALIGN"},
		{"row": [
			{"id": "flatten_x", "label": "Flat X", "icon": "flatten_x", "act": ["flatten_axis", 0], "tip": "Put the selected points on one X plane (same X)"},
			{"id": "flatten_y", "label": "Flat Y", "icon": "flatten_y", "act": ["flatten_axis", 1], "tip": "Put the selected points on one Y plane (same height)"},
			{"id": "flatten_z", "label": "Flat Z", "icon": "flatten_z", "act": ["flatten_axis", 2], "tip": "Put the selected points on one Z plane"},
			{"id": "snap_grid", "label": "Snap", "icon": "snap_grid", "act": "snap_to_grid", "tip": "Round the selected points to the snap grid"},
		]},
	],
	2: [
		{"heading": "EDGE"},
		{"id": "bevel", "label": "Bevel", "icon": "bevel", "key": "B", "act": "op:bevel", "tip": "Replace the edge by a flat strip (more segments = rounder). Width and segments can be changed afterwards"},
		{"id": "subdivide", "label": "Subdivide", "icon": "subdivide", "key": "W", "act": "op:subdivide", "tip": "Add evenly spaced vertices on the edge"},
		{"id": "dissolve", "label": "Dissolve", "icon": "dissolve", "key": "Ctrl+X", "act": "dissolve_edges", "tip": "Remove the edge: the two faces next to it become one"},
		{"id": "collapse", "label": "Collapse", "icon": "collapse", "key": "Alt+X", "act": "collapse_edges", "tip": "Shrink the edge to a single point"},
		{"heading": "ALIGN"},
		{"row": [
			{"id": "flatten_x", "label": "Flat X", "icon": "flatten_x", "act": ["flatten_axis", 0], "tip": "Put the selected edges' points on one X plane"},
			{"id": "flatten_y", "label": "Flat Y", "icon": "flatten_y", "act": ["flatten_axis", 1], "tip": "Put the selected edges' points on one Y plane"},
			{"id": "flatten_z", "label": "Flat Z", "icon": "flatten_z", "act": ["flatten_axis", 2], "tip": "Put the selected edges' points on one Z plane"},
			{"id": "snap_grid", "label": "Snap", "icon": "snap_grid", "act": "snap_to_grid", "tip": "Round the points to the snap grid"},
		]},
	],
	3: [
		{"heading": "FACE"},
		{"id": "extrude", "label": "Extrude", "icon": "extrude", "key": "E", "act": "op:extrude", "tip": "Push the faces out into new volume. The distance can be changed afterwards"},
		{"id": "inset", "label": "Inset", "icon": "inset", "key": "I", "act": "op:inset", "tip": "Make a smaller face inside each face (frame around it); optional depth"},
		{"id": "subdivide_face", "label": "Subdivide", "icon": "subdivide_face", "key": "", "act": "subdivide_faces", "tip": "Cut every face into one quad per corner"},
		{"id": "triangulate", "label": "Triangulate", "icon": "triangulate", "key": "Ctrl+T", "act": "triangulate_faces", "tip": "Split faces into triangles"},
		{"id": "flatten_face", "label": "Flatten", "icon": "flatten_face", "key": "", "act": "flatten_faces", "tip": "Put the selected faces on one plane"},
		{"heading": "MODULE"},
		{"id": "make_module", "label": "Make module", "icon": "make_module", "key": "N", "act": "make_module", "tip": "The selected faces become a new module of the type chosen in the Add tab. They must form a closed container"},
		{"heading": "ALIGN"},
		{"row": [
			{"id": "flatten_x", "label": "Flat X", "icon": "flatten_x", "act": ["flatten_axis", 0], "tip": "Put the points of the selected faces on one X plane"},
			{"id": "flatten_y", "label": "Flat Y", "icon": "flatten_y", "act": ["flatten_axis", 1], "tip": "Put the points of the selected faces on one Y plane"},
			{"id": "flatten_z", "label": "Flat Z", "icon": "flatten_z", "act": ["flatten_axis", 2], "tip": "Put the points of the selected faces on one Z plane"},
			{"id": "snap_grid", "label": "Snap", "icon": "snap_grid", "act": "snap_to_grid", "tip": "Round the points to the snap grid"},
		]},
	],
}

## Tools for every selection type: bottom of the left panel.
const COMMON_TOOLS := [
	{"heading": "TRANSFORM"},
	{"id": "move", "label": "Move", "icon": "move", "key": "G", "act": ["begin_transform", 1], "tip": "Move the selection. X / Y / Z locks an axis, type a number for an exact distance, click or Enter confirms, Esc cancels"},
	{"id": "rotate", "label": "Rotate", "icon": "rotate", "key": "R", "act": ["begin_transform", 2], "tip": "Rotate the selection around its centre (type degrees for an exact angle)"},
	{"id": "scale", "label": "Scale", "icon": "scale", "key": "S", "act": ["begin_transform", 3], "tip": "Scale the selection around its centre (type a factor)"},
	{"heading": "SELECT"},
	{"row": [
		{"id": "select_all", "label": "All", "icon": "select_all", "act": "select_all", "tip": "Select everything (A)"},
		{"id": "select_none", "label": "None", "icon": "select_none", "act": "clear_selection", "tip": "Select nothing (Alt+A)"},
		{"id": "select_invert", "label": "Invert", "icon": "select_invert", "act": "select_invert", "tip": "Select what is not selected (Ctrl+I)"},
		{"id": "grow", "label": "Grow", "icon": "grow", "act": "select_grow", "tip": "Add the neighbours of the selection (Ctrl +)"},
		{"id": "select_linked", "label": "Linked", "icon": "select_linked", "act": "select_linked", "tip": "Select everything connected to the selection (Ctrl+L)"},
	]},
	{"heading": "GENERAL"},
	{"id": "adjust", "label": "Adjust last operation", "icon": "adjust", "key": "F9", "act": "reopen_last_operator", "tip": "Open the numbers of the last bevel / extrude / inset... again, as long as you did nothing else"},
	{"id": "frame_sel", "label": "Frame", "icon": "frame", "key": "F", "act": "frame_selection", "tip": "Centre the camera on the selection"},
	{"id": "delete", "label": "Delete", "icon": "delete", "key": "X", "act": "delete_selection", "tip": "Delete the selection (in vertex / edge mode: the faces touching it)"},
]

const AXES := ["X (left-right)", "Y (up-down)", "Z (front-back)"]

## The adjustable operations (see ShipBuilder "ADJUSTABLE OPERATIONS"). `mode`: 0 object, 1 vertex, 2 edge, 3 face.
const OPERATORS := {
	"bevel": {"title": "Bevel", "mode": 2, "params": [
		{"key": "width", "label": "Width", "type": "float", "min": 0.005, "max": 3.0, "step": 0.005, "value": 0.1, "suffix": "m"},
		{"key": "segments", "label": "Segments", "type": "int", "min": 1, "max": 3, "step": 1, "value": 1, "suffix": " (1 flat, 2-3 round)"},
	]},
	"extrude": {"title": "Extrude", "mode": 3, "params": [
		{"key": "distance", "label": "Distance", "type": "float", "min": -10.0, "max": 10.0, "step": 0.05, "value": 0.4, "suffix": "m"},
	]},
	"inset": {"title": "Inset", "mode": 3, "params": [
		{"key": "amount", "label": "Thickness", "type": "float", "min": 0.01, "max": 5.0, "step": 0.01, "value": 0.15, "suffix": "m"},
		{"key": "depth", "label": "Depth", "type": "float", "min": -5.0, "max": 5.0, "step": 0.01, "value": 0.0, "suffix": "m"},
	]},
	"subdivide": {"title": "Subdivide edge", "mode": 2, "params": [
		{"key": "cuts", "label": "Cuts", "type": "int", "min": 1, "max": 12, "step": 1, "value": 1, "suffix": "new vertices"},
	]},
	"mirror": {"title": "Mirror", "mode": 0, "params": [
		{"key": "axis", "label": "Across", "type": "option", "options": ["X plane (left-right)", "Y plane (up-down)", "Z plane (front-back)"], "value": 0},
		{"key": "offset", "label": "Plane at", "type": "float", "min": -50.0, "max": 50.0, "step": 0.05, "value": 0.0, "suffix": "m"},
	]},
	"array": {"title": "Array", "mode": 0, "params": [
		{"key": "count", "label": "Copies in total", "type": "int", "min": 2, "max": 20, "step": 1, "value": 3, "suffix": ""},
		{"key": "dx", "label": "Step X", "type": "float", "min": -50.0, "max": 50.0, "step": 0.05, "value": 2.0, "suffix": "m"},
		{"key": "dy", "label": "Step Y", "type": "float", "min": -50.0, "max": 50.0, "step": 0.05, "value": 0.0, "suffix": "m"},
		{"key": "dz", "label": "Step Z", "type": "float", "min": -50.0, "max": 50.0, "step": 0.05, "value": 0.0, "suffix": "m"},
	]},
}
