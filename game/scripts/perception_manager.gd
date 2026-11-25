class_name PerceptionManager
extends RefCounted
## Phase 04 perception: builds a structured snapshot of the game state
## from the live controllers plus the current level's data (obstacles,
## gaps, gates, segments, collectibles). No screenshot processing —
## the level dictionary IS the agent's world model, and the physics
## engine remains the ground truth for collisions.
##
## sense() is O(obstacles + segments) and is meant to be called at the
## controller's decision interval (default 0.08 s), never per frame.

const LOOKAHEAD := 34.0

func sense(game, level: Dictionary) -> Dictionary:
    var ctrl = game.active_controller()
    if ctrl == null:
        # Phase 09 — perception unavailable (mode switch / level
        # load in progress). Return a well-formed snapshot marked
        # unavailable instead of dereferencing null and crashing
        # the controller; callers must check "available".
        return {
            "available": false,
            "mode": str(game.mode),
            "pos": Vector3.ZERO,
            "speed": 0.0,
            "velocity": Vector3.ZERO,
            "grounded": false,
            "sliding": false,
            "rotation_y": 0.0,
            "obstacles_ahead": [],
            "gaps_ahead": [],
            "segment": {},
            "segment_mode": str(game.mode),
            "segment_feature": "run",
            "lane_offset": 0.0,
            "width": float(level.get("width", 14.0)),
            "finish_z": 0.0,
            "distance_to_finish": 0.0,
            "pad_z": float(level.get("vehicle_pad_z", -30.0)),
            "nearest_collectible": null,
            "level_number": int(level.get("level_number", 0)),
            "world": str(level.get("world", level.get("theme", ""))),
        }
    var pos: Vector3 = ctrl.global_position
    var mode: String = str(game.mode)
    var obstacles: Array = []
    for ob in level.get("obstacles", []):
        var oz := float(ob["z"])
        var dist := pos.z - oz
        if dist > -2.0 and dist < LOOKAHEAD:
            obstacles.append({"type": str(ob["type"]), "x": float(ob["x"]),
                "z": oz, "dist": dist})
    obstacles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return float(a["dist"]) < float(b["dist"]))
    var gaps: Array = []
    for g in level.get("gaps", []):
        var gz := float(g["z_center"])
        var near_edge := gz + float(g["len"]) / 2.0
        var dist := pos.z - near_edge
        if dist > -3.0 and dist < LOOKAHEAD:
            gaps.append({"z_center": gz, "len": float(g["len"]),
                "near_edge": near_edge, "dist": dist})
    gaps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return float(a["dist"]) < float(b["dist"]))
    var segment: Dictionary = _segment_at(level, pos.z)
    var nearest_collectible = null
    var best := 1e9
    for c in level.get("collectibles", []):
        var cv: Vector3 = c
        var d := pos.z - cv.z
        if d > -1.0 and d < 20.0 and absf(cv.x - pos.x) < 4.0 and d < best:
            best = d
            nearest_collectible = cv
    var length := float(level.get("length", 120.0))
    return {
        "available": true,
        "mode": mode,
        "pos": pos,
        "speed": float(ctrl.call("current_speed")),
        "velocity": ctrl.velocity,
        "grounded": bool(ctrl.is_on_floor()),
        "sliding": bool(ctrl.get("sliding")) if mode == "character" else false,
        "rotation_y": float(ctrl.rotation.y),
        "obstacles_ahead": obstacles,
        "gaps_ahead": gaps,
        "segment": segment,
        "segment_mode": str(segment.get("mode", mode)),
        "segment_feature": str(segment.get("feature", "run")),
        "lane_offset": float(segment.get("lane_offset", 0.0)),
        "width": float(level.get("width", 14.0)),
        "finish_z": -length + 2.0,
        "distance_to_finish": pos.z - (-length + 2.0),
        "pad_z": float(level.get("vehicle_pad_z", -30.0)),
        "nearest_collectible": nearest_collectible,
        "level_number": int(level.get("level_number", 0)),
        "world": str(level.get("world", level.get("theme", ""))),
    }

func _segment_at(level: Dictionary, z: float) -> Dictionary:
    var segments: Array = level.get("segments", [])
    if segments.is_empty():
        return {}
    for seg in segments:
        var start_z := float(seg["start_z"])
        if z <= start_z + 0.5 and z > start_z - float(seg["length"]) - 0.5:
            return seg
    if z > float(segments[0]["start_z"]):
        return segments[0]
    return segments[segments.size() - 1]
