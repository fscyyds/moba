extends Control
class_name HealthBarUI

## 血条 UI — 角色头顶，宽60高8，蓝方绿/红方红

@onready var bar: ProgressBar = $ProgressBar

var stats: CharacterStats
var target_tween: Tween


func _ready() -> void:
	for child in get_parent().get_children():
		if child is CharacterStats:
			stats = child
			break
	if stats:
		stats.hp_changed.connect(_on_hp)
		stats.died.connect(_hide)
		stats.respawned.connect(_show)
		_on_hp(stats.current_hp, stats.max_hp)

func _on_hp(current: int, maximum: int) -> void:
	if target_tween and target_tween.is_valid():
		target_tween.kill()
	target_tween = create_tween()
	target_tween.tween_property(bar, "value", current, 0.2)
	bar.max_value = maximum

func _hide() -> void: visible = false
func _show() -> void: visible = true; _on_hp(stats.current_hp, stats.max_hp)
