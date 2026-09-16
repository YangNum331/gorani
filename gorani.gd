extends CharacterBody3D


enum State {
	IDLE,
	TURN,
	STARE,
	SCREAM,
	CHASE,
	LUNGE,
	RECOVER
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
# 장거리 추격
# ==================================================

# 처음 추격 시작 속도
@export var chase_start_speed: float = 3.2

# 플레이어 달리기(6.5)보다 살짝 빠름
@export var chase_max_speed: float = 8.0

@export var chase_acceleration: float = 7.0

@export var far_steering: float = 3.0
@export var far_body_turn: float = 3.0

@export var return_distance: float = 30.0


# ==================================================
# 근접 추격
#
# 이 거리 안에서는 NavigationAgent를 버리고
# 고라니가 플레이어를 직접 추격한다.
# ==================================================

@export var direct_chase_distance: float = 5.0

# 기존 5.2 → 6.9
# 플레이어가 전력질주해도 조금씩 따라붙음
@export var close_chase_speed: float = 6.9

@export var close_acceleration: float = 10.0
@export var close_deceleration: float = 14.0

# 근거리 몸 전체 회전 속도
@export var close_turn_speed: float = 7.5

# 플레이어가 완전히 뒤에 있을 때는
# 뛰면서 원을 그리지 않고 속도를 죽임
@export var close_turning_speed: float = 1.5

@export var close_slow_angle: float = 60.0
@export var close_stop_angle: float = 105.0


# ==================================================
# 공격 조건
# ==================================================

# 일반 공격 시작 가능 거리
@export var attack_distance: float = 3.2

# 일반 공격 시작 각도
@export var attack_angle: float = 30.0

# 이 거리 안에 플레이어가 들어오면
# 각도 상관없이 바로 공격
@export var emergency_attack_distance: float = 2.25

@export var attack_cooldown_time: float = 0.60


# ==================================================
# 돌진
# ==================================================

# 기존 7.8 → 8.3
@export var lunge_speed: float = 8.3

@export var lunge_duration: float = 0.44

# 너무 높이면 유도탄처럼 됨
@export var lunge_steering: float = 1.0


# ==================================================
# 공격 실패 후 관성
# ==================================================

@export var recover_duration: float = 0.34
@export var recover_deceleration: float = 13.0


# ==================================================
# 공격 판정
# ==================================================

@export var attack_cast_height: float = 1.0

# 기존 2.4보다 짧게.
# 멀리서 죽는 현상을 줄임.
@export var attack_cast_length: float = 1.8

@export var attack_cast_radius: float = 0.70


# ==================================================
# ★ 실제 사망 거리
#
# ShapeCast 안에 들어왔다고 바로 죽이지 않는다.
# 고라니가 이 거리까지 붙어야 죽음.
# ==================================================

@export var death_trigger_distance: float = 1.25


# ==================================================
# 장거리 목표 예측
# ==================================================

@export var prediction_time: float = 0.35
@export var max_prediction_distance: float = 1.5

@export var player_velocity_smoothing: float = 4.0
@export var target_smoothing: float = 5.0

@export var target_refresh_interval: float = 0.15


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

@onready var navigation_agent: NavigationAgent3D = \
	$NavigationAgent3D

@onready var scream_audio: AudioStreamPlayer3D = \
	$ScreamAudio

@onready var hoof_audio: AudioStreamPlayer3D = \
	$HoofAudio

@onready var visual: Node3D = \
	$Visual

@onready var animation_player: AnimationPlayer = \
	$Visual/Skeletal_Base_Mesh/Character/AnimationPlayer


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

var lunge_direction: Vector3 = Vector3.ZERO

var attack_cooldown: float = 0.0

var smoothed_player_velocity: Vector3 = Vector3.ZERO
var smoothed_target_position: Vector3 = Vector3.ZERO

var target_refresh_timer: float = 0.0

var has_killed_player: bool = false


var gravity: float = float(
	ProjectSettings.get_setting(
		"physics/3d/default_gravity"
	)
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

	player = get_tree().get_first_node_in_group(
		"player"
	) as CharacterBody3D


	if player == null:

		print("ERROR: PLAYER NOT FOUND")

	else:

		print("GORANI READY")

		smoothed_target_position = (
			player.global_position
		)


	skeleton = _find_skeleton(
		$Visual/Skeletal_Base_Mesh
	)


	if skeleton == null:

		print(
			"WARNING: Skeleton3D NOT FOUND"
		)


	_find_animations()


	# ==================================================
	# NavigationAgent 안정화
	# ==================================================

	navigation_agent.path_desired_distance = 0.8
	navigation_agent.target_desired_distance = 1.2

	navigation_agent.simplify_path = true
	navigation_agent.simplify_epsilon = 0.20


	# ==================================================
	# 공격용 ShapeCast 자동 생성
	# ==================================================

	_setup_attack_cast()


	animation_player.speed_scale = 1.0


	_play_anim(
		anim_idle
	)


# ==================================================
# 공격 ShapeCast 생성
# ==================================================

func _setup_attack_cast() -> void:

	attack_cast = ShapeCast3D.new()

	attack_cast.name = "AttackCast"


	attack_cast.position = Vector3(
		0.0,
		attack_cast_height,
		0.0
	)


	var attack_shape: SphereShape3D = (
		SphereShape3D.new()
	)


	attack_shape.radius = (
		attack_cast_radius
	)


	attack_cast.shape = (
		attack_shape
	)


	# 고라니 정면 = -Z
	attack_cast.target_position = Vector3(
		0.0,
		0.0,
		-attack_cast_length
	)


	attack_cast.collide_with_bodies = true
	attack_cast.collide_with_areas = false

	attack_cast.exclude_parent = true

	attack_cast.enabled = true
	attack_cast.max_results = 16


	# 플레이어가 있는 Collision Layer를
	# 자동으로 공격 마스크로 설정
	if player != null:

		var player_layers: int = (
			player.collision_layer
		)


		if player_layers == 0:

			player_layers = 1


		attack_cast.collision_mask = (
			player_layers
		)


	add_child(
		attack_cast
	)


# ==================================================
# Skeleton 검색
# ==================================================

func _find_skeleton(
	node: Node
) -> Skeleton3D:

	if node is Skeleton3D:

		return node as Skeleton3D


	for child in node.get_children():

		var found: Skeleton3D = (
			_find_skeleton(
				child
			)
		)


		if found != null:

			return found


	return null


# ==================================================
# 애니메이션 검색
# ==================================================

func _find_animations() -> void:

	for animation_name in animation_player.get_animation_list():

		var lower_name: String = (
			String(
				animation_name
			).to_lower()
		)


		if "idle" in lower_name:

			anim_idle = (
				animation_name
			)


		elif "run" in lower_name:

			anim_run = (
				animation_name
			)


		elif "sight" in lower_name:

			anim_sight = (
				animation_name
			)


		elif "attack" in lower_name:

			if anim_attack == "":

				anim_attack = (
					animation_name
				)


	print(
		"IDLE = ",
		anim_idle
	)

	print(
		"RUN = ",
		anim_run
	)

	print(
		"SIGHT = ",
		anim_sight
	)

	print(
		"ATTACK = ",
		anim_attack
	)


# ==================================================
# 애니메이션 재생
#
# 블렌딩하지 않는다.
# 이전 pose가 섞이는 문제 방지.
# ==================================================

func _play_anim(
	animation_name: StringName
) -> void:

	if animation_name == "":
		return


	if not animation_player.has_animation(
		animation_name
	):
		return


	if animation_player.current_animation == animation_name \
	and animation_player.is_playing():

		return


	animation_player.stop(
		false
	)


	if skeleton != null:

		skeleton.reset_bone_poses()


	animation_player.play(
		animation_name,
		0.0
	)


	animation_player.advance(
		0.0
	)


# ==================================================
# 상태 변경
# ==================================================

func _change_state(
	new_state: int
) -> void:

	state = new_state
	state_elapsed = 0.0


# ==================================================
# 메인 AI
# ==================================================

func _physics_process(
	delta: float
) -> void:

	if player == null:
		return


	state_elapsed += delta


	# ==================================================
	# 공격 쿨다운
	# ==================================================

	if attack_cooldown > 0.0:

		attack_cooldown = maxf(
			0.0,
			attack_cooldown - delta
		)


	# ==================================================
	# 이미 플레이어 사망
	# ==================================================

	if has_killed_player:

		velocity = Vector3.ZERO

		return


	# ==================================================
	# 중력
	# ==================================================

	if not is_on_floor():

		velocity.y -= (
			gravity * delta
		)

	else:

		velocity.y = 0.0


	# ==================================================
	# 플레이어 정보
	# ==================================================

	var to_player: Vector3 = (
		player.global_position
		- global_position
	)


	to_player.y = 0.0


	var distance_to_player: float = (
		to_player.length()
	)


	var angle_to_player: float = (
		_get_angle_to_player()
	)


	# ==================================================
	# ★ 초근접 공격 최우선
	# ==================================================

	if state == State.CHASE \
	and distance_to_player <= emergency_attack_distance \
	and attack_cooldown <= 0.0:

		_enter_lunge(
			true
		)


	# ==================================================
	# 상태 머신
	# ==================================================

	match state:


		# --------------------------------------------------
		# IDLE
		# --------------------------------------------------

		State.IDLE:

			_stop_horizontal()

			current_speed = 0.0

			current_move_direction = Vector3.ZERO


			hoof_audio.stop()


			animation_player.speed_scale = 1.0


			_update_lean(
				0.0,
				delta
			)


			_play_anim(
				anim_idle
			)


			if distance_to_player <= detect_distance:

				_change_state(
					State.TURN
				)


				state_timer = (
					turn_time
				)


				_play_anim(
					anim_sight
				)


		# --------------------------------------------------
		# 첫 조우 회전
		# --------------------------------------------------

		State.TURN:

			_stop_horizontal()


			_face_position(
				player.global_position,
				encounter_turn_speed,
				delta
			)


			state_timer -= delta


			if state_timer <= 0.0:

				_change_state(
					State.STARE
				)


				state_timer = (
					stare_time
				)


		# --------------------------------------------------
		# 응시
		# --------------------------------------------------

		State.STARE:

			_stop_horizontal()


			_face_position(
				player.global_position,
				encounter_turn_speed,
				delta
			)


			state_timer -= delta


			if state_timer <= 0.0:

				_change_state(
					State.SCREAM
				)


				state_timer = (
					scream_pause
				)


				scream_audio.play()


		# --------------------------------------------------
		# 비명
		# --------------------------------------------------

		State.SCREAM:

			_stop_horizontal()


			_face_position(
				player.global_position,
				encounter_turn_speed,
				delta
			)


			state_timer -= delta


			if state_timer <= 0.0:

				_enter_chase()


		# --------------------------------------------------
		# 추격
		# --------------------------------------------------

		State.CHASE:

			if distance_to_player > return_distance:

				_enter_idle()

				return


			# ==============================================
			# 가까우면 NavMesh 안 씀
			# ==============================================

			if distance_to_player <= direct_chase_distance:

				_direct_close_chase(
					delta,
					angle_to_player
				)


			else:

				_navigation_chase(
					delta
				)


			# ==============================================
			# 일반 공격
			# ==============================================

			if distance_to_player <= attack_distance \
			and angle_to_player <= attack_angle \
			and attack_cooldown <= 0.0:

				_enter_lunge(
					false
				)


		# --------------------------------------------------
		# 돌진
		# --------------------------------------------------

		State.LUNGE:

			_lunge_update(
				delta
			)


		# --------------------------------------------------
		# 공격 실패 후 관성
		# --------------------------------------------------

		State.RECOVER:

			_recover_update(
				delta
			)


	# ==================================================
	# 실제 이동
	# ==================================================

	move_and_slide()


	# 몸 자체 충돌도 공격 중엔 판정
	_check_body_collision()


# ==================================================
# CHASE 진입
# ==================================================

func _enter_chase() -> void:

	_change_state(
		State.CHASE
	)


	target_refresh_timer = 0.0


	var direction: Vector3 = (
		player.global_position
		- global_position
	)


	direction.y = 0.0


	if direction.length() > 0.01:

		current_move_direction = (
			direction.normalized()
		)


	current_speed = maxf(
		current_speed,
		chase_start_speed
	)


	_play_anim(
		anim_run
	)


# ==================================================
# 근거리 직접 추격
# ==================================================

func _direct_close_chase(
	delta: float,
	angle_to_player: float
) -> void:

	var direction_to_player: Vector3 = (
		player.global_position
		- global_position
	)


	direction_to_player.y = 0.0


	if direction_to_player.length() <= 0.01:
		return


	direction_to_player = (
		direction_to_player.normalized()
	)


	# ==================================================
	# 몸 전체로 플레이어를 따라봄
	# ==================================================

	_face_direction(
		direction_to_player,
		close_turn_speed,
		delta
	)


	# ==================================================
	# 플레이어가 옆/뒤면 감속
	# ==================================================

	var target_speed: float = (
		close_chase_speed
	)


	if angle_to_player >= close_stop_angle:

		target_speed = (
			close_turning_speed
		)


	elif angle_to_player >= close_slow_angle:

		var turn_ratio: float = clampf(
			(
				angle_to_player
				- close_slow_angle
			)
			/
			(
				close_stop_angle
				- close_slow_angle
			),
			0.0,
			1.0
		)


		target_speed = lerpf(
			close_chase_speed,
			close_turning_speed,
			turn_ratio
		)


	# ==================================================
	# 가감속
	# ==================================================

	if current_speed < target_speed:

		current_speed = move_toward(
			current_speed,
			target_speed,
			close_acceleration
			* delta
		)

	else:

		current_speed = move_toward(
			current_speed,
			target_speed,
			close_deceleration
			* delta
		)


	# ==================================================
	# 몸 정면으로만 전진
	# ==================================================

	var body_forward: Vector3 = (
		-get_global_transform().basis.z
	)


	body_forward.y = 0.0


	if body_forward.length() > 0.01:

		body_forward = (
			body_forward.normalized()
		)


	current_move_direction = (
		body_forward
	)


	velocity.x = (
		body_forward.x
		* current_speed
	)


	velocity.z = (
		body_forward.z
		* current_speed
	)


	# ==================================================
	# 근접에서도 Run 유지
	# ==================================================

	_play_anim(
		anim_run
	)


	var animation_ratio: float = clampf(
		current_speed
		/ close_chase_speed,
		0.0,
		1.0
	)


	animation_player.speed_scale = lerpf(
		0.65,
		1.08,
		animation_ratio
	)


	if current_speed > 2.0:

		_update_hoof_sound()

	else:

		hoof_audio.stop()


	_update_lean(
		0.0,
		delta
	)


# ==================================================
# 장거리 Navigation 추격
# ==================================================

func _navigation_chase(
	delta: float
) -> void:

	var raw_velocity: Vector3 = (
		player.velocity
	)


	raw_velocity.y = 0.0


	var velocity_weight: float = (
		1.0
		- exp(
			-player_velocity_smoothing
			* delta
		)
	)


	smoothed_player_velocity = (
		smoothed_player_velocity.lerp(
			raw_velocity,
			velocity_weight
		)
	)


	# ==================================================
	# 플레이어 미래 위치 약간 예측
	# ==================================================

	var prediction: Vector3 = (
		smoothed_player_velocity
		* prediction_time
	)


	if prediction.length() > max_prediction_distance:

		prediction = (
			prediction.normalized()
			* max_prediction_distance
		)


	var raw_target: Vector3 = (
		player.global_position
		+ prediction
	)


	var target_weight: float = (
		1.0
		- exp(
			-target_smoothing
			* delta
		)
	)


	smoothed_target_position = (
		smoothed_target_position.lerp(
			raw_target,
			target_weight
		)
	)


	# ==================================================
	# 목적지 갱신
	# ==================================================

	target_refresh_timer -= delta


	if target_refresh_timer <= 0.0:

		target_refresh_timer = (
			target_refresh_interval
		)


		navigation_agent.target_position = (
			smoothed_target_position
		)


	# ==================================================
	# 경로 진행 방향
	# ==================================================

	var desired_direction: Vector3


	if navigation_agent.is_navigation_finished():

		desired_direction = (
			player.global_position
			- global_position
		)


	else:

		var next_position: Vector3 = (
			navigation_agent.get_next_path_position()
		)


		desired_direction = (
			next_position
			- global_position
		)


	desired_direction.y = 0.0


	if desired_direction.length() <= 0.01:

		_stop_horizontal()

		return


	desired_direction = (
		desired_direction.normalized()
	)


	# ==================================================
	# 이동 방향 관성
	# ==================================================

	if current_move_direction.length() <= 0.01:

		current_move_direction = (
			desired_direction
		)


	var steering_weight: float = (
		1.0
		- exp(
			-far_steering
			* delta
		)
	)


	current_move_direction = (
		current_move_direction.lerp(
			desired_direction,
			steering_weight
		)
	)


	current_move_direction.y = 0.0


	if current_move_direction.length() > 0.01:

		current_move_direction = (
			current_move_direction.normalized()
		)


	# ==================================================
	# 속도
	# ==================================================

	current_speed = move_toward(
		current_speed,
		chase_max_speed,
		chase_acceleration
		* delta
	)


	velocity.x = (
		current_move_direction.x
		* current_speed
	)


	velocity.z = (
		current_move_direction.z
		* current_speed
	)


	_face_direction(
		current_move_direction,
		far_body_turn,
		delta
	)


	# ==================================================
	# Run
	# ==================================================

	_play_anim(
		anim_run
	)


	var speed_ratio: float = clampf(
		current_speed
		/ chase_max_speed,
		0.0,
		1.0
	)


	animation_player.speed_scale = lerpf(
		0.92,
		1.10,
		speed_ratio
	)


	_update_hoof_sound()


# ==================================================
# 공격 시작
# ==================================================

func _enter_lunge(
	emergency: bool
) -> void:

	if state == State.LUNGE:
		return


	_change_state(
		State.LUNGE
	)


	hoof_audio.stop()


	animation_player.speed_scale = 1.0


	# ==================================================
	# 공격 순간 플레이어 방향
	# ==================================================

	lunge_direction = (
		player.global_position
		- global_position
	)


	lunge_direction.y = 0.0


	if lunge_direction.length() <= 0.01:

		lunge_direction = (
			-get_global_transform().basis.z
		)


	lunge_direction = (
		lunge_direction.normalized()
	)


	# ==================================================
	# 초근접이면 몸을 바로 돌림
	# ==================================================

	if emergency:

		_snap_face_direction(
			lunge_direction
		)


	else:

		_face_direction(
			lunge_direction,
			12.0,
			0.1
		)


	current_speed = (
		lunge_speed
	)


	_play_anim(
		anim_attack
	)


	# 이미 코앞이면 즉시 확인하되,
	# 실제 사망 거리는 따로 검사함.
	_check_attack_cast()


# ==================================================
# 돌진 공격
# ==================================================

func _lunge_update(
	delta: float
) -> void:

	var desired: Vector3 = (
		player.global_position
		- global_position
	)


	desired.y = 0.0


	if desired.length() > 0.01:

		desired = (
			desired.normalized()
		)


		var weight: float = (
			1.0
			- exp(
				-lunge_steering
				* delta
			)
		)


		lunge_direction = (
			lunge_direction.lerp(
				desired,
				weight
			)
		)


		lunge_direction.y = 0.0


		if lunge_direction.length() > 0.01:

			lunge_direction = (
				lunge_direction.normalized()
			)


	# ==================================================
	# 돌진 이동
	# ==================================================

	velocity.x = (
		lunge_direction.x
		* lunge_speed
	)


	velocity.z = (
		lunge_direction.z
		* lunge_speed
	)


	_face_direction(
		lunge_direction,
		8.0,
		delta
	)


	# ==================================================
	# 공격 판정
	# ==================================================

	_check_attack_cast()


	if state_elapsed >= lunge_duration:

		_enter_recover()


# ==================================================
# ★ ShapeCast 공격 판정
# ==================================================

func _check_attack_cast() -> void:

	if attack_cast == null:
		return


	if has_killed_player:
		return


	attack_cast.force_shapecast_update()


	if not attack_cast.is_colliding():
		return


	var collision_count: int = (
		attack_cast.get_collision_count()
	)


	for i in range(
		collision_count
	):

		var collider: Object = (
			attack_cast.get_collider(
				i
			)
		)


		var hit_player: bool = false


		if collider == player:

			hit_player = true


		elif collider is Node:

			var node: Node = (
				collider as Node
			)


			if node.is_in_group(
				"player"
			):

				hit_player = true


		if hit_player:

			# ==============================================
			# 중요:
			# ShapeCast에 걸렸다고 바로 죽지 않음.
			#
			# 실제로 고라니가 가까이까지 들어와야 함.
			# ==============================================

			var to_player: Vector3 = (
				player.global_position
				- global_position
			)


			to_player.y = 0.0


			var real_distance: float = (
				to_player.length()
			)


			if real_distance <= death_trigger_distance:

				_kill_player()


			return


# ==================================================
# RECOVER 시작
# ==================================================

func _enter_recover() -> void:

	_change_state(
		State.RECOVER
	)


	attack_cooldown = (
		attack_cooldown_time
	)


	current_speed = (
		lunge_speed
	)


	hoof_audio.stop()


# ==================================================
# RECOVER
# ==================================================

func _recover_update(
	delta: float
) -> void:

	current_speed = move_toward(
		current_speed,
		0.0,
		recover_deceleration
		* delta
	)


	velocity.x = (
		lunge_direction.x
		* current_speed
	)


	velocity.z = (
		lunge_direction.z
		* current_speed
	)


	# 공격 직후 바로 U턴하지 않음
	if state_elapsed >= recover_duration * 0.65:

		_face_position(
			player.global_position,
			2.5,
			delta
		)


	if state_elapsed >= recover_duration:

		current_move_direction = (
			-get_global_transform().basis.z
		)


		current_move_direction.y = 0.0


		if current_move_direction.length() > 0.01:

			current_move_direction = (
				current_move_direction.normalized()
			)


		current_speed = (
			chase_start_speed
		)


		_enter_chase()


# ==================================================
# IDLE 진입
# ==================================================

func _enter_idle() -> void:

	_change_state(
		State.IDLE
	)


	_stop_horizontal()

	hoof_audio.stop()


	current_speed = 0.0


	animation_player.speed_scale = 1.0


	_play_anim(
		anim_idle
	)


# ==================================================
# 플레이어가 고라니 정면에서 몇 도인지
# ==================================================

func _get_angle_to_player() -> float:

	var direction: Vector3 = (
		player.global_position
		- global_position
	)


	direction.y = 0.0


	if direction.length() <= 0.01:

		return 0.0


	direction = (
		direction.normalized()
	)


	var forward: Vector3 = (
		-get_global_transform().basis.z
	)


	forward.y = 0.0


	if forward.length() <= 0.01:

		return 0.0


	forward = (
		forward.normalized()
	)


	var dot_value: float = clampf(
		forward.dot(
			direction
		),
		-1.0,
		1.0
	)


	return rad_to_deg(
		acos(
			dot_value
		)
	)


# ==================================================
# 특정 위치 바라보기
# ==================================================

func _face_position(
	target_position: Vector3,
	speed: float,
	delta: float
) -> void:

	var direction: Vector3 = (
		target_position
		- global_position
	)


	direction.y = 0.0


	_face_direction(
		direction,
		speed,
		delta
	)


# ==================================================
# 특정 방향 바라보기
# ==================================================

func _face_direction(
	direction: Vector3,
	speed: float,
	delta: float
) -> void:

	if direction.length() <= 0.01:
		return


	var normal: Vector3 = (
		direction.normalized()
	)


	var target_angle: float = atan2(
		-normal.x,
		-normal.z
	)


	rotation.y = lerp_angle(
		rotation.y,
		target_angle,
		clampf(
			speed
			* delta,
			0.0,
			1.0
		)
	)


# ==================================================
# 즉시 몸 전체 회전
# ==================================================

func _snap_face_direction(
	direction: Vector3
) -> void:

	if direction.length() <= 0.01:
		return


	var normal: Vector3 = (
		direction.normalized()
	)


	rotation.y = atan2(
		-normal.x,
		-normal.z
	)


# ==================================================
# 몸 기울기
# ==================================================

func _update_lean(
	target_lean: float,
	delta: float
) -> void:

	var weight: float = (
		1.0
		- exp(
			-lean_speed
			* delta
		)
	)


	visual.rotation.z = lerp_angle(
		visual.rotation.z,
		target_lean,
		weight
	)


# ==================================================
# 수평 정지
# ==================================================

func _stop_horizontal() -> void:

	velocity.x = 0.0
	velocity.z = 0.0


# ==================================================
# 발굽
# ==================================================

func _update_hoof_sound() -> void:

	if not hoof_audio.playing:

		hoof_audio.stream = (
			HOOF_SOUNDS.pick_random()
		)


		var ratio: float = clampf(
			current_speed
			/ chase_max_speed,
			0.0,
			1.0
		)


		hoof_audio.pitch_scale = (
			lerpf(
				0.94,
				1.06,
				ratio
			)
			* randf_range(
				0.98,
				1.02
			)
		)


		hoof_audio.play()


# ==================================================
# 몸 자체 충돌
#
# 실제 몸끼리 닿은 경우이므로
# ShapeCast 거리 제한과 별개로 공격 성공 처리.
# ==================================================

func _check_body_collision() -> void:

	if has_killed_player:
		return


	if state != State.LUNGE:
		return


	for i in range(
		get_slide_collision_count()
	):

		var collision: KinematicCollision3D = (
			get_slide_collision(
				i
			)
		)


		if collision.get_collider() == player:

			_kill_player()

			return


# ==================================================
# 플레이어 사망
# ==================================================

func _kill_player() -> void:

	if has_killed_player:
		return


	has_killed_player = true


	velocity = Vector3.ZERO

	_stop_horizontal()


	scream_audio.stop()
	hoof_audio.stop()


	animation_player.speed_scale = 1.0


	# 이미 공격 모션 중이면
	# 다시 Attack 처음부터 재생하지 않음.
	if animation_player.current_animation != anim_attack:

		_play_anim(
			anim_attack
		)


	if player.has_method(
		"die"
	):

		player.die(
			global_position
		)


	print(
		"PLAYER DEAD"
	)
