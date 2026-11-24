class_name LevelFingerprintManager
extends RefCounted
## Turns a generated level into (a) a canonical structural fingerprint
## string and (b) a set of structural tokens used for similarity.
##
## The fingerprint deliberately describes STRUCTURE ONLY — segment kind
## sequence, obstacle type sequence (as bigrams, so order matters),
## quantized lane offsets, platform/gap/gate counts. Colours, theme and
## seed are NOT part of it, so a level that is merely a recolor or a
## re-seed of an earlier layout still collides with the original.

func canonical_string(level: Dictionary) -> String:
	var parts: Array[String] = []
	var segments: Array = level.get("segments", [])
	var seg_tokens: Array[String] = []
	for seg in segments:
		seg_tokens.append("%s:%s:%s" % [str(seg.get("mode", "?")), str(seg.get("feature", "?")),
			str(int(round(float(seg.get("lane_offset", 0.0)))))])
	parts.append("segs=" + ",".join(seg_tokens))
	var obstacles: Array = level.get("obstacles", [])
	var types: Array[String] = []
	for ob in obstacles:
		types.append(str(ob.get("type", "?")))
	var bigrams: Array[String] = []
	for i in types.size():
		var nxt: String = types[i + 1] if i + 1 < types.size() else "END"
		bigrams.append(types[i] + ">" + nxt)
	bigrams.sort()
	parts.append("obs=" + ",".join(bigrams))
	parts.append("nobs=%d" % _bucket(types.size(), 4))
	parts.append("plat=%d" % _bucket((level.get("platforms", []) as Array).size(), 2))
	parts.append("mplat=%d" % _bucket((level.get("moving_platforms", []) as Array).size(), 1))
	parts.append("gate=%d" % _bucket((level.get("gates", []) as Array).size(), 2))
	parts.append("gap=%d" % _bucket((level.get("gaps", []) as Array).size(), 1))
	return "|".join(parts)

func fingerprint_for(level: Dictionary) -> String:
	return canonical_string(level).md5_text()

## Structural token set for Jaccard similarity. Includes the segment
## sequence itself (not just a set) via position-tagged tokens, plus
## obstacle bigrams and count buckets.
func tokens_for(level: Dictionary) -> Dictionary:
	var set := {}
	var segments: Array = level.get("segments", [])
	for i in segments.size():
		var seg: Dictionary = segments[i]
		set["seg%d:%s:%s" % [i, str(seg.get("mode", "?")), str(seg.get("feature", "?"))]] = true
		set["lane%d:%d" % [i, int(round(float(seg.get("lane_offset", 0.0))))]] = true
	var obstacles: Array = level.get("obstacles", [])
	var types: Array[String] = []
	for ob in obstacles:
		types.append(str(ob.get("type", "?")))
		set["ob:" + str(ob.get("type", "?"))] = true
	for i in types.size():
		var nxt: String = types[i + 1] if i + 1 < types.size() else "END"
		set["bg:" + types[i] + ">" + nxt] = true
	set["nobs:%d" % _bucket(types.size(), 4)] = true
	set["plat:%d" % _bucket((level.get("platforms", []) as Array).size(), 2)] = true
	set["gate:%d" % _bucket((level.get("gates", []) as Array).size(), 2)] = true
	set["gap:%d" % _bucket((level.get("gaps", []) as Array).size(), 1)] = true
	return set

## Jaccard similarity of two token sets, in [0, 1]. Identical
## structure -> 1.0 regardless of theme/seed.
func similarity(tokens_a: Dictionary, tokens_b: Dictionary) -> float:
	if tokens_a.is_empty() and tokens_b.is_empty():
		return 1.0
	var intersection: int = 0
	for key in tokens_a:
		if tokens_b.has(key):
			intersection += 1
	var union_count: int = tokens_a.size() + tokens_b.size() - intersection
	if union_count <= 0:
		return 0.0
	return float(intersection) / float(union_count)

func _bucket(value: int, step: int) -> int:
	return int(floor(float(value) / float(maxi(step, 1))))
