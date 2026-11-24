class_name EnvironmentGenerator
extends RefCounted
## EnvironmentGenerator - per-level variation inside a world.
##
## Without this, eight worlds still look like eight levels because every visit to Neon City
## is identical. Each visit shifts light energy, fog density, decor density and a small
## palette offset, all seeded, so two Neon City runs are recognisably the same place but not
## the same picture.

func variation(world_id: String, rng: RandomNumberGenerator) -> Dictionary:
	return {
		"world": world_id,
		"light_energy_scale": rng.randf_range(0.85, 1.2),
		"fog_scale": rng.randf_range(0.7, 1.35),
		"decor_density": rng.randf_range(0.6, 1.4),
		"palette_shift": rng.randf_range(-0.06, 0.06),
		"obstacle_palette_offset": rng.randf_range(-0.05, 0.05),
		"sky_rotation": rng.randf_range(0.0, 360.0),
	}
