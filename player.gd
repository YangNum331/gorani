extends CharacterBody3D


@export var walk_speed: float = 4.0
@export var sprint_speed: float = 6.5

@export var acceleration: float = 12.0
@export var deceleration: float = 16.0

@export var mouse_sensitivity: float = 0.002


@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/SmartphoneFlash


var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	camera.current = true

	flashlight.visible = false


func _unhandled_input(event: InputEvent) -> void:

	# 마우스로 시점 회전
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:

		# 좌우 회전 = 플레이어 몸 전체
		rotate_y(-event.relative.x * mouse_sensitivity)

		# 위아래 회전 = 머리만
		head.rotate_x(-event.relative.y * mouse_sensitivity)

		head.rotation.x = clamp(
			head.rotation.x,
			deg_to_rad(-80.0),
			deg_to_rad(80.0)
		)


	# 플래시 ON / OFF
	if event.is_action_pressed("flashlight"):
		flashlight.visible = !flashlight.visible


	# ESC 누르면 마우스 해제
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


	# 마우스 클릭하면 다시 게임에 마우스 고정
	if event is InputEventMouseButton:
		if event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:

	# WASD 입력
	var input_dir := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)


	# 플레이어가 바라보는 방향 기준으로 변환
	var direction := (
		transform.basis *
		Vector3(input_dir.x, 0.0, input_dir.y)
	).normalized()


	# 달리기 여부
	var target_speed := walk_speed

	if Input.is_action_pressed("sprint"):
		target_speed = sprint_speed


	# 이동
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


	# 중력
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0


	move_and_slide()
