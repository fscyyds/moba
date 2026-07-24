extends Control
class_name ExpBar

## 经验条 + 等级标签 — 金色条 + "Lv.X"

@onready var bar: ProgressBar = $ProgressBar
@onready var label: Label = $LevelLabel

var level_sys: LevelSystem


func _ready() -> void:
	for child in get_parent().get_children():
		if child is LevelSystem:
			level_sys = child
			break
	if level_sys:
		level_sys.xp_changed.connect(_on_xp)
		level_sys.level_up.connect(_on_level)
		label.text = "Lv." + str(level_sys.level)

func _on_xp(current: int, to_next: int) -> void:
	bar.max_value = to_next
	bar.value = current

func _on_level(new_level: int) -> void:
	label.text = "Lv." + str(new_level)
	# 金色闪烁
	var tw := create_tween()
	tw.tween_property(label, "modulate", Color.GOLD, 0.15)
	tw.tween_property(label, "modulate", Color.WHITE, 0.15)
	# 飘字
	_spawn_float("Lv." + str(new_level))

func _spawn_float(text: String) -> void:
	var l := Label.new(); l.text = text
	l.add_theme_color_override("font_color", Color.GOLD)
	l.add_theme_font_size_override("font_size", 20)
	l.position = Vector2(-20, -60); add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position", l.position + Vector2(0, -35), 1.0)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)
