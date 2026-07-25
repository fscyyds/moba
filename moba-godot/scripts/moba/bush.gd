extends Area2D
class_name Bush

## 草丛 — 进入隐身，攻击暴露1秒

@export var hide_alpha: float = 0.3

var heroes_inside: Array[CharacterBody2D] = []

func _ready() -> void:
	body_entered.connect(_enter)
	body_exited.connect(_exit)

func _enter(body: Node2D) -> void:
	if body.is_in_group("heroes"):
		body.modulate.a = hide_alpha
		heroes_inside.append(body)

func _exit(body: Node2D) -> void:
	if body.is_in_group("heroes"):
		body.modulate.a = 1.0
		heroes_inside.erase(body)

func alert_hero(hero: CharacterBody2D) -> void:
	if hero in heroes_inside:
		hero.modulate.a = 1.0
		await hero.get_tree().create_timer(1.0).timeout
		if hero in heroes_inside:
			hero.modulate.a = hide_alpha
