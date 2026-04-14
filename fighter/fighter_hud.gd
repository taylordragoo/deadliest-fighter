# fighter/fighter_hud.gd
extends Control
class_name FighterHUD

@export var fighter_a_path: NodePath
@export var fighter_b_path: NodePath
var fighter_a: FighterBody
var fighter_b: FighterBody

const DOT_RADIUS: float = 8.0
const DIAGRAM_SPACING: float = 30.0

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

func _ready() -> void:
	if not fighter_a_path.is_empty():
		fighter_a = get_node_or_null(fighter_a_path) as FighterBody
	if not fighter_b_path.is_empty():
		fighter_b = get_node_or_null(fighter_b_path) as FighterBody

	if fighter_a:
		fighter_a.limb_state_changed.connect(_on_limb_changed)
		fighter_a.death_started.connect(func(): queue_redraw())
	if fighter_b:
		fighter_b.limb_state_changed.connect(_on_limb_changed)
		fighter_b.death_started.connect(func(): queue_redraw())

	set_anchors_preset(Control.PRESET_TOP_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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
