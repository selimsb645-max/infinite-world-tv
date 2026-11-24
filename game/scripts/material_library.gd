class_name MaterialLibrary
extends RefCounted
## Phase 05 — material & visual effects library.
##
## Original material library: one palette per world (drawn from the
## EnvironmentManager themes so worlds stay consistent), lighting
## presets per world, and VFX descriptors + builders for the common
## effects (speed lines, jump puff, collect sparkle, landing dust,
## transition flash). Everything is procedural StandardMaterial3D /
## GPUParticles3D — no external textures or shaders.

const VFX := {
	"speed_lines": {"amount": 24, "lifetime": 0.4, "color": Color(1, 1, 1), "size": 0.06},
	"jump_puff": {"amount": 12, "lifetime": 0.5, "color": Color(0.9, 0.9, 0.9), "size": 0.12},
	"collect_sparkle": {"amount": 16, "lifetime": 0.6, "color": Color(1.0, 0.84, 0.25), "size": 0.08},
	"landing_dust": {"amount": 14, "lifetime": 0.5, "color": Color(0.8, 0.75, 0.6), "size": 0.14},
	"transition_flash": {"amount": 20, "lifetime": 0.35, "color": Color(0.6, 0.9, 1.0), "size": 0.1},
	"celebrate_burst": {"amount": 32, "lifetime": 0.9, "color": Color(1.0, 0.6, 0.9), "size": 0.09},
}

static func vfx_names() -> Array[String]:
	var out: Array[String] = []
	for key in VFX.keys():
		out.append(key)
	return out

static func vfx_spec(effect_name: String) -> Dictionary:
	if not VFX.has(effect_name):
		return {}
	return VFX[effect_name]

## Full material palette for one world: ground, path, decor, accent,
## obstacle and collectible colours, all from the world theme.
static func palette(world: String) -> Dictionary:
	var env := EnvironmentManager.new()
	if not env.has_theme(world):
		return {}
	var theme: Dictionary = env.theme_data(world)
	if theme.is_empty():
		return {}
	return {
		"sky": theme["sky_color"],
		"ground": theme["ground_color"],
		"path": theme["path_color"],
		"fog": theme["fog_color"],
		"decor": theme["decor_color"],
		"accent": theme["accent_color"],
		"obstacle": theme["obstacle_color"],
		"collectible": theme["collectible_color"],
		"sun": theme["sun_color"],
		"ambient": theme["ambient_color"],
	}

static func material(color: Color, emission: float = 0.0, roughness: float = 0.7) -> StandardMaterial3D:
	var mat := CollisionManager.make_material(color, emission)
	mat.roughness = roughness
	return mat

## Lighting preset for a world: sun energy/colour, ambient energy and
## fog density, matching the EnvironmentManager theme.
static func lighting_preset(world: String) -> Dictionary:
	var env := EnvironmentManager.new()
	if not env.has_theme(world):
		return {}
	var theme: Dictionary = env.theme_data(world)
	if theme.is_empty():
		return {}
	return {
		"sun_color": theme["sun_color"],
		"sun_energy": float(theme["sun_energy"]),
		"ambient_color": theme["ambient_color"],
		"ambient_energy": float(theme["ambient_energy"]),
		"fog_color": theme["fog_color"],
		"fog_density": float(theme["fog_density"]),
	}

## Builds a one-shot GPUParticles3D for an effect. emitting=false by
## default; call play_effect() on it to fire once.
static func build_vfx(effect_name: String) -> GPUParticles3D:
	var spec: Dictionary = vfx_spec(effect_name)
	if spec.is_empty():
		return null
	var particles := GPUParticles3D.new()
	particles.name = "VFX_%s" % effect_name
	particles.amount = int(spec["amount"])
	particles.lifetime = float(spec["lifetime"])
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.emitting = false
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0, 1, 0)
	material.spread = 45.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 5.0
	material.gravity = Vector3(0, -4, 0)
	material.color = spec["color"]
	particles.process_material = material
	var draw_pass := SphereMesh.new()
	draw_pass.radius = float(spec["size"])
	draw_pass.height = float(spec["size"]) * 2.0
	particles.draw_pass_1 = draw_pass
	return particles
