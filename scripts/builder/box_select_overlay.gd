extends Control
## Draws the rubber-band rectangle of a box selection (node "BoxSelectOverlay"). The builder tells it where the box is.

var rect := Rect2()


func show_box(r: Rect2) -> void:
	rect = r
	queue_redraw()


func _draw() -> void:
	if rect.size.length() < 1.0:
		return
	draw_rect(rect, Color(1.0, 0.8, 0.2, 0.12))
	draw_rect(rect, Color(1.0, 0.8, 0.2, 0.9), false, 1.5)
