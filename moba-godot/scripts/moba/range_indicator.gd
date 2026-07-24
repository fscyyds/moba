extends Node2D
class_name RangeIndicator

## 防御塔攻击范围可视化 — 预警圈 + 危险圈 + 脉冲动画

# ===== 范围参数（从 TowerStats 读取）=====
var range_radius: float = 500.0
var warning_radius: float = 750.0

# ===== 敌方塔颜色 =====
@export var enemy_warn_color: Color = Color(1.0, 0.2, 0.2, 0.12)     # 预警：半透明红
@export var enemy_danger_fill: Color = Color(1.0, 0.1, 0.1, 0.25)     # 危险：填充
@export var enemy_danger_border: Color = Color(1.0, 0.05, 0.05, 0.5)  # 危险：边框
@export var ally_color: Color = Color(0.2, 0.6, 1.0, 0.08)            # 我方塔颜色

# ===== 动画参数 =====
@export var border_width: float = 2.5
@export var pulse_speed: float = 4.0
@export var fade_duration: float = 0.4
@export var dash_count: int = 48       # 虚线分段数

# ===== 内部状态 =====
var tower_team: String = ""
var player_hero: CharacterBody2D = null
var current_alpha: float = 0.0
var target_alpha: float = 0.0
var _is_danger: bool = false
var _show_impact_wave: bool = false
var _impact_wave_scale: float = 1.0
var _impact_wave_alpha: float = 0.0
var _just_entered_danger: bool = false


func setup(team: String, attack_range: float) -> void:
	tower_team = team
	range_radius = attack_range
	warning_radius = attack_range * 1.5
	# 找玩家英雄
	_find_player()


func _find_player() -> void:
	# 根据我方阵营找玩家英雄
	var player_team := "team_blue"  # 默认
	# 简单策略：蓝图找 HeroBlue，红图找 HeroRed
	for h in get_tree().get_nodes_in_group("heroes"):
		if h.is_in_group("team_blue"):
			player_hero = h; player_team = "team_blue"; break
	if not player_hero:
		for h in get_tree().get_nodes_in_group("heroes"):
			player_hero = h; player_team = h.get_groups()[0] if h.get_groups().size() > 0 else ""; break


func _process(_delta: float) -> void:
	if not player_hero or not is_instance_valid(player_hero):
		_find_player()
		if not player_hero:
			return

	var dist := global_position.distance_to(player_hero.global_position)
	var is_enemy := tower_team != "" and not player_hero.is_in_group(tower_team)
	var was_danger := _is_danger

	# 超出两倍预警范围 → 完全隐藏
	if dist > warning_radius * 2.0:
		target_alpha = 0.0
		_is_danger = false
	elif dist <= range_radius:
		target_alpha = 1.0
		_is_danger = true
	elif dist <= warning_radius:
		target_alpha = 0.55  # 预警状态
		_is_danger = false
	else:
		target_alpha = 0.0
		_is_danger = false

	# 平滑过渡
	current_alpha = move_toward(current_alpha, target_alpha, (1.0 / fade_duration) * _delta)

	# 进入危险范围的冲击波
	if _is_danger and not was_danger:
		_just_entered_danger = true
		_trigger_impact_wave()

	# 冲击波动画
	if _show_impact_wave:
		_impact_wave_scale += _delta * 3.0
		_impact_wave_alpha = max(0.0, _impact_wave_alpha - _delta * 2.5)
		if _impact_wave_alpha <= 0.0:
			_show_impact_wave = false

	# 只在需要时重绘
	queue_redraw()


func _trigger_impact_wave() -> void:
	_show_impact_wave = true
	_impact_wave_scale = 0.5
	_impact_wave_alpha = 0.7


func _draw() -> void:
	if current_alpha < 0.01: return
	var is_enemy := tower_team != "" and (not player_hero or not player_hero.is_in_group(tower_team))

	# 敌方/我方颜色
	var fill_c: Color
	var border_c: Color
	if is_enemy:
		if _is_danger:
			fill_c = enemy_danger_fill; fill_c.a *= current_alpha
			border_c = enemy_danger_border; border_c.a *= current_alpha
		else:
			fill_c = enemy_warn_color; fill_c.a *= current_alpha
			border_c = enemy_warn_color; border_c.a = current_alpha * 0.6
	else:
		fill_c = ally_color; fill_c.a *= current_alpha
		border_c = ally_color; border_c.a = current_alpha * 0.5

	# 危险时脉冲边框宽度
	var bw := border_width
	if _is_danger:
		var pulse := sin(Time.get_ticks_msec() * 0.001 * pulse_speed) * 0.5 + 0.5
		bw = border_width + pulse * 3.0

	# 填充圆
	draw_circle(Vector2.ZERO, range_radius, fill_c)

	# 虚线边框（分段画 arc）
	var step_angle := TAU / float(dash_count)
	for i in range(dash_count):
		if i % 2 == 0:  # 隔一段画一段（虚线效果）
			var angle_from := i * step_angle
			var angle_to := angle_from + step_angle * 0.7
			draw_arc(Vector2.ZERO, range_radius, angle_from, angle_to, 16, border_c, bw)

	# 冲击波
	if _show_impact_wave and _impact_wave_alpha > 0.01:
		var wave_c := Color(1.0, 0.3, 0.3, _impact_wave_alpha)
		var wave_r := range_radius * _impact_wave_scale
		draw_arc(Vector2.ZERO, wave_r, 0, TAU, 32, wave_c, 4.0)

	# 感叹号标记（进入预警时）
	if not _is_danger and current_alpha > 0.3 and is_enemy:
		var exclaim_c := Color(1.0, 0.2, 0.2, current_alpha * 1.5)
		_draw_exclamation(exclaim_c)

	# 双感叹号（进入危险时）
	if _is_danger and is_enemy:
		var exclaim_c := Color(1.0, 0.0, 0.0, current_alpha * 1.8)
		_draw_exclamation(exclaim_c)
		_draw_exclamation(exclaim_c, Vector2(12, 0))


func _draw_exclamation(color: Color, offset := Vector2(0, -range_radius - 20)) -> void:
	# 简化的 "!" 符号
	var p := offset
	draw_rect(Rect2(p + Vector2(-2, -8), Vector2(4, 12)), color)
	draw_circle(p + Vector2(0, 6), 2.5, color)
