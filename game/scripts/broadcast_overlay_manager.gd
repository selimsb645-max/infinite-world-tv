class_name BroadcastOverlayManager
extends CanvasLayer
## Phase 06 — original broadcast graphics, drawn as a CanvasLayer
## above the game HUD so the viewport capture includes them. Four
## small edge panels only — current world, current level, score,
## gameplay mode, a thin level-progress bar and optional channel
## branding — with translucent backgrounds so gameplay is never
## obstructed. All text is set through the set_* methods (GameManager
## feeds them from the same values it gives the HUD).

var world_name: String = ""
var level_name: String = ""
var score: int = 0
var mode_name: String = ""
var progress: float = 0.0
var branding_enabled: bool = true

var _world_label: Label
var _level_label: Label
var _score_label: Label
var _mode_label: Label
var _progress_bar: ProgressBar
var _brand_label: Label

func _init(show_branding: bool = true, channel_name: String = "INFINITE WORLD TV") -> void:
	layer = 10
	branding_enabled = show_branding
	_build(channel_name)

func set_world(value: String) -> void:
	world_name = value
	_world_label.text = "WORLD  %s" % value

func set_level(value: String) -> void:
	level_name = value
	_level_label.text = "LEVEL  %s" % value

func set_score(value: int) -> void:
	score = value
	_score_label.text = "SCORE  %d" % value

func set_mode(value: String) -> void:
	mode_name = value
	_mode_label.text = "MODE  %s" % value

func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	_progress_bar.value = progress * 1000.0

func snapshot_state() -> Dictionary:
	return {"world": world_name, "level": level_name, "score": score,
		"mode": mode_name, "progress": progress,
		"branding": branding_enabled and _brand_label.visible}

func _build(channel_name: String) -> void:
	var left := _make_panel()
	left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left.offset_left = 12.0
	left.offset_top = 12.0
	left.offset_right = 224.0
	var left_box := VBoxContainer.new()
	left.add_child(left_box)
	_world_label = _make_label(left_box)
	_level_label = _make_label(left_box)

	var right := _make_panel()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -212.0
	right.offset_right = -12.0
	right.offset_top = 12.0
	var right_box := VBoxContainer.new()
	right.add_child(right_box)
	_score_label = _make_label(right_box)
	_mode_label = _make_label(right_box)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1000.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(0, 8)
	_progress_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_progress_bar.offset_left = 12.0
	_progress_bar.offset_right = -12.0
	_progress_bar.offset_top = -20.0
	_progress_bar.offset_bottom = -12.0
	add_child(_progress_bar)

	_brand_label = Label.new()
	_brand_label.text = channel_name
	_brand_label.add_theme_font_size_override("font_size", 15)
	_brand_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_brand_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_brand_label.offset_left = -260.0
	_brand_label.offset_right = -12.0
	_brand_label.offset_top = -52.0
	_brand_label.offset_bottom = -28.0
	_brand_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_brand_label.visible = branding_enabled
	add_child(_brand_label)

	set_world("—")
	set_level("—")
	set_score(0)
	set_mode("—")

func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.45)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(200, 0)
	add_child(panel)
	return panel

func _make_label(parent: Control) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	parent.add_child(label)
	return label
