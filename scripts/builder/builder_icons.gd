class_name BuilderIcons
extends RefCounted
## Every icon of the ship builder, drawn as tiny inline SVG (24 x 24). No image files, so nothing has to be imported:
##   BuilderIcons.get_icon("bevel")  ->  Texture2D (cached)
##
## To add an icon: add a line to ICONS. Use the colour tokens:  $I = ink (light grey-blue)   $A = accent (amber)   $B = blue.
## Shapes use stroke-width 1.6 and round caps so they look alike. Unknown names give an empty texture (never an error).

const INK := "#dbe6f7"
const ACCENT := "#ffc447"
const BLUE := "#6cb8ff"
const SIZE := 24

const ICONS := {
	# ---- selection types
	"mode_object": '<path d="M12 3l8 4v10l-8 4-8-4V7z" fill="none" stroke="$A" stroke-width="1.6" stroke-linejoin="round"/><path d="M4 7l8 4 8-4M12 11v10" fill="none" stroke="$I" stroke-width="1.4" stroke-linejoin="round"/>',
	"mode_vertex": '<path d="M5 5h14v14H5z" fill="none" stroke="$I" stroke-width="1.4" opacity=".55"/><circle cx="5" cy="5" r="2.3" fill="$I"/><circle cx="19" cy="5" r="2.3" fill="$I"/><circle cx="5" cy="19" r="2.3" fill="$I"/><circle cx="19" cy="19" r="3" fill="$A"/>',
	"mode_edge": '<path d="M5 5h14v14H5z" fill="none" stroke="$I" stroke-width="1.4" opacity=".55"/><path d="M5 19L19 19" stroke="$A" stroke-width="3" stroke-linecap="round"/><circle cx="5" cy="19" r="1.8" fill="$A"/><circle cx="19" cy="19" r="1.8" fill="$A"/>',
	"mode_face": '<path d="M12 3l8 4v10l-8 4-8-4V7z" fill="none" stroke="$I" stroke-width="1.4" stroke-linejoin="round" opacity=".6"/><path d="M12 11l8-4v10l-8 4z" fill="$A" stroke="$A" stroke-width="1.4" stroke-linejoin="round" opacity=".9"/>',
	# ---- transform
	"move": '<path d="M12 3v18M3 12h18" stroke="$I" stroke-width="1.6" stroke-linecap="round"/><path d="M9 6l3-3 3 3M9 18l3 3 3-3M6 9l-3 3 3 3M18 9l3 3-3 3" fill="none" stroke="$A" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>',
	"rotate": '<path d="M19 12a7 7 0 1 1-2.2-5.1" fill="none" stroke="$I" stroke-width="1.8" stroke-linecap="round"/><path d="M19 4v4h-4" fill="none" stroke="$A" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
	"scale": '<path d="M4 20V10h10v10z" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><path d="M14 10l6-6M15 4h5v5" fill="none" stroke="$A" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
	# ---- vertex tools
	"connect": '<circle cx="5" cy="19" r="2.4" fill="$A"/><circle cx="19" cy="5" r="2.4" fill="$A"/><path d="M7 17L17 7" stroke="$I" stroke-width="1.8" stroke-dasharray="3 2.5" stroke-linecap="round"/>',
	"create_face": '<path d="M12 4l8 15H4z" fill="$A" fill-opacity=".35" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><circle cx="12" cy="4" r="1.8" fill="$A"/><circle cx="20" cy="19" r="1.8" fill="$A"/><circle cx="4" cy="19" r="1.8" fill="$A"/>',
	"link": '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1" fill="none" stroke="$I" stroke-width="1.8" stroke-linecap="round"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1" fill="none" stroke="$A" stroke-width="1.8" stroke-linecap="round"/>',
	"unlink": '<path d="M10 14a4 4 0 0 0 5.7 0l1.5-1.5M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7" fill="none" stroke="$I" stroke-width="1.8" stroke-linecap="round"/><path d="M16 4l-1 3M20 8l-3 1M8 20l1-3M4 16l3-1" stroke="$A" stroke-width="1.8" stroke-linecap="round"/>',
	"merge_center": '<circle cx="4" cy="6" r="2" fill="$I"/><circle cx="4" cy="18" r="2" fill="$I"/><circle cx="20" cy="12" r="2" fill="$I"/><path d="M6 7l5 4M6 17l5-4M18 12h-4" stroke="$I" stroke-width="1.4" stroke-linecap="round"/><circle cx="13" cy="12" r="2.8" fill="$A"/>',
	"flatten_x": '<path d="M12 3v18" stroke="$B" stroke-width="1.6" stroke-dasharray="2.5 2" stroke-linecap="round"/><circle cx="5" cy="7" r="2" fill="$I"/><circle cx="19" cy="15" r="2" fill="$I"/><path d="M7.5 7H11M16.5 15H13" stroke="$A" stroke-width="1.6" stroke-linecap="round"/><circle cx="12" cy="7" r="1.4" fill="$A"/><circle cx="12" cy="15" r="1.4" fill="$A"/>',
	"flatten_y": '<path d="M3 12h18" stroke="$B" stroke-width="1.6" stroke-dasharray="2.5 2" stroke-linecap="round"/><circle cx="7" cy="5" r="2" fill="$I"/><circle cx="15" cy="19" r="2" fill="$I"/><path d="M7 7.5V11M15 16.5V13" stroke="$A" stroke-width="1.6" stroke-linecap="round"/><circle cx="7" cy="12" r="1.4" fill="$A"/><circle cx="15" cy="12" r="1.4" fill="$A"/>',
	"flatten_z": '<path d="M5 19L19 5" stroke="$B" stroke-width="1.6" stroke-dasharray="2.5 2" stroke-linecap="round"/><circle cx="5" cy="7" r="2" fill="$I"/><circle cx="19" cy="17" r="2" fill="$I"/><path d="M6.5 8.5L10 12M17.5 15.5L14 12" stroke="$A" stroke-width="1.6" stroke-linecap="round"/><circle cx="12" cy="12" r="1.4" fill="$A"/>',
	"snap_grid": '<path d="M4 4h16v16H4zM4 12h16M12 4v16" fill="none" stroke="$I" stroke-width="1.2" opacity=".6"/><circle cx="12" cy="12" r="3" fill="$A"/>',
	# ---- edge tools
	"bevel": '<path d="M4 20V12l8-8h8" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round" opacity=".6"/><path d="M4 20h16V4" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><path d="M12 4L4 12" stroke="$A" stroke-width="2.4" stroke-linecap="round"/>',
	"subdivide": '<path d="M3 12h18" stroke="$I" stroke-width="1.8" stroke-linecap="round"/><circle cx="3" cy="12" r="2" fill="$I"/><circle cx="21" cy="12" r="2" fill="$I"/><circle cx="9" cy="12" r="2.2" fill="$A"/><circle cx="15" cy="12" r="2.2" fill="$A"/>',
	"dissolve": '<path d="M4 5h16v14H4z" fill="none" stroke="$I" stroke-width="1.5" stroke-linejoin="round"/><path d="M12 5v14" stroke="$A" stroke-width="1.8" stroke-dasharray="2 2.2" stroke-linecap="round"/><path d="M8 9l8 6M16 9l-8 6" stroke="$A" stroke-width="1.2" opacity=".0"/>',
	"collapse": '<circle cx="4" cy="12" r="2.2" fill="$I"/><circle cx="20" cy="12" r="2.2" fill="$I"/><path d="M7 12h3M17 12h-3" stroke="$A" stroke-width="1.8" stroke-linecap="round"/><path d="M9 9l3 3-3 3M15 9l-3 3 3 3" fill="none" stroke="$A" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>',
	# ---- face tools
	"extrude": '<path d="M5 20h12v-7H5z" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><path d="M5 13l4-4h12v7l-4 4" fill="none" stroke="$I" stroke-width="1.4" stroke-linejoin="round" opacity=".6"/><path d="M12 10V3M8.5 6.5L12 3l3.5 3.5" fill="none" stroke="$A" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
	"inset": '<path d="M3 3h18v18H3z" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><path d="M8 8h8v8H8z" fill="$A" fill-opacity=".35" stroke="$A" stroke-width="1.6" stroke-linejoin="round"/><path d="M3 3l5 5M21 3l-5 5M3 21l5-5M21 21l-5-5" stroke="$I" stroke-width="1.1" opacity=".6"/>',
	"subdivide_face": '<path d="M3 3h18v18H3zM12 3v18M3 12h18" fill="none" stroke="$I" stroke-width="1.5" stroke-linejoin="round"/><circle cx="12" cy="12" r="2.4" fill="$A"/>',
	"triangulate": '<path d="M4 4h16v16H4z" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><path d="M4 4l16 16" stroke="$A" stroke-width="1.8" stroke-linecap="round"/>',
	"flatten_face": '<path d="M3 15l9-5 9 5-9 5z" fill="$A" fill-opacity=".3" stroke="$A" stroke-width="1.6" stroke-linejoin="round"/><path d="M3 9l9-5 9 5" fill="none" stroke="$I" stroke-width="1.4" stroke-dasharray="2.5 2" stroke-linejoin="round" opacity=".7"/>',
	"make_module": '<path d="M12 3l8 4v10l-8 4-8-4V7z" fill="$A" fill-opacity=".25" stroke="$A" stroke-width="1.6" stroke-linejoin="round"/><path d="M4 7l8 4 8-4M12 11v10" fill="none" stroke="$I" stroke-width="1.3" stroke-linejoin="round"/><path d="M18 3v4M16 5h4" stroke="$I" stroke-width="1.6" stroke-linecap="round"/>',
	# ---- object tools
	"duplicate": '<path d="M8 8h12v12H8z" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><path d="M4 16V4h12" fill="none" stroke="$A" stroke-width="1.6" stroke-linejoin="round"/>',
	"mirror": '<path d="M12 2v20" stroke="$B" stroke-width="1.5" stroke-dasharray="2.5 2" stroke-linecap="round"/><path d="M9 6L3 12l6 6z" fill="$I" fill-opacity=".35" stroke="$I" stroke-width="1.5" stroke-linejoin="round"/><path d="M15 6l6 6-6 6z" fill="none" stroke="$A" stroke-width="1.5" stroke-linejoin="round"/>',
	"array": '<path d="M2 8h6v8H2z" fill="none" stroke="$I" stroke-width="1.5" stroke-linejoin="round"/><path d="M9 8h6v8H9z" fill="none" stroke="$A" stroke-width="1.5" stroke-linejoin="round" opacity=".85"/><path d="M16 8h6v8h-6z" fill="none" stroke="$A" stroke-width="1.5" stroke-linejoin="round" opacity=".55"/>',
	"center_origin": '<circle cx="12" cy="12" r="3" fill="none" stroke="$A" stroke-width="1.7"/><path d="M12 2v6M12 16v6M2 12h6M16 12h6" stroke="$I" stroke-width="1.6" stroke-linecap="round"/>',
	"isolate": '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><circle cx="12" cy="12" r="3.2" fill="$A"/>',
	"hide": '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round" opacity=".6"/><path d="M4 20L20 4" stroke="$A" stroke-width="2" stroke-linecap="round"/>',
	"reveal": '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><path d="M12 8v8M8 12h8" stroke="$A" stroke-width="1.8" stroke-linecap="round"/>',
	"link_turret": '<circle cx="9" cy="14" r="5" fill="none" stroke="$I" stroke-width="1.6"/><path d="M12 11l9-7" stroke="$A" stroke-width="3.2" stroke-linecap="round"/><path d="M4 21h10" stroke="$I" stroke-width="1.6" stroke-linecap="round"/>',
	# ---- common
	"delete": '<path d="M5 7h14M10 7V4h4v3M7 7l1 13h8l1-13" fill="none" stroke="$I" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/><path d="M10 11v6M14 11v6" stroke="$A" stroke-width="1.5" stroke-linecap="round"/>',
	"frame": '<path d="M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5" fill="none" stroke="$I" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><circle cx="12" cy="12" r="2.6" fill="$A"/>',
	"select_all": '<path d="M4 4h16v16H4z" fill="$A" fill-opacity=".3" stroke="$A" stroke-width="1.6" stroke-dasharray="3 2" stroke-linejoin="round"/>',
	"select_none": '<path d="M4 4h16v16H4z" fill="none" stroke="$I" stroke-width="1.6" stroke-dasharray="3 2" stroke-linejoin="round" opacity=".8"/>',
	"select_invert": '<path d="M4 4h16v16H4z" fill="none" stroke="$I" stroke-width="1.5" stroke-dasharray="3 2" opacity=".7"/><path d="M4 4h16v16z" fill="$A" fill-opacity=".45"/>',
	"grow": '<path d="M9 9h6v6H9z" fill="$A" fill-opacity=".5" stroke="$A" stroke-width="1.5"/><path d="M5 5h14v14H5z" fill="none" stroke="$I" stroke-width="1.5" stroke-dasharray="2.5 2"/>',
	"shrink": '<path d="M5 5h14v14H5z" fill="$A" fill-opacity=".35" stroke="$A" stroke-width="1.5"/><path d="M9 9h6v6H9z" fill="none" stroke="$I" stroke-width="1.5" stroke-dasharray="2.5 2"/>',
	"select_linked": '<path d="M3 12h4l2-5 3 10 3-8 2 3h4" fill="none" stroke="$A" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
	"adjust": '<path d="M4 7h10M18 7h2M4 17h2M10 17h10" stroke="$I" stroke-width="1.8" stroke-linecap="round"/><circle cx="16" cy="7" r="2.4" fill="$A"/><circle cx="8" cy="17" r="2.4" fill="$A"/>',
	"undo": '<path d="M9 7L4 12l5 5" fill="none" stroke="$I" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M4 12h10a5 5 0 0 1 0 10h-3" transform="translate(0 -4)" fill="none" stroke="$I" stroke-width="1.8" stroke-linecap="round"/>',
	"redo": '<path d="M15 7l5 5-5 5" fill="none" stroke="$I" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M20 12H10a5 5 0 0 0 0 10h3" transform="translate(0 -4)" fill="none" stroke="$I" stroke-width="1.8" stroke-linecap="round"/>',
	# ---- viewport: shading, camera, overlays
	"shading_solid": '<path d="M12 3l8 4v10l-8 4-8-4V7z" fill="$I" fill-opacity=".75" stroke="$I" stroke-width="1.4" stroke-linejoin="round"/><path d="M12 11l8-4v10l-8 4z" fill="$B" fill-opacity=".9"/>',
	"shading_xray": '<path d="M12 3l8 4v10l-8 4-8-4V7z" fill="$B" fill-opacity=".18" stroke="$I" stroke-width="1.4" stroke-linejoin="round"/><path d="M4 7l8 4 8-4M12 11v10" fill="none" stroke="$I" stroke-width="1.2" stroke-linejoin="round" stroke-dasharray="2 2"/>',
	"shading_wire": '<path d="M12 3l8 4v10l-8 4-8-4V7z" fill="none" stroke="$I" stroke-width="1.5" stroke-linejoin="round"/><path d="M4 7l8 4 8-4M12 11v10" fill="none" stroke="$I" stroke-width="1.5" stroke-linejoin="round"/>',
	"view": '<path d="M3 8l3-3h8l3 3v8l-3 3H6l-3-3z" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><circle cx="10" cy="12" r="3" fill="$A"/><path d="M17 10l4-2v8l-4-2" fill="none" stroke="$I" stroke-width="1.5" stroke-linejoin="round"/>',
	"overlays": '<path d="M12 3l9 5-9 5-9-5z" fill="none" stroke="$I" stroke-width="1.5" stroke-linejoin="round"/><path d="M3 12l9 5 9-5M3 16l9 5 9-5" fill="none" stroke="$A" stroke-width="1.5" stroke-linejoin="round" opacity=".85"/>',
	"persp": '<path d="M3 20L9 5h6l6 15z" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><path d="M7 14h10" stroke="$A" stroke-width="1.5"/>',
	"ortho": '<path d="M5 5h14v14H5z" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><path d="M5 12h14M12 5v14" stroke="$A" stroke-width="1.2" stroke-dasharray="2 2"/>',
	"cam_front": '<path d="M5 5h14v14H5z" fill="none" stroke="$I" stroke-width="1.5"/><path d="M5 5h14v14H5z" fill="$A" fill-opacity=".45"/>',
	"cam_top": '<path d="M5 9l7-4 7 4-7 4z" fill="$A" fill-opacity=".55" stroke="$A" stroke-width="1.4" stroke-linejoin="round"/><path d="M5 9v8l7 4 7-4V9" fill="none" stroke="$I" stroke-width="1.4" stroke-linejoin="round"/>',
	"cam_side": '<path d="M12 3l8 4v10l-8 4-8-4V7z" fill="none" stroke="$I" stroke-width="1.4" stroke-linejoin="round"/><path d="M12 11l8-4v10l-8 4z" fill="$A" fill-opacity=".55"/>',
	"axes": '<path d="M5 19L5 4M5 19h15M5 19l8-8" stroke="$I" stroke-width="1.5" stroke-linecap="round"/><circle cx="5" cy="4" r="1.6" fill="#6ee27b"/><circle cx="20" cy="19" r="1.6" fill="#ff6b6b"/><circle cx="13" cy="11" r="1.6" fill="$B"/>',
	# ---- module types
	"type_hull": '<path d="M12 3l8 4.5v9L12 21l-8-4.5v-9z" fill="$I" fill-opacity=".25" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/>',
	"type_armor": '<path d="M12 3l7 3v6c0 4-3 7-7 9-4-2-7-5-7-9V6z" fill="$I" fill-opacity=".3" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><path d="M12 7v10" stroke="$A" stroke-width="1.4"/>',
	"type_thruster": '<path d="M7 3h10l-1.5 11h-7z" fill="$I" fill-opacity=".3" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><path d="M9 16c0 3 3 5 3 5s3-2 3-5" fill="$A" fill-opacity=".8" stroke="$A" stroke-width="1.2" stroke-linejoin="round"/>',
	"type_turret": '<circle cx="9" cy="14" r="5.5" fill="$I" fill-opacity=".25" stroke="$I" stroke-width="1.6"/><path d="M13 10l8-6" stroke="$A" stroke-width="3" stroke-linecap="round"/>',
	"type_turret_barrel": '<path d="M3 15l14-9 4 6-14 9z" fill="$I" fill-opacity=".25" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><circle cx="19" cy="9" r="1.6" fill="$A"/>',
	"type_commander": '<path d="M12 3l2.6 5.6 6 .8-4.4 4.2 1.1 6-5.3-2.9-5.3 2.9 1.1-6L3.4 9.4l6-.8z" fill="$A" fill-opacity=".35" stroke="$A" stroke-width="1.5" stroke-linejoin="round"/>',
	"type_radar": '<path d="M4 17a9 9 0 0 1 16 0z" fill="$I" fill-opacity=".25" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><path d="M12 17V8l5-4" stroke="$A" stroke-width="1.8" stroke-linecap="round"/><circle cx="17" cy="4" r="1.5" fill="$A"/><path d="M6 21h12" stroke="$I" stroke-width="1.6" stroke-linecap="round"/>',
	"type_antenna": '<path d="M12 21V8" stroke="$I" stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="7" r="2" fill="$A"/><path d="M7 5a7 7 0 0 0 0 4M17 5a7 7 0 0 1 0 4M4 3a11 11 0 0 0 0 8M20 3a11 11 0 0 1 0 8" fill="none" stroke="$A" stroke-width="1.4" stroke-linecap="round"/>',
	# ---- primitive shapes
	"shape_box": '<path d="M12 3l8 4v10l-8 4-8-4V7z" fill="$I" fill-opacity=".2" stroke="$I" stroke-width="1.5" stroke-linejoin="round"/><path d="M4 7l8 4 8-4M12 11v10" fill="none" stroke="$I" stroke-width="1.3"/>',
	"shape_wedge": '<path d="M3 19h18L7 7z" fill="$I" fill-opacity=".2" stroke="$I" stroke-width="1.5" stroke-linejoin="round"/><path d="M7 7v12" stroke="$I" stroke-width="1.3"/>',
	"shape_pyramid": '<path d="M12 3l9 16H3z" fill="$I" fill-opacity=".2" stroke="$I" stroke-width="1.5" stroke-linejoin="round"/><path d="M12 3v16" stroke="$I" stroke-width="1.3"/>',
	"shape_tetra": '<path d="M12 3l9 15-9 3-9-3z" fill="$I" fill-opacity=".2" stroke="$I" stroke-width="1.5" stroke-linejoin="round"/><path d="M12 3v18M3 18l18 0" stroke="$I" stroke-width="1.2" opacity=".6"/>',
	"shape_cylinder": '<ellipse cx="12" cy="6" rx="7" ry="3" fill="$I" fill-opacity=".25" stroke="$I" stroke-width="1.5"/><path d="M5 6v12c0 1.7 3.1 3 7 3s7-1.3 7-3V6" fill="none" stroke="$I" stroke-width="1.5"/>',
	"shape_cone": '<path d="M12 3L4 18c0 1.7 3.6 3 8 3s8-1.3 8-3z" fill="$I" fill-opacity=".2" stroke="$I" stroke-width="1.5" stroke-linejoin="round"/>',
	"shape_sphere": '<circle cx="12" cy="12" r="9" fill="$I" fill-opacity=".2" stroke="$I" stroke-width="1.5"/><ellipse cx="12" cy="12" rx="9" ry="3.4" fill="none" stroke="$I" stroke-width="1.2" opacity=".7"/>',
	"shape_dome": '<path d="M3 17a9 9 0 0 1 18 0z" fill="$I" fill-opacity=".2" stroke="$I" stroke-width="1.5" stroke-linejoin="round"/><ellipse cx="12" cy="17" rx="9" ry="3" fill="none" stroke="$I" stroke-width="1.2" opacity=".7"/>',
	# ---- ship creation
	"ship_blank": '<path d="M5 3h10l4 4v14H5z" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><path d="M14 3v5h5" fill="none" stroke="$I" stroke-width="1.4"/>',
	"ship_starter": '<path d="M12 3l5 9v6l-2 3H9l-2-3v-6z" fill="$I" fill-opacity=".25" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><circle cx="12" cy="11" r="2" fill="$A"/>',
	"ship_open": '<path d="M3 7h7l2 2h9v10H3z" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><path d="M12 12v4M10 14h4" stroke="$A" stroke-width="1.6" stroke-linecap="round"/>',
	"plan": '<path d="M3 3h18v18H3z" fill="none" stroke="$I" stroke-width="1.5"/><path d="M3 10h8v-7M11 10v11M11 15h10" stroke="$A" stroke-width="1.5" fill="none"/>',
	"save": '<path d="M4 4h13l3 3v13H4z" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><path d="M8 4v6h8V4M8 20v-6h8v6" fill="none" stroke="$A" stroke-width="1.5" stroke-linejoin="round"/>',
	"new": '<path d="M5 3h10l4 4v14H5z" fill="none" stroke="$I" stroke-width="1.6" stroke-linejoin="round"/><path d="M12 11v6M9 14h6" stroke="$A" stroke-width="1.8" stroke-linecap="round"/>',
	"back": '<path d="M10 6l-6 6 6 6M4 12h16" fill="none" stroke="$I" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
	"check": '<path d="M4 12l5 5L20 6" fill="none" stroke="$A" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>',
	"close": '<path d="M5 5l14 14M19 5L5 19" stroke="$I" stroke-width="2" stroke-linecap="round"/>',
}

static var _cache: Dictionary = {}


## The icon called `id` (see ICONS) as a texture. `px` = size in pixels (the SVG is rendered sharp at that size).
static func get_icon(id: String, px: int = 24) -> Texture2D:
	var key := "%s@%d" % [id, px]
	if _cache.has(key):
		return _cache[key]
	var body: String = ICONS.get(id, "")
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>' % [
		px, px, SIZE, SIZE, body.replace("$I", INK).replace("$A", ACCENT).replace("$B", BLUE)]
	var img := Image.new()
	var tex: Texture2D
	if body != "" and img.load_svg_from_string(svg) == OK:
		tex = ImageTexture.create_from_image(img)
	else:
		tex = PlaceholderTexture2D.new()
		(tex as PlaceholderTexture2D).size = Vector2(px, px)
	_cache[key] = tex
	return tex
