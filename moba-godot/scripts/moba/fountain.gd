extends Area2D
class_name Fountain

## 泉水 — 友方回血，敌方秒杀

@export var heal_percent: float = 0.10
@export var enemy_damage: int = 2000
var heal_timer: float = 0.0
var team: String = "team_blue"


func _ready() -> void:
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)

func _process(delta: float) -> void:
	heal_timer += delta
	if heal_timer < 1.0: return
	heal_timer -= 1.0
	for b in get_overlapping_bodies():
		if b.is_in_group(team):
			if b.has_method("heal"):
				b.heal(int(b.get_max_hp() * heal_percent))
		else:
			if b.has_method("take_damage"):
				b.take_damage(enemy_damage)

func _on_enter(_b: Node2D) -> void: pass
func _on_exit(_b: Node2D) -> void: pass
