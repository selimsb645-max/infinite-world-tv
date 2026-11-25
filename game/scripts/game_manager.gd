extends Node3D
## GameManager — root of the main scene and Phase 02 orchestrator.
## Owns every manager, the two playable controllers and the shared
## camera; handles game state (menu / playing / paused), scoring,
## level loading, mode transitions and restart.

enum State { MENU, PLAYING, PAUSED }

const SPAWN := Vector3(0, 0.15, 4.0)

var state: State = State.MENU
var score: int = 0
var mode: String = "character"
var near_vehicle_pad: bool = false

# Phase 05.1: live asset selection for the Phase 05 factories.
# Defaults: Pip (variant 0) and the SportsCar. Overridable via
# environment (IWT_CHARACTER, IWT_CHARACTER_VARIANT, IWT_VEHICLE)
# and at runtime via the controllers' set_character/set_vehicle_kind.
# IWT_FACTORY_VISUALS=0 forces the Phase 02 primitive visuals
# (fallback/comparison mode used by tools and the guard test).
var character_name: String = "Pip"
var character_variant: int = 0
var vehicle_kind: String = "SportsCar"
var factory_visuals_enabled: bool = true

func set_factory_visuals_enabled(enabled: bool) -> void:
	factory_visuals_enabled = enabled
	if character != null:
		character.set_factory_visual_enabled(enabled)
	if vehicle != null:
		vehicle.set_factory_visual_enabled(enabled)

var input_manager: InputManager
var environment_manager: EnvironmentManager
var level_manager: LevelManager
var world_manager: WorldManager
var collision_manager: CollisionManager
var audio_manager: AudioManager
var character: CharacterController
var vehicle: VehicleController
var camera_rig: CameraController
var ui: UIManager

var _selected_theme: String = ""

# Phase 03: endless procedural mode. When active, finishing a level
# advances the LevelTransitionManager (current + one pregenerated
# level) instead of cycling the handcrafted list.
var transition_manager: LevelTransitionManager
var endless_active: bool = false
var _current_generated: Dictionary = {}

func start_endless(base_seed: int) -> void:
	if transition_manager == null:
		transition_manager = LevelTransitionManager.new(
			LevelGenerator.new(environment_manager))
	score = 0
	endless_active = true
	var result: Dictionary = transition_manager.start(base_seed)
	_load_generated(result)
	state = State.PLAYING
	get_tree().paused = false
	ui.show_hud()
	_update_hud()

## Phase 04: autonomous play. Creates the AutonomousController (which
## substitutes its AutopilotInput for the human InputManager) and
## starts endless procedural play under its control. No Play press,
## no human input from this point.
var autonomous_controller: AutonomousController

func start_autonomous(base_seed: int) -> void:
	if autonomous_controller == null:
		autonomous_controller = AutonomousController.new()
		autonomous_controller.name = "AutonomousController"
		add_child(autonomous_controller)
		autonomous_controller.setup(self)
	autonomous_controller.start_endless(base_seed)

## Phase 04: the autopilot's bounded give-up path — advance to the
## next level WITHOUT the finish bonus (this is a skip, not a win).
func autopilot_request_new_level() -> void:
	if endless_active and transition_manager != null:
		_load_generated(transition_manager.advance())
	else:
		_load_level(level_manager.next_index(), _selected_theme)

## Phase 06: automated video production. Opt-in like
## start_autonomous(): creates the VideoRenderer (capture, encode,
## overlay, segments, recovery) without changing normal play.
## Recording starts only when the renderer's start_recording() /
## start_continuous() is called.
var broadcast: VideoRenderer

func setup_broadcast(cfg: EncodingConfig = null) -> VideoRenderer:
	if broadcast == null:
		broadcast = VideoRenderer.new()
		broadcast.name = "VideoRenderer"
		add_child(broadcast)
		broadcast.setup(self, cfg)
	return broadcast

func _load_generated(result: Dictionary) -> void:
	_current_generated = result
	var level: Dictionary = result["level"]
	environment_manager.apply_theme(str(level["theme"]))
	character.reset_to(SPAWN)
	vehicle.reset_to(Vector3(4.5, 0.15, float(level["vehicle_pad_z"])))
	world_manager.build(level, level["theme_data"], str(level["theme"]))
	near_vehicle_pad = false
	_set_mode(str(level["start_mode"]))
	_update_hud()

func _ready() -> void:
	input_manager = InputManager.new()
	input_manager.name = "InputManager"
	add_child(input_manager)
	collision_manager = CollisionManager.new()
	collision_manager.name = "CollisionManager"
	add_child(collision_manager)
	environment_manager = EnvironmentManager.new()
	environment_manager.name = "EnvironmentManager"
	add_child(environment_manager)
	environment_manager.setup(self)
	level_manager = LevelManager.new()
	level_manager.name = "LevelManager"
	add_child(level_manager)
	world_manager = WorldManager.new()
	world_manager.name = "WorldManager"
	world_manager.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world_manager)
	world_manager.collectible_picked.connect(_on_collectible_picked)
	world_manager.finish_reached.connect(_on_finish_reached)
	world_manager.vehicle_pad_entered.connect(_on_vehicle_pad)
	audio_manager = AudioManager.new()
	audio_manager.name = "AudioManager"
	add_child(audio_manager)
	character = CharacterController.new()
	character.name = "Character"
	character.process_mode = Node.PROCESS_MODE_PAUSABLE
	character.input_manager = input_manager
	add_child(character)
	vehicle = VehicleController.new()
	vehicle.name = "Vehicle"
	vehicle.process_mode = Node.PROCESS_MODE_PAUSABLE
	vehicle.input_manager = input_manager
	add_child(vehicle)
	character.bumped_obstacle.connect(func() -> void: audio_manager.play_bump())
	# Phase 05.1: apply the asset selection (env overrides win over
	# the defaults above) to the freshly built controllers.
	var env_character := OS.get_environment("IWT_CHARACTER").strip_edges()
	if not env_character.is_empty():
		character_name = env_character
	var env_variant := OS.get_environment("IWT_CHARACTER_VARIANT").strip_edges()
	if env_variant.is_valid_int():
		character_variant = int(env_variant)
	var env_vehicle := OS.get_environment("IWT_VEHICLE").strip_edges()
	if not env_vehicle.is_empty():
		vehicle_kind = env_vehicle
	if OS.get_environment("IWT_FACTORY_VISUALS").strip_edges() == "0":
		factory_visuals_enabled = false
	character.set_factory_visual_enabled(factory_visuals_enabled)
	character.set_character(character_name, character_variant)
	vehicle.set_factory_visual_enabled(factory_visuals_enabled)
	vehicle.set_vehicle_kind(vehicle_kind)
	camera_rig = CameraController.new()
	camera_rig.name = "CameraRig"
	camera_rig.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(camera_rig)
	ui = UIManager.new()
	ui.name = "UI"
	add_child(ui)
	ui.play_requested.connect(start_game)
	ui.resume_requested.connect(resume_game)
	ui.restart_requested.connect(restart_level)
	ui.quit_to_menu_requested.connect(quit_to_menu)
	ui.volume_changed.connect(func(v: float) -> void: audio_manager.set_volume(v))
	ui.quality_toggled.connect(_on_quality_toggled)
	_load_level(0, "")
	character.set_active(false)
	vehicle.set_active(false)
	camera_rig.set_target(character, "character")
	camera_rig.snap_to_target()
	state = State.MENU
	ui.show_menu()

func _on_quality_toggled(low: bool) -> void:
	var sun := environment_manager.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.shadow_enabled = not low
	ProjectSettings.set_setting("rendering/scaling_3d/scale", 0.75 if low else 1.0)

## --- Game flow -------------------------------------------------------

func start_game(start_mode: String, theme: String) -> void:
	score = 0
	endless_active = false
	_selected_theme = theme
	_load_level(level_manager.current_index, theme)
	_set_mode(start_mode)
	state = State.PLAYING
	get_tree().paused = false
	ui.show_hud()
	_update_hud()

func load_level_public(index: int) -> void:
	endless_active = false
	_load_level(index, _selected_theme)

func _load_level(index: int, theme_override: String) -> void:
	var level := level_manager.set_current(index)
	var theme_name: String = theme_override if theme_override != "" else level["theme"]
	environment_manager.apply_theme(theme_name)
	# Move the bodies to spawn BEFORE building: a body still standing at
	# its old position would overlap fresh collectible areas the moment
	# they are created and trigger phantom pickups.
	character.reset_to(SPAWN)
	vehicle.reset_to(Vector3(4.5, 0.15, level["vehicle_pad_z"]))
	world_manager.build(level, environment_manager.theme_data(theme_name), theme_name)
	near_vehicle_pad = false
	_set_mode(level["start_mode"])
	_update_hud()

func _set_mode(new_mode: String) -> void:
	mode = new_mode
	if mode == "vehicle":
		character.set_active(false)
		vehicle.set_active(true)
		camera_rig.set_target(vehicle, "vehicle")
		world_manager.set_active_body(vehicle)
	else:
		vehicle.set_active(false)
		character.set_active(true)
		camera_rig.set_target(character, "character")
		world_manager.set_active_body(character)
	_update_hud()

func switch_mode() -> void:
	if state != State.PLAYING:
		return
	if mode == "character":
		# The car comes to the runner: spawn it right at his position.
		vehicle.reset_to(character.global_position + Vector3(0, 0.1, -2.5))
		_set_mode("vehicle")
	else:
		character.reset_to(vehicle.global_position + Vector3(1.5, 0.1, 0))
		_set_mode("character")
	audio_manager.play_switch()
	if broadcast != null:
		broadcast.note_sfx("transition")
	ui.show_hint("")

func active_controller() -> CharacterBody3D:
	return vehicle if mode == "vehicle" else character

func toggle_pause() -> void:
	if state == State.PLAYING:
		state = State.PAUSED
		get_tree().paused = true
		ui.show_pause(true)
	elif state == State.PAUSED:
		resume_game()

func resume_game() -> void:
	if state == State.PAUSED:
		state = State.PLAYING
		get_tree().paused = false
		ui.show_pause(false)

func restart_level() -> void:
	score = 0
	get_tree().paused = false
	ui.show_pause(false)
	if endless_active and not _current_generated.is_empty():
		_load_generated(_current_generated)
	else:
		_load_level(level_manager.current_index, _selected_theme)
	if state != State.MENU:
		state = State.PLAYING
		ui.show_hud()
	_update_hud()

func quit_to_menu() -> void:
	get_tree().paused = false
	state = State.MENU
	character.set_active(false)
	vehicle.set_active(false)
	camera_rig.set_target(character, "character")
	camera_rig.snap_to_target()
	ui.show_menu()

## --- Events ----------------------------------------------------------

func _unhandled_input(_event: InputEvent) -> void:
	if input_manager.pause_just_pressed():
		if state == State.PLAYING or state == State.PAUSED:
			toggle_pause()
	elif input_manager.switch_just_pressed():
		switch_mode()

func _process(_delta: float) -> void:
	if state == State.PLAYING:
		var ctrl := active_controller()
		if ctrl != null:
			ui.set_speed(float(ctrl.call("current_speed")))
			if broadcast != null:
				var level: Dictionary = _current_generated.get("level", {}) if endless_active \
					else level_manager.current_level()
				var length := float(level.get("length", 0.0))
				if length > 0.0:
					broadcast.set_progress(clampf(-ctrl.global_position.z / length, 0.0, 1.0))

func add_score(points: int) -> void:
	score += points
	_update_hud()

func _on_collectible_picked(_area: Area3D) -> void:
	add_score(10)
	audio_manager.play_collect()
	if broadcast != null:
		broadcast.note_sfx("collect")

func _on_finish_reached() -> void:
	if state != State.PLAYING:
		return
	add_score(100)
	character.celebrate()
	world_manager.play_vfx("celebrate_burst",
		active_controller().global_position + Vector3(0, 1.5, 0))
	if broadcast != null:
		broadcast.note_sfx("celebrate")
	if endless_active and transition_manager != null:
		_load_generated(transition_manager.advance())
	else:
		_load_level(level_manager.next_index(), _selected_theme)
	ui.show_hint("Level complete! +100")

func _on_vehicle_pad() -> void:
	near_vehicle_pad = true
	if state == State.PLAYING and mode == "character":
		ui.show_hint("Car pad! Press Tab / E to switch to the car")

func _update_hud() -> void:
	if ui == null:
		return
	ui.set_score(score)
	var level: Dictionary = _current_generated.get("level", {}) if endless_active \
		else level_manager.current_level()
	ui.set_level("%s · %s" % [level.get("name", "Level"), environment_manager.current_theme])
	ui.set_mode("Vehicle" if mode == "vehicle" else "Character")
	if broadcast != null:
		broadcast.update_overlay(score,
			"Vehicle" if mode == "vehicle" else "Character",
			"%s · %s" % [level.get("name", "Level"), environment_manager.current_theme],
			environment_manager.current_theme)
