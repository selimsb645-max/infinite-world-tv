class_name VehicleDecisionEngine
extends RefCounted
## Phase 04 vehicle decisions. The car steers by rotating (arcade
## model): a positive strafe input rotates the heading toward +x, so
## steering = lane-error term + heading-correction term that keeps
## pulling the nose back to straight (-Z). Throttle targets a cruise
## speed from RiskAssessmentManager (slower near obstacles / on
## curves, bridges and tunnels) and brakes only on overshoot.

var _risk := RiskAssessmentManager.new()
var _route := RouteSelectionManager.new()

var brakes_applied: int = 0
## Adaptive cruise scale, adjusted by AutonomousController from the
## PerformanceTracker after each level (0.7 cautious .. 1.05 bold).
var speed_scale: float = 1.0

func decide(p: Dictionary) -> Dictionary:
    var risk := _risk.assess_vehicle(p)
    var target := _route.target_x(p, risk)
    var pos: Vector3 = p["pos"]
    var dx := target - pos.x
    var steer := clampf(dx * 0.30 + float(p["rotation_y"]) * 1.1, -1.0, 1.0)
    if absf(dx) < 0.3 and absf(float(p["rotation_y"])) < 0.05:
        steer = 0.0
    var target_speed := float(risk.get("target_speed", 13.0)) * speed_scale
    var speed := float(p["speed"])
    var throttle := 0.0
    if speed < target_speed - 0.5:
        throttle = 1.0
    elif speed > target_speed + 3.0:
        throttle = -1.0
        brakes_applied += 1
    return {"strafe": steer, "throttle": throttle, "jump": false,
        "slide": false, "target_x": target, "target_speed": target_speed,
        "risk_action": str(risk["action"])}
