# fighter/fighter_body.gd
# FighterBody — forked from CharacterBodySoulsBase (player/character_body_souls_base.gd).
# Stripped of: ladders, inventory, items, gadgets, interactables, direct input handling.
# All input comes through the brain's intent_* methods.
# Movement rewritten: strafing is opponent-relative (Phase 1 math), sprint is camera-relative.
extends CharacterBody3D
class_name FighterBody

# --- Stance enum (brain maps input → stance, fighter maps stance → weapon_type) ---
enum Stance { MIDDLE, UPPER, LOWER, SHEATHED }
const STANCE_TO_WEAPON: Dictionary = {
	Stance.MIDDLE: "SLASH",
	Stance.UPPER: "HEAVY",
}

# --- Animation tree ---
@export var anim_state_tree: FighterAnimationTree
@onready var anim_length: float = 0.5

# --- Camera (sprint/freelook movement only — strafing is opponent-relative) ---
var _cached_cam: Camera3D

# --- Opponent reference ---
@export var opponent_path: NodePath
var opponent: Node3D

# --- Weapon type / stance identity for the animation tree ---
# "SLASH" = MIDDLE stance, "HEAVY" = UPPER stance.
var weapon_type: String = "SLASH"
signal weapon_change_started
signal weapon_changed
signal weapon_change_ended

# --- Attack signals (souls template pattern: started → activated → ended) ---
signal attack_started
signal attack_activated
signal air_attack_started
signal big_attack_started
var attack_combo_timer: Timer = Timer.new()

# --- Guard / parry (Phase 5 wires these; kept so hit() compiles) ---
@onready var guarding: bool = false
@onready var can_be_hurt: bool = true
@onready var parry_active: bool = false
var parry_window: float = 0.3
signal parry_started
signal block_started

# --- Health (Phase 4 replaces with LimbHealth; kept so hit() compiles) ---
signal hurt_started
signal damage_taken
signal death_started
var is_dead: bool = false

# --- Shim for dormant AnimationTree advance_expressions ---
# The forked scene's AnimationTree graph has advance_expressions like
# "fighter_node.current_item.object_type == \"DRINK\"" in the UseItem
# sub-graph. That sub-graph is never entered at Phase 2, but Godot may
# evaluate the expression during tree init. This null satisfies the
# reference without adding item system code.
var current_item: Variant = null

# --- Jump and gravity ---
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var jump_velocity: float = 4.5
@onready var last_altitude: Vector3 = global_position
var _tracking_fall: bool = false
@export var hard_landing_height: float = 4.0
signal landed_hard
signal jump_started

# --- Dodge and sprint ---
@export var dodge_speed: float = 10.0
@onready var dodge_timer: Timer = Timer.new()
@onready var sprint_timer: Timer = Timer.new()
@export var sprint_speed: float = 7.0
signal dodge_started
signal dodge_ended
signal sprint_started

# --- Movement ---
var input_dir: Vector2
@export var default_speed: float = 4.0
@export var walk_speed: float = 1.0
@onready var speed: float = default_speed
var direction: Vector3 = Vector3.ZERO

# --- Strafing ---
var strafing: bool = true
@onready var strafe_cross_product: float = 0.0
@onready var move_dot_product: float = 0.0
signal strafe_toggled

# --- Re-engage tuning (ported from Phase 1) ---
@export var engage_range: float = 8.0
@export var engage_facing_dot: float = 0.6

# --- State machine ---
enum state { SPAWN, FREE, STATIC_ACTION, DYNAMIC_ACTION, DODGE, SPRINT, ATTACK }
@onready var current_state: int = state.STATIC_ACTION : set = change_state
signal changed_state

# =========================================================================
# Lifecycle
# =========================================================================

func _ready() -> void:
	if anim_state_tree:
		anim_state_tree.animation_measured.connect(_on_animation_measured)

	add_child(sprint_timer)
	sprint_timer.one_shot = true

	add_child(dodge_timer)
	dodge_timer.one_shot = true
	dodge_timer.connect("timeout", _on_dodge_timer_timeout)

	add_child(attack_combo_timer)
	attack_combo_timer.one_shot = true

	# Resolve opponent from NodePath — synchronous because siblings are
	# already in the tree when _ready() runs (Godot adds children depth-first).
	# An async frame-skip here would race with animation_measured below.
	if opponent == null and not opponent_path.is_empty():
		opponent = get_node_or_null(opponent_path) as Node3D

	# Wait for spawn animation, then transition to FREE
	if anim_state_tree:
		await anim_state_tree.animation_measured
	await get_tree().create_timer(anim_length).timeout
	current_state = state.FREE

# =========================================================================
# State machine
# =========================================================================

func change_state(new_state: int) -> void:
	current_state = new_state
	changed_state.emit(current_state)
	# Update strafing flag for the animation tree's set_strafe()/set_free_move() branch
	strafing = (new_state == state.FREE or new_state == state.DYNAMIC_ACTION)
	match current_state:
		state.FREE:
			speed = default_speed
		state.DODGE:
			speed = dodge_speed
		state.SPRINT:
			speed = sprint_speed
		state.DYNAMIC_ACTION:
			speed = walk_speed
		state.STATIC_ACTION:
			speed = 0.0

# =========================================================================
# Intent surface (called by FighterBrain subclasses)
# =========================================================================

## Continuous: the brain's desired movement vector this frame.
func intent_move(dir: Vector2) -> void:
	input_dir = dir

## Continuous: sprint held/released. Holding breaks lock.
func intent_sprint(held: bool) -> void:
	if held:
		if current_state == state.FREE:
			current_state = state.SPRINT
			sprint_started.emit()
	else:
		if current_state == state.SPRINT:
			if _should_re_engage_lock():
				current_state = state.FREE
			# else: stay in SPRINT, checked again next frame

## Rising-edge: request a stance change.
func intent_change_stance(stance: int) -> void:
	if stance not in STANCE_TO_WEAPON:
		return  # LOWER, SHEATHED are no-ops at Phase 2
	var new_weapon: String = STANCE_TO_WEAPON[stance]
	if new_weapon == weapon_type:
		return
	weapon_type = new_weapon
	if anim_state_tree:
		# Bypass weapon_change_started (no sheath/draw animation — instant swap)
		anim_state_tree._on_weapon_change_ended(weapon_type)

## Rising-edge: request a strike.
func intent_strike() -> void:
	if current_state == state.FREE:
		attack()

## Rising-edge: request a parry. (Phase 5)
func intent_parry() -> void:
	pass

## Rising-edge: request a dodge. (Phase 5)
func intent_dodge(_dir: Vector2) -> void:
	pass

## Toggle: sheathe/draw. Reserved; no-op at MVP.
func intent_sheathe(_sheathed: bool) -> void:
	pass

# =========================================================================
# Physics loop
# =========================================================================

func _physics_process(_delta: float) -> void:
	match current_state:
		state.FREE:
			if opponent:
				_face_opponent(0.25)
				_strafing_movement()
			else:
				_freelook_rotate()
				_freelook_movement()

		state.SPRINT:
			_freelook_rotate()
			_freelook_movement()

		state.DODGE:
			dash_movement()
			_freelook_rotate()

		state.ATTACK:
			dash_movement()

		state.DYNAMIC_ACTION:
			if opponent and strafing:
				_face_opponent(0.25)
				_strafing_movement()
			else:
				_freelook_movement()
				_freelook_rotate()

	apply_gravity(_delta)
	fall_check()

# =========================================================================
# Movement — Opponent-relative strafing (ported from Phase 1's fighter.gd)
# =========================================================================

func _strafing_movement() -> void:
	var desired := _compute_strafe_velocity() * speed
	var rate: float = 0.5 if is_on_floor() else 0.1
	velocity.x = move_toward(velocity.x, desired.x, rate)
	velocity.z = move_toward(velocity.z, desired.z, rate)
	# Update strafe blend values for the animation tree
	strafe_cross_product = input_dir.x
	move_dot_product = -input_dir.y
	move_and_slide()

func _compute_strafe_velocity() -> Vector3:
	if opponent == null:
		return Vector3.ZERO
	var to_opp := opponent.global_position - global_position
	to_opp.y = 0.0
	if to_opp.length_squared() < 0.0001:
		return Vector3.ZERO
	var forward := to_opp.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	return forward * (-input_dir.y) + right * input_dir.x

func _face_opponent(weight: float) -> void:
	if opponent == null:
		return
	var to_opp := opponent.global_position - global_position
	to_opp.y = 0.0
	if to_opp.length_squared() < 0.0001:
		return
	var target_yaw := atan2(to_opp.x, to_opp.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, weight)

func _should_re_engage_lock() -> bool:
	if opponent == null:
		return false
	var to_opp := opponent.global_position - global_position
	to_opp.y = 0.0
	var dist_sq := to_opp.length_squared()
	if dist_sq > engage_range * engage_range:
		return false
	if dist_sq < 0.0001:
		return true
	var to_opp_n := to_opp / sqrt(dist_sq)
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return false
	fwd = fwd.normalized()
	return fwd.dot(to_opp_n) >= engage_facing_dot

# =========================================================================
# Movement — Camera-relative freelook (kept from souls template, for sprint)
# =========================================================================

func _freelook_movement() -> void:
	var new_direction := _calc_cam_direction()
	if new_direction:
		var rate: float = 0.5 if is_on_floor() else 0.1
		velocity.x = move_toward(velocity.x, new_direction.x * speed, rate)
		velocity.z = move_toward(velocity.z, new_direction.z * speed, rate)
	else:
		velocity.x = move_toward(velocity.x, 0, 0.5)
		velocity.z = move_toward(velocity.z, 0, 0.5)
	move_and_slide()

func _freelook_rotate() -> void:
	if input_dir:
		var new_direction := _calc_cam_direction().normalized()
		var current_rotation := global_transform.basis.get_rotation_quaternion()
		var target_rotation := current_rotation.slerp(
			Quaternion(Vector3.UP, atan2(new_direction.x, new_direction.z)), 0.2)
		global_transform.basis = Basis(target_rotation)

func _calc_cam_direction() -> Vector3:
	var cam := _cached_cam
	if cam == null or not is_instance_valid(cam):
		cam = get_viewport().get_camera_3d()
		_cached_cam = cam
	if cam == null:
		return Vector3(input_dir.x, 0.0, input_dir.y)
	var forward_vector := Vector3(0, 0, 1).rotated(Vector3.UP, cam.global_rotation.y)
	var horizontal_vector := Vector3(1, 0, 0).rotated(Vector3.UP, cam.global_rotation.y)
	return forward_vector * input_dir.y + horizontal_vector * input_dir.x

# =========================================================================
# Attack (kept from souls template — Phase 3 replaces timer phasing)
# =========================================================================

func attack(_is_special_attack: bool = false) -> void:
	current_state = state.ATTACK
	if _is_special_attack:
		big_attack_started.emit()
	else:
		attack_started.emit()
	if anim_state_tree:
		await anim_state_tree.animation_measured
	await get_tree().create_timer(anim_length * 0.3).timeout
	attack_activated.emit()
	dash(Vector3.FORWARD, 0.3)
	await get_tree().create_timer(anim_length * 0.7).timeout
	if current_state == state.ATTACK:
		current_state = state.FREE

func air_attack() -> void:
	air_attack_started.emit()
	current_state = state.DYNAMIC_ACTION
	if anim_state_tree:
		await anim_state_tree.animation_measured
	await get_tree().create_timer(anim_length * 0.5).timeout
	attack_activated.emit()
	await get_tree().create_timer(anim_length * 0.5).timeout
	current_state = state.FREE

# =========================================================================
# Dash / dodge / sprint (kept from souls template)
# =========================================================================

func dash(_new_direction: Vector3 = Vector3.FORWARD, _duration: float = 0.1) -> void:
	speed = dodge_speed
	if _new_direction:
		direction = (global_position - to_global(_new_direction)).normalized()
	await get_tree().create_timer(_duration).timeout
	direction = Vector3.ZERO

func dash_movement() -> void:
	var rate := 0.1
	velocity.x = move_toward(velocity.x, direction.x * speed, rate)
	velocity.z = move_toward(velocity.z, direction.z * speed, rate)
	move_and_slide()

func dodge() -> void:
	current_state = state.DODGE
	can_be_hurt = false
	sprint_timer.stop()
	if input_dir:
		direction = _calc_cam_direction()
		dodge_started.emit()
	else:
		var backward_dir := (global_position - to_global(Vector3.BACK)).normalized()
		velocity = backward_dir * (dodge_speed * 0.75)
		dodge_started.emit()
	if anim_state_tree:
		await anim_state_tree.animation_measured
	dodge_timer.start(anim_length * 0.7)

func _on_dodge_timer_timeout() -> void:
	dodge_ended.emit()
	speed = default_speed
	current_state = state.FREE
	can_be_hurt = true

func end_sprint() -> void:
	if current_state == state.SPRINT:
		current_state = state.FREE

# =========================================================================
# Gravity / falling (kept from souls template)
# =========================================================================

func apply_gravity(_delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * _delta

func fall_check() -> void:
	if not is_on_floor() and not _tracking_fall:
		last_altitude = global_position
		_tracking_fall = true
	if is_on_floor() and _tracking_fall:
		var fall_distance: float = abs(last_altitude.y - global_position.y)
		if fall_distance > hard_landing_height:
			hard_landing()
		_tracking_fall = false

func hard_landing() -> void:
	current_state = state.STATIC_ACTION
	landed_hard.emit()
	anim_length = 0.4
	if anim_state_tree:
		await anim_state_tree.animation_measured
	await get_tree().create_timer(anim_length).timeout
	if current_state == state.STATIC_ACTION:
		current_state = state.FREE

func jump() -> void:
	if is_on_floor():
		if anim_state_tree:
			jump_started.emit()
			anim_length = 0.5
			await anim_state_tree.animation_measured
			await get_tree().create_timer(anim_length * 0.7).timeout
		velocity.y = jump_velocity

# =========================================================================
# Guard / parry / hit contract (kept from souls template)
# =========================================================================

func start_guard() -> void:
	guarding = true
	parry_active = true
	current_state = state.DYNAMIC_ACTION
	await get_tree().create_timer(parry_window).timeout
	parry_active = false

func end_guard() -> void:
	guarding = false
	parry_active = false
	current_state = state.FREE

func hit(_who: Node, _by_what: Variant) -> void:
	if can_be_hurt:
		if parry_active:
			parry()
			if _who.has_method("parried"):
				_who.parried()
			return
		elif guarding:
			block()
		else:
			damage_taken.emit(_by_what)
			hurt()

func block() -> void:
	current_state = state.STATIC_ACTION
	block_started.emit()
	if anim_state_tree:
		await anim_state_tree.animation_measured
	await get_tree().create_timer(anim_length).timeout
	if current_state == state.STATIC_ACTION:
		current_state = state.DYNAMIC_ACTION

func parry() -> void:
	current_state = state.STATIC_ACTION
	can_be_hurt = false
	parry_started.emit()
	if anim_state_tree:
		await anim_state_tree.animation_measured
	await get_tree().create_timer(anim_length).timeout
	if current_state == state.STATIC_ACTION:
		current_state = state.FREE
	can_be_hurt = true

func parried() -> void:
	# Called when this fighter's attack was parried. Phase 5 adds extended recovery.
	pass

func hurt() -> void:
	current_state = state.STATIC_ACTION
	can_be_hurt = false
	hurt_started.emit()
	if anim_state_tree:
		await anim_state_tree.animation_measured
	await get_tree().create_timer(anim_length).timeout
	if not is_dead:
		if current_state == state.STATIC_ACTION:
			current_state = state.FREE
		can_be_hurt = true

func death() -> void:
	current_state = state.STATIC_ACTION
	can_be_hurt = false
	is_dead = true
	death_started.emit()
	# Phase 6 handles round reset via FighterArena; no scene reload.

# =========================================================================
# Animation callback
# =========================================================================

func _on_animation_measured(_new_length: float) -> void:
	anim_length = _new_length - 0.05
