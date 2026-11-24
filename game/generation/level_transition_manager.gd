class_name LevelTransitionManager
extends RefCounted
## LevelTransitionManager - keeps only the segments the player can still reach.
##
## Infinite progression means unbounded levels; without eviction the scene tree grows until
## the process dies. This keeps the active segment plus a small look-ahead window and frees
## everything behind the player.

var _segments: Array = []          # [{ "z": float, "node": Node3D }]
var _freed: int = 0
var _peak: int = 0

func push(z: float, node: Node3D) -> void:
	_segments.append({"z": z, "node": node})
	_peak = maxi(_peak, _segments.size())

## Drop segments that are behind `current_z` beyond the retention window.
func evict_behind(current_z: float) -> int:
	var kept: Array = []
	var removed := 0
	for entry in _segments:
		var z: float = entry["z"]
		if z > current_z + 40.0:      # behind the player (track runs toward -Z)
			var node: Node3D = entry["node"]
			if is_instance_valid(node):
				node.queue_free()
				removed += 1
			_freed += 1
		else:
			kept.append(entry)
	_segments = kept
	return removed

func active_count() -> int:
	return _segments.size()

func peak_count() -> int:
	return _peak

func freed_count() -> int:
	return _freed

func clear() -> void:
	for entry in _segments:
		var node: Node3D = entry["node"]
		if is_instance_valid(node):
			node.queue_free()
	_segments.clear()
