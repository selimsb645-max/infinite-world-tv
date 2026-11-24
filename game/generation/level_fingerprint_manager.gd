class_name LevelFingerprintManager
extends RefCounted
## LevelFingerprintManager - two different measures, because they catch different clones.
##
## fingerprint: exact identity. Same seed and same inputs must produce the same string, so a
## replay is provable. structural(): a small feature vector used for similarity, because a
## level with new colours and one extra crate is still the same level to a viewer.

func fingerprint(spec: Dictionary) -> String:
	var canonical := _canonical(spec)
	return canonical.sha256_text().substr(0, 16)

func _canonical(spec: Dictionary) -> String:
	var parts: Array = [String(spec.get("theme", "")), str(int(round(float(spec.get("length", 0.0)))))]
	for seg in spec.get("segments", []):
		parts.append("%s:%.0f" % [seg.get("type", ""), float(seg.get("length", 0.0))])
	for obs in spec.get("obstacles", []):
		var p: Vector3 = obs["pos"]
		var s: Vector3 = obs["size"]
		parts.append("%s@%.1f,%.1f:%.1fx%.1f" % [obs.get("kind", ""), p.x, p.z, s.x, s.y])
	return "|".join(parts)

## Structural signature: what a viewer would notice, not what the seed happens to be.
## Histograms of segment types and obstacle kinds do the discriminating; the scalars add the
## pacing. Cosine similarity on this vector separates "same level, new paint" from
## "different level that happens to share a theme".
func structural(spec: Dictionary) -> Array:
	var segment_kinds := ["run", "jump", "slide", "road", "curve", "tunnel", "bridge"]
	var obstacle_kinds := ["barrier", "crate", "rock", "ice_block", "low_bar", "high_bar", "speed_gate"]
	var segments: Array = spec.get("segments", [])
	var obstacles: Array = spec.get("obstacles", [])

	var seg_hist := {}
	for k in segment_kinds:
		seg_hist[k] = 0.0
	var obs_hist := {}
	for k in obstacle_kinds:
		obs_hist[k] = 0.0

	var vehicle_len := 0.0
	var total_len := 0.0
	for seg in segments:
		total_len += float(seg.get("length", 0.0))
		if seg.get("mode", "character") == "vehicle":
			vehicle_len += float(seg.get("length", 0.0))
		var type: String = seg.get("type", "run")
		seg_hist[type] = float(seg_hist.get(type, 0.0)) + 1.0

	var zs: Array = []
	var full_width := 0.0
	for obs in obstacles:
		var kind: String = obs.get("kind", "barrier")
		obs_hist[kind] = float(obs_hist.get(kind, 0.0)) + 1.0
		if float(obs["size"].x) >= GenerationConfig.TRACK_HALF_WIDTH:
			full_width += 1.0
		zs.append(float(obs["pos"].z))

	var seg_n := maxf(1.0, float(segments.size()))
	var obs_n := maxf(1.0, float(obstacles.size()))
	var mean_gap := 0.0
	if zs.size() > 1:
		zs.sort()
		for i in range(1, zs.size()):
			mean_gap += absf(float(zs[i]) - float(zs[i - 1]))
		mean_gap /= float(zs.size() - 1)

	var vec: Array = []
	vec.append(vehicle_len / maxf(1.0, total_len))
	vec.append(1.0 - vehicle_len / maxf(1.0, total_len))
	for k in segment_kinds:
		vec.append(float(seg_hist[k]) / seg_n)
	for k in obstacle_kinds:
		vec.append(float(obs_hist[k]) / obs_n)
	vec.append(clampf(float(obstacles.size()) / maxf(1.0, total_len) * 20.0, 0.0, 2.0))
	vec.append(clampf(mean_gap / 40.0, 0.0, 2.0))
	vec.append(clampf(total_len / 300.0, 0.0, 2.0))
	vec.append(clampf(full_width / obs_n, 0.0, 1.0))
	return vec

func similarity(a: Array, b: Array) -> float:
	# Mean absolute difference, not cosine. Cosine on sparse histograms sits at 0.99 for
	# genuinely different levels, which is useless as a duplicate signal; MAD separates them.
	var n: int = min(a.size(), b.size())
	if n == 0:
		return 0.0
	var total := 0.0
	for i in n:
		total += absf(float(a[i]) - float(b[i]))
	return clampf(1.0 - total / float(n), 0.0, 1.0)
