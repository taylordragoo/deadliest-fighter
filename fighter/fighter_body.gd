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

var attack_combo_timer: Timer = Timer.new()

# --- Strike system (Phase 3: sim-clock authoritative) ---
## Current Strike resource being executed (null when not striking)
var current_strike: Strike = null

## Stance → Strike resource lookup. Loaded in _ready().
var STANCE_TO_STRIKE: Dictionary = {}

## Preloaded strike resources
@export var strike_upper: Strike
@export var strike_middle: Strike

## Reference to the weapon Area3D for hitbox control.
## Set via export to WeaponSystem/RightHand/HandPivot/Sword in the scene.
@export var weapon_hitbox: Area3D

## Round ID — incremented on every round reset. In-flight coroutines
## (execute_strike, hurt, parry, etc.) capture this at start and bail
## if it changes, preventing stale timers from corrupting the next round.
var _round_id: int = 0

signal strike_started(strike: Strike)
signal strike_activated(strike: Strike)
signal strike_ended(strike: Strike)

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

# --- Shims for dormant AnimationTree advance_expressions ---
# The forked scene's AnimationTree graph has advance_expressions that
# reference fighter_node properties from stripped systems. These sub-graphs
# are never entered at Phase 2, but Godot may evaluate the expressions
# during tree init. These shims prevent "Invalid get index" errors.
#   fighter_node.gadget_type == "SHIELD"  (Gadget sub-graph)
#   fighter_node.current_item.object_type == "DRINK"/"THROWN"  (UseItem sub-graph)
#   fighter_node.current_item == null  (UseItem sub-graph)
var gadget_type: String = "SHIELD"
var current_item: ItemStub = ItemStub.new()

## Minimal stub satisfying dormant advance_expressions that dereference
## current_item.object_type. Avoids depending on the souls ItemResource.
class ItemStub:
	var object_type: String = "NONE"

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
enum state { SPAWN, FREE, STATIC_ACTION, DYNAMIC_ACTION, DODGE, SPRINT, WINDING_UP, STRIKING, RECOVERING, HURT, DEAD }
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

	# Build (stance, dir) → strike lookup. Key is Vector2i(Stance, StrikeDir).
	# Phase 3: only SLASH_HORIZONTAL. Future dirs add more entries, no code change.
	if strike_upper:
		STANCE_TO_STRIKE[Vector2i(Stance.UPPER, Strike.StrikeDir.SLASH_HORIZONTAL)] = strike_upper
	if strike_middle:
		STANCE_TO_STRIKE[Vector2i(Stance.MIDDLE, Strike.StrikeDir.SLASH_HORIZONTAL)] = strike_middle

	# Auto-find weapon hitbox if not set via export
	if weapon_hitbox == null:
		var weapon_system := get_node_or_null("WeaponSystem")
		if weapon_system:
			for child in weapon_system.get_children():
				weapon_hitbox = _find_first_area3d(child)
				if weapon_hitbox:
					break

	# Auto-load strike resources if not set via export
	if strike_upper == null:
		strike_upper = load("res://fighter/strikes/upper_horizontal.tres")
		if strike_upper:
			STANCE_TO_STRIKE[Vector2i(Stance.UPPER, Strike.StrikeDir.SLASH_HORIZONTAL)] = strike_upper
	if strike_middle == null:
		strike_middle = load("res://fighter/strikes/middle_horizontal.tres")
		if strike_middle:
			STANCE_TO_STRIKE[Vector2i(Stance.MIDDLE, Strike.StrikeDir.SLASH_HORIZONTAL)] = strike_middle

	# Connect weapon hitbox body_entered
	if weapon_hitbox:
		weapon_hitbox.monitoring = false
		weapon_hitbox.body_entered.connect(_on_weapon_body_entered)

	# Ensure this fighter is in the "Targets" group so opponents' weapon
	# Area3Ds can detect it. The hit contract requires both the Targets
	# physics layer (layer 3) and the "Targets" group.
	if not is_in_group("Targets"):
		add_to_group("Targets")

	# Add collision layer 3 (Targets) so opponent sword Area3Ds can detect this body.
	# Layer 2 (Player) is kept from the scene file.
	collision_layer |= (1 << 2)  # layer 3 (0-indexed bit 2)

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
		state.WINDING_UP:
			speed = 0.0
		state.STRIKING:
			speed = 0.0
		state.RECOVERING:
			speed = 0.0
		state.HURT:
			speed = 0.0
		state.DEAD:
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
	# Cannot change stance while executing a strike
	if current_state in [state.WINDING_UP, state.STRIKING, state.RECOVERING]:
		return
	if stance not in STANCE_TO_WEAPON:
		return  # LOWER, SHEATHED are no-ops at Phase 2
	var new_weapon: String = STANCE_TO_WEAPON[stance]
	if new_weapon == weapon_type:
		return
	weapon_type = new_weapon
	if anim_state_tree:
		anim_state_tree._on_weapon_change_ended(weapon_type)

## Rising-edge: request a strike with the given stance and direction.
## Matches the spec's Brain→Fighter contract: intent_strike(stance, dir).
## Phase 3: dir is always SLASH_HORIZONTAL. The parameter exists so the
## contract is stable when directional strikes arrive later.
func intent_strike(stance: int = -1, dir: int = Strike.StrikeDir.SLASH_HORIZONTAL) -> void:
	# Accept strike from FREE or SPRINT. Sprinting auto-breaks lock
	# and forces re-lock per spec § Movement sub-model.
	if current_state == state.SPRINT:
		current_state = state.FREE  # break sprint, re-lock
	if current_state != state.FREE:
		return
	if stance < 0:
		# Default: use current stance
		stance = STANCE_TO_WEAPON.find_key(weapon_type)
		if stance == null:
			stance = Stance.MIDDLE
	execute_strike(stance, dir)

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

		state.WINDING_UP:
			if opponent:
				_face_opponent(0.15)

		state.STRIKING:
			dash_movement()

		state.RECOVERING:
			pass  # Frozen in place, vulnerable

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
# Strike system (Phase 3 — sim-clock authoritative timing)
# =========================================================================

func execute_strike(stance: int, dir: int) -> void:
	# Look up strike by (stance, dir) composite key
	var key := Vector2i(stance, dir)
	var strike: Strike = STANCE_TO_STRIKE.get(key)
	if strike == null:
		return

	current_strike = strike
	var round_at_start := _round_id

	# --- WINDING_UP ---
	current_state = state.WINDING_UP

	# Trigger animation via strike_started (visualization only — sim clock is authoritative).
	# FighterAnimationTree._on_strike_started reads strike.animation_name to pick the oneshot.
	strike_started.emit(strike)

	# Dev-time timing comparison — fire-and-forget, does NOT block the sim clock.
	if anim_state_tree:
		_check_strike_timing_async(strike)

	# Sim-clock authoritative: wind_up_time governs, not anim_length.
	await get_tree().create_timer(strike.wind_up_time).timeout

	# Guard: bail if round reset or state changed (e.g. got hit during wind-up)
	if _round_id != round_at_start or current_state != state.WINDING_UP:
		current_strike = null
		return

	# --- STRIKING ---
	current_state = state.STRIKING
	strike_activated.emit(strike)
	_arm_weapon(true)
	dash(Vector3.FORWARD, min(strike.active_time, 0.3))

	await get_tree().create_timer(strike.active_time).timeout

	if _round_id != round_at_start or current_state != state.STRIKING:
		_arm_weapon(false)
		current_strike = null
		return

	_arm_weapon(false)

	# --- RECOVERING ---
	current_state = state.RECOVERING
	strike_ended.emit(strike)

	await get_tree().create_timer(strike.recover_time).timeout

	if _round_id != round_at_start:
		current_strike = null
		return
	if current_state == state.RECOVERING:
		current_state = state.FREE
	current_strike = null

func _arm_weapon(armed: bool) -> void:
	if weapon_hitbox:
		weapon_hitbox.monitoring = armed

## Walk a subtree to find the first Area3D descendant.
func _find_first_area3d(node: Node) -> Area3D:
	if node is Area3D:
		return node
	for child in node.get_children():
		var found := _find_first_area3d(child)
		if found:
			return found
	return null

## Dev-time only: awaits animation_measured and warns if declared strike
## timing diverges from the actual animation length by >20%. Fire-and-forget —
## this never blocks the sim clock.
func _check_strike_timing_async(strike: Strike) -> void:
	if not anim_state_tree:
		return
	await anim_state_tree.animation_measured
	var declared_total := strike.wind_up_time + strike.active_time + strike.recover_time
	if abs(anim_length - declared_total) / max(declared_total, 0.01) > 0.2:
		push_warning("Strike '%s' timing mismatch: declared=%.2f anim=%.2f" % [
			strike.strike_id, declared_total, anim_length])

func _on_weapon_body_entered(body: Node3D) -> void:
	if body == self:
		return
	if not body.is_in_group("Targets"):
		return
	if current_strike == null:
		return
	if current_state != state.STRIKING:
		return

	# Map FighterBody states to HitResolver's decoupled CombatState enum
	var attacker_combat := _to_combat_state(current_state)
	var target_combat := HitResolver.CombatState.IDLE
	var target_can_be_hurt := true
	if body is FighterBody:
		target_combat = _to_combat_state(body.current_state)
		target_can_be_hurt = body.can_be_hurt

	var outcome := HitResolver.resolve(
		current_strike,
		attacker_combat,
		target_combat,
		target_can_be_hurt
	)

	if outcome["type"] == "HIT":
		if body.has_method("hit"):
			body.hit(self, outcome)
		# Disarm after first hit to prevent multi-hit
		_arm_weapon(false)

## Map FighterBody's internal state enum to HitResolver.CombatState.
## This is the single translation point — HitResolver never imports
## FighterBody.state.
static func _to_combat_state(fighter_state: int) -> int:
	match fighter_state:
		state.WINDING_UP:
			return HitResolver.CombatState.WINDING_UP
		state.STRIKING:
			return HitResolver.CombatState.STRIKING
		state.RECOVERING:
			return HitResolver.CombatState.RECOVERING
		state.DODGE:
			return HitResolver.CombatState.DODGING
		state.HURT:
			return HitResolver.CombatState.HURT
		state.DEAD:
			return HitResolver.CombatState.DEAD
		# Phase 5: add PARRYING mapping when parry state exists
		_:
			return HitResolver.CombatState.IDLE

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
	# Guard: if we're no longer in DODGE (e.g., round reset changed state),
	# don't mutate state.
	if current_state != state.DODGE:
		return
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
	var round_at_start := _round_id
	if anim_state_tree:
		await anim_state_tree.animation_measured
	await get_tree().create_timer(anim_length).timeout
	if _round_id != round_at_start:
		return
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
	var round_at_start := _round_id
	await get_tree().create_timer(parry_window).timeout
	if _round_id != round_at_start:
		return
	parry_active = false

func end_guard() -> void:
	guarding = false
	parry_active = false
	current_state = state.FREE

## Hit contract — Phase 3+.
## _who: the attacking FighterBody.
## _by_what: HitOutcome Dictionary from HitResolver (single source of truth).
## This method dispatches consequences only — it does NOT re-resolve.
func hit(_who: Node, _by_what: Variant) -> void:
	# Interrupt any in-progress strike
	if current_state == state.WINDING_UP:
		_arm_weapon(false)
		current_strike = null

	# Dispatch based on the resolved outcome type
	if not (_by_what is Dictionary):
		return
	match _by_what.get("type"):
		"HIT":
			damage_taken.emit(_by_what)
			if _by_what.get("lethal", false):
				death()
			else:
				hurt()
		"PARRIED":
			# Phase 5: attacker enters extended recovery
			pass
		"DODGED":
			# Phase 5: no effect on target
			pass

func block() -> void:
	current_state = state.STATIC_ACTION
	block_started.emit()
	var round_at_start := _round_id
	if anim_state_tree:
		await anim_state_tree.animation_measured
	await get_tree().create_timer(anim_length).timeout
	if _round_id != round_at_start:
		return
	if current_state == state.STATIC_ACTION:
		current_state = state.DYNAMIC_ACTION

func parry() -> void:
	current_state = state.STATIC_ACTION
	can_be_hurt = false
	parry_started.emit()
	var round_at_start := _round_id
	if anim_state_tree:
		await anim_state_tree.animation_measured
	await get_tree().create_timer(anim_length).timeout
	if _round_id != round_at_start:
		return
	if current_state == state.STATIC_ACTION:
		current_state = state.FREE
	can_be_hurt = true

func parried() -> void:
	# Called when this fighter's attack was parried. Phase 5 adds extended recovery.
	pass

func hurt() -> void:
	current_state = state.HURT
	can_be_hurt = false
	hurt_started.emit()
	var round_at_start := _round_id
	if anim_state_tree:
		await anim_state_tree.animation_measured
	await get_tree().create_timer(anim_length).timeout
	if _round_id != round_at_start:
		return
	if not is_dead:
		if current_state == state.HURT:
			current_state = state.FREE
		can_be_hurt = true

func death() -> void:
	current_state = state.DEAD
	can_be_hurt = false
	is_dead = true
	death_started.emit()
	# Phase 6 handles round reset via FighterArena; no scene reload.

## Called by FighterArena on round reset. Increments _round_id to
## invalidate all in-flight async actions (execute_strike, hurt, parry, etc.),
## stops all callback-driven timers, then restores all combat state to
## round-start defaults.
func reset_for_round(spawn_transform: Transform3D) -> void:
	_round_id += 1

	# Stop callback-driven timers so their timeout signals don't fire
	# into the next round (these are NOT covered by _round_id — they
	# trigger methods directly, not via awaited coroutines).
	dodge_timer.stop()
	sprint_timer.stop()
	attack_combo_timer.stop()

	global_transform = spawn_transform
	velocity = Vector3.ZERO
	direction = Vector3.ZERO
	is_dead = false
	can_be_hurt = true
	guarding = false
	parry_active = false
	current_strike = null
	_arm_weapon(false)
	# Restore default stance (MIDDLE = "SLASH")
	weapon_type = "SLASH"
	current_state = state.FREE
	# Reset animation tree out of Death (or any other state) back to idle
	if anim_state_tree:
		anim_state_tree.reset_to_idle("SLASH")

# =========================================================================
# Animation callback
# =========================================================================

func _on_animation_measured(_new_length: float) -> void:
	anim_length = _new_length - 0.05
