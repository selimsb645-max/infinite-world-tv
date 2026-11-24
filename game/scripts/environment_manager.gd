class_name EnvironmentManager
extends Node
## Owns the environment themes: the five Phase 02 worlds plus the
## three Phase 03 worlds (Ocean, Fantasy Islands, Futuristic Highway).
## THEME_NAMES stays the Phase 02 menu list; THEMES holds all eight,
## which is what the procedural WorldGenerator draws from. A theme is pure data:
## sky/fog/light colours plus a decoration style and palette that
## WorldManager uses to build the level. apply_theme() re-skins the
## live scene (WorldEnvironment + DirectionalLight3D) instantly.

const THEME_NAMES: Array[String] = [
	"Green Valley", "Neon City", "Desert World", "Snow Mountain", "Space World",
]

const THEMES := {
	"Green Valley": {
		"sky_color": Color(0.53, 0.81, 0.92),
		"ground_color": Color(0.35, 0.75, 0.35),
		"path_color": Color(0.85, 0.75, 0.55),
		"fog_color": Color(0.75, 0.88, 0.95),
		"fog_density": 0.008,
		"sun_color": Color(1.0, 0.96, 0.85),
		"sun_energy": 1.15,
		"ambient_color": Color(0.65, 0.78, 0.9),
		"ambient_energy": 0.6,
		"decor": "trees",
		"decor_color": Color(0.16, 0.55, 0.25),
		"accent_color": Color(0.55, 0.35, 0.2),
		"obstacle_color": Color(0.9, 0.45, 0.2),
		"collectible_color": Color(1.0, 0.84, 0.25),
	},
	"Neon City": {
		"sky_color": Color(0.07, 0.03, 0.18),
		"ground_color": Color(0.13, 0.13, 0.22),
		"path_color": Color(0.2, 0.2, 0.35),
		"fog_color": Color(0.35, 0.1, 0.5),
		"fog_density": 0.02,
		"sun_color": Color(0.8, 0.6, 1.0),
		"sun_energy": 0.55,
		"ambient_color": Color(0.4, 0.3, 0.65),
		"ambient_energy": 0.7,
		"decor": "buildings",
		"decor_color": Color(0.1, 0.9, 0.9),
		"accent_color": Color(1.0, 0.2, 0.8),
		"obstacle_color": Color(1.0, 0.25, 0.6),
		"collectible_color": Color(0.3, 1.0, 1.0),
	},
	"Desert World": {
		"sky_color": Color(0.98, 0.85, 0.6),
		"ground_color": Color(0.9, 0.75, 0.45),
		"path_color": Color(0.8, 0.62, 0.38),
		"fog_color": Color(0.95, 0.82, 0.6),
		"fog_density": 0.012,
		"sun_color": Color(1.0, 0.85, 0.6),
		"sun_energy": 1.3,
		"ambient_color": Color(0.9, 0.8, 0.6),
		"ambient_energy": 0.55,
		"decor": "cacti",
		"decor_color": Color(0.25, 0.6, 0.3),
		"accent_color": Color(0.7, 0.5, 0.3),
		"obstacle_color": Color(0.75, 0.4, 0.2),
		"collectible_color": Color(1.0, 0.6, 0.2),
	},
	"Snow Mountain": {
		"sky_color": Color(0.8, 0.88, 0.98),
		"ground_color": Color(0.93, 0.95, 1.0),
		"path_color": Color(0.75, 0.82, 0.92),
		"fog_color": Color(0.9, 0.94, 1.0),
		"fog_density": 0.025,
		"sun_color": Color(0.95, 0.97, 1.0),
		"sun_energy": 1.0,
		"ambient_color": Color(0.8, 0.87, 0.98),
		"ambient_energy": 0.65,
		"decor": "pines",
		"decor_color": Color(0.2, 0.45, 0.35),
		"accent_color": Color(0.85, 0.9, 0.95),
		"obstacle_color": Color(0.4, 0.6, 0.9),
		"collectible_color": Color(0.5, 0.85, 1.0),
	},
	"Space World": {
		"sky_color": Color(0.01, 0.01, 0.05),
		"ground_color": Color(0.16, 0.12, 0.3),
		"path_color": Color(0.25, 0.2, 0.45),
		"fog_color": Color(0.08, 0.05, 0.2),
		"fog_density": 0.006,
		"sun_color": Color(0.85, 0.9, 1.0),
		"sun_energy": 0.8,
		"ambient_color": Color(0.35, 0.3, 0.6),
		"ambient_energy": 0.5,
		"decor": "crystals",
		"decor_color": Color(0.6, 0.3, 1.0),
		"accent_color": Color(0.3, 0.9, 0.7),
		"obstacle_color": Color(0.9, 0.3, 0.9),
		"collectible_color": Color(0.4, 1.0, 0.8),
	},
	"Ocean World": {
		"sky_color": Color(0.35, 0.75, 0.9),
		"ground_color": Color(0.85, 0.78, 0.55),
		"path_color": Color(0.55, 0.8, 0.85),
		"fog_color": Color(0.6, 0.85, 0.95),
		"fog_density": 0.01,
		"sun_color": Color(1.0, 0.98, 0.9),
		"sun_energy": 1.25,
		"ambient_color": Color(0.6, 0.8, 0.9),
		"ambient_energy": 0.65,
		"decor": "coral",
		"decor_color": Color(1.0, 0.45, 0.55),
		"accent_color": Color(0.1, 0.6, 0.75),
		"obstacle_color": Color(0.85, 0.35, 0.45),
		"collectible_color": Color(1.0, 0.9, 0.4),
	},
	"Fantasy Islands": {
		"sky_color": Color(0.75, 0.6, 0.95),
		"ground_color": Color(0.5, 0.85, 0.55),
		"path_color": Color(0.95, 0.85, 0.6),
		"fog_color": Color(0.85, 0.75, 0.98),
		"fog_density": 0.014,
		"sun_color": Color(1.0, 0.9, 0.95),
		"sun_energy": 1.1,
		"ambient_color": Color(0.8, 0.7, 0.95),
		"ambient_energy": 0.7,
		"decor": "mushrooms",
		"decor_color": Color(0.95, 0.4, 0.6),
		"accent_color": Color(0.5, 0.35, 0.9),
		"obstacle_color": Color(0.6, 0.35, 0.95),
		"collectible_color": Color(1.0, 0.95, 0.45),
	},
	"Futuristic Highway": {
		"sky_color": Color(0.05, 0.1, 0.25),
		"ground_color": Color(0.18, 0.2, 0.3),
		"path_color": Color(0.3, 0.35, 0.5),
		"fog_color": Color(0.15, 0.3, 0.55),
		"fog_density": 0.016,
		"sun_color": Color(0.7, 0.85, 1.0),
		"sun_energy": 0.7,
		"ambient_color": Color(0.35, 0.5, 0.8),
		"ambient_energy": 0.75,
		"decor": "pillars",
		"decor_color": Color(0.2, 0.9, 1.0),
		"accent_color": Color(1.0, 0.6, 0.15),
		"obstacle_color": Color(1.0, 0.5, 0.15),
		"collectible_color": Color(0.45, 1.0, 0.9),
	},
}

var current_theme: String = "Green Valley"

var _env_node: WorldEnvironment
var _environment: Environment
var _sun: DirectionalLight3D

func setup(parent: Node) -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.fog_enabled = true
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env_node = WorldEnvironment.new()
	_env_node.name = "WorldEnvironment"
	_env_node.environment = _environment
	parent.add_child(_env_node)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	_sun.shadow_enabled = true
	parent.add_child(_sun)
	apply_theme(current_theme)

func has_theme(theme_name: String) -> bool:
	return THEMES.has(theme_name)

func theme_data(theme_name: String) -> Dictionary:
	return THEMES.get(theme_name, THEMES["Green Valley"])

func apply_theme(theme_name: String) -> bool:
	if not THEMES.has(theme_name):
		return false
	current_theme = theme_name
	var t: Dictionary = THEMES[theme_name]
	if _environment != null:
		_environment.background_color = t["sky_color"]
		_environment.ambient_light_color = t["ambient_color"]
		_environment.ambient_light_energy = t["ambient_energy"]
		_environment.fog_light_color = t["fog_color"]
		_environment.fog_density = t["fog_density"]
	if _sun != null:
		_sun.light_color = t["sun_color"]
		_sun.light_energy = t["sun_energy"]
	return true

func sky_color_of(theme_name: String) -> Color:
	return THEMES[theme_name]["sky_color"]
