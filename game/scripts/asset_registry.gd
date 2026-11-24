class_name AssetRegistry
extends RefCounted
## Phase 05 — asset management system.
##
## The single registry for every Phase 05 asset: characters, vehicles,
## environment props, obstacles, collectibles, materials/VFX and
## audio clips. validate() builds one of everything and reports any
## gap; summary() counts what the pipeline owns. The registry is pure
## data + factories — it never changes gameplay or generation.

static func summary() -> Dictionary:
	var total_props: int = 0
	for world in EnvironmentAssetLibrary.world_names():
		total_props += EnvironmentAssetLibrary.prop_kinds(world).size()
	return {
		"characters": CharacterFactory.character_names().size(),
		"character_variants": CharacterFactory.variant_count(),
		"vehicles": VehicleFactory.vehicle_names().size(),
		"worlds": EnvironmentAssetLibrary.world_names().size(),
		"environment_props": total_props,
		"obstacles": ObstacleCollectibleLibrary.obstacle_names().size(),
		"collectibles": ObstacleCollectibleLibrary.collectible_names().size(),
		"animation_states": CharacterAnimation.STATES.size(),
		"vfx": MaterialLibrary.vfx_names().size(),
		"audio_clips": AudioLibrary.clip_names().size(),
	}

## Builds one of every registered asset and checks the counts the
## spec requires. Returns an array of error strings (empty = valid).
## audio is a ready AudioLibrary node (or null to skip audio checks).
static func validate(audio: AudioLibrary = null) -> Array[String]:
	var errors: Array[String] = []
	var names := CharacterFactory.character_names()
	if names.size() != 4:
		errors.append("characters: expected 4, got %d" % names.size())
	for character_name in names:
		for variant in CharacterFactory.variant_count():
			var built := CharacterFactory.build(character_name, variant)
			if built == null:
				errors.append("character %s variant %d: build returned null" % [character_name, variant])
				continue
			for part in ["Body", "Head", "Accessory", "ArmL", "ArmR", "LegL", "LegR"]:
				if built.get_node_or_null(part) == null:
					errors.append("character %s: missing part %s" % [character_name, part])
			built.queue_free()
	var vehicles := VehicleFactory.vehicle_names()
	if vehicles.size() != 5:
		errors.append("vehicles: expected 5, got %d" % vehicles.size())
	for vehicle_name in vehicles:
		var built_vehicle := VehicleFactory.build(vehicle_name)
		if built_vehicle == null:
			errors.append("vehicle %s: build returned null" % vehicle_name)
			continue
		for wheel_name in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
			if built_vehicle.get_node_or_null(wheel_name) == null:
				errors.append("vehicle %s: missing %s" % [vehicle_name, wheel_name])
		var spec: Dictionary = VehicleFactory.collision_spec(vehicle_name)
		if spec.is_empty() or not spec.has("size"):
			errors.append("vehicle %s: missing collision spec" % vehicle_name)
		built_vehicle.queue_free()
	var worlds := EnvironmentAssetLibrary.world_names()
	if worlds.size() != 8:
		errors.append("worlds: expected 8, got %d" % worlds.size())
	for world in worlds:
		var kinds := EnvironmentAssetLibrary.prop_kinds(world)
		if kinds.size() < 4:
			errors.append("world %s: only %d props" % [world, kinds.size()])
		for kind in kinds:
			var prop := EnvironmentAssetLibrary.build_prop(world, kind)
			if prop == null:
				errors.append("world %s prop %s: build returned null" % [world, kind])
			else:
				prop.queue_free()
		var palette: Dictionary = MaterialLibrary.palette(world)
		if palette.size() < 8:
			errors.append("world %s: palette incomplete (%d entries)" % [world, palette.size()])
		var lighting: Dictionary = MaterialLibrary.lighting_preset(world)
		if lighting.is_empty():
			errors.append("world %s: missing lighting preset" % world)
	if ObstacleCollectibleLibrary.obstacle_names().size() != 8:
		errors.append("obstacles: expected 8, got %d" % ObstacleCollectibleLibrary.obstacle_names().size())
	for kind in ObstacleCollectibleLibrary.obstacle_names():
		var obstacle := ObstacleCollectibleLibrary.build_obstacle(kind)
		if obstacle == null or not obstacle.is_in_group("obstacle"):
			errors.append("obstacle %s: not built as obstacle group" % kind)
		else:
			obstacle.queue_free()
	if ObstacleCollectibleLibrary.collectible_names().size() != 5:
		errors.append("collectibles: expected 5, got %d" % ObstacleCollectibleLibrary.collectible_names().size())
	for kind in ObstacleCollectibleLibrary.collectible_names():
		var item := ObstacleCollectibleLibrary.build_collectible(kind)
		if item == null or not item.is_in_group("collectible"):
			errors.append("collectible %s: not built as collectible group" % kind)
		else:
			item.queue_free()
	if CharacterAnimation.STATES.size() != 10:
		errors.append("animation states: expected 10, got %d" % CharacterAnimation.STATES.size())
	for effect_name in MaterialLibrary.vfx_names():
		var vfx := MaterialLibrary.build_vfx(effect_name)
		if vfx == null:
			errors.append("vfx %s: build returned null" % effect_name)
		else:
			vfx.queue_free()
	if audio != null:
		var failed: Array[String] = audio.load_all()
		for clip_name in failed:
			errors.append("audio clip missing: %s" % clip_name)
		for clip_name in AudioLibrary.clip_names():
			if audio.duration(clip_name) <= 0.0:
				errors.append("audio clip zero length: %s" % clip_name)
	return errors
