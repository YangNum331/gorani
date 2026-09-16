extends CharacterBody3D

enum State {
	IDLE,
	STARE,
	CHASE
}

@export var detect_distance: float = 12.0
@export var stare_time: float = 2.0
@export var chase_speed: float = 7.0
@export var kill_distance: float = 1.2
@export var return_distance: float = 25.0
@export var turn_speed: float = 3.0

var state: State = State.IDLE
var player: Node3D
var stare_timer: float = 0.0

var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
)


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as Node3D

	if player == null:
		print("ERROR: PLAYER NOT FOUND")
	else:
		print("GORANI READY")


func _physics_process(delta: float) -> void:

	if player == null:
		return

	# 중력
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0


	# 플레이어 방향
	var to_player := player.global_position - global_position
	to_player.y = 0.0

	var distance_to_player := to_player.length()


	match state:

		State.IDLE:
			velocity.x = 0.0
			velocity.z = 0.0

			if distance_to_player <= detect_distance:
				state = State.STARE
				stare_timer = stare_time
				print("GORANI STARE")


		State.STARE:
			_face_player(to_player, delta)

			velocity.x = 0.0
			velocity.z = 0.0

			stare_timer -= delta

			if stare_timer <= 0.0:
				state = State.CHASE
				print("GORANI CHASE")


		State.CHASE:
			_face_player(to_player, delta)

			if distance_to_player > return_distance:
				state = State.IDLE

				velocity.x = 0.0
				velocity.z = 0.0

				print("GORANI IDLE")

			else:
				if distance_to_player > 0.01:
					var direction := to_player.normalized()

					velocity.x = direction.x * chase_speed
					velocity.z = direction.z * chase_speed

				if distance_to_player <= kill_distance:
					_kill_player()


	move_and_slide()


func _face_player(to_player: Vector3, delta: float) -> void:

	if to_player.length() <= 0.01:
		return

	# Godot 캐릭터 정면이 -Z 방향이라는 기준
	var target_angle := atan2(
		-to_player.x,
		-to_player.z
	)

	rotation.y = lerp_angle(
		rotation.y,
		target_angle,
		turn_speed * delta
	)


func _kill_player() -> void:

	print("PLAYER DEAD")

	get_tree().reload_current_scene()
