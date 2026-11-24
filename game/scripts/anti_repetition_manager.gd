class_name AntiRepetitionManager
extends RefCounted
## Decides whether a candidate level is fresh enough to serve.
## Rejects (a) exact structural duplicates — same fingerprint as ANY
## retained history entry, even under a different seed/theme — and
## (b) near-duplicates whose structural similarity to a recent level
## meets/exceeds the configured threshold. The LevelGenerator reacts
## to a rejection by regenerating with a derived seed (bounded), so
## this manager is a pure predicate over LevelHistoryManager data.

var _config: GenerationConfig
var _history: LevelHistoryManager
var _fingerprints := LevelFingerprintManager.new()

var rejected_duplicates: int = 0
var rejected_similar: int = 0

func _init(config: GenerationConfig, history: LevelHistoryManager) -> void:
	_config = config
	_history = history

## Returns {accepted, duplicate, max_similarity, fingerprint, tokens}.
func evaluate(level: Dictionary) -> Dictionary:
	var fingerprint: String = _fingerprints.fingerprint_for(level)
	var tokens: Dictionary = _fingerprints.tokens_for(level)
	if _history.has_fingerprint(fingerprint):
		rejected_duplicates += 1
		return {"accepted": false, "duplicate": true, "max_similarity": 1.0,
			"fingerprint": fingerprint, "tokens": tokens}
	var sim: float = _history.max_recent_similarity(tokens)
	if sim >= _config.similarity_threshold:
		rejected_similar += 1
		return {"accepted": false, "duplicate": false, "max_similarity": sim,
			"fingerprint": fingerprint, "tokens": tokens}
	return {"accepted": true, "duplicate": false, "max_similarity": sim,
		"fingerprint": fingerprint, "tokens": tokens}

## Registers an accepted level in history.
func commit(level: Dictionary, evaluation: Dictionary) -> void:
	_history.add(level, str(evaluation["fingerprint"]), evaluation["tokens"])
