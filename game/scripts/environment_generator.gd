class_name EnvironmentGenerator
extends RefCounted
## Produces the per-level environmental variation of a world: a small
## deterministic palette shift (hue rotation of the theme's colours),
## fog density scaling and decoration density. This is what stops two
## levels in the same world from looking identical, while the world's
## identity (sky family, decor style) stays recognisable. Structure is
## NOT varied here — that is the route/segment generators' job, and
## the fingerprint system ignores colour entirely.

## Returns a theme dictionary in exactly the shape WorldManager.build()
## consumes, derived from the base theme with a seeded variation.
func vary_theme(base_theme: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var theme: Dictionary = base_theme.duplicate()
	var hue_shift: float = rng.randf_range(-0.045, 0.045)
	var sat_scale: float = rng.randf_range(0.92, 1.08)
	for key in ["sky_color", "ground_color", "path_color", "fog_color",
			"decor_color", "accent_color", "obstacle_color", "collectible_color"]:
		if theme.has(key):
			theme[key] = _shifted(theme[key], hue_shift, sat_scale)
	theme["fog_density"] = float(theme.get("fog_density", 0.01)) * rng.randf_range(0.8, 1.25)
	return theme

func decor_count(rng: RandomNumberGenerator, base_count: int) -> int:
	return clampi(base_count + rng.randi_range(-6, 8), 12, 44)

func _shifted(color: Color, hue_shift: float, sat_scale: float) -> Color:
	var h: float = color.h + hue_shift
	h = h - floor(h)
	return Color.from_hsv(h, clampf(color.s * sat_scale, 0.0, 1.0), color.v, color.a)
