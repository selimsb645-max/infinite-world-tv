class_name UIManager
extends CanvasLayer
## All UI is built in code (no fragile scene files): Main Menu with
## Play / mode select / theme select / Settings, HUD (score, level,
## mode, speed, hint), and a Pause menu (Resume / Restart / Menu).

signal play_requested(mode: String, theme: String)
signal resume_requested
signal restart_requested
signal quit_to_menu_requested
signal volume_changed(value: float)
signal quality_toggled(low_quality: bool)

var _menu: Control
var _settings: Control
var _hud: Control
var _pause: Control
var _mode_select: OptionButton
var _theme_select: OptionButton
var _score_label: Label
var _level_label: Label
var _mode_label: Label
var _speed_label: Label
var _hint_label: Label
var _volume_slider: HSlider

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_menu()
	_build_hud()
	_build_pause()
	show_menu()

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.22, 0.92)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	p.add_theme_stylebox_override("panel", style)
	return p

func _centered(control: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.add_child(control)
	return center

func _title(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	return label

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 44)
	b.add_theme_font_size_override("font_size", 20)
	return b

func _build_menu() -> void:
	var panel := _panel()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	vbox.add_child(_title("INFINITE WORLD TV", 40))
	var sub := Label.new()
	sub.text = "Run, jump, slide — then hop in the car!"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	vbox.add_child(sub)
	var mode_row := HBoxContainer.new()
	var mode_label := Label.new()
	mode_label.text = "Start as:"
	mode_row.add_child(mode_label)
	_mode_select = OptionButton.new()
	_mode_select.add_item("Character", 0)
	_mode_select.add_item("Vehicle", 1)
	mode_row.add_child(_mode_select)
	vbox.add_child(mode_row)
	var theme_row := HBoxContainer.new()
	var theme_label := Label.new()
	theme_label.text = "World theme:"
	theme_row.add_child(theme_label)
	_theme_select = OptionButton.new()
	for theme_name in EnvironmentManager.THEME_NAMES:
		_theme_select.add_item(theme_name)
	theme_row.add_child(_theme_select)
	vbox.add_child(theme_row)
	var play := _button("▶  PLAY")
	play.pressed.connect(func() -> void:
		var m := "vehicle" if _mode_select.selected == 1 else "character"
		play_requested.emit(m, _theme_select.get_item_text(_theme_select.selected)))
	vbox.add_child(play)
	var settings_btn := _button("Settings")
	settings_btn.pressed.connect(func() -> void: _settings.visible = not _settings.visible)
	vbox.add_child(settings_btn)
	_settings = VBoxContainer.new()
	_settings.add_theme_constant_override("separation", 8)
	var vol_row := HBoxContainer.new()
	var vol_label := Label.new()
	vol_label.text = "Volume"
	vol_row.add_child(vol_label)
	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.05
	_volume_slider.value = 0.8
	_volume_slider.custom_minimum_size = Vector2(160, 24)
	_volume_slider.value_changed.connect(func(v: float) -> void: volume_changed.emit(v))
	vol_row.add_child(_volume_slider)
	_settings.add_child(vol_row)
	var quality := CheckBox.new()
	quality.text = "Low quality (faster, no shadows)"
	quality.toggled.connect(func(on: bool) -> void: quality_toggled.emit(on))
	_settings.add_child(quality)
	_settings.visible = false
	vbox.add_child(_settings)
	var help := Label.new()
	help.text = "Move: A/D or ←/→   Jump: Space   Slide: S   Drive: W/S\nSwitch mode: Tab / E (at the glowing pad)   Pause: Esc / P"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 14)
	vbox.add_child(help)
	_menu = _centered(panel)
	add_child(_menu)

func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("separation", 30)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	_score_label = _hud_label("Score: 0")
	_level_label = _hud_label("Level 1")
	_mode_label = _hud_label("Mode: Character")
	_speed_label = _hud_label("Speed: 0")
	top.add_child(_score_label)
	top.add_child(_level_label)
	top.add_child(_mode_label)
	top.add_child(_speed_label)
	_hud.add_child(top)
	_hint_label = _hud_label("")
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.position.y = -70
	_hud.add_child(_hint_label)
	add_child(_hud)

func _hud_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label

func _build_pause() -> void:
	var panel := _panel()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	vbox.add_child(_title("PAUSED", 32))
	var resume := _button("Resume")
	resume.pressed.connect(func() -> void: resume_requested.emit())
	vbox.add_child(resume)
	var restart := _button("Restart Level")
	restart.pressed.connect(func() -> void: restart_requested.emit())
	vbox.add_child(restart)
	var quit := _button("Quit to Menu")
	quit.pressed.connect(func() -> void: quit_to_menu_requested.emit())
	vbox.add_child(quit)
	_pause = _centered(panel)
	add_child(_pause)

func show_menu() -> void:
	_menu.visible = true
	_hud.visible = false
	_pause.visible = false

func show_hud() -> void:
	_menu.visible = false
	_hud.visible = true
	_pause.visible = false

func show_pause(value: bool) -> void:
	_pause.visible = value

func is_pause_visible() -> bool:
	return _pause.visible

func set_score(value: int) -> void:
	_score_label.text = "Score: %d" % value

func set_level(text: String) -> void:
	_level_label.text = text

func set_mode(text: String) -> void:
	_mode_label.text = "Mode: %s" % text

func set_speed(value: float) -> void:
	_speed_label.text = "Speed: %d" % int(round(value * 3.6))

func show_hint(text: String) -> void:
	_hint_label.text = text
