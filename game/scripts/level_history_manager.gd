class_name LevelHistoryManager
extends RefCounted
## Bounded history of recently generated levels: fingerprint, token
## set, world and seed per entry. Capacity is fixed by GenerationConfig
## (oldest entries are evicted), so memory stays flat no matter how
## many levels an endless session generates.
##
## Exact-duplicate checks run against the FULL retained history via a
## fingerprint index; structural-similarity checks run against the
## most recent window (older layouts may legitimately recur after the
## window has passed — that is the documented anti-repetition policy).

var _config: GenerationConfig
var _entries: Array[Dictionary] = []
var _fingerprint_counts: Dictionary = {}
var _fingerprints := LevelFingerprintManager.new()

func _init(config: GenerationConfig = null) -> void:
	_config = config if config != null else GenerationConfig.new()

func size() -> int:
	return _entries.size()

func capacity() -> int:
	return _config.history_size

func clear() -> void:
	_entries.clear()
	_fingerprint_counts.clear()

func add(level: Dictionary, fingerprint: String, tokens: Dictionary) -> void:
	_entries.append({
		"fingerprint": fingerprint,
		"tokens": tokens,
		"world": str(level.get("world", level.get("theme", ""))),
		"seed": int(level.get("seed", 0)),
		"level_number": int(level.get("level_number", 0)),
	})
	_fingerprint_counts[fingerprint] = int(_fingerprint_counts.get(fingerprint, 0)) + 1
	while _entries.size() > _config.history_size:
		var evicted: Dictionary = _entries.pop_front()
		var fp: String = str(evicted["fingerprint"])
		var remaining: int = int(_fingerprint_counts.get(fp, 0)) - 1
		if remaining <= 0:
			_fingerprint_counts.erase(fp)
		else:
			_fingerprint_counts[fp] = remaining

func has_fingerprint(fingerprint: String) -> bool:
	return _fingerprint_counts.has(fingerprint)

func entries() -> Array[Dictionary]:
	return _entries

## Highest structural similarity of `tokens` against the most recent
## `recent_window` retained entries.
func max_recent_similarity(tokens: Dictionary) -> float:
	var best: float = 0.0
	var start: int = maxi(0, _entries.size() - _config.recent_window)
	for i in range(start, _entries.size()):
		var other: Dictionary = _entries[i]["tokens"]
		best = maxf(best, _fingerprints.similarity(tokens, other))
	return best

## Worlds of the last `count` entries, most recent last.
func recent_worlds(count: int) -> Array[String]:
	var out: Array[String] = []
	var start: int = maxi(0, _entries.size() - count)
	for i in range(start, _entries.size()):
		out.append(str(_entries[i]["world"]))
	return out
