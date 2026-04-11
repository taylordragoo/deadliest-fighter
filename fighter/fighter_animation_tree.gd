# fighter/fighter_animation_tree.gd
# FighterAnimationTree — forked from AnimationTreeSoulsBase (player/souls_animation_tree.gd).
# Stripped of: ladder, interact, item, gadget handlers.
# Renamed: player_node → fighter_node throughout.
extends AnimationTree
class_name FighterAnimationTree

@export var fighter_node: FighterBody
@onready var base_state_machine: AnimationNodeStateMachinePlayback = self["parameters/MovementStates/playback"]
@onready var current_weapon_tree: AnimationNodeStateMachinePlayback
@onready var weapon_type: String = "SLASH"
@onready var attack_count: int = 1
@onready var hurt_count: int = 1
@onready var anim_length: float

var last_oneshot: String = "Attack"
var lerp_movement: Vector2

var guard_value: float = 0.0

# --- Shim for dormant AnimationTree advance_expressions ---
# The interact_type expressions (e.g. interact_type == "GENERIC") resolve
# against the anim tree script itself, not fighter_node. This shim prevents
# errors if Godot evaluates the dormant Interacts sub-graph during init.
var interact_type: String = "GENERIC"

signal animation_measured

func _ready() -> void:
	if not fighter_node:
		push_warning(str(self) + ": fighter_node must be set")
		return

	fighter_node.dodge_started.connect(_on_dodge_started)
	fighter_node.jump_started.connect(_on_jump_started)
	fighter_node.sprint_started.connect(_on_sprint_started)
	fighter_node.landed_hard.connect(_on_landed_hard)

	fighter_node.weapon_change_started.connect(_on_weapon_change_started)
	fighter_node.weapon_change_ended.connect(_on_weapon_change_ended)
	fighter_node.strike_started.connect(_on_strike_started)

	fighter_node.parry_started.connect(_on_parry_started)
	fighter_node.hurt_started.connect(_on_hurt_started)
	fighter_node.block_started.connect(_on_block_started)

	fighter_node.death_started.connect(_on_death_started)

	_on_weapon_change_ended(fighter_node.weapon_type)

func _process(_delta: float) -> void:
	if not fighter_node:
		return
	if fighter_node.strafing:
		set_strafe()
	else:
		set_free_move()
	set_guarding()

func request_oneshot(oneshot: String) -> void:
	last_oneshot = oneshot
	set("parameters/" + oneshot + "/request", true)

func _on_landed_hard() -> void:
	request_oneshot("LandedHard")

func set_guarding() -> void:
	if fighter_node.guarding:
		guard_value = 1
	else:
		guard_value = 0
	var new_blend: float = lerp(float(get("parameters/Guarding/blend_amount")), guard_value, 0.2)
	set("parameters/Guarding/blend_amount", new_blend)

func _on_parry_started() -> void:
	request_oneshot("Parry")

func _on_strike_started(strike: Strike) -> void:
	# Set attack_count to select the correct animation in the ATTACK sub-tree.
	# The serialized AnimationTree graph has advance_expressions like
	# "attack_count == 1" on transitions to Slash1/Heavy1, "attack_count == 2"
	# for Slash2/Heavy2, etc. Phase 3 always uses the first attack animation
	# (attack_count = 1). Future phases can add a field to the Strike resource
	# to select a specific animation variant.
	attack_count = 1
	request_oneshot(strike.animation_name)

func _on_block_started() -> void:
	request_oneshot("Block")

func _on_hurt_started() -> void:
	abort_oneshot(last_oneshot)
	hurt_count = randi_range(1, 2)
	request_oneshot("Hurt")
	current_weapon_tree.start("MoveStrafe")

func abort_oneshot(_last_oneshot: String) -> void:
	set("parameters/" + _last_oneshot + "/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)

func _on_death_started() -> void:
	base_state_machine.travel("Death")

func _on_sprint_started() -> void:
	base_state_machine.travel("SPRINT_tree")

func _on_dodge_started() -> void:
	request_oneshot("Dodge")

func _on_jump_started() -> void:
	request_oneshot("Jump")

func _on_weapon_change_started() -> void:
	request_oneshot("WeaponChange")

func _on_weapon_change_ended(_new_weapon_type: String) -> void:
	var weapon_tree_exists: bool = tree_root.get_node("MovementStates").has_node(str(_new_weapon_type) + "_tree")
	if weapon_tree_exists:
		weapon_type = _new_weapon_type
	else:
		weapon_type = "SLASH"
	current_weapon_tree = get("parameters/MovementStates/" + str(_new_weapon_type) + "_tree/playback") as AnimationNodeStateMachinePlayback

## Called by FighterBody.reset_for_round() to return the animation tree
## from any state (including Death) to idle with the given weapon type.
func reset_to_idle(reset_weapon_type: String) -> void:
	# Travel back to the movement states — this leaves Death, Hurt, or any oneshot.
	base_state_machine.travel(reset_weapon_type + "_tree")
	_on_weapon_change_ended(reset_weapon_type)

func set_strafe() -> void:
	var new_blend := Vector2(fighter_node.strafe_cross_product, fighter_node.move_dot_product)
	if fighter_node.current_state == fighter_node.state.DYNAMIC_ACTION:
		new_blend *= 0.25
	else:
		new_blend *= Vector2(abs(fighter_node.input_dir.x), abs(fighter_node.input_dir.y))
	lerp_movement = Vector2(get("parameters/MovementStates/" + weapon_type + "_tree/MoveStrafe/blend_position"))
	lerp_movement = lerp(lerp_movement, new_blend, 0.2)
	set("parameters/MovementStates/" + weapon_type + "_tree/MoveStrafe/blend_position", lerp_movement)

func set_free_move() -> void:
	var new_blend := Vector2(0, abs(fighter_node.input_dir.x) + abs(fighter_node.input_dir.y))
	if fighter_node.current_state == fighter_node.state.DYNAMIC_ACTION:
		new_blend *= 0.4
	lerp_movement = Vector2(get("parameters/MovementStates/" + weapon_type + "_tree/MoveStrafe/blend_position"))
	lerp_movement = lerp(lerp_movement, new_blend, 0.2)
	set("parameters/MovementStates/" + weapon_type + "_tree/MoveStrafe/blend_position", lerp_movement)

func _on_animation_started(anim_name: String) -> void:
	anim_length = (get_node(anim_player) as AnimationPlayer).get_animation(anim_name).length
	animation_measured.emit(anim_length)

