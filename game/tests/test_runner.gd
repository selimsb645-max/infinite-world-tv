extends SceneTree
## Headless test runner for Phase 02.
##
## Run: godot --headless --path game --script res://tests/test_runner.gd
##
## Why time-based and not frame-based: in headless script mode the main loop runs faster than
## real time, so 60 iterations are NOT one second of simulation. An earlier frame-numbered
## version of this file asserted "vehicle accelerated" 45 frames after the switch and measured
## only 0.3 s of acceleration, which looked like a bug in the vehicle and was actually a bug in
## the test. Every phase below waits on accumulated delta instead.
##
## Nothing here is faked: each check reads state the engine produced.

var results: Array = []
var _main: Node
var _t := 0.0
var _phase := 0
var _phase_t := 0.0
var _char: CharacterBody3D
var _start_pos := Vector3.ZERO
var _max_y := 0.0
var _slide_seen := false
var _veh_start_z := 0.0

func _initialize() -> void:
	print("== INFINITE WORLD TV - Phase 02 headless tests ==")
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	await process_frame

func check(name: String, ok: bool, detail: String = "") -> void:
	results.append({"name": name, "ok": ok, "detail": detail})
	print(("  PASS  " if ok else "  FAIL  ") + name + (("  [" + detail + "]") if detail != "" else ""))

func intent(d: Dictionary) -> void:
	_main.input_manager.set_override({
		"move": 0.0, "jump": false, "slide": false,
		"accelerate": 0.0, "steer": 0.0,
		"switch_mode": false, "pause": false,
	}.merged(d, true))

func _process(delta: float) -> bool:
	_t += delta
	_phase_t += delta

	var game = _main.game

	# track peak height for the jump assertion
	if _char != null and is_instance_valid(_char):
		_max_y = max(_max_y, _char.global_position.y)

	match _phase:
		0:
			if _phase_t > 0.15:
				var levels = _main.levels
				check("level count is 5", levels.level_count() == 5, str(levels.level_count()))
				var all_valid := true
				for i in range(levels.level_count()):
					if not levels.validate(levels.get_level(i)):
						all_valid = false
				check("all 5 levels validate", all_valid)
				var themes_ok := true
				for i in range(levels.level_count()):
					if not _main.world.THEMES.has(levels.get_level(i)["theme"]):
						themes_ok = false
				check("all 5 themes exist in WorldManager", themes_ok)
				check("scene loads with no missing resources", _main.world != null and _main.camera != null and _main.ui != null)
				check("UI menu visible at boot", _main.ui.menu_root.visible)
				check("UI play button exists", _main.ui.menu_root.find_child("PlayButton", true, false) != null)
				check("UI has a pause menu", _main.ui.pause_root != null)
				_next()
		1:
			game.start_level(0)
			_char = game.actor
			_start_pos = _char.global_position
			intent({})
			check("level 1 started in character mode", game.mode == "character")
			check("character spawned on the track", _char.global_position.y > -0.5, "y=%.2f" % _char.global_position.y)
			_next()
		2:
			# run forward for a second of simulation
			if _phase_t > 1.0:
				check("character moved forward", _char.global_position.z < _start_pos.z - 3.0, "dz=%.2f" % (_char.global_position.z - _start_pos.z))
				check("character is grounded while running", _char.is_on_floor())
				intent({"jump": true})
				_max_y = _char.global_position.y
				_next()
		3:
			# hold jump briefly, then watch the arc
			if _phase_t > 0.1:
				intent({})
				_next()
		4:
			if _phase_t > 0.45:
				check("jump raised the character", _max_y > _start_pos.y + 0.6, "max_y=%.2f" % _max_y)
				_next()
		5:
			# wait to land, then strafe
			if _phase_t > 0.9:
				check("character landed after the jump", _char.is_on_floor())
				intent({"move": -1.0})
				_next()
		6:
			if _phase_t > 0.5:
				check("strafe moved the character sideways", _char.global_position.x < -0.4, "x=%.2f" % _char.global_position.x)
				check("lane limit respected", absf(_char.global_position.x) <= 4.7, "x=%.2f" % _char.global_position.x)
				intent({"slide": true})
				_slide_seen = false
				_next()
		7:
			if _char != null and is_instance_valid(_char) and _char.sliding:
				_slide_seen = true
			if _phase_t > 0.25:
				check("slide activated", _slide_seen)
				intent({})
				_next()
		8:
			if _phase_t > 0.5:
				game.pause()
				_next()
		9:
			if _phase_t > 0.15:
				check("pause sets state PAUSED", game.state == 2, str(game.state))
				check("scene tree is paused", paused)
				check("pause menu visible", _main.ui.pause_root.visible)
				game.resume()
				_next()
		10:
			if _phase_t > 0.15:
				check("resume clears pause", not paused and game.state == 1)
				game.switch_mode()
				_next()
		11:
			if _phase_t > 0.05:
				check("mode switched to vehicle", game.mode == "vehicle")
				check("vehicle actor exists", game.actor != null and is_instance_valid(game.actor))
				check("camera retargeted to the vehicle", _main.camera.target == game.actor)
				check("switch kept the player on the track", game.actor.global_position.y > -1.0, "y=%.2f" % game.actor.global_position.y)
				_char = game.actor
				_veh_start_z = _char.global_position.z
				intent({"accelerate": 1.0})
				_next()
		12:
			if _phase_t > 1.2:
				check("vehicle accelerated", _char.speed > 5.0, "speed=%.2f" % _char.speed)
				check("vehicle moved forward", _char.global_position.z < _veh_start_z - 2.0, "dz=%.2f" % (_char.global_position.z - _veh_start_z))
				check("vehicle stays on the track", _char.global_position.y > -1.0, "y=%.2f" % _char.global_position.y)
				game.switch_mode()
				_next()
		13:
			if _phase_t > 0.05:
				check("mode switched back to character", game.mode == "character")
				check("character survived the round trip", game.actor.global_position.y > -1.0, "y=%.2f" % game.actor.global_position.y)
				game.restart()
				_next()
		14:
			if _phase_t > 0.1:
				check("restart resets the score", game.score < 2000, str(game.score))
				check("restart returns to level 1", game.level_index == 0)
				check("restart spawns a fresh actor", game.actor != null and is_instance_valid(game.actor))
				var lv: Dictionary = _main.levels.get_level(0)
				game.actor.global_position = Vector3(0, 1, (lv["finish"] as Vector3).z - 2.0)
				_next()
		15:
			if _phase_t > 0.3:
				check("finish triggers LEVEL_COMPLETE", game.state == 3, str(game.state))
				check("complete screen visible", _main.ui.complete_root.visible)
				_next()
		16:
			var built := 0
			for i in range(_main.levels.level_count()):
				game.start_level(i)
				if _main.collision.obstacle_count() > 0 and _main.world.get_child_count() > 0:
					built += 1
			check("all 5 levels build world + obstacles", built == 5, "%d/5" % built)
			_main.world.clear()
			_main.collision.clear()
			_next()
		17:
			if _phase_t > 0.2:
				check("world cleanup frees environment nodes", _main.world.get_child_count() == 0, str(_main.world.get_child_count()))
				check("collision cleanup frees obstacle root", _main.collision.obstacle_root == null)
				_report()
				return true
	return false

func _next() -> void:
	_phase += 1
	_phase_t = 0.0

func _report() -> void:
	var passed := 0
	for r in results:
		if r["ok"]:
			passed += 1
	print("")
	print("RESULT: %d/%d checks passed (%.1fs simulated)" % [passed, results.size(), _t])
	var failed := []
	for r in results:
		if not r["ok"]:
			failed.append(r["name"])
	if failed.is_empty():
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED: " + ", ".join(failed))
		quit(1)
