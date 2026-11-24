extends Node
## GameManager - session state machine and the owner of mode switching.
##
## States: MENU -> PLAYING -> PAUSED -> LEVEL_COMPLETE -> (next level) PLAYING
## Modes:  "character" (runner) and "vehicle" (racer)
##
## Mode switching is centralised here because the Phase 02 brief calls out "no broken camera
## states": exactly one actor is alive at a time, the camera is re-targeted in the same frame
## the actor changes, and the swap is a pure function of the level's vehicle_spawn point.

signal state_changed(state: String)
signal mode_changed(mode: String)
signal score_changed(score: int)
signal level_changed(index: int, name: String)
signal finished(level_index: int, score: int)

enum State { MENU, PLAYING, PAUSED, LEVEL_COMPLETE }

const CharacterScript := preload("res://entities/character_controller.gd")
const VehicleScript := preload("res://entities/vehicle_controller.gd")

var state: State = State.MENU
var mode := "character"
var level_index := 0
var score := 0

var world: Node3D
var level_manager: Node
var input_manager: Node
var collision_manager: Node
var audio: Node
var camera: Camera3D

var actor: CharacterBody3D
var _actor_root: Node3D

func setup(p_world: Node3D, p_levels: Node, p_input: Node, p_collision: Node, p_audio: Node, p_camera: Camera3D) -> void:
	world = p_world
	level_manager = p_levels
	input_manager = p_input
	collision_manager = p_collision
	audio = p_audio
	camera = p_camera

	_actor_root = Node3D.new()
	_actor_root.name = "ActorRoot"
	add_child(_actor_root)

func start_level(index: int) -> void:
	level_index = clampi(index, 0, level_manager.level_count() - 1)
	var level: Dictionary = level_manager.get_level(level_index)

	collision_manager.build(level, get_parent())
	world.build(level["theme"], level)

	score = 0
	score_changed.emit(score)
	_spawn_character(level)
	state = State.PLAYING
	state_changed.emit("PLAYING")
	level_changed.emit(level_index, level["name"])

func _spawn_character(level: Dictionary, at: Vector3 = Vector3.INF) -> void:
	_clear_actor()
	actor = CharacterScript.new()
	actor.name = "Character"
	_actor_root.add_child(actor)
	# switching mid-run must not teleport the player backwards, so the caller can pass the
	# current position; only a fresh level start uses the level's spawn point
	actor.reset_at(level["spawn"] if at == Vector3.INF else at)
	actor.jumped.connect(func(): audio.play("jump"))
	actor.landed.connect(func(): audio.play("land"))
	mode = "character"
	camera.set_target(actor, mode)
	mode_changed.emit(mode)

func _spawn_vehicle(level: Dictionary, at: Vector3 = Vector3.INF) -> void:
	_clear_actor()
	actor = VehicleScript.new()
	actor.name = "Vehicle"
	_actor_root.add_child(actor)
	actor.active = true
	actor.reset_at(level["vehicle_spawn"] if at == Vector3.INF else at)
	actor.bumped.connect(func(): audio.play("bump"))
	mode = "vehicle"
	camera.set_target(actor, mode)
	mode_changed.emit(mode)

func _clear_actor() -> void:
	if actor and is_instance_valid(actor):
		actor.queue_free()
	actor = null

func switch_mode() -> void:
	if state != State.PLAYING:
		return
	var level: Dictionary = level_manager.get_level(level_index)
	audio.play("switch")
	# carry the position across the swap: same place, new body, camera re-targeted in the
	# same frame (the brief's "no broken camera states")
	var here: Vector3 = actor.global_position + Vector3(0, 1.4, 0)
	if mode == "character":
		_spawn_vehicle(level, here)
	else:
		_spawn_character(level, here)

func pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	get_tree().paused = true
	state_changed.emit("PAUSED")

func resume() -> void:
	if state != State.PAUSED:
		return
	state = State.PLAYING
	get_tree().paused = false
	state_changed.emit("PLAYING")

func restart() -> void:
	get_tree().paused = false
	start_level(level_index)

func next_level() -> void:
	if level_index + 1 < level_manager.level_count():
		start_level(level_index + 1)
	else:
		start_level(0)

func complete_level() -> void:
	if state != State.PLAYING:
		return
	state = State.LEVEL_COMPLETE
	audio.play("finish")
	finished.emit(level_index, score)
	state_changed.emit("LEVEL_COMPLETE")

func _physics_process(delta: float) -> void:
	if state != State.PLAYING or actor == null or not is_instance_valid(actor):
		return

	var intent: Dictionary = input_manager.intent()
	if intent.get("pause", false):
		pause()
		return
	if intent.get("switch_mode", false):
		switch_mode()
		return

	actor.step(intent, delta)

	# score: distance based, so it rises on both modes and is comparable across levels
	score = int(actor.distance_travelled * 10.0) + (level_index * 1000)
	score_changed.emit(score)

	# finish detection (Area3D body_entered is unreliable for a fast mover at 60Hz)
	var level: Dictionary = level_manager.get_level(level_index)
	if actor.global_position.z <= (level["finish"] as Vector3).z:
		complete_level()
