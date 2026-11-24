extends Node3D
## Main - composition root. Nothing here knows gameplay rules; it wires the modules and
## connects signals. Keeping this thin is what lets Phase 03 replace the level source
## (handcrafted -> generated) without touching this file.

const LevelManagerScript := preload("res://core/level_manager.gd")
const WorldManagerScript := preload("res://core/world_manager.gd")
const GameManagerScript := preload("res://core/game_manager.gd")
const InputManagerScript := preload("res://systems/input_manager.gd")
const CollisionManagerScript := preload("res://systems/collision_manager.gd")
const AudioManagerScript := preload("res://systems/audio_manager.gd")
const CameraScript := preload("res://entities/camera_controller.gd")
const UIScript := preload("res://ui/game_ui.gd")

var levels: Node
var world: Node3D
var game: Node
var input_manager: Node
var collision: Node
var audio: Node
var camera: Camera3D
var ui: CanvasLayer

func _ready() -> void:
	levels = LevelManagerScript.new()
	levels.name = "LevelManager"
	add_child(levels)

	world = WorldManagerScript.new()
	world.name = "WorldManager"
	add_child(world)

	input_manager = InputManagerScript.new()
	input_manager.name = "InputManager"
	add_child(input_manager)

	collision = CollisionManagerScript.new()
	collision.name = "CollisionManager"
	add_child(collision)

	audio = AudioManagerScript.new()
	audio.name = "AudioManager"
	add_child(audio)

	camera = CameraScript.new()
	camera.name = "Camera"
	add_child(camera)
	camera.global_position = Vector3(0, 4, 8)

	game = GameManagerScript.new()
	game.name = "GameManager"
	add_child(game)
	game.setup(world, levels, input_manager, collision, audio, camera)

	ui = UIScript.new()
	ui.name = "UI"
	add_child(ui)

	_connect_ui()
	ui.show_menu()

func _connect_ui() -> void:
	ui.play_pressed.connect(_on_play)
	ui.resume_pressed.connect(func(): game.resume(); ui.hide_pause())
	ui.restart_pressed.connect(func(): game.restart(); ui.show_game())
	ui.next_pressed.connect(func(): game.next_level(); ui.show_game())
	ui.quit_pressed.connect(func(): game.state = 0; ui.show_menu())
	ui.settings_pressed.connect(func(): ui.settings_visible = true)
	ui.audio_toggled.connect(func(on: bool): audio.enabled = on)

	game.score_changed.connect(func(s: int): ui.set_score(s))
	game.level_changed.connect(func(i: int, n: String): ui.set_level(i, n))
	game.mode_changed.connect(func(m: String): ui.set_mode(m))
	game.state_changed.connect(_on_state)

func _on_play() -> void:
	game.start_level(0)
	if ui.selected_mode == "vehicle":
		game.switch_mode()
	ui.show_game()

func _on_state(state: String) -> void:
	if state == "PAUSED":
		ui.show_pause()
	elif state == "LEVEL_COMPLETE":
		ui.show_complete()
