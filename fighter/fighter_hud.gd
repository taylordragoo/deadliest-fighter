# fighter/fighter_hud.gd
extends Control
class_name FighterHUD

@export var fighter_a_path: NodePath
@export var fighter_b_path: NodePath
@export var arena_path: NodePath

var fighter_a: FighterBody
var fighter_b: FighterBody
var arena: FighterArena

const DOT_RADIUS: float = 8.0

const LIMB_OFFSETS: Dictionary = {
	"head":  Vector2(0, -40),
	"torso": Vector2(0, 0),
	"arm_r": Vector2(30, -10),
	"arm_l": Vector2(-30, -10),
	"leg_r": Vector2(12, 40),
	"leg_l": Vector2(-12, 40),
}

const COLOR_OK := Color(0.2, 0.8, 0.2)
const COLOR_WOUNDED := Color(0.9, 0.8, 0.1)
const COLOR_CRIPPLED := Color(0.9, 0.15, 0.15)

const WEAPON_TO_STANCE_LABEL: Dictionary = {
	"SLASH": "MID",
	"HEAVY": "UP",
}

var _phase_label: Label
var _score_label: Label
var _stance_label_a: Label
var _stance_label_b: Label
var _phase_timer: float = 0.0
var _showing_fight_text: bool = false

func _ready() -> void:
	if not fighter_a_path.is_empty():
		fighter_a = get_node_or_null(fighter_a_path) as FighterBody
	if not fighter_b_path.is_empty():
		fighter_b = get_node_or_null(fighter_b_path) as FighterBody
	if not arena_path.is_empty():
		arena = get_node_or_null(arena_path) as FighterArena

	if fighter_a:
		fighter_a.limb_state_changed.connect(_on_limb_changed)
		fighter_a.death_started.connect(func(): queue_redraw())
	if fighter_b:
		fighter_b.limb_state_changed.connect(_on_limb_changed)
		fighter_b.death_started.connect(func(): queue_redraw())

	if arena:
		arena.round_phase_changed.connect(_on_round_phase_changed)

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Phase overlay label (centered, large)
	_phase_label = Label.new()
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_phase_label.set_anchors_preset(Control.PRESET_CENTER)
	_phase_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_phase_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_phase_label.custom_minimum_size = Vector2(400, 100)
	_phase_label.position = Vector2(-200, -50)
	_phase_label.add_theme_font_size_override("font_size", 48)
	_phase_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_phase_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_phase_label.add_theme_constant_override("shadow_offset_x", 2)
	_phase_label.add_theme_constant_override("shadow_offset_y", 2)
	_phase_label.text = ""
	add_child(_phase_label)

	# Score label (top center)
	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_score_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_score_label.custom_minimum_size = Vector2(300, 30)
	_score_label.position = Vector2(-150, 10)
	_score_label.add_theme_font_size_override("font_size", 24)
	_score_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_score_label.add_theme_constant_override("shadow_offset_x", 1)
	_score_label.add_theme_constant_override("shadow_offset_y", 1)
	_score_label.text = ""
	add_child(_score_label)

	# Stance indicator labels (below each limb diagram)
	_stance_label_a = _create_stance_label()
	add_child(_stance_label_a)
	_stance_label_b = _create_stance_label()
	add_child(_stance_label_b)

func _create_stance_label() -> Label:
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(60, 24)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	return lbl

func _process(delta: float) -> void:
	if _showing_fight_text:
		_phase_timer -= delta
		if _phase_timer <= 0.0:
			_showing_fight_text = false
			_phase_label.text = ""

	# Update stance labels every frame (simple, no signal needed)
	if fighter_a:
		_stance_label_a.text = WEAPON_TO_STANCE_LABEL.get(fighter_a.weapon_type, "?")
		_stance_label_a.position = Vector2(120 - 30, 135)
	if fighter_b:
		var vp_w := get_viewport_rect().size.x
		_stance_label_b.text = WEAPON_TO_STANCE_LABEL.get(fighter_b.weapon_type, "?")
		_stance_label_b.position = Vector2(vp_w - 120 - 30, 135)

func _on_round_phase_changed(phase: int, round_num: int) -> void:
	_showing_fight_text = false
	match phase:
		FighterArena.Phase.PRE_ROUND:
			_phase_label.text = "Round %d" % round_num
			_update_score()
		FighterArena.Phase.COUNTDOWN:
			_phase_label.text = "Ready..."
		FighterArena.Phase.FIGHTING:
			_phase_label.text = "Fight!"
			_showing_fight_text = true
			_phase_timer = 1.0
		FighterArena.Phase.RESULT:
			_phase_label.text = "Slain!"
			_update_score()
	queue_redraw()

func _update_score() -> void:
	if arena:
		_score_label.text = "P1  %d - %d  P2" % [arena.wins_a, arena.wins_b]

func _on_limb_changed(_limb: String, _new_state: int) -> void:
	queue_redraw()

func _draw() -> void:
	var vp_size := get_viewport_rect().size
	if fighter_a:
		_draw_fighter_diagram(Vector2(120, 80), fighter_a.limb_health)
	if fighter_b:
		_draw_fighter_diagram(Vector2(vp_size.x - 120, 80), fighter_b.limb_health)

func _draw_fighter_diagram(center: Vector2, limbs: LimbHealth) -> void:
	for limb_name in LimbHealth.LIMB_NAMES:
		var offset: Vector2 = LIMB_OFFSETS.get(limb_name, Vector2.ZERO)
		var integrity: int = limbs.get_integrity(limb_name)
		var color: Color
		match integrity:
			LimbHealth.Integrity.OK:
				color = COLOR_OK
			LimbHealth.Integrity.WOUNDED:
				color = COLOR_WOUNDED
			LimbHealth.Integrity.CRIPPLED:
				color = COLOR_CRIPPLED
			_:
				color = COLOR_OK
		draw_circle(center + offset, DOT_RADIUS, color)
		draw_arc(center + offset, DOT_RADIUS, 0, TAU, 24, Color(0, 0, 0, 0.5), 1.5)