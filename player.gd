extends CharacterBody3D


# =========================
# 이동
# =========================

@export var walk_speed: float = 4.0
@export var sprint_speed: float = 6.5

@export var acceleration: float = 12.0
@export var deceleration: float = 16.0

@export var mouse_sensitivity: float = 0.002


# =========================
# 발소리
# =========================

@export var walk_step_interval: float = 0.50
@export var sprint_step_interval: float = 0.32


const FOOTSTEPS = [
	preload("res://audio/player/footsteps/footstep_01.wav"),
	preload("res://audio/player/footsteps/footstep_02.wav"),
	preload("res://audio/player/footsteps/footstep_03.wav"),
	preload("res://audio/player/footsteps/footstep_04.wav"),
	preload("res://audio/player/footsteps/footstep_05.wav"),
	preload("res://audio/player/footsteps/footstep_06.wav")
]


# =========================
# 노드
# =========================

@onready var head: Node3D = $Head

@onready var camera: Camera3D = \
	$Head/Camera3D

@onready var flashlight: SpotLight3D = \
	$Head/SmartphoneFlash

@onready var footstep_audio: AudioStreamPlayer = \
	$FootstepAudio


# =========================
# 변수
# =========================

var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
)

var step_timer: float = 0.0

var dead: bool = false


var death_shake_timer: float = 0.0
var death_shake_duration: float = 0.45

var camera_base_position: Vector3


var fade_layer: CanvasLayer
var fade_rect: ColorRect


# =========================
# 시작
# =========================

func _ready() -> void:

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	camera.make_current()

	flashlight.visible = false

	camera_base_position = camera.position

	_create_death_fade()


# =========================
# 암전 UI 자동 생성
# =========================

func _create_death_fade() -> void:

	fade_layer = CanvasLayer.new()

	add_child(fade_layer)


	fade_rect = ColorRect.new()

	fade_rect.color = Color(
		0.0,
		0.0,
		0.0,
		0.0
	)


	fade_rect.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)


	fade_rect.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)


	fade_layer.add_child(fade_rect)


# =========================
# 일반 처리
# =========================

func _process(delta: float) -> void:

	if dead:
		_update_death_shake(delta)


# =========================
# 입력
# =========================

func _unhandled_input(event: InputEvent) -> void:

	if dead:
		return


	# 마우스만 카메라/손전등 방향 변경
	if event is InputEventMouseMotion \
	and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:

		# 좌우 회전
		rotate_y(
			-event.relative.x
			* mouse_sensitivity
		)

		# 위아래 회전
		head.rotate_x(
			-event.relative.y
			* mouse_sensitivity
		)

		head.rotation.x = clamp(
			head.rotation.x,
			deg_to_rad(-80.0),
			deg_to_rad(80.0)
		)


	# 손전등 ON/OFF
	if event.is_action_pressed("flashlight"):

		flashlight.visible = !flashlight.visible


	if event.is_action_pressed("ui_cancel"):

		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


	if event is InputEventMouseButton:

		if event.pressed \
		and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:

			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# =========================
# 이동
# =========================

func _physics_process(delta: float) -> void:

	if dead:

		velocity.x = 0.0
		velocity.z = 0.0

		return


	var input_dir := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)


	var direction := (
		transform.basis
		* Vector3(
			input_dir.x,
			0.0,
			input_dir.y
		)
	).normalized()


	var sprinting := Input.is_action_pressed(
		"sprint"
	)


	var target_speed := walk_speed


	if sprinting:
		target_speed = sprint_speed


	if direction != Vector3.ZERO:

		velocity.x = move_toward(
			velocity.x,
			direction.x * target_speed,
			acceleration * delta
		)

		velocity.z = move_toward(
			velocity.z,
			direction.z * target_speed,
			acceleration * delta
		)

	else:

		velocity.x = move_toward(
			velocity.x,
			0.0,
			deceleration * delta
		)

		velocity.z = move_toward(
			velocity.z,
			0.0,
			deceleration * delta
		)


	if not is_on_floor():

		velocity.y -= gravity * delta

	else:

		velocity.y = 0.0


	move_and_slide()


	update_footsteps(
		delta,
		input_dir,
		sprinting
	)


# =========================
# 발소리
# =========================

func update_footsteps(
	delta: float,
	input_dir: Vector2,
	sprinting: bool
) -> void:

	if input_dir.length() < 0.1:

		step_timer = 0.0
		return


	if not is_on_floor():

		step_timer = 0.0
		return


	step_timer -= delta


	if step_timer <= 0.0:

		footstep_audio.stream = (
			FOOTSTEPS.pick_random()
		)


		footstep_audio.pitch_scale = randf_range(
			0.96,
			1.04
		)


		footstep_audio.play()


		if sprinting:

			step_timer = sprint_step_interval

		else:

			step_timer = walk_step_interval


# =========================
# 사망
# =========================

func die(
	killer_position: Vector3
) -> void:

	if dead:
		return


	dead = true

	velocity = Vector3.ZERO

	footstep_audio.stop()


	# 고라니 방향으로 시선 돌리기
	var direction := (
		killer_position
		- global_position
	)

	direction.y = 0.0


	if direction.length() > 0.01:

		var target_angle := atan2(
			-direction.x,
			-direction.z
		)

		rotation.y = target_angle


	# 죽을 때 카메라 흔들기
	death_shake_timer = death_shake_duration


	# 몸이 아래로 쓰러지는 연출
	var fall_tween := create_tween()

	fall_tween.set_parallel(true)


	fall_tween.tween_property(
		head,
		"position:y",
		0.65,
		0.35
	)


	fall_tween.tween_property(
		head,
		"rotation:z",
		deg_to_rad(20.0),
		0.35
	)


	# 잠깐 고라니를 보여준 뒤 암전
	await get_tree().create_timer(
		0.35
	).timeout


	var fade_tween := create_tween()

	fade_tween.tween_property(
		fade_rect,
		"color:a",
		1.0,
		0.45
	)


	await fade_tween.finished


	await get_tree().create_timer(
		0.5
	).timeout


	get_tree().reload_current_scene()


# =========================
# 카메라 흔들림
# =========================

func _update_death_shake(
	delta: float
) -> void:

	if death_shake_timer <= 0.0:

		camera.position = camera_base_position

		return


	death_shake_timer -= delta


	var amount := (
		death_shake_timer
		/ death_shake_duration
	)


	var strength := (
		0.08
		* amount
	)


	camera.position = (
		camera_base_position
		+ Vector3(
			randf_range(
				-strength,
				strength
			),
			randf_range(
				-strength,
				strength
			),
			0.0
		)
	)
