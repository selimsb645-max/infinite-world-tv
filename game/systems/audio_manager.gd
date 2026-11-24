extends Node
## AudioManager - procedural SFX, no audio files in the repo.
##
## Phase 02 only needs feedback tones (jump, land, mode switch, finish). They are generated as
## AudioStreamWAV buffers at runtime so the project stays asset-free and Content ID has nothing
## to match. Music beds arrive with the Blender/audio pipeline in Phase 03.

var _players: Array[AudioStreamPlayer] = []
var enabled := true

func _ready() -> void:
	for i in range(4):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

func _tone(freq: float, dur: float, volume_db: float = -12.0) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(rate * dur)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / float(rate)
		var env := 1.0 - (t / dur)
		var s := sin(TAU * freq * t) * env * 0.6
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream

func play(kind: String) -> void:
	if not enabled or _players.is_empty():
		return
	var freq := 440.0
	var dur := 0.12
	var vol := -14.0
	match kind:
		"jump": freq = 620.0; dur = 0.10
		"land": freq = 220.0; dur = 0.08
		"switch": freq = 880.0; dur = 0.16; vol = -10.0
		"finish": freq = 990.0; dur = 0.35; vol = -8.0
		"bump": freq = 160.0; dur = 0.09
	for p in _players:
		if not p.playing:
			p.stream = _tone(freq, dur)
			p.volume_db = vol
			p.play()
			return
