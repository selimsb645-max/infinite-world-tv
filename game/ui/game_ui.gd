extends CanvasLayer
## GameUI - menu, HUD, pause, level complete, settings.
##
## Built in code rather than a .tscn so every control is created in one readable place and a
## headless test can find it by name (get_node("Menu/PlayButton")). Colours follow the Phase 01
## broadcast palette: near-black stage, one hot accent, heavy display type.

signal play_pressed
signal resume_pressed
signal restart_pressed
signal next_pressed
signal settings_pressed
signal mode_selected(mode: String)
signal quit_pressed

const BG := Color(0.05, 0.06, 0.09)
const PANEL := Color(0.09, 0.10, 0.14, 0.92)
const ACCENT := Color(1.0, 0.18, 0.18)
const INK := Color(0.97, 0.97, 1.0)
const MUTED := Color(0.62, 0.66, 0.74)

var menu_root: Control
var hud_root: Control
var pause_root: Control
var complete_root: Control
var settings_root: Control
var score_label: Label
var level_label: Label
var mode_label: Label
var selected_mode := "character"

func _ready() -> void:
	layer = 10
	_build_menu()
	_build_hud()
	_build_pause()
	_build_complete()
	_build_settings()
	show_menu()

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(34)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _label(text: String, size: int, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _button(text: String, size: int = 26) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 62)
	b.add_theme_font_size_override("font_size", size)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.06)
	normal.set_corner_radius_all(12)
	normal.set_content_margin_all(14)
	var hover := normal.duplicate()
	hover.bg_color = ACCENT
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	return b

func _full_rect() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	return c

func _build_menu() -> void:
	menu_root = _full_rect()
	menu_root.name = "Menu"
	add_child(menu_root)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(center)

	var panel := _panel()
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.name = "MenuBox"
	v.add_theme_constant_override("separation", 18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)

	v.add_child(_label("INFINITE WORLD TV", 64))
	v.add_child(_label("Run. Race. Repeat forever.", 22, MUTED))

	var play := _button("PLAY", 32)
	play.name = "PlayButton"
	play.pressed.connect(func(): play_pressed.emit())
	v.add_child(play)

	var mode_box := HBoxContainer.new()
	mode_box.name = "ModeBox"
	mode_box.add_theme_constant_override("separation", 12)
	var char_btn := _button("Character", 20)
	char_btn.name = "ModeCharacter"
	char_btn.pressed.connect(func(): _select_mode("character"))
	var veh_btn := _button("Vehicle", 20)
	veh_btn.name = "ModeVehicle"
	veh_btn.pressed.connect(func(): _select_mode("vehicle"))
	mode_box.add_child(char_btn)
	mode_box.add_child(veh_btn)
	v.add_child(mode_box)

	var settings := _button("Settings", 20)
	settings.name = "SettingsButton"
	settings.pressed.connect(func(): settings_pressed.emit())
	v.add_child(settings)

func _select_mode(m: String) -> void:
	selected_mode = m
	if menu_root:
		var char_btn := menu_root.get_node_or_null("CenterContainer/PanelContainer/MenuBox/ModeBox/ModeCharacter")
		var veh_btn := menu_root.get_node_or_null("CenterContainer/PanelContainer/MenuBox/ModeBox/ModeVehicle")
		if char_btn: char_btn.modulate = ACCENT if m == "character" else Color.WHITE
		if veh_btn: veh_btn.modulate = ACCENT if m == "vehicle" else Color.WHITE

func _build_hud() -> void:
	hud_root = _full_rect()
	hud_root.name = "HUD"
	add_child(hud_root)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("separation", 24)
	top.offset_left = 28
	top.offset_top = 20
	hud_root.add_child(top)

	level_label = _label("LEVEL 1", 28)
	level_label.name = "LevelLabel"
	top.add_child(level_label)

	mode_label = _label("CHARACTER", 22, MUTED)
	mode_label.name = "ModeLabel"
	top.add_child(mode_label)

	score_label = _label("0", 40, ACCENT)
	score_label.name = "ScoreLabel"
	score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	score_label.offset_left = -220
	score_label.offset_top = 18
	hud_root.add_child(score_label)

func _build_pause() -> void:
	pause_root = _full_rect()
	pause_root.name = "Pause"
	add_child(pause_root)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.65)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_root.add_child(center)
	var panel := _panel()
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	v.add_child(_label("PAUSED", 46))
	var resume := _button("Resume", 24)
	resume.name = "ResumeButton"
	resume.pressed.connect(func(): resume_pressed.emit())
	v.add_child(resume)
	var restart := _button("Restart", 24)
	restart.name = "RestartButton"
	restart.pressed.connect(func(): restart_pressed.emit())
	v.add_child(restart)
	var quit := _button("Main Menu", 20)
	quit.name = "QuitButton"
	quit.pressed.connect(func(): quit_pressed.emit())
	v.add_child(quit)

func _build_complete() -> void:
	complete_root = _full_rect()
	complete_root.name = "Complete"
	add_child(complete_root)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	complete_root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	complete_root.add_child(center)
	var panel := _panel()
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	v.add_child(_label("LEVEL COMPLETE", 44))
	var next := _button("Next Level", 26)
	next.name = "NextButton"
	next.pressed.connect(func(): next_pressed.emit())
	v.add_child(next)
	var again := _button("Replay", 20)
	again.name = "ReplayButton"
	again.pressed.connect(func(): restart_pressed.emit())
	v.add_child(again)

func _build_settings() -> void:
	settings_root = _full_rect()
	settings_root.name = "Settings"
	add_child(settings_root)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_root.add_child(center)
	var panel := _panel()
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	v.add_child(_label("SETTINGS", 40))
	v.add_child(_label("Audio feedback", 22, MUTED))
	var toggle := CheckButton.new()
	toggle.name = "AudioToggle"
	toggle.button_pressed = true
	toggle.toggled.connect(func(on: bool): audio_toggled.emit(on))
	v.add_child(toggle)
	v.add_child(_label("Fullscreen (Alt+Enter in the editor)", 18, MUTED))
	var back := _button("Back", 20)
	back.name = "SettingsBack"
	back.pressed.connect(func(): settings_visible = false; show_menu())
	v.add_child(back)

signal audio_toggled(on: bool)

var settings_visible := false:
	set(value):
		settings_visible = value
		if settings_root: settings_root.visible = value
		if value and menu_root: menu_root.visible = false
		if value and hud_root: hud_root.visible = false

func show_menu() -> void:
	menu_root.visible = true
	hud_root.visible = false
	pause_root.visible = false
	complete_root.visible = false
	settings_root.visible = false

func show_game() -> void:
	menu_root.visible = false
	hud_root.visible = true
	pause_root.visible = false
	complete_root.visible = false
	settings_root.visible = false

func show_pause() -> void:
	pause_root.visible = true

func hide_pause() -> void:
	pause_root.visible = false

func show_complete() -> void:
	complete_root.visible = true

func set_score(value: int) -> void:
	if score_label: score_label.text = str(value)

func set_level(index: int, name: String) -> void:
	if level_label: level_label.text = "LEVEL %d  %s" % [index + 1, name.to_upper()]

func set_mode(m: String) -> void:
	if mode_label: mode_label.text = m.to_upper()
