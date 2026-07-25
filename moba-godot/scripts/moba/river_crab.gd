extends JungleMonster
class_name RiverCrab

## 河蟹 — 被攻击后逃跑，5秒脱战回血

@export var flee_speed: float = 300.0
@export var disengage_time: float = 5.0

var flee_dir: Vector2 = Vector2.RIGHT
var flee_timer: float = 0.0
var was_hit: bool = false


func _ready() -> void:
	super._ready()
	flee_dir = Vector2.RIGHT if randf() > 0.5 else Vector2.LEFT

func _physics_process(delta: float) -> void:
	if state == State.DEAD: return
	hit_flash = max(0.0, hit_flash - delta)
	_update_hp_bar()

	if was_hit and state != State.RETREAT:
		flee_timer += delta
		_flee(delta)

func _flee(_delta: float) -> void:
	if flee_timer > disengage_time:
		was_hit = false; flee_timer = 0.0
		current_hp = data.max_hp if data else 1500
		return
	# 沿河道方向逃
	velocity = flee_dir * flee_speed
	move_and_slide()
	# 撞墙回头
	if is_on_wall(): flee_dir = -flee_dir

func take_damage(dmg: int) -> void:
	if state == State.DEAD: return
	current_hp = max(current_hp - dmg, 0)
	hit_flash = 0.1
	was_hit = true; flee_timer = 0.0
	if current_hp <= 0: _die()
