class_name FontCatalog
extends RefCounted
## Fonts for the TEXT details on ships. Index 0 is the default (Godot's built-in font). All the others are free
## (SIL Open Font License) fonts in assets/fonts, picked for a futuristic or military-stencil look.
## The index is what is saved in the ship file, so NEVER reorder: only append.

const LIST := [
	["Default", ""],
	["Orbitron (sci-fi)", "res://assets/fonts/Orbitron.ttf"],
	["Audiowide (rounded tech)", "res://assets/fonts/Audiowide.ttf"],
	["Michroma (wide)", "res://assets/fonts/Michroma.ttf"],
	["Oxanium (angular)", "res://assets/fonts/Oxanium.ttf"],
	["Rajdhani (slim tech)", "res://assets/fonts/Rajdhani-Bold.ttf"],
	["Share Tech Mono (terminal)", "res://assets/fonts/ShareTechMono.ttf"],
	["Bruno Ace (racing)", "res://assets/fonts/BrunoAce.ttf"],
	["Electrolize (clean)", "res://assets/fonts/Electrolize.ttf"],
	["Aldrich (industrial)", "res://assets/fonts/Aldrich.ttf"],
	["Black Ops One (military stencil)", "res://assets/fonts/BlackOpsOne.ttf"],
	["Saira Stencil (stencil)", "res://assets/fonts/SairaStencilOne.ttf"],
	["Stardos Stencil (serif stencil)", "res://assets/fonts/StardosStencil-Bold.ttf"],
	["Zen Dots (futuristic)", "res://assets/fonts/ZenDots.ttf"],
	["Jura (soft sci-fi)", "res://assets/fonts/Jura.ttf"],
]
static var _cache := {}


static func count() -> int:
	return LIST.size()


static func name_of(i: int) -> String:
	return LIST[clampi(i, 0, LIST.size() - 1)][0]


## The Font for index `i` (null = use the engine default).
static func get_font(i: int) -> Font:
	i = clampi(i, 0, LIST.size() - 1)
	if i == 0:
		return null
	if not _cache.has(i):
		_cache[i] = load(LIST[i][1]) as Font
	return _cache[i]
