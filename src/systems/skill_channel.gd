class_name SkillChannel
extends RefCounted

# ============================================================
# 引导状态机（计划 §5 / §3）
# ------------------------------------------------------------
# 把「站桩持续结算」的引导逻辑从 SkillEngine 抽离成独立状态机。
# 每 tick 通过 on_pulse 回调通知引擎结算一次；玩家移动超过容差或再次按键则打断。
# 引擎只需持有本对象并转发 start / update / interrupt。
# ============================================================

const MOVE_TOLERANCE := 14.0

var active := false
var def: Dictionary = {}
var dmg: float = 0.0
var left: float = 0.0
var timer: float = 0.0
var pulses_remaining: int = 0
var origin: Vector2 = Vector2.ZERO
var point: Vector2 = Vector2.ZERO

var on_pulse: Callable = Callable()      # (def, dmg, point, unit) -> void
var on_interrupt: Callable = Callable()  # (msg: String) -> void


func start(p_def: Dictionary, p_dmg: float, p_point: Vector2, p_origin: Vector2, p_on_pulse: Callable) -> void:
	if p_def.is_empty():
		return
	def = p_def
	dmg = p_dmg
	left = maxf(float(p_def.get("duration", 3.0)), 0.0)
	timer = 0.0
	var interval := maxf(0.1, float(p_def.get("tick_interval", 0.5)))
	pulses_remaining = maxi(1, ceili(left / interval))
	origin = p_origin
	point = p_point
	on_pulse = p_on_pulse
	active = true
	_pulse()
	pulses_remaining -= 1


func interrupt(msg := "") -> void:
	if not active:
		return
	active = false
	def = {}
	left = 0.0
	if on_interrupt.is_valid():
		on_interrupt.call(msg)


func is_active() -> bool:
	return active


func update(delta: float, player_pos: Vector2) -> void:
	if not active:
		return
	# 防御性检查：移动入口会立即打断，这里用于处理位移类效果或外部位移。
	if player_pos.distance_to(origin) > MOVE_TOLERANCE:
		interrupt("引导被移动打断！")
		return
	left = maxf(left - delta, 0.0)
	timer += delta
	var interval := maxf(0.1, float(def.get("tick_interval", 0.5)))
	while timer >= interval and pulses_remaining > 0:
		timer -= interval
		_pulse()
		pulses_remaining -= 1
	if left <= 0.0:
		interrupt("【%s】引导完成。" % def.get("name", "技能"))


func _pulse() -> void:
	if not active:
		return
	if on_pulse.is_valid():
		on_pulse.call(def, dmg, point, null)
