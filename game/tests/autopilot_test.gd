extends Node
## Headless test suite for INFINITE WORLD TV Phase 04 (AI autonomous
## gameplay controller). Run:
##   godot --headless --path game res://tests/AutopilotTest.tscn
## Unit checks exercise the decision engines / risk / recovery /
## tracker on crafted perception snapshots; the integration run then
## starts endless play via GameManager.start_autonomous() with NO
## human input and plays until several levels complete or the frame
## budget ends. Prints PASS/FAIL, an AUTOPILOT_STATS line with the
## real numbers, and AUTOPILOT_DONE failures=N.

var failures: int = 0

func check(test_name: String, condition: bool, detail: String = "") -> void:
    if condition:
        print("PASS: ", test_name, (" — " + detail) if detail != "" else "")
    else:
        failures += 1
        print("FAIL: ", test_name, (" — " + detail) if detail != "" else "")

func step_physics(n: int) -> void:
    for i in n:
        await get_tree().physics_frame

func _perception(mode: String, obstacles: Array) -> Dictionary:
    return {
        "mode": mode, "pos": Vector3(0, 0, -20), "speed": 8.0 if mode == "character" else 5.0,
        "velocity": Vector3.ZERO, "grounded": true, "sliding": false,
        "rotation_y": 0.0, "obstacles_ahead": obstacles, "gaps_ahead": [],
        "segment": {}, "segment_mode": mode, "segment_feature": "run",
        "lane_offset": 0.0, "width": 14.0, "finish_z": -180.0,
        "distance_to_finish": 160.0, "pad_z": -30.0,
        "nearest_collectible": null, "level_number": 1, "world": "Test",
    }

func _test_units() -> void:
    var char_engine := CharacterDecisionEngine.new()
    var jump_p := _perception("character",
        [{"type": "jump", "x": 0.0, "z": -24.0, "dist": 4.0}])
    var a := char_engine.decide(jump_p)
    check("unit_jump_timed_for_barrier", bool(a["jump"]), "dist=4.0 in window")
    var slide_p := _perception("character",
        [{"type": "slide", "x": 0.0, "z": -23.0, "dist": 3.0}])
    a = char_engine.decide(slide_p)
    check("unit_slide_timed_for_barrier", bool(a["slide"]), "dist=3.0")
    var block_p := _perception("character",
        [{"type": "block", "x": 0.0, "z": -30.0, "dist": 10.0}])
    a = char_engine.decide(block_p)
    check("unit_block_avoided_by_steering",
        absf(float(a["target_x"])) >= 2.0 and signf(float(a["strafe"])) == signf(float(a["target_x"])),
        "target_x=%.1f" % float(a["target_x"]))
    var far_p := _perception("character",
        [{"type": "jump", "x": 5.0, "z": -24.0, "dist": 4.0}])
    a = char_engine.decide(far_p)
    check("unit_no_jump_when_barrier_not_in_lane", not bool(a["jump"]))

    var veh_engine := VehicleDecisionEngine.new()
    var vblock := _perception("vehicle",
        [{"type": "block", "x": 0.0, "z": -27.0, "dist": 7.0}])
    var va := veh_engine.decide(vblock)
    check("unit_vehicle_slows_for_close_block",
        float(va["target_speed"]) <= 8.5, "target=%.1f" % float(va["target_speed"]))
    check("unit_vehicle_steers_for_block", absf(float(va["strafe"])) > 0.05,
        "steer=%.2f" % float(va["strafe"]))
    var vopen := _perception("vehicle", [])
    va = veh_engine.decide(vopen)
    check("unit_vehicle_accelerates_on_open_road",
        float(va["throttle"]) == 1.0 and float(va["target_speed"]) >= 12.0)

    # Recovery: same position forever -> jump/reverse, then at most
    # MAX restarts, then exactly one give_up, then silence.
    var rec := RecoveryManager.new()
    var actions: Array = []
    var rp := {"pos": Vector3(0, 0, -20), "mode": "character"}
    for i in 200:
        var r := rec.update(0.3, rp, true)
        if str(r["action"]) != "none":
            actions.append(str(r["action"]))
    check("recovery_first_action_is_jump",
        actions.size() > 0 and actions[0] == "jump", str(actions))
    check("recovery_restarts_bounded",
        actions.count("restart") <= RecoveryManager.MAX_RESTARTS_PER_LEVEL,
        "restarts=%d" % actions.count("restart"))
    check("recovery_gives_up_exactly_once",
        actions.count("give_up") == 1, str(actions))

    # Tracker history is bounded (no memory growth on long runs).
    var tr := PerformanceTracker.new()
    for i in 150:
        tr.begin_level(i + 1, "W")
        tr.finish_level(i % 2 == 0)
    check("tracker_history_bounded", tr.records.size() == PerformanceTracker.MAX_RECORDS,
        "kept=%d" % tr.records.size())
    check("tracker_success_rate_math", absf(tr.success_rate() - 0.5) < 0.02,
        "rate=%.2f" % tr.success_rate())

    # Adaptation: the performance nudge contract and the vehicle
    # speed scale both move in the cautious direction after a bad
    # level, with no external API involved.
    var tr2 := PerformanceTracker.new()
    tr2.begin_level(1, "W")
    tr2.note_recovery(true)
    tr2.note_recovery(true)
    tr2.finish_level(false)
    var perf := tr2.performance_for_generator()
    check("adaptation_performance_nudge", int(perf.get("deaths", 0)) == 2
        and not bool(perf.get("flawless", true)), str(perf))
    var cautious := VehicleDecisionEngine.new()
    cautious.speed_scale = 0.7
    var va2 := cautious.decide(_perception("vehicle", []))
    var bold := VehicleDecisionEngine.new()
    var va3 := bold.decide(_perception("vehicle", []))
    check("adaptation_speed_scale_applies",
        float(va2["target_speed"]) < float(va3["target_speed"]) - 2.0,
        "cautious=%.1f default=%.1f" % [float(va2["target_speed"]), float(va3["target_speed"])])

func _ready() -> void:
    print("AUTOPILOT_START")
    _test_units()
    Engine.time_scale = 4.0
    var main = load("res://scenes/Main.tscn").instantiate()
    add_child(main)
    await step_physics(5)
    main.start_autonomous(777)
    await step_physics(2)
    var ac = main.autonomous_controller
    check("starts_without_human_input",
        int(main.state) == 1 and bool(main.endless_active) and ac != null and bool(ac.enabled))
    var start_pos: Vector3 = main.active_controller().global_position
    var saw_character := false
    var saw_vehicle := false
    var frames := 0
    var max_frames := 60 * 480
    while frames < max_frames:
        await step_physics(30)
        frames += 30
        if str(main.mode) == "vehicle":
            saw_vehicle = true
        else:
            saw_character = true
        if ac.state_manager.levels_completed >= 6:
            break
    var stats: Dictionary = ac.stats()
    var travelled: float = start_pos.z - main.active_controller().global_position.z
    check("player_progresses_forward", travelled > 20.0 or stats["levels_completed"] > 0,
        "travelled=%.1f (current level)" % travelled)
    check("character_mode_used", saw_character)
    check("vehicle_mode_used", saw_vehicle)
    check("mode_switches_happen", int(stats["switches"]) >= 1,
        "switches=%d" % int(stats["switches"]))
    check("autopilot_actions_executed",
        int(stats["jumps"]) + int(stats["slides"]) + int(stats["brakes"]) > 0,
        "jumps=%d slides=%d brakes=%d" % [int(stats["jumps"]), int(stats["slides"]), int(stats["brakes"])])
    check("completes_multiple_consecutive_levels", int(stats["levels_completed"]) >= 2,
        "completed=%d attempted=%d" % [int(stats["levels_completed"]), int(stats["levels_attempted"])])
    var max_restarts := 0
    for r in ac.tracker.records:
        max_restarts = maxi(max_restarts, int(r["restarts"]))
    check("recovery_never_loops_forever", max_restarts <= RecoveryManager.MAX_RESTARTS_PER_LEVEL,
        "max_restarts_in_a_level=%d" % max_restarts)
    check("still_playing_at_end", int(main.state) == 1 and bool(ac.enabled))
    check("long_run_six_levels", int(stats["levels_completed"]) >= 6,
        "completed=%d frames=%d decisions=%d" % [int(stats["levels_completed"]), frames, int(stats["decisions"])])
    check("decision_interval_respected", int(stats["decisions"]) <= frames + 10,
        "decisions=%d frames=%d (never more than one decision per physics frame; at time_scale 1 the 0.08 s interval is ~5 frames)" % [int(stats["decisions"]), frames])
    var worlds_seen := {}
    for r in ac.tracker.records:
        worlds_seen[str(r["world"])] = true
    check("multiple_generated_worlds_played", worlds_seen.size() >= 2,
        "worlds=%s" % str(worlds_seen.keys()))
    print("AUTOPILOT_STATS ", stats)

    # --- Handcrafted Phase 02 level under autopilot -------------------
    # Wedge the runner head-on into Level 1's block with decisions
    # frozen (huge interval): the per-frame RecoveryManager must fire
    # bounded recoveries on its own. Then unfreeze and let the
    # autopilot finish the level for real.
    ac.start_handcrafted()
    await step_physics(3)
    ac.decision_interval = 9999.0
    ac._timer = 9999.0
    main.character.reset_to(Vector3(-2.5, 0.15, -61.0))
    var events_before: int = ac.recovery.events
    await step_physics(150)
    check("recovery_fires_when_wedged", ac.recovery.events > events_before,
        "events %d -> %d restarts=%d" % [events_before, ac.recovery.events, ac.recovery.restarts_this_level])
    check("recovery_restarts_bounded_live", ac.recovery.restarts_this_level <= RecoveryManager.MAX_RESTARTS_PER_LEVEL,
        "restarts=%d" % ac.recovery.restarts_this_level)
    ac.decision_interval = 0.08
    ac._timer = 0.0
    var hc_frames := 0
    while hc_frames < 1500 and int(main.level_manager.current_index) == 0:
        await step_physics(30)
        hc_frames += 30
    check("autopilot_completes_handcrafted_level1",
        int(main.level_manager.current_index) == 1,
        "index=%d frames=%d pos=%s" % [int(main.level_manager.current_index), hc_frames, str(main.active_controller().global_position)])
    print("AUTOPILOT_STATS_FINAL ", ac.stats())
    print("AUTOPILOT_DONE failures=", failures)
    get_tree().quit(mini(failures, 125))
