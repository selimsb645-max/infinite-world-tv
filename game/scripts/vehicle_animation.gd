class_name VehicleAnimation
extends RefCounted
## Phase 05 — vehicle animation system.
##
## Drives a VehicleFactory vehicle: wheel spin from speed, front-axle
## steering, suspension bob, acceleration squat / braking dive and a
## small collision shake. All motion is derived from live values, so
## the same component works for every vehicle kind and every speed.

var root: Node3D
var _wheel_spin: float = 0.0
var _bob_phase: float = 0.0
var _shake: float = 0.0

func _init(p_root: Node3D = null) -> void:
	root = p_root

func wheel_spin() -> float:
	return _wheel_spin

func wheels() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if root == null:
		return out
	for wheel_name in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var node := root.get_node_or_null(wheel_name) as Node3D
		if node != null:
			out.append(node)
	return out

## speed in m/s, steer in [-1, 1], braking true while the brake is held.
func update(delta: float, speed: float, steer: float, braking: bool) -> void:
	if root == null:
		return
	var wheel_r: float = float(root.get_meta("wheel_radius", 0.36))
	_wheel_spin += delta * speed / maxf(wheel_r, 0.05)
	_bob_phase += delta * (2.0 + absf(speed) * 0.6)
	_shake = maxf(0.0, _shake - delta * 3.0)
	for wheel in wheels():
		var tire := wheel.get_node_or_null("Tire") as Node3D
		var hub := wheel.get_node_or_null("Hub") as Node3D
		if tire != null:
			tire.rotation.x = _wheel_spin
		if hub != null:
			hub.rotation.x = _wheel_spin
		var front: bool = wheel.name.ends_with("FL") or wheel.name.ends_with("FR")
		if front:
			wheel.rotation.y = -steer * 0.42
	var body := root.get_node_or_null("Body") as Node3D
	if body != null:
		var bob: float = sin(_bob_phase) * 0.02 * clampf(absf(speed) / 12.0, 0.2, 1.0)
		body.position.y = body.position.y * 0.0 + _base_body_y(body) + bob
		body.rotation.x = 0.0
		if braking and speed > 1.0:
			body.rotation.x = 0.06
		elif speed > 14.0:
			body.rotation.x = -0.03
		if _shake > 0.0:
			body.rotation.z = sin(_bob_phase * 9.0) * 0.02 * _shake
		else:
			body.rotation.z = 0.0

func _base_body_y(body: Node3D) -> float:
	# Body rest height is baked into the factory build; recover it from
	# the metadata-free position by reading the stored rest value.
	if body.has_meta("rest_y"):
		return float(body.get_meta("rest_y"))
	var y: float = body.position.y
	body.set_meta("rest_y", y)
	return y

## Call on a collision: a short shake that decays in update().
func on_collision(strength: float = 1.0) -> void:
	_shake = clampf(strength, 0.0, 1.0)
