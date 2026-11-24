class_name ObjectPool
extends RefCounted
## Minimal keyed node pool. WorldManager uses it for the two
## high-churn node kinds in level building — obstacle bodies and
## collectible areas — so endless play reuses nodes instead of
## allocating/freeing hundreds per level. Each key is capped
## (GenerationConfig.pool_cap_per_key); nodes released beyond the cap
## are freed, which keeps pooled memory bounded too.

var _cap: int = 48
var _pooled: Dictionary = {}  # key -> Array[Node]
var reused_count: int = 0
var created_count: int = 0

func _init(cap_per_key: int = 48) -> void:
	_cap = maxi(cap_per_key, 0)

func acquire(key: String) -> Node:
	var arr: Array = _pooled.get(key, [])
	if arr.is_empty():
		return null
	var node: Node = arr.pop_back()
	_pooled[key] = arr
	reused_count += 1
	return node

func release(node: Node, key: String) -> void:
	if node == null:
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	var arr: Array = _pooled.get(key, [])
	if arr.size() >= _cap:
		node.queue_free()
		return
	arr.append(node)
	_pooled[key] = arr

func note_created() -> void:
	created_count += 1

func size(key: String = "") -> int:
	if key != "":
		return (_pooled.get(key, []) as Array).size()
	var total: int = 0
	for k in _pooled:
		total += (_pooled[k] as Array).size()
	return total

func clear() -> void:
	for k in _pooled:
		for node in _pooled[k]:
			if is_instance_valid(node):
				(node as Node).queue_free()
	_pooled.clear()
