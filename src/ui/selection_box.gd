extends Node2D
# (无 class_name：仅由 Arena 通过 preload 实例化，避免与 Arena 内部同名类冲突)

# 在独立高 layer 的 CanvasLayer 上绘制框选矩形，避免被 HUD 层盖住。
# _world 矩形由所属 arena 提供，这里用相机 unproject 转成屏幕坐标再画。

var arena: Node2D = null

func _draw() -> void:
	if arena == null or not arena._is_dragging:
		return
	var box: Rect2 = arena._selection_box
	if box.size.length() <= 4.0:
		return
	# 世界坐标 → 屏幕坐标：用视口 canvas_transform（已含相机变换）
	var ct := get_viewport().canvas_transform
	var p1: Vector2 = ct * box.position
	var p2: Vector2 = ct * box.end
	var r := Rect2(p1, p2 - p1).abs()
	draw_rect(r, Color(0.3, 1.0, 0.5, 0.22), true)
	draw_rect(r, Color(0.4, 1.0, 0.6, 1.0), false, 2.0)
