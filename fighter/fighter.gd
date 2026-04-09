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
## The other fighter. Set in the editor on each Fighter instance in the demo.
@export var opponent: Node3D

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
	match current_state:
		State.STRAFING:
			_face_opponent(rotation_lerp_weight)
			_strafing_movement(delta)
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
