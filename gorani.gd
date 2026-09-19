extends CharacterBody3D

# ==================================================
# GORANI AI v5 - PIVOT FIX
#
# 핵심 변경점
# 1) v4의 강제 도주(BREAK_AWAY)를 추격 중에는 사용하지 않음.
# 2) 플레이어가 옆/뒤를 잡으면 앞으로 멀리 도망가는 대신,
#    속도를 급격히 줄이고 거의 제자리에서 몸을 돌려 정면을 다시 만든다.
# 3) 정면이 잡히는 즉시 다시 추격하거나 가까우면 돌진한다.
# 4) 빠를수록 일반 추격 회전 반경이 커지는 성질은 유지.
# 5) 돌진은 방향 커밋 + 실패 시 오버슈트 유지.
# 6) 몸/옆구리 접촉 즉사 판정 유지.
# 7) 나무 뒤 시야 판정은 없음. 기존처럼 거리만으로 첫 조우함.
# ==================================================

enum State {
	IDLE,
	TURN,
	STARE,
	SCREAM,
	CHASE,
	BREAK_AWAY,
	REORIENT,
	LUNGE,
	OVERSHOOT
}

# ==================================================
# 첫 조우
# ==================================================

@export var detect_distance: float = 12.0
@export var turn_time: float = 0.7
@export var stare_time: float = 1.3
@export var scream_pause: float = 0.25
@export var encounter_turn_speed: float = 3.5

# ==================================================
# 추격 기본값
# ==================================================

@export var chase_start_speed: float = 3.2
@export var chase_max_speed: float = 7.25
@export var chase_corner_speed: float = 3.2
@export var chase_acceleration: float = 7.0
@export var chase_deceleration: float = 10.0

# 저속일 때는 잘 돌고, 고속일 때는 크게 돌아야 생물처럼 보임.
@export var chase_turn_low_speed: float = 4.8
@export var chase_turn_high_speed: float = 2.0
@export var sharp_turn_angle: float = 100.0

@export var return_distance: float = 30.0

# ==================================================
# 플레이어 예측 추격
# ==================================================

@export var prediction_time: float = 0.35
@export var max_prediction_distance: float = 1.6
@export var player_velocity_smoothing: float = 4.5
@export var target_smoothing: float = 5.0
@export var target_refresh_interval: float = 0.18

# 완벽한 직선 추적을 피하기 위한 작은 접근 편향.
# 프레임마다 랜덤이 아니라 한동안 같은 방향을 유지한다.
@export var approach_bias_min: float = 0.30
@export var approach_bias_max: float = 0.85
@export var approach_bias_change_min: float = 0.9
@export var approach_bias_change_max: float = 1.6

# 미세한 속도 변화. 너무 크게 잡으면 술 취한 것처럼 보임.
@export var pace_change_min: float = 1.0
@export var pace_change_max: float = 2.0
@export var pace_min: float = 0.94
@export var pace_max: float = 1.02

# ==================================================
# 초근접 / 옆구리 exploit 방지
# ==================================================

# 플레이어가 고라니 몸통 안으로 비비고 들어오면
# 정면 공격 각도와 무관하게 접촉으로 사망 처리한다.
# 로컬 좌표 기준의 몸통 직사각형 범위.
@export var body_kill_half_width: float = 0.95
@export var body_kill_front: float = 1.35
@export var body_kill_back: float = 1.25
@export var body_kill_vertical_tolerance: float = 1.8

# 바로 옆/뒤에 너무 가까이 붙으면 기다리지 않고 즉시 앞으로 튄다.
@export var flank_escape_distance: float = 2.6
@export var flank_escape_angle: float = 62.0

# 조금 더 먼 후방은 짧게 확인한 뒤 이탈.
@export var rear_escape_distance: float = 4.2
@export var rear_escape_angle: float = 105.0
@export var rear_escape_hold_time: float = 0.08

# BREAK_AWAY는 플레이어를 향해 돌지 않고 현재 정면으로 직선 질주한다.
@export var breakaway_clear_distance: float = 4.0
@export var breakaway_min_duration: float = 0.42
@export var breakaway_max_duration: float = 0.95
@export var breakaway_speed: float = 9.0
@export var breakaway_acceleration: float = 18.0
@export var breakaway_cooldown_time: float = 0.65

# ==================================================
# v4 근접 압박 / 강강술래 방지
#
# ★ v4_ 접두사를 일부러 붙였다.
# Godot Inspector가 예전 export 값을 보존해도 이 값들은 새 기본값으로 들어간다.
# ==================================================

# 이 거리 안에서는 "플레이어를 향해 계속 회전"하는 추격 자체를 금지한다.
# 플레이어가 정면 공격각에 있으면 돌진, 아니면 무조건 거리 확보.
@export var v4_close_pressure_distance: float = 3.8

# 약간 더 먼 옆/뒤도 탈출하게 만드는 2차 안전망.
@export var v4_rear_pressure_distance: float = 5.2
@export var v4_rear_pressure_angle: float = 78.0

# 몸에 사실상 붙은 플레이는 방향과 무관하게 접촉 위험으로 취급.
@export var v4_contact_kill_radius: float = 1.35

# BREAK_AWAY는 한 번 시작하면 충분히 멀어질 때까지 끝내지 않는다.
@export var v4_breakaway_target_distance: float = 8.0
@export var v4_breakaway_clear_distance: float = 6.0
@export var v4_breakaway_min_duration: float = 0.72
@export var v4_breakaway_max_leg_duration: float = 1.35
@export var v4_breakaway_speed: float = 9.4
@export var v4_breakaway_acceleration: float = 20.0
@export var v4_breakaway_turn_speed: float = 3.2

# 탈출 방향 = 플레이어 반대 방향이 주성분 + 현재 전방을 약간 섞음.
# 그래서 옆구리에 붙었을 때 제자리 U턴하지 않고 대각선으로 빠져나감.
@export var v4_escape_away_weight: float = 1.0
@export var v4_escape_forward_weight: float = 0.35

# ==================================================
# 다시 몸 돌리기
# ==================================================

@export var reorient_speed: float = 2.7
@export var reorient_turn_speed: float = 3.1
@export var reorient_duration: float = 1.0
@export var reorient_exit_angle: float = 38.0
@export var reorient_min_time: float = 0.18

# ==================================================
# v5 PIVOT - 엉덩이 강강술래 해결
# ==================================================

# 이 거리 안에서 플레이어가 옆/뒤에 있으면 달리며 원을 그리지 않고 PIVOT.
@export var v5_pivot_distance: float = 4.4
@export var v5_pivot_angle: float = 52.0

# PIVOT 중에는 이동 속도를 거의 0까지 죽이고 몸만 빠르게 돌린다.
@export var v5_pivot_move_speed: float = 0.35
@export var v5_pivot_deceleration: float = 18.0
@export var v5_pivot_turn_speed: float = 9.0

# 이 정도로 플레이어를 정면에 잡으면 PIVOT 종료.
@export var v5_pivot_exit_angle: float = 28.0
@export var v5_pivot_min_time: float = 0.07
@export var v5_pivot_max_time: float = 0.65

# PIVOT이 끝났을 때 충분히 가까우면 바로 돌진.
@export var v5_pivot_attack_distance: float = 3.25

# ==================================================
# 공격
# ==================================================

@export var attack_distance: float = 3.1
@export var attack_angle: float = 28.0

# 초근접이라고 180도 자동공격하지 않음.
# 앞/앞옆에 있을 때만 긴급 돌진 가능.
@export var emergency_attack_distance: float = 1.75
@export var emergency_attack_angle: float = 55.0
@export var attack_cooldown_time: float = 0.80

# ==================================================
# 돌진
# ==================================================

@export var lunge_speed: float = 8.3
@export var lunge_duration: float = 0.44
@export var lunge_prediction_time: float = 0.18
@export var lunge_max_prediction_distance: float = 0.9

# 돌진 실패 후 바로 U턴하지 않고 그대로 지나감.
@export var overshoot_duration: float = 0.36
@export var overshoot_end_speed: float = 4.2
@export var overshoot_deceleration: float = 12.0

# ==================================================
# 공격 판정
# ==================================================

@export var attack_cast_height: float = 1.0
@export var attack_cast_length: float = 1.8
@export var attack_cast_radius: float = 0.70
@export var death_trigger_distance: float = 1.25

# ==================================================
# 몸 기울기
# ==================================================

@export var max_lean_degrees: float = 6.0
@export var lean_speed: float = 4.5
@export var lean_direction: float = 1.0

# ==================================================
# 발굽
# ==================================================

const HOOF_SOUNDS = [
	preload("res://audio/gorani/hoof/hoof_run_01.wav"),
	preload("res://audio/gorani/hoof/hoof_run_02.wav"),
	preload("res://audio/gorani/hoof/hoof_run_03.wav"),
	preload("res://audio/gorani/hoof/hoof_run_04.wav"),
	preload("res://audio/gorani/hoof/hoof_run_05.wav"),
	preload("res://audio/gorani/hoof/hoof_run_06.wav")
]

# ==================================================
# 노드
# ==================================================

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var scream_audio: AudioStreamPlayer3D = $ScreamAudio
@onready var hoof_audio: AudioStreamPlayer3D = $HoofAudio
@onready var visual: Node3D = $Visual
@onready var animation_player: AnimationPlayer = $Visual/Skeletal_Base_Mesh/Character/AnimationPlayer

# ==================================================
# 내부 변수
# ==================================================

var player: CharacterBody3D = null
var skeleton: Skeleton3D = null
var attack_cast: ShapeCast3D = null

var state: int = State.IDLE
var state_elapsed: float = 0.0
var state_timer: float = 0.0

var current_speed: float = 0.0
var current_move_direction: Vector3 = Vector3.ZERO

var smoothed_player_velocity: Vector3 = Vector3.ZERO
var smoothed_target_position: Vector3 = Vector3.ZERO
var target_refresh_timer: float = 0.0

var approach_bias_timer: float = 0.0
var approach_bias_amount: float = 0.0
var approach_bias_sign: float = 1.0

var pace_timer: float = 0.0
var pace_multiplier: float = 1.0

var rear_hold_timer: float = 0.0
var breakaway_cooldown: float = 0.0
var breakaway_target_position: Vector3 = Vector3.ZERO
var breakaway_direction: Vector3 = Vector3.ZERO

var lunge_direction: Vector3 = Vector3.ZERO
var attack_cooldown: float = 0.0

var has_killed_player: bool = false

var gravity: float = float(
	ProjectSettings.get_setting("physics/3d/default_gravity")
)

# ==================================================
# 애니메이션 이름
# ==================================================

var anim_idle: StringName = ""
var anim_run: StringName = ""
var anim_sight: StringName = ""
var anim_attack: StringName = ""

# ==================================================
# 시작
# ==================================================

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D

	if player == null:
		print("ERROR: PLAYER NOT FOUND")
	else:
		print("GORANI AI v4 READY")
		smoothed_target_position = player.global_position

	skeleton = _find_skeleton($Visual/Skeletal_Base_Mesh)
	if skeleton == null:
		print("WARNING: Skeleton3D NOT FOUND")

	_find_animations()

	navigation_agent.path_desired_distance = 0.8
	navigation_agent.target_desired_distance = 1.0
	navigation_agent.simplify_path = true
	navigation_agent.simplify_epsilon = 0.20

	_setup_attack_cast()

	_reset_approach_bias()
	_reset_pace()

	animation_player.speed_scale = 1.0
	_play_anim(anim_idle)

# ==================================================
# 메인 AI
# ==================================================

func _physics_process(delta: float) -> void:
	if player == null:
		return

	state_elapsed += delta
	_update_timers(delta)
	_update_player_motion(delta)

	if has_killed_player:
		velocity = Vector3.ZERO
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var distance_to_player: float = to_player.length()
	var angle_to_player: float = _get_angle_to_player()

	# 몸통에 붙어 비비는 플레이는 공격 각도 계산 전에 처리한다.
	# 실제 슬라이드 충돌 판정은 move_and_slide() 뒤에서도 한 번 더 검사한다.
	if _check_body_proximity_kill():
		return

	match state:
		State.IDLE:
			_idle_update(delta, distance_to_player)

		State.TURN:
			_turn_update(delta)

		State.STARE:
			_stare_update(delta)

		State.SCREAM:
			_scream_update(delta)

		State.CHASE:
			if distance_to_player > return_distance:
				_enter_idle()
			else:
				_chase_state_update(delta, distance_to_player, angle_to_player)

		State.BREAK_AWAY:
			_breakaway_update(delta)

		State.REORIENT:
			_reorient_update(delta)

		State.LUNGE:
			_lunge_update(delta)

		State.OVERSHOOT:
			_overshoot_update(delta)

	move_and_slide()

	_check_body_collision()

	# v4에서는 BREAK_AWAY가 고정 탈출 목표 + NavMesh를 사용하므로
	# 나무에 한 번 스쳤다고 바로 REORIENT하지 않는다.
	# 가까운 플레이어 앞에서 다시 몸을 돌며 원을 그리는 현상을 막기 위함.

# ==================================================
# 공통 타이머 / 플레이어 속도
# ==================================================

func _update_timers(delta: float) -> void:
	if attack_cooldown > 0.0:
		attack_cooldown = maxf(0.0, attack_cooldown - delta)

	if breakaway_cooldown > 0.0:
		breakaway_cooldown = maxf(0.0, breakaway_cooldown - delta)

	approach_bias_timer -= delta
	if approach_bias_timer <= 0.0:
		_reset_approach_bias()

	pace_timer -= delta
	if pace_timer <= 0.0:
		_reset_pace()

func _update_player_motion(delta: float) -> void:
	var raw_velocity: Vector3 = player.velocity
	raw_velocity.y = 0.0

	var weight: float = 1.0 - exp(-player_velocity_smoothing * delta)
	smoothed_player_velocity = smoothed_player_velocity.lerp(raw_velocity, weight)

func _reset_approach_bias() -> void:
	approach_bias_timer = randf_range(
		approach_bias_change_min,
		approach_bias_change_max
	)
	approach_bias_amount = randf_range(approach_bias_min, approach_bias_max)
	approach_bias_sign = -1.0 if randf() < 0.5 else 1.0

func _reset_pace() -> void:
	pace_timer = randf_range(pace_change_min, pace_change_max)
	pace_multiplier = randf_range(pace_min, pace_max)

# ==================================================
# IDLE / 첫 조우
# ==================================================

func _idle_update(delta: float, distance_to_player: float) -> void:
	_stop_horizontal()
	current_speed = 0.0
	current_move_direction = Vector3.ZERO
	rear_hold_timer = 0.0
	hoof_audio.stop()
	animation_player.speed_scale = 1.0
	_update_lean(0.0, delta)
	_play_anim(anim_idle)

	# 시야 가림 판정 없음. 기존처럼 거리만 봄.
	if distance_to_player <= detect_distance:
		_change_state(State.TURN)
		state_timer = turn_time
		_play_anim(anim_sight)

func _turn_update(delta: float) -> void:
	_stop_horizontal()
	_face_position(player.global_position, encounter_turn_speed, delta)
	state_timer -= delta

	if state_timer <= 0.0:
		_change_state(State.STARE)
		state_timer = stare_time

func _stare_update(delta: float) -> void:
	_stop_horizontal()
	_face_position(player.global_position, encounter_turn_speed, delta)
	state_timer -= delta

	if state_timer <= 0.0:
		_change_state(State.SCREAM)
		state_timer = scream_pause
		scream_audio.play()

func _scream_update(delta: float) -> void:
	_stop_horizontal()
	_face_position(player.global_position, encounter_turn_speed, delta)
	state_timer -= delta

	if state_timer <= 0.0:
		_enter_chase(true)

# ==================================================
# CHASE
# ==================================================

func _enter_chase(point_toward_player: bool = false) -> void:
	_change_state(State.CHASE)
	target_refresh_timer = 0.0
	rear_hold_timer = 0.0

	if point_toward_player:
		var direction: Vector3 = player.global_position - global_position
		direction.y = 0.0
		if direction.length() > 0.01:
			current_move_direction = direction.normalized()
	else:
		current_move_direction = _get_forward()

	current_speed = maxf(current_speed, chase_start_speed)
	_play_anim(anim_run)

func _chase_state_update(
	delta: float,
	distance_to_player: float,
	angle_to_player: float
) -> void:
	# ==================================================
	# v5 핵심
	#
	# 가까운 플레이어가 옆/뒤에 있으면 "도망"도 하지 않고
	# "달리면서 회전"도 하지 않는다.
	# 속도를 죽인 뒤 REORIENT 상태를 PIVOT처럼 사용한다.
	# ==================================================

	# 정면에 제대로 들어오면 바로 공격.
	if attack_cooldown <= 0.0:
		if distance_to_player <= emergency_attack_distance \
		and angle_to_player <= emergency_attack_angle:
			_enter_lunge()
			return

		if distance_to_player <= attack_distance \
		and angle_to_player <= attack_angle:
			_enter_lunge()
			return

	# 옆/뒤 근접 = 제자리 피벗.
	# 절대 BREAK_AWAY로 보내지 않는다.
	if distance_to_player <= v5_pivot_distance \
	and angle_to_player >= v5_pivot_angle:
		_enter_reorient()
		_reorient_update(delta)
		return

	# 일반 추격.
	_navigation_chase(delta, distance_to_player)

	# 이동 후 각도가 정면으로 들어왔으면 공격.
	var new_angle: float = _get_angle_to_player()

	if attack_cooldown <= 0.0:
		if distance_to_player <= emergency_attack_distance \
		and new_angle <= emergency_attack_angle:
			_enter_lunge()
			return

		if distance_to_player <= attack_distance \
		and new_angle <= attack_angle:
			_enter_lunge()
			return


func _navigation_chase(delta: float, distance_to_player: float) -> void:
	# 플레이어의 짧은 미래 위치 예측
	var prediction: Vector3 = smoothed_player_velocity * prediction_time
	if prediction.length() > max_prediction_distance:
		prediction = prediction.normalized() * max_prediction_distance

	var raw_target: Vector3 = player.global_position + prediction

	# 멀리 있을 때만 아주 조금 옆에서 들어오는 성향을 줌.
	# 가까워질수록 0으로 사라져서 공격 정밀도는 유지.
	var to_target: Vector3 = raw_target - global_position
	to_target.y = 0.0

	if to_target.length() > 0.01:
		var dir_to_target: Vector3 = to_target.normalized()
		var lateral: Vector3 = Vector3(-dir_to_target.z, 0.0, dir_to_target.x)
		var bias_strength: float = clampf((distance_to_player - 4.0) / 8.0, 0.0, 1.0)
		raw_target += lateral * approach_bias_amount * approach_bias_sign * bias_strength

	var target_weight: float = 1.0 - exp(-target_smoothing * delta)
	smoothed_target_position = smoothed_target_position.lerp(raw_target, target_weight)

	target_refresh_timer -= delta
	if target_refresh_timer <= 0.0:
		target_refresh_timer = target_refresh_interval
		navigation_agent.target_position = smoothed_target_position

	var desired_direction: Vector3 = _get_navigation_direction(smoothed_target_position)
	if desired_direction.length() <= 0.01:
		_stop_horizontal()
		return

	var forward: Vector3 = _get_forward()
	var turn_angle: float = _angle_between_flat(forward, desired_direction)

	# --------------------------------------------------
	# 속도가 빠를수록 회전이 둔해짐.
	# 급커브에서는 먼저 감속하고 크게 돈다.
	# --------------------------------------------------
	var turn_ratio: float = clampf(turn_angle / sharp_turn_angle, 0.0, 1.0)
	var target_speed: float = lerpf(
		chase_max_speed * pace_multiplier,
		chase_corner_speed,
		turn_ratio
	)

	if turn_angle > 145.0:
		target_speed = minf(target_speed, 2.3)

	if current_speed < target_speed:
		current_speed = move_toward(
			current_speed,
			target_speed,
			chase_acceleration * delta
		)
	else:
		current_speed = move_toward(
			current_speed,
			target_speed,
			chase_deceleration * delta
		)

	var speed_ratio: float = clampf(current_speed / chase_max_speed, 0.0, 1.0)
	var turn_speed: float = lerpf(
		chase_turn_low_speed,
		chase_turn_high_speed,
		speed_ratio
	)

	_face_direction(desired_direction, turn_speed, delta)

	# 실제 이동은 몸 정면으로만. 옆으로 미끄러지는 NPC 느낌을 줄임.
	forward = _get_forward()
	current_move_direction = forward
	velocity.x = forward.x * current_speed
	velocity.z = forward.z * current_speed

	_play_anim(anim_run)
	animation_player.speed_scale = lerpf(0.78, 1.10, speed_ratio)
	_update_hoof_sound()
	_update_turn_lean(desired_direction, delta)

# ==================================================
# BREAK_AWAY
# ==================================================

func _enter_breakaway() -> void:
	_change_state(State.BREAK_AWAY)
	rear_hold_timer = 0.0
	breakaway_cooldown = breakaway_cooldown_time
	attack_cooldown = maxf(attack_cooldown, 0.25)

	_choose_v4_breakaway_target()

	current_speed = maxf(current_speed, 6.2)
	current_move_direction = breakaway_direction
	_play_anim(anim_run)

func _choose_v4_breakaway_target() -> void:
	var away: Vector3 = global_position - player.global_position
	away.y = 0.0

	if away.length() <= 0.01:
		away = _get_forward()
	else:
		away = away.normalized()

	var forward: Vector3 = _get_forward()

	# 플레이어에게서 멀어지는 성분을 가장 크게 잡고,
	# 현재 전진 관성을 조금 섞어서 순간 180도 스냅을 막는다.
	var escape: Vector3 = (
		away * v4_escape_away_weight
		+ forward * v4_escape_forward_weight
	)
	escape.y = 0.0

	if escape.length() <= 0.01:
		escape = away
	else:
		escape = escape.normalized()

	breakaway_direction = escape
	breakaway_target_position = (
		global_position
		+ breakaway_direction * v4_breakaway_target_distance
	)

	# 플레이어가 아니라 고정된 탈출 지점을 NavMesh 목표로 잡는다.
	# 탈출 중 플레이어가 빙빙 돌아도 목표점은 따라 돌지 않는다.
	navigation_agent.target_position = breakaway_target_position
	target_refresh_timer = target_refresh_interval

func _breakaway_update(delta: float) -> void:
	current_speed = move_toward(
		current_speed,
		v4_breakaway_speed,
		v4_breakaway_acceleration * delta
	)

	# 플레이어를 추적하지 않고, 처음 정한 "탈출 지점"으로만 간다.
	# NavMesh는 나무를 피하기 위한 용도로만 사용한다.
	var nav_direction: Vector3 = _get_navigation_direction(
		breakaway_target_position
	)

	if nav_direction.length() > 0.01:
		var steer_weight: float = 1.0 - exp(
			-v4_breakaway_turn_speed * delta
		)
		breakaway_direction = breakaway_direction.lerp(
			nav_direction,
			steer_weight
		)
		breakaway_direction.y = 0.0
		if breakaway_direction.length() > 0.01:
			breakaway_direction = breakaway_direction.normalized()

	velocity.x = breakaway_direction.x * current_speed
	velocity.z = breakaway_direction.z * current_speed
	_face_direction(breakaway_direction, v4_breakaway_turn_speed, delta)

	_play_anim(anim_run)
	animation_player.speed_scale = 1.12
	_update_hoof_sound()
	_update_lean(0.0, delta)

	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var player_distance: float = to_player.length()

	# 충분한 시간 + 충분한 거리, 둘 다 만족해야 다시 몸을 돌린다.
	if state_elapsed >= v4_breakaway_min_duration \
	and player_distance >= v4_breakaway_clear_distance:
		_enter_reorient()
		return

	# 플레이어가 계속 따라붙는다면 REORIENT로 가지 않는다.
	# 새로운 탈출 지점을 잡고 한 번 더 빠져나간다.
	if state_elapsed >= v4_breakaway_max_leg_duration:
		if player_distance < v4_breakaway_clear_distance:
			_change_state(State.BREAK_AWAY)
			_choose_v4_breakaway_target()
			return

		_enter_reorient()


# ==================================================
# REORIENT
# ==================================================

func _enter_reorient() -> void:
	# v5에서는 REORIENT를 사실상 'PIVOT' 상태로 사용한다.
	# 플레이어에게서 멀어지지 않고, 제자리에서 정면만 다시 만든다.
	if state != State.REORIENT:
		_change_state(State.REORIENT)

	current_speed = minf(current_speed, 2.2)
	_play_anim(anim_run)


func _reorient_update(delta: float) -> void:
	var to_player_now: Vector3 = player.global_position - global_position
	to_player_now.y = 0.0

	if to_player_now.length() <= 0.01:
		_stop_horizontal()
		return

	var player_distance: float = to_player_now.length()
	var desired: Vector3 = to_player_now.normalized()

	# --------------------------------------------------
	# 핵심: 회전 중 앞으로 달리지 않는다.
	# 기존 강강술래는 '전진 + 회전' 때문에 생겼다.
	# --------------------------------------------------
	current_speed = move_toward(
		current_speed,
		v5_pivot_move_speed,
		v5_pivot_deceleration * delta
	)

	_face_direction(
		desired,
		v5_pivot_turn_speed,
		delta
	)

	# 몸이 향하는 정면으로 아주 조금만 전진.
	# 거의 제자리 회전이라 플레이어와 같은 원을 만들지 않는다.
	var forward: Vector3 = _get_forward()
	current_move_direction = forward

	velocity.x = forward.x * current_speed
	velocity.z = forward.z * current_speed

	_play_anim(anim_run)

	# 달리기 애니가 너무 빠르게 재생되지 않게 억제.
	animation_player.speed_scale = 0.52

	if current_speed > 1.1:
		_update_hoof_sound()
	else:
		hoof_audio.stop()

	_update_turn_lean(desired, delta)

	var angle_to_player: float = _get_angle_to_player()

	# 정면이 잡혔고 충분히 가까우면 피벗에서 바로 돌진.
	if state_elapsed >= v5_pivot_min_time \
	and angle_to_player <= v5_pivot_exit_angle:
		if attack_cooldown <= 0.0 \
		and player_distance <= v5_pivot_attack_distance:
			_enter_lunge()
			return

		_enter_chase(false)
		return

	# 플레이어가 계속 빙빙 돌아도 무한 PIVOT은 하지 않음.
	# 일정 시간이 지나면 현재 정면을 기준으로 다시 추격해서 압박한다.
	if state_elapsed >= v5_pivot_max_time:
		_enter_chase(false)


# ==================================================
# LUNGE - 방향 커밋
# ==================================================

func _enter_lunge() -> void:
	if state == State.LUNGE:
		return

	_change_state(State.LUNGE)
	rear_hold_timer = 0.0
	hoof_audio.stop()
	animation_player.speed_scale = 1.0

	# 돌진 시작 순간의 짧은 미래 위치만 잡고, 이후에는 재조준하지 않는다.
	var prediction: Vector3 = smoothed_player_velocity * lunge_prediction_time
	if prediction.length() > lunge_max_prediction_distance:
		prediction = prediction.normalized() * lunge_max_prediction_distance

	var attack_target: Vector3 = player.global_position + prediction
	lunge_direction = attack_target - global_position
	lunge_direction.y = 0.0

	if lunge_direction.length() <= 0.01:
		lunge_direction = _get_forward()
	else:
		lunge_direction = lunge_direction.normalized()

	# 공격 자체가 정면 조건을 통과했으므로 큰 스냅 회전은 필요 없음.
	_face_direction(lunge_direction, 9.0, 0.08)

	current_speed = lunge_speed
	_play_anim(anim_attack)
	_update_lean(0.0, 0.08)

func _lunge_update(delta: float) -> void:
	# 여기서 플레이어 위치로 lunge_direction을 갱신하지 않는다.
	# 즉, 플레이어가 옆으로 피하면 고라니는 지나친다.
	velocity.x = lunge_direction.x * lunge_speed
	velocity.z = lunge_direction.z * lunge_speed

	_face_direction(lunge_direction, 6.0, delta)
	_update_lean(0.0, delta)

	_check_attack_cast()

	if state_elapsed >= lunge_duration:
		_enter_overshoot()

# ==================================================
# OVERSHOOT - 공격 실패 후 그대로 지나가기
# ==================================================

func _enter_overshoot() -> void:
	_change_state(State.OVERSHOOT)
	attack_cooldown = attack_cooldown_time
	current_speed = lunge_speed

func _overshoot_update(delta: float) -> void:
	current_speed = move_toward(
		current_speed,
		overshoot_end_speed,
		overshoot_deceleration * delta
	)

	velocity.x = lunge_direction.x * current_speed
	velocity.z = lunge_direction.z * current_speed
	_face_direction(lunge_direction, 4.0, delta)
	_update_lean(0.0, delta)

	if state_elapsed >= overshoot_duration:
		_enter_reorient()

# ==================================================
# Navigation 방향 얻기
# ==================================================

func _get_navigation_direction(fallback_target: Vector3) -> Vector3:
	var desired_direction: Vector3

	if navigation_agent.is_navigation_finished():
		desired_direction = fallback_target - global_position
	else:
		var next_position: Vector3 = navigation_agent.get_next_path_position()
		desired_direction = next_position - global_position

	desired_direction.y = 0.0

	if desired_direction.length() <= 0.01:
		return Vector3.ZERO

	return desired_direction.normalized()

# ==================================================
# 공격 ShapeCast
# ==================================================

func _setup_attack_cast() -> void:
	attack_cast = ShapeCast3D.new()
	attack_cast.name = "AttackCast"
	attack_cast.position = Vector3(0.0, attack_cast_height, 0.0)

	var attack_shape := SphereShape3D.new()
	attack_shape.radius = attack_cast_radius
	attack_cast.shape = attack_shape
	attack_cast.target_position = Vector3(0.0, 0.0, -attack_cast_length)
	attack_cast.collide_with_bodies = true
	attack_cast.collide_with_areas = false
	attack_cast.exclude_parent = true
	attack_cast.enabled = true
	attack_cast.max_results = 16

	if player != null:
		var player_layers: int = player.collision_layer
		if player_layers == 0:
			player_layers = 1
		attack_cast.collision_mask = player_layers

	add_child(attack_cast)

func _check_attack_cast() -> void:
	if attack_cast == null or has_killed_player:
		return

	attack_cast.force_shapecast_update()
	if not attack_cast.is_colliding():
		return

	for i in range(attack_cast.get_collision_count()):
		var collider: Object = attack_cast.get_collider(i)

		if _collider_is_player(collider):
			var to_player: Vector3 = player.global_position - global_position
			to_player.y = 0.0

			if to_player.length() <= death_trigger_distance:
				_kill_player()
			return

# ==================================================
# 몸 충돌 공격 판정
# ==================================================

func _check_body_collision() -> void:
	if has_killed_player or not _is_hostile_state():
		return

	for i in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(i)
		if _collider_is_player(collision.get_collider()):
			_kill_player()
			return

# 모델 몸통 바로 옆에 붙어서 collision shape의 빈틈을 비비는 경우까지 잡는
# 작은 로컬 몸통 판정. 공격 방향과 상관없이 적용한다.
func _check_body_proximity_kill() -> bool:
	if has_killed_player or not _is_hostile_state():
		return false

	# v4: 모델 원점/CollisionShape가 약간 어긋나 있어도
	# 몸에 사실상 붙은 플레이어는 접촉 위험으로 처리한다.
	var horizontal: Vector3 = player.global_position - global_position
	horizontal.y = 0.0
	if horizontal.length() <= v4_contact_kill_radius:
		_kill_player()
		return true

	var vertical_gap: float = absf(
		player.global_position.y - global_position.y
	)
	if vertical_gap > body_kill_vertical_tolerance:
		return false

	var local_player: Vector3 = to_local(player.global_position)

	var inside_width: bool = absf(local_player.x) <= body_kill_half_width
	var inside_length: bool = (
		local_player.z >= -body_kill_front
		and local_player.z <= body_kill_back
	)

	if inside_width and inside_length:
		_kill_player()
		return true

	return false

func _is_hostile_state() -> bool:
	return state == State.CHASE \
	or state == State.BREAK_AWAY \
	or state == State.REORIENT \
	or state == State.LUNGE \
	or state == State.OVERSHOOT

func _collider_is_player(collider: Object) -> bool:
	if collider == player:
		return true

	if collider is Node:
		var node := collider as Node
		if node.is_in_group("player"):
			return true

	return false

func _hit_world_this_frame() -> bool:
	for i in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(i)
		var collider: Object = collision.get_collider()
		var normal: Vector3 = collision.get_normal()

		# 바닥 접촉은 장애물 충돌로 취급하지 않음.
		if normal.y > 0.60:
			continue

		if collider != player:
			return true
	return false

# ==================================================
# 방향 / 각도
# ==================================================

func _get_forward() -> Vector3:
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	if forward.length() <= 0.01:
		return Vector3.FORWARD
	return forward.normalized()

func _get_angle_to_player() -> float:
	var direction: Vector3 = player.global_position - global_position
	direction.y = 0.0
	if direction.length() <= 0.01:
		return 0.0
	return _angle_between_flat(_get_forward(), direction.normalized())

func _angle_between_flat(a: Vector3, b: Vector3) -> float:
	var aa := a
	var bb := b
	aa.y = 0.0
	bb.y = 0.0

	if aa.length() <= 0.01 or bb.length() <= 0.01:
		return 0.0

	aa = aa.normalized()
	bb = bb.normalized()
	return rad_to_deg(acos(clampf(aa.dot(bb), -1.0, 1.0)))

func _signed_angle_flat(a: Vector3, b: Vector3) -> float:
	var aa := a
	var bb := b
	aa.y = 0.0
	bb.y = 0.0

	if aa.length() <= 0.01 or bb.length() <= 0.01:
		return 0.0

	aa = aa.normalized()
	bb = bb.normalized()
	return atan2(aa.cross(bb).y, aa.dot(bb))

func _face_position(target_position: Vector3, speed: float, delta: float) -> void:
	var direction: Vector3 = target_position - global_position
	direction.y = 0.0
	_face_direction(direction, speed, delta)

func _face_direction(direction: Vector3, speed: float, delta: float) -> void:
	if direction.length() <= 0.01:
		return

	var normal: Vector3 = direction.normalized()
	var target_angle: float = atan2(-normal.x, -normal.z)

	rotation.y = lerp_angle(
		rotation.y,
		target_angle,
		clampf(speed * delta, 0.0, 1.0)
	)

# ==================================================
# 기울기
# ==================================================

func _update_turn_lean(desired_direction: Vector3, delta: float) -> void:
	var signed_angle: float = _signed_angle_flat(_get_forward(), desired_direction)
	var ratio: float = clampf(
		absf(signed_angle) / deg_to_rad(sharp_turn_angle),
		0.0,
		1.0
	)

	var sign_value: float = 0.0
	if signed_angle > 0.001:
		sign_value = 1.0
	elif signed_angle < -0.001:
		sign_value = -1.0

	var target_lean: float = deg_to_rad(max_lean_degrees) * ratio * sign_value * lean_direction
	_update_lean(target_lean, delta)

func _update_lean(target_lean: float, delta: float) -> void:
	var weight: float = 1.0 - exp(-lean_speed * delta)
	visual.rotation.z = lerp_angle(visual.rotation.z, target_lean, weight)

# ==================================================
# 애니메이션
# ==================================================

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D

	for child in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found

	return null

func _find_animations() -> void:
	for animation_name in animation_player.get_animation_list():
		var lower_name: String = String(animation_name).to_lower()

		if "idle" in lower_name:
			anim_idle = animation_name
		elif "run" in lower_name:
			anim_run = animation_name
		elif "sight" in lower_name:
			anim_sight = animation_name
		elif "attack" in lower_name and anim_attack == "":
			anim_attack = animation_name

	print("IDLE = ", anim_idle)
	print("RUN = ", anim_run)
	print("SIGHT = ", anim_sight)
	print("ATTACK = ", anim_attack)

func _play_anim(animation_name: StringName) -> void:
	if animation_name == "":
		return
	if not animation_player.has_animation(animation_name):
		return
	if animation_player.current_animation == animation_name \
	and animation_player.is_playing():
		return

	animation_player.stop(false)
	if skeleton != null:
		skeleton.reset_bone_poses()

	animation_player.play(animation_name, 0.0)
	animation_player.advance(0.0)

# ==================================================
# 상태 / 정지 / 발굽
# ==================================================

func _change_state(new_state: int) -> void:
	state = new_state
	state_elapsed = 0.0

func _stop_horizontal() -> void:
	velocity.x = 0.0
	velocity.z = 0.0

func _update_hoof_sound() -> void:
	if not hoof_audio.playing:
		hoof_audio.stream = HOOF_SOUNDS.pick_random()

		var ratio: float = clampf(current_speed / chase_max_speed, 0.0, 1.0)
		hoof_audio.pitch_scale = lerpf(0.94, 1.06, ratio) * randf_range(0.98, 1.02)
		hoof_audio.play()

# ==================================================
# IDLE 진입 / 플레이어 사망
# ==================================================

func _enter_idle() -> void:
	_change_state(State.IDLE)
	_stop_horizontal()
	hoof_audio.stop()
	current_speed = 0.0
	rear_hold_timer = 0.0
	animation_player.speed_scale = 1.0
	_play_anim(anim_idle)

func _kill_player() -> void:
	if has_killed_player:
		return

	has_killed_player = true
	velocity = Vector3.ZERO
	_stop_horizontal()
	scream_audio.stop()
	hoof_audio.stop()
	animation_player.speed_scale = 1.0

	if animation_player.current_animation != anim_attack:
		_play_anim(anim_attack)

	if player.has_method("die"):
		player.die(global_position)

	print("PLAYER DEAD")
