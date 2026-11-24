class_name CharacterDecisionEngine
extends RefCounted
## Phase 04 character decisions. The runner auto-runs at a fixed
## 8 m/s (CharacterController), so this engine owns exactly three
## outputs: strafe (toward the selected target x), jump and slide,
## timed from RiskAssessmentManager's windows. Predictive rule for
## platform steps: if forward progress stalls against a step, the
## RecoveryManager escalates to a jump (see AutonomousController).

var _risk := RiskAssessmentManager.new()
var _route := RouteSelectionManager.new()

var jumps_made: int = 0
var slides_made: int = 0

func decide(p: Dictionary) -> Dictionary:
    var risk := _risk.assess_character(p)
    var target := _route.target_x(p, risk)
    var pos: Vector3 = p["pos"]
    var dx := target - pos.x
    var strafe := 0.0
    if absf(dx) > 0.25:
        strafe = clampf(dx * 0.4, -1.0, 1.0)
    var jump := false
    var slide := false
    if bool(p["grounded"]) and not bool(p["sliding"]):
        if str(risk["action"]) == "jump" and bool(risk["ready"]):
            jump = true
            jumps_made += 1
        elif str(risk["action"]) == "slide" and bool(risk["ready"]):
            slide = true
            slides_made += 1
    return {"strafe": strafe, "throttle": 0.0, "jump": jump, "slide": slide,
        "target_x": target, "risk_action": str(risk["action"])}
