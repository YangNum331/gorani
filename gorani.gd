extends CharacterBody3D


enum State {
	IDLE,
	TURN,
	STARE,
	SCREAM,
	CHASE
}


# =========================
# 조우 설정
# =========================

@export var detect_distance: float = 12.0

@export var turn_time: float = 0.7
@export var stare_time: float = 1.3
@export var scream_pause: float = 0.25

@export var turn_speed: float = 3.5


# =========================
# 추격 설정
# =========================

@export var chase_start_speed: float = 3.0
@export var chase_max_speed: float = 7.5
@export var chase_acceleration: float = 7.0

@export var return_distance: float = 30.0


# =========================
# 발굽 사운드
# =========================

const HOOF_SOUNDS = [
	preload("res://audio/gorani/hoof/hoof_run_01.wav"),
	preload("res://audio/gorani/hoof/hoof_run_02.wav"),
	preload("res://audio/gorani/hoof/hoof_run_03.wav"),
	preload("res://audio/gorani/hoof/hoof_run_04.wav"),
	preload("res://audio/gorani/hoof/hoof_run_05.wav"),
	preload("res://audio/gorani/hoof/hoof_run_06.wav")
]


# =========================
# 노드
# =========================

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

@onready var scream_audio: AudioStreamPlayer3D = $ScreamAudio
@onready var hoof_audio: AudioStreamPlayer3D = $HoofAudio


# =========================
# 내부 변수
# =========================

var player: CharacterBody3D

var state: State = State.IDLE

var state_timer: float = 0.0

var current_chase_speed: float = 0.0

var has_killed_player: bool = false


var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
)


# =========================
# 시작
# =========================

func _ready() -> void:

	player = get_tree().get_first_node_in_group(
		"player"
	) as CharacterBody3D


	if player == null:
		print("ERROR: PLAYER NOT FOUND")
	else:
		print("GORANI READY")


# =========================
# AI
# =========================

func _physics_process(delta: float) -> void:

	if player == null:
		return


	# 이미 플레이어를 잡았으면
	# 더 이상 AI 처리하지 않음
	if has_killed_player:

		velocity = Vector3.ZERO

		return


	# -------------------------
	# 중력
	# -------------------------

	if not is_on_floor():

		velocity.y -= gravity * delta

	else:

		velocity.y = 0.0


	# -------------------------
	# 플레이어 거리
	# -------------------------

	var to_player := (
		player.global_position
		- global_position
	)

	to_player.y = 0.0


	var distance_to_player := (
		to_player.length()
	)


	# =========================
	# 상태 처리
	# =========================

	match state:


		# ---------------------
		# 평상시
		# ---------------------

		State.IDLE:

			_stop_horizontal()

			hoof_audio.stop()


			if distance_to_player <= detect_distance:

				state = State.TURN

				state_timer = turn_time

				print("GORANI DETECTED")


		# ---------------------
		# 천천히 돌아보기
		# ---------------------

		State.TURN:

			_stop_horizontal()

			_face_position(
				player.global_position,
				delta
			)


			state_timer -= delta


			if state_timer <= 0.0:

				state = State.STARE

				state_timer = stare_time

				print("GORANI STARE")


		# ---------------------
		# 정적 응시
		# ---------------------

		State.STARE:

			_stop_horizontal()

			_face_position(
				player.global_position,
				delta
			)


			state_timer -= delta


			if state_timer <= 0.0:

				state = State.SCREAM

				state_timer = scream_pause

				scream_audio.play()

				print("GORANI SCREAM")


		# ---------------------
		# 비명 후 잠깐 정지
		# ---------------------

		State.SCREAM:

			_stop_horizontal()

			_face_position(
				player.global_position,
				delta
			)


			state_timer -= delta


			if state_timer <= 0.0:

				state = State.CHASE

				current_chase_speed = chase_start_speed

				print("GORANI CHASE")


		# ---------------------
		# 추격
		# ---------------------

		State.CHASE:

			if distance_to_player > return_distance:

				state = State.IDLE

				_stop_horizontal()

				hoof_audio.stop()

				print("GORANI LOST PLAYER")


			else:

				current_chase_speed = move_toward(
					current_chase_speed,
					chase_max_speed,
					chase_acceleration * delta
				)


				_chase_player(delta)


	# 실제 이동
	move_and_slide()


	# 몸통/머리 포함 실제 충돌 체크
	_check_player_collision()


# =========================
# 추격
# =========================

func _chase_player(delta: float) -> void:

	# 플레이어 위치를 계속 목적지로 갱신
	navigation_agent.target_position = (
		player.global_position
	)


	# 다음 경로 지점
	var next_position := (
		navigation_agent.get_next_path_position()
	)


	var direction := (
		next_position
		- global_position
	)

	direction.y = 0.0


	# 경로를 못 찾았거나
	# 사실상 제자리면 정지
	if direction.length() <= 0.05:

		_stop_horizontal()

		hoof_audio.stop()

		return


	direction = direction.normalized()


	velocity.x = (
		direction.x
		* current_chase_speed
	)

	velocity.z = (
		direction.z
		* current_chase_speed
	)


	# 실제 이동 방향 바라보기
	_face_position(
		next_position,
		delta
	)


	# 실제로 움직일 때만 발굽소리
	_update_hoof_sound()


# =========================
# 수평 정지
# =========================

func _stop_horizontal() -> void:

	velocity.x = 0.0
	velocity.z = 0.0


# =========================
# 목표 바라보기
# =========================

func _face_position(
	target_position: Vector3,
	delta: float
) -> void:

	var direction := (
		target_position
		- global_position
	)

	direction.y = 0.0


	if direction.length() <= 0.01:
		return


	var target_angle := atan2(
		-direction.x,
		-direction.z
	)


	rotation.y = lerp_angle(
		rotation.y,
		target_angle,
		clamp(
			turn_speed * delta,
			0.0,
			1.0
		)
	)


# =========================
# 발굽 사운드
# =========================

func _update_hoof_sound() -> void:

	if not hoof_audio.playing:

		hoof_audio.stream = (
			HOOF_SOUNDS.pick_random()
		)


		hoof_audio.pitch_scale = randf_range(
			0.95,
			1.05
		)


		hoof_audio.play()


# =========================
# 플레이어 충돌 확인
# =========================

func _check_player_collision() -> void:

	if has_killed_player:
		return


	for i in range(
		get_slide_collision_count()
	):

		var collision := (
			get_slide_collision(i)
		)


		if collision.get_collider() == player:

			_kill_player()

			return


# =========================
# 플레이어 사망
# =========================

func _kill_player() -> void:

	if has_killed_player:
		return


	has_killed_player = true


	# -------------------------
	# 고라니 완전 정지
	# -------------------------

	velocity = Vector3.ZERO

	_stop_horizontal()


	# -------------------------
	# 고라니 사운드 정지
	# -------------------------

	scream_audio.stop()

	hoof_audio.stop()


	# -------------------------
	# 플레이어 사망 연출 호출
	# -------------------------

	if player.has_method("die"):

		player.die(
			global_position
		)


	print("PLAYER DEAD")
