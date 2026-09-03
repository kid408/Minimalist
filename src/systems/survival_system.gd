extends Node
class_name SurvivalSystem

# ============================================================================
# M3 生存目标系统
# 职责：单局倒计时、Boss 配额计数、死亡次数、威胁等级缩放、胜负判定、结算数据。
# 设计文档 §1：单局 = 30 分钟倒计时，期间击杀 Boss ≥ 5 且死亡 ≤ 3 即胜利；
#            时间耗尽未达标 / 死亡超过上限即失败。
# 备注：死亡触发「复活 + 计数」而非直接 game over；倒计时不因死亡暂停。
# ============================================================================

const Arena = preload("res://src/arena.gd")
const Enemy = preload("res://src/actors/enemy.gd")

# —— M3 配置（设计文档 §1.1，可被难度档位覆盖） ——
const SURVIVAL_TIME := 1800.0   # 30 分钟倒计时
const BOSS_QUOTA := 5           # Boss 击杀配额
const DEATH_LIMIT := 3          # 死亡次数上限

var arena: Arena

# —— 运行时状态 ——
var time_remaining := SURVIVAL_TIME
var bosses_killed := 0
var deaths := 0
var threat_tier := 1            # 1..4（设计 §1.3）
var phase := "running"          # running | win | lose
var result := ""                # win | lose

var _ended := false

func start() -> void:
	time_remaining = SURVIVAL_TIME
	bosses_killed = 0
	deaths = 0
	threat_tier = 1
	phase = "running"
	result = ""
	_ended = false

# 由 arena._process 手动驱动（已 set_process(false)，避免 Godot 自动回调导致重复计时）
func _process(delta: float) -> void:
	if _ended:
		return

	# 倒计时：死亡不暂停（死亡即损失时间，是最重的惩罚）
	time_remaining -= delta
	if time_remaining <= 0.0:
		time_remaining = 0.0
		_end_time_up()
		return

	# 威胁等级（按设计 §1.3：0-5 分钟 Lv.1 / 5-12 分钟 Lv.2 / 12-20 分钟 Lv.3 / 20-30 分钟 Lv.4）
	_update_threat()

# Boss 击杀上报（world_system 在击败 Boss 时调用）
func register_boss_kill() -> void:
	if _ended:
		return
	bosses_killed += 1
	if arena != null and is_instance_valid(arena) and is_instance_valid(arena.hud):
		arena.hud.set_message("击杀 Boss！进度 %d / %d" % [bosses_killed, BOSS_QUOTA])
	# 提前达标即可结算胜利（目标已达成，无需再熬时间）
	if bosses_killed >= BOSS_QUOTA and deaths <= DEATH_LIMIT:
		_finish("win")

# 玩家死亡上报，返回结算结果："lose" 表示本局结束；"" 表示继续（复活）
func register_death() -> String:
	deaths += 1
	if deaths > DEATH_LIMIT:
		_finish("lose")
		return "lose"
	return ""

func _end_time_up() -> void:
	if deaths > DEATH_LIMIT:
		_finish("lose")
	else:
		_finish("win")

func _finish(res: String) -> void:
	if _ended:
		return
	_ended = true
	phase = res
	result = res
	if arena != null and is_instance_valid(arena):
		arena._show_settlement(res)

# —— 威胁等级缩放（设计 §1.3「疯长」曲线） ——
# Lv.1 ×1.00  /  Lv.2 ×1.18  /  Lv.3 ×1.36  /  Lv.4 ×1.54
func _update_threat() -> void:
	var elapsed := SURVIVAL_TIME - time_remaining
	var tier := 1
	if elapsed >= 1200.0:
		tier = 4
	elif elapsed >= 720.0:
		tier = 3
	elif elapsed >= 300.0:
		tier = 2
	if tier != threat_tier:
		threat_tier = tier
		_apply_threat_scale()
		if arena != null and is_instance_valid(arena) and is_instance_valid(arena.hud):
			arena.hud.set_message("威胁等级提升至 Lv.%d，在场敌人已变强！" % threat_tier)

# 普通敌人属性缩放系数
func stat_scale() -> float:
	return 1.0 + float(threat_tier - 1) * 0.18

# Boss 额外 25% 强化
func boss_scale() -> float:
	return stat_scale() * 1.25

# 对当前在场存活敌人施加威胁增量缩放（新生成敌人由 world_system 在创建时直接读取 scale）
func _apply_threat_scale() -> void:
	if arena == null:
		return
	for child in arena.enemies_root.get_children():
		if child is Enemy and not (child as Enemy).is_dead():
			var e := child as Enemy
			var new_scale := stat_scale() if e.enemy_type != Enemy.EnemyType.BOSS else boss_scale()
			var applied := float(e.get_meta("threat_scale", 1.0))
			var ratio := new_scale / applied  # 仅按倍率差增量缩放，避免重复乘算
			e.max_hp = int(float(e.max_hp) * ratio)
			e.hp = minf(float(e.hp) * ratio, float(e.max_hp))
			e.set_meta("threat_scale", new_scale)
