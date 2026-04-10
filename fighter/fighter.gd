# fighter/fighter.gd
# Fighter — the single combatant controller used by both human and AI.
# Its state is authoritative; Brains (PlayerBrain / AIBrain) emit intents
# by calling intent_* methods, and the Fighter decides whether to honor them
# based on current_state.
#
# Phase 1 scope: movement + sprint + lock-on rotation. No combat, no stance,
# no damage. Those arrive in later phase plans.
class_name Fighter
extends CharacterBody3D

# --- Signals (most are stubs for later phases; only state_changed fires in Phase 1) ---
signal state_changed(new_state: int, old_state: int)
signal stance_changed(new_stance: int)            # stub — Phase 2+
signal strike_started(strike)                     # stub — Phase 3+
signal strike_activated(strike)                   # stub — Phase 3+
signal strike_ended(strike)                       # stub — Phase 3+
signal parried_by(other_fighter)                  # stub — Phase 5+
signal hit_taken(outcome)                         # stub — Phase 4+
signal limb_state_changed(limb, new_state)        # stub — Phase 4+
signal died                                       # stub — Phase 4+

# --- State machine ---
enum State {
	SPAWN,
	STRAFING,
	SPRINTING,
	WINDING_UP,
	STRIKING,
	RECOVERING,
	PARRYING,
	DODGING,
	HURT,
	DEAD,
}

var current_state: int = State.STRAFING : set = _set_current_state

# --- Exported references and tuning ---
## NodePath to the other fighter, resolved in _ready(). Set this in the
## scene file (Godot does not auto-resolve typed Node3D exports from .tscn
## NodePath strings, so we use an explicit NodePath + manual resolution).
## Tests can still set `opponent` directly in code; the resolver only runs
## when `opponent` is null.
@export var opponent_path: NodePath
var opponent: Node3D

@export_group("Movement tuning")
@export var default_speed: float = 4.0
@export var sprint_speed: float = 7.0
@export var acceleration: float = 40.0           # velocity units per second toward target
@export var rotation_lerp_weight: float = 0.25   # per physics tick
@export var engage_range: float = 8.0            # within this distance, sprint-release re-engages lock
@export var engage_facing_dot: float = 0.6       # cos(~53°) — must face opponent this closely to re-engage

# --- Runtime state ---
var input_dir: Vector2 = Vector2.ZERO   # last value set by intent_move; X = strafe, Y = approach/retreat
var sprint_held: bool = false           # last value set by intent_sprint

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# =========================================================================
# Lifecycle
# =========================================================================

func _ready() -> void:
	# Sibling node resolution — wait one frame so all peers in the parent
	# scene have entered the tree before walking the path. The guard on
	# `opponent` lets test code (and any future programmatic spawn) set
	# the reference directly without being clobbered by path resolution.
	if opponent != null or opponent_path.is_empty():
		return
	await get_tree().process_frame
	if opponent == null:
		opponent = get_node_or_null(opponent_path) as Node3D

# =========================================================================
# Intent surface (called by FighterBrain subclasses)
# =========================================================================

## Continuous intent: the brain's desired movement vector this frame.
## X = strafe (left/right around opponent), Y = approach/retreat.
## Y convention matches Input.get_vector: up-on-stick = negative Y.
func intent_move(dir: Vector2) -> void:
	input_dir = dir

## Continuous intent: sprint held/released. Holding breaks lock.
func intent_sprint(held: bool) -> void:
	sprint_held = held
	# Actual state transition happens in _physics_process — that's where
	# the Fighter decides whether to honor the intent based on current_state.

## Rising-edge intent: request a stance change. (Phase 2+; no-op at Phase 1.)
func intent_change_stance(_stance: int) -> void:
	pass

## Rising-edge intent: request a strike. (Phase 3+; no-op at Phase 1.)
func intent_strike(_stance: int, _dir: int) -> void:
	pass

## Rising-edge intent: request a parry. (Phase 5+; no-op at Phase 1.)
func intent_parry() -> void:
	pass

## Rising-edge intent: request a dodge. (Phase 5+; no-op at Phase 1.)
func intent_dodge(_dir: Vector2) -> void:
	pass

## Toggle intent: sheathe/draw. Reserved; no-op at MVP per spec.
func intent_sheathe(_sheathed: bool) -> void:
	pass

# =========================================================================
# Physics loop
# =========================================================================

func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_update_lock_state()
	match current_state:
		State.STRAFING:
			_face_opponent(rotation_lerp_weight)
			_strafing_movement(delta)
		State.SPRINTING:
			_face_movement(rotation_lerp_weight)
			_sprinting_movement(delta)
		_:
			pass  # other states added in later batches
	move_and_slide()

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = max(velocity.y, 0.0)

# =========================================================================
# State machine
# =========================================================================

func _set_current_state(new_state: int) -> void:
	if new_state == current_state:
		return
	var old := current_state
	current_state = new_state
	state_changed.emit(new_state, old)

# =========================================================================
# Movement — STRAFING
# =========================================================================

# Movement while locked on. Builds a desired horizontal velocity from
# input_dir in a frame of reference defined by the opponent's direction:
#   forward axis = unit vector from self to opponent (horizontal)
#   right axis   = forward cross UP
# input_dir.y convention: up on the stick = negative Y (Godot default),
# which we negate to get "approach the opponent" on W.
func _strafing_movement(delta: float) -> void:
	var desired := _compute_strafe_velocity() * default_speed
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)

func _compute_strafe_velocity() -> Vector3:
	if opponent == null:
		return Vector3.ZERO
	var to_opp := opponent.global_position - global_position
	to_opp.y = 0.0
	if to_opp.length_squared() < 0.0001:
		return Vector3.ZERO
	var forward := to_opp.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var approach := -input_dir.y    # W (stick up = -y) means "approach"
	var strafe := input_dir.x
	return forward * approach + right * strafe

# Slerps the Y rotation toward facing the opponent directly.
# Uses lerp_angle which handles wraparound cleanly.
func _face_opponent(weight: float) -> void:
	if opponent == null:
		return
	var to_opp := opponent.global_position - global_position
	to_opp.y = 0.0
	if to_opp.length_squared() < 0.0001:
		return
	# Godot character forward is -Z. atan2 of (x,z) gives the yaw such that
	# the vector aligns with +Z; we add PI to flip to -Z.
	var target_yaw := atan2(to_opp.x, to_opp.z) + PI
	rotation.y = lerp_angle(rotation.y, target_yaw, weight)

# =========================================================================
# Movement — SPRINTING / break-lock
# =========================================================================

# Decides between STRAFING and SPRINTING based on:
#  - the sprint intent (while held, force SPRINTING)
#  - the re-engage predicate (on release, only re-lock when facing opponent within range)
func _update_lock_state() -> void:
	if sprint_held:
		if current_state == State.STRAFING:
			current_state = State.SPRINTING
		return
	# Sprint not held: maybe re-engage.
	if current_state == State.SPRINTING and _should_re_engage_lock():
		current_state = State.STRAFING

# Re-engage predicate: within engage_range of the opponent AND facing them
# closely enough (dot product of our forward vs to-opponent >= engage_facing_dot).
func _should_re_engage_lock() -> bool:
	if opponent == null:
		return false
	var to_opp := opponent.global_position - global_position
	to_opp.y = 0.0
	var dist_sq := to_opp.length_squared()
	if dist_sq > engage_range * engage_range:
		return false
	if dist_sq < 0.0001:
		return true  # degenerate but safe
	var to_opp_n := to_opp / sqrt(dist_sq)
	# Godot character forward is -Z in local space; in global space that's
	# -global_transform.basis.z.
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return false
	forward = forward.normalized()
	return forward.dot(to_opp_n) >= engage_facing_dot

# Movement while lock is broken. Velocity is in world space.
# Speed is sprint_speed while sprint_held, otherwise default_speed
# (the "graceful walk" state after sprint release but before re-engage).
func _sprinting_movement(delta: float) -> void:
	var speed := sprint_speed if sprint_held else default_speed
	var desired := _compute_sprint_velocity() * speed
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)

# Computes a camera-relative movement direction for the sprint (free) mode.
# Projects the camera's local -Z onto the horizontal plane for forward,
# and cam_forward x UP for the right axis.
# Stick up (input_dir.y < 0) moves the fighter away from the camera = "forward."
func _compute_sprint_velocity() -> Vector3:
	if input_dir.length_squared() < 0.0001:
		return Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		# Fallback: world-space movement if there is no current camera.
		var fallback := Vector3(input_dir.x, 0.0, input_dir.y)
		return fallback.normalized()
	# Project the camera's forward (its local -Z in world space) onto the
	# horizontal plane. This is the direction the player sees as "away."
	var cam_forward := -cam.global_transform.basis.z
	cam_forward.y = 0.0
	if cam_forward.length_squared() < 0.0001:
		return Vector3.ZERO
	cam_forward = cam_forward.normalized()
	var cam_right := cam_forward.cross(Vector3.UP).normalized()
	# Stick up = -y, which should move "forward" (away from camera viewer).
	var move := -cam_forward * input_dir.y + cam_right * input_dir.x
	return move.normalized()

# Slerps the Y rotation toward the direction of the current horizontal velocity.
# Used while sprinting so the fighter faces where it's going, not the opponent.
func _face_movement(weight: float) -> void:
	var horizontal_vel := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_vel.length_squared() < 0.04:
		return  # don't snap facing when nearly stopped (~0.2 units/s threshold)
	var target_yaw := atan2(horizontal_vel.x, horizontal_vel.z) + PI
	rotation.y = lerp_angle(rotation.y, target_yaw, weight)
