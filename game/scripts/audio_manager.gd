class_name AudioManager
extends Node
## Minimal original audio: soft synthesized sine blips (jump, collect,
## bump) generated with AudioStreamGenerator — no audio files, no
## external assets. Safe under the dummy headless audio driver: if no
## stream playback is available every call is a no-op.

var volume: float = 0.8

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "BlipPlayer"
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.25
	_player.stream = stream
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	set_volume(volume)

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))

func blip(frequency: float = 660.0, duration: float = 0.09) -> void:
	if _playback == null:
		return
	var frames := int(22050.0 * duration)
	var buffer := PackedVector2Array()
	buffer.resize(frames)
	for i in frames:
		var t := float(i) / 22050.0
		var fade := 1.0 - float(i) / float(frames)
		var s := sin(TAU * frequency * t) * 0.25 * fade * volume
		buffer[i] = Vector2(s, s)
	_playback.push_buffer(buffer)

func play_jump() -> void:
	blip(520.0, 0.08)

func play_collect() -> void:
	blip(880.0, 0.1)

func play_bump() -> void:
	blip(140.0, 0.12)

func play_switch() -> void:
	blip(720.0, 0.07)
