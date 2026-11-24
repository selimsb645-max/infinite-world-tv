class_name AudioLibrary
extends Node
## Phase 05 — original audio pipeline.
##
## Loads the original WAV clips synthesised by tools/generate_audio.py
## (all original synthesis — no external or licensed audio). Music and
## ambience loop; one-shots play through a small pool of players so
## overlapping effects never cut each other off. If a clip is missing
## the call is a no-op and the error is reported by load_all() instead
## of crashing the game.

const AUDIO_DIR := "res://assets/audio/"

const CLIPS := {
	"jump": {"file": "jump.wav", "loop": false},
	"land": {"file": "land.wav", "loop": false},
	"collect": {"file": "collect.wav", "loop": false},
	"coin": {"file": "coin.wav", "loop": false},
	"star": {"file": "star.wav", "loop": false},
	"energy": {"file": "energy.wav", "loop": false},
	"ui_click": {"file": "ui_click.wav", "loop": false},
	"run": {"file": "run.wav", "loop": false},
	"engine": {"file": "engine.wav", "loop": true},
	"music": {"file": "music.wav", "loop": true},
	"transition": {"file": "transition.wav", "loop": false},
	"celebrate": {"file": "celebrate.wav", "loop": false},
	"ambience_green_valley": {"file": "ambience_green_valley.wav", "loop": true},
	"ambience_neon_city": {"file": "ambience_neon_city.wav", "loop": true},
	"ambience_desert_world": {"file": "ambience_desert_world.wav", "loop": true},
	"ambience_snow_mountain": {"file": "ambience_snow_mountain.wav", "loop": true},
	"ambience_space_world": {"file": "ambience_space_world.wav", "loop": true},
	"ambience_ocean_world": {"file": "ambience_ocean_world.wav", "loop": true},
	"ambience_fantasy_islands": {"file": "ambience_fantasy_islands.wav", "loop": true},
	"ambience_futuristic_highway": {"file": "ambience_futuristic_highway.wav", "loop": true},
}

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _ambience_player: AudioStreamPlayer

static func clip_names() -> Array[String]:
	var out: Array[String] = []
	for key in CLIPS.keys():
		out.append(key)
	return out

static func ambience_for_world(world: String) -> String:
	return "ambience_" + world.to_lower().replace(" ", "_")

## Loads every clip. Returns the list of clip names that failed.
func load_all() -> Array[String]:
	var failed: Array[String] = []
	_streams.clear()
	for clip_name in CLIPS.keys():
		var stream := stream(clip_name)
		if stream == null:
			failed.append(clip_name)
	return failed

func stream(clip_name: String) -> AudioStream:
	if _streams.has(clip_name):
		return _streams[clip_name]
	if not CLIPS.has(clip_name):
		return null
	var path: String = AUDIO_DIR + str((CLIPS[clip_name] as Dictionary)["file"])
	if not ResourceLoader.exists(path):
		return null
	var loaded := load(path) as AudioStream
	if loaded == null:
		return null
	if bool((CLIPS[clip_name] as Dictionary)["loop"]) and loaded is AudioStreamWAV:
		(loaded as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(loaded as AudioStreamWAV).loop_begin = 0
		(loaded as AudioStreamWAV).loop_end = int(loaded.get_length() * loaded.mix_rate)
	_streams[clip_name] = loaded
	return loaded

func duration(clip_name: String) -> float:
	var s := stream(clip_name)
	if s == null:
		return 0.0
	return s.get_length()

func play(clip_name: String, volume_db: float = 0.0) -> void:
	var s := stream(clip_name)
	if s == null:
		return
	var player: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			player = p
			break
	if player == null:
		if _players.size() >= 6:
			return
		player = AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % _players.size()
		add_child(player)
		_players.append(player)
	player.stream = s
	player.volume_db = volume_db
	player.play()

func play_music() -> void:
	_music_player = _start_loop(_music_player, "music", -12.0)

func play_ambience(world: String) -> void:
	_ambience_player = _start_loop(_ambience_player, ambience_for_world(world), -16.0)

func stop_loops() -> void:
	if _music_player != null:
		_music_player.stop()
	if _ambience_player != null:
		_ambience_player.stop()

func _start_loop(player: AudioStreamPlayer, clip_name: String, volume_db: float) -> AudioStreamPlayer:
	var s := stream(clip_name)
	if s == null:
		return player
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = "Loop_%s" % clip_name
		add_child(player)
	player.stream = s
	player.volume_db = volume_db
	if not player.playing:
		player.play()
	return player
