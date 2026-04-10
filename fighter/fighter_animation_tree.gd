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
@onready var attack_timer: Timer = Timer.new()
@onready var hurt_count: int = 1
@onready var anim_length: float

var last_oneshot: String = "Attack"
var lerp_movement: Vector2

var guard_value: float = 0.0

# --- Shim properties for dormant AnimationTree advance_expressions ---
# The forked scene's AnimationTree graph contains serialized advance_expression
# strings in sub-graphs that are never entered at Phase 2 (Gadget, UseItem,
# Interacts). Those expressions reference player_node.gadget_type,
# player_node.current_item, and interact_type. After renaming player_node →
# fighter_node in the .tscn, the expressions resolve against fighter_node
# (FighterBody) — but FighterBody doesn't have gadget_type or current_item.
# These shims prevent expression evaluation errors if Godot touches the
# dormant sub-graphs during tree initialization.
var gadget_type: String = "SHIELD"
var interact_type: String = "GENERIC"

signal animation_measured

func _ready() -> void:
	add_child(attack_timer)
	attack_timer.one_shot = true
	attack_timer.timeout.connect(_on_attack_timer_timeout)

	if not fighter_node:
		push_warning(str(self) + ": fighter_node must be set")
		return

	fighter_node.dodge_started.connect(_on_dodge_started)
	fighter_node.jump_started.connect(_on_jump_started)
	fighter_node.sprint_started.connect(_on_sprint_started)
	fighter_node.landed_hard.connect(_on_landed_hard)

	fighter_node.weapon_change_started.connect(_on_weapon_change_started)
	fighter_node.weapon_change_ended.connect(_on_weapon_change_ended)
	fighter_node.attack_started.connect(_on_attack_started)
	fighter_node.big_attack_started.connect(_on_big_attack_started)
	fighter_node.air_attack_started.connect(_on_air_attack_started)

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

func _on_attack_started() -> void:
	request_oneshot("Attack")
	await animation_measured
	attack_timer.start(anim_length + 0.2)
	match attack_count:
		1:
			attack_count = 2
		2:
			attack_count = 1

func _on_big_attack_started() -> void:
	attack_count = 3
	request_oneshot("Attack")
	await animation_measured
	attack_timer.start(anim_length + 0.2)
	attack_count = 2

func _on_air_attack_started() -> void:
	attack_count = 4
	request_oneshot("Attack")
	await animation_measured
	attack_timer.start(0.1)

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

func _on_weapon_change_ended(_new_weapon_type) -> void:
	var weapon_tree_exists: bool = tree_root.get_node("MovementStates").has_node(str(_new_weapon_type) + "_tree")
	if weapon_tree_exists:
		weapon_type = _new_weapon_type
	else:
		weapon_type = "SLASH"
	current_weapon_tree = get("parameters/MovementStates/" + str(_new_weapon_type) + "_tree/playback")

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
	anim_length = get_node(anim_player).get_animation(anim_name).length
	animation_measured.emit(anim_length)

func _on_attack_timer_timeout() -> void:
	attack_count = 1
