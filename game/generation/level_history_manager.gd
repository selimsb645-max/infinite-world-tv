class_name LevelHistoryManager
extends RefCounted
## LevelHistoryManager - a bounded record of what has already been generated.
##
## Bounded on purpose: an infinite game cannot keep every level forever, and the generator
## only ever asks about the recent window. Older entries fall out, so memory is flat no
## matter how long the session runs.

var _fingerprints: Array[String] = []
var _features: Array = []
var _worlds: Array[String] = []
var _total_generated: int = 0
var _rejections: int = 0

func record(fingerprint: String, features: Array, world: String) -> void:
	_fingerprints.append(fingerprint)
	_features.append(features)
	_worlds.append(world)
	_total_generated += 1
	while _fingerprints.size() > GenerationConfig.HISTORY_SIZE:
		_fingerprints.pop_front()
		_features.pop_front()
		_worlds.pop_front()

func count_rejection() -> void:
	_rejections += 1

func has_fingerprint(fp: String) -> bool:
	return _fingerprints.has(fp)

func recent_worlds(n: int) -> Array:
	var out: Array = []
	var start: int = max(0, _worlds.size() - n)
	for i in range(start, _worlds.size()):
		out.append(_worlds[i])
	return out

func recent_features(n: int) -> Array:
	var out: Array = []
	var start: int = max(0, _features.size() - n)
	for i in range(start, _features.size()):
		out.append(_features[i])
	return out

func size() -> int:
	return _fingerprints.size()

func total_generated() -> int:
	return _total_generated

func rejections() -> int:
	return _rejections

func clear() -> void:
	_fingerprints.clear()
	_features.clear()
	_worlds.clear()
	_total_generated = 0
	_rejections = 0
