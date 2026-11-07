class_name PaintPreview
extends Control
## A small swatch showing the current paint (two colours + pattern), so the pattern can be judged in the builder
## (the builder's 3D view only shows the first colour; the game shows the real pattern).

var c1: Color = Color.WHITE
var c2: Color = Color.BLACK
var pattern: int = 0
var pscale: float = 1.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 44)


func set_paint(a: Color, b: Color, pat: int, sc: float) -> void:
	c1 = a
	c2 = b
	pattern = pat
	pscale = sc
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, c1)
	var w := maxf(pscale * 12.0, 4.0)
	match pattern:
		1:    # stripes
			var x := 0.0
			var on := false
			while x < size.x:
				if on:
					draw_rect(Rect2(x, 0, minf(w, size.x - x), size.y), c2)
				on = not on
				x += w
		2:    # checker
			var iy := 0
			var y := 0.0
			while y < size.y:
				var ix := 0
				var x2 := 0.0
				while x2 < size.x:
					if (ix + iy) % 2 == 1:
						draw_rect(Rect2(x2, y, minf(w, size.x - x2), minf(w, size.y - y)), c2)
					ix += 1
					x2 += w
				iy += 1
				y += w
		3:    # hazard: diagonal stripes
			var x3 := -size.y
			var on3 := false
			while x3 < size.x:
				if on3:
					draw_colored_polygon(PackedVector2Array([Vector2(x3, size.y), Vector2(x3 + w, size.y), Vector2(x3 + w + size.y, 0), Vector2(x3 + size.y, 0)]).duplicate(), c2)
				on3 = not on3
				x3 += w
		4:    # two-tone
			draw_rect(Rect2(0, size.y * 0.5, size.x, size.y * 0.5), c2)
	draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)
