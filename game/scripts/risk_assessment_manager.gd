class_name RiskAssessmentManager
extends RefCounted
## Phase 04 risk assessment: turns the nearest relevant obstacle into
## a concrete, fair reaction plan, using the REAL controller numbers:
## character run speed 8 m/s, jump velocity 9.5 / gravity 26 (air time
## ~0.73 s, jump range ~5.8 m), slide duration 0.65 s. Trigger windows
## below sit comfortably inside those limits.
##
## Obstacle geometry (WorldManager): "jump"/"slide" barriers are 6 m
## wide centred on ob.x; "block" is a 2.2 m cube.

const JUMP_TRIGGER_MIN := 2.6
const JUMP_TRIGGER_MAX := 5.2
const SLIDE_TRIGGER := 3.4

func assess_character(p: Dictionary) -> Dictionary:
    var pos: Vector3 = p["pos"]
    for ob in p["obstacles_ahead"]:
        var dx := absf(pos.x - float(ob["x"]))
        var dist := float(ob["dist"])
        match str(ob["type"]):
            "jump":
                if dx < 3.2:
                    return {"action": "jump", "obstacle": ob,
                        "ready": dist >= JUMP_TRIGGER_MIN and dist <= JUMP_TRIGGER_MAX,
                        "target_x": float(p["lane_offset"])}
            "slide":
                if dx < 3.2:
                    return {"action": "slide", "obstacle": ob,
                        "ready": dist <= SLIDE_TRIGGER and dist > 0.2,
                        "target_x": float(p["lane_offset"])}
            "block":
                if dx < 1.7 and dist < 16.0:
                    return {"action": "avoid", "obstacle": ob, "ready": false,
                        "target_x": _free_side(float(ob["x"]), pos.x,
                            float(p["lane_offset"]), float(p["width"]))}
    # Gaps: the spanning platform sits on the route lane, so a runner
    # aligned with the lane simply runs across it; only a badly
    # misaligned runner needs a jump.
    for g in p["gaps_ahead"]:
        var dist := float(g["dist"])
        if dist > 0.5 and dist < 12.0 and absf(pos.x - float(p["lane_offset"])) > 1.4:
            return {"action": "jump", "obstacle": {"type": "gap", "x": float(p["lane_offset"]), "z": float(g["near_edge"]), "dist": dist},
                "ready": dist >= JUMP_TRIGGER_MIN and dist <= JUMP_TRIGGER_MAX,
                "target_x": float(p["lane_offset"])}
    return {"action": "none", "obstacle": {}, "ready": false,
        "target_x": float(p["lane_offset"])}

func assess_vehicle(p: Dictionary) -> Dictionary:
    var pos: Vector3 = p["pos"]
    var target_speed := 13.0
    if str(p["segment_feature"]) in ["curve", "bridge", "tunnel"]:
        target_speed = 11.0
    for ob in p["obstacles_ahead"]:
        if str(ob["type"]) != "block":
            continue
        var dx := absf(pos.x - float(ob["x"]))
        var dist := float(ob["dist"])
        if dx < 1.9 and dist < 26.0:
            return {"action": "avoid", "obstacle": ob, "ready": false,
                "target_x": _free_side(float(ob["x"]), pos.x,
                    float(p["lane_offset"]), float(p["width"])),
                "target_speed": 8.0 if dist < 9.0 else 11.0}
    return {"action": "none", "obstacle": {}, "ready": false,
        "target_x": float(p["lane_offset"]), "target_speed": target_speed}

func _free_side(ob_x: float, pos_x: float, lane: float, width: float) -> float:
    var limit := width / 2.0 - 1.6
    var left := clampf(ob_x - 3.4, -limit, limit)
    var right := clampf(ob_x + 3.4, -limit, limit)
    # Prefer the side closer to where the player already is, then lane.
    if absf(pos_x - left) + absf(lane - left) * 0.3 <= absf(pos_x - right) + absf(lane - right) * 0.3:
        return left
    return right
