class_name RouteSelectionManager
extends RefCounted
## Phase 04 route selection: decides the lateral target (x) the active
## controller should aim for this decision tick. Priority: obstacle
## avoidance (from RiskAssessmentManager) > route lane of the current
## segment > nearby collectible (only when it costs almost nothing).

func target_x(p: Dictionary, risk: Dictionary) -> float:
    var limit := float(p["width"]) / 2.0 - 1.2
    if str(risk.get("action", "none")) == "avoid":
        return clampf(float(risk["target_x"]), -limit, limit)
    var base := float(p["lane_offset"])
    var col = p["nearest_collectible"]
    if col != null:
        var cv: Vector3 = col
        if absf(cv.x - float(p["pos"].x)) < 3.0:
            base = cv.x
    return clampf(base, -limit, limit)
