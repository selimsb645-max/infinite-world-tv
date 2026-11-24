class_name ActionPlanner
extends RefCounted
## Phase 04 action planner: the one place where perception becomes a
## unified action for this tick — mode engine output plus the mode
## switch decision. A switch is requested when the player has crossed
## into a segment whose mode differs from the active mode (generated
## levels alternate character/vehicle segments; the pad marks the
## same transition for a human player). GameManager.switch_mode()
## teleports the incoming body to the player, so switching at the
## segment boundary is always safe.

var character_engine := CharacterDecisionEngine.new()
var vehicle_engine := VehicleDecisionEngine.new()

var switches_planned: int = 0

func plan(p: Dictionary, current_mode: String) -> Dictionary:
    var action: Dictionary
    if current_mode == "vehicle":
        action = vehicle_engine.decide(p)
    else:
        action = character_engine.decide(p)
    action["switch_mode"] = false
    var segment: Dictionary = p["segment"]
    if not segment.is_empty():
        var seg_mode := str(segment.get("mode", current_mode))
        if seg_mode != current_mode:
            var start_z := float(segment.get("start_z", 0.0))
            if float(p["pos"].z) <= start_z - 1.0:
                action["switch_mode"] = true
                switches_planned += 1
    return action
