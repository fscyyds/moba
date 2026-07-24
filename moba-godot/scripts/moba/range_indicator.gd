extends Node2D
class_name RangeIndicator

## 防御塔攻击范围可视化 — 状态机 A/B/C/D
## 敌我判断：对比塔 team 和玩家 team，不硬编码颜色

enum IndicatorState { A_IDLE, B_WARNING, C_DANGER }

# ===== 范围参数 =====
var range_radius: float = 500.0
@export var warning_multiplier: float = 1.5

# ===== 敌方塔颜色（红色系，代表危险）=====
@export var enemy_warn_fill: Color = Color(1.0, 0.15, 0.15, 0.12)
@export var enemy_danger_fill: Color = Color(1.0, 0.1, 0.1, 0.35)
@export var enemy_border: Color = Color(1.0, 0.2, 0.2, 0.7)

# ===== 我方塔颜色（蓝绿色系，代表安全）=====
@export var ally_fill: Color = Color(0.15, 0.7, 0.55, 0.08)
@export var ally_border: Color = Color(0.25, 0.75, 0.6, 0.25)

# ===== 动画参数 =====
@export var border_width: float = 2.5
@export var dash_count: int = 32
@export var dash_ratio: float = 0.6
@export var warn_pulse: float = 2.5    # 预警呼吸速度
@export var danger_pulse: float = 6.0   # 危险闪烁速度
@export var fade_duration: float = 0.5  # 淡入淡出时间

# ===== 内部状态 =====
var current_state: IndicatorState = IndicatorState.A_IDLE
var current_alpha: float = 0.0
var target_alpha: float = 0.0
var time: float = 0.0
var is_enemy_tower: bool = false
var player_hero: CharacterBody2D = null
var tower_team: String = ""

# ===== 冲击波 =====
var shockwave_active: bool = false
var shockwave_radius: float = 0.0
var shockwave_alpha: float = 0.0


func setup(atk_range: float, team: String) -> void:
	range_radius = atk_range
	tower_team = team
	# 找玩家英雄
	for h in get_tree().get_nodes_in_group("heroes"):
		if h.is_in_group("team_blue"):
			player_hero = h; break
	if not player_hero:
		for h in get_tree().get_nodes_in_group("heroes"):
			player_hero = h; break
	# 判断敌我
	if player_hero:
		var pt: String = ""
		for g in player_hero.get_groups():
			if g.begins_with("team_"): pt = g; break
		is_enemy_tower = (tower_team != pt)
	visible = false


func _process(delta: float) -> void:
	if not player_hero or not is_instance_valid(player_hero):
		visible = false; return
	var es := player_hero.get_node_or_null("CharacterStats") as CharacterStats
	if es and es.is_dead:
		visible = false; return

	time += delta
	var dist := global_position.distance_to(player_hero.global_position)
	var wr := range_radius * warning_multiplier
	var prev := current_state

	# 状态判定
	if dist > wr * 2.0:
		current_state = IndicatorState.A_IDLE
		target_alpha = 0.0
	elif dist > range_radius:
		current_state = IndicatorState.B_WARNING
		target_alpha = 0.6
	elif dist <= range_radius:
		current_state = IndicatorState.C_DANGER
		target_alpha = 1.0

	# 平滑过渡
	current_alpha = move_toward(current_alpha, target_alpha, (1.0 / fade_duration) * delta)

	# 进入危险→冲击波
	if current_state == IndicatorState.C_DANGER and prev != IndicatorState.C_DANGER:
		_trigger_shockwave()

	# 更新告警图标和屏幕 vignette
	_update_alert()

	# 隐藏远处
	if current_state == IndicatorState.A_IDLE and current_alpha < 0.01:
		visible = false
	else:
		visible = true

	if current_state != IndicatorState.A_IDLE or shockwave_active:
		queue_redraw()


func _trigger_shockwave() -> void:
	shockwave_active = true
	shockwave_radius = range_radius * 0.3
	shockwave_alpha = 0.8
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "shockwave_radius", range_radius * 1.1, 0.4)
	tw.tween_property(self, "shockwave_alpha", 0.0, 0.4)
	tw.tween_callback(func(): shockwave_active = false).set_delay(0.4)


func _update_alert() -> void:
	var alert := get_node_or_null("../AlertIcon") as Label
	if not alert: return
	if not is_enemy_tower:
		alert.visible = false; return
	match current_state:
		IndicatorState.A_IDLE:
			alert.visible = false
		IndicatorState.B_WARNING:
			alert.visible = true; alert.text = "!"; alert.modulate = Color.YELLOW
		IndicatorState.C_DANGER:
			alert.visible = true; alert.text = "!!"
			var blink := sin(time * danger_pulse) * 0.5 + 0.5
			alert.modulate = Color(1.0, 0.0, 0.0, 0.3 + blink * 0.7)


func _draw() -> void:
	if current_alpha < 0.01 and not shockwave_active: return

	# 填充颜色
	var fill_c := enemy_warn_fill if is_enemy_tower else ally_fill
	if current_state == IndicatorState.C_DANGER and is_enemy_tower:
		fill_c = enemy_danger_fill
	fill_c.a *= current_alpha
	draw_circle(Vector2.ZERO, range_radius, fill_c)

	# 边框
	var border_c := enemy_border if is_enemy_tower else ally_border
	var pulse_spd := danger_pulse if current_state == IndicatorState.C_DANGER else warn_pulse
	var pulse := sin(time * pulse_spd) * 0.5 + 0.5
	border_c.a *= current_alpha * (0.5 + pulse * 0.5)

	if current_state == IndicatorState.C_DANGER:
		# 实线
		draw_arc(Vector2.ZERO, range_radius, 0, TAU, 64, border_c, border_width)
	else:
		# 虚线
		for i in range(dash_count):
			var a0 := float(i) * (TAU / dash_count)
			var a1 := a0 + (TAU / dash_count) * dash_ratio
			draw_arc(Vector2.ZERO, range_radius, a0, a1, 4, border_c, border_width)

	# 冲击波
	if shockwave_active and shockwave_alpha > 0.01:
		var sw := Color(1.0, 0.2, 0.2, shockwave_alpha)
		draw_arc(Vector2.ZERO, shockwave_radius, 0, TAU, 64, sw, 4.0)


## 塔被摧毁时调用
func play_destroy() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.5, 0.5), 0.4)
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free).set_delay(0.5)
