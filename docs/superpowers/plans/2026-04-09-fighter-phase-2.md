# Fighter Phase 2 — Animation Tree Integration (Fork-and-Wrap)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Phase 1's capsule fighter with a fork of the souls character controller + scene + animation tree, wire stance-switching (MIDDLE=Light, UPPER=Heavy) and strike animation playback, and close the stance-legibility risk.

**Architecture:** Fork `player/character_body_souls_base.gd`, `player/souls_animation_tree.gd`, and `player/character_body_souls_base.tscn` into `fighter/`. Strip souls-specific systems. Rewrite strafing movement to be opponent-relative (porting Phase 1's math). Bolt the existing brain abstraction on top. The animation tree's weapon-swap mechanism (`SLASH_tree`/`HEAVY_tree`) becomes stance-swap with zero graph changes.

**Tech Stack:** Godot 4.7 + GDScript. No external test framework — pure-math tests run via `godot --headless --script <path>`. Scene wiring tests run headless via scene instantiation. Visual verification is manual F5.

**Source spec:** `docs/superpowers/specs/2026-04-09-phase-2-animation-tree-integration-design.md`

**Commit style:** `type: description` (e.g., `feat:`, `chore:`, `test:`).

---

## File map

By the end of this plan, these files exist:

| File | Status | Responsibility |
|---|---|---|
| `fighter/fighter_body.gd` | **New** (fork of `player/character_body_souls_base.gd`) | `FighterBody` — stripped controller with opponent-relative strafing, intent methods, Stance enum |
| `fighter/fighter_animation_tree.gd` | **New** (fork of `player/souls_animation_tree.gd`) | `FighterAnimationTree` — stripped anim tree, renamed references |
| `fighter/fighter_body.tscn` | **New** (save-as from `player/character_body_souls_base.tscn`) | Fighter scene — rigged character with sword, stripped of souls systems |
| `fighter/fighter_brain.gd` | **Modified** | Export type `Fighter` → `FighterBody`, auto-binding guard updated |
| `fighter/brains/player_brain.gd` | **Modified** | Adds stance/strike intent polling |
| `fighter/fighter_cam.gd` | Untouched | Midpoint-orbit camera |
| `fighter/fighter_demo.tscn` | **Modified** | References `fighter_body.tscn` instead of `fighter.tscn` |
| `fighter/tests/test_runner.gd` | Untouched | Base test harness |
| `fighter/tests/test_fighter_cam.gd` | Untouched | Camera math tests |
| `fighter/tests/test_fighter_states.gd` | **Modified** | Updated for `FighterBody` class and state names |
| `fighter/tests/test_fighter_anim_wiring.gd` | **New** | Headless smoke test for scene wiring |
| `fighter/fighter.gd` | **Deleted** | Replaced by `fighter_body.gd` |
| `fighter/fighter.tscn` | **Deleted** | Replaced by `fighter_body.tscn` |
| `project.godot` | **Modified** | Adds `p0_stance_upper`, `p0_strike` input actions |

---

## Task 1: Write `fighter/fighter_body.gd` — the forked controller

**Files:**
- Create: `fighter/fighter_body.gd`

This is the largest single artifact in the plan. It is a fork of `player/character_body_souls_base.gd` (703 lines) stripped to ~320 lines, with the strafing movement rewritten for opponent-relative targeting and intent methods added for the brain contract.

- [ ] **Step 1: Write `fighter/fighter_body.gd`**

```gdscript
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

# --- Jump and gravity ---
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var jump_velocity: float = 4.5
@onready var last_altitude = global_position
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

	# Resolve opponent from NodePath (same pattern as Phase 1's fighter.gd)
	if opponent == null and not opponent_path.is_empty():
		await get_tree().process_frame
		if opponent == null:
			opponent = get_node_or_null(opponent_path) as Node3D

	add_child(sprint_timer)
	sprint_timer.one_shot = true

	add_child(dodge_timer)
	dodge_timer.one_shot = true
	dodge_timer.connect("timeout", _on_dodge_timer_timeout)

	add_child(attack_combo_timer)
	attack_combo_timer.one_shot = true

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
	var target_yaw := atan2(to_opp.x, to_opp.z) + PI
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
	if not is_on_floor() and last_altitude == null:
		last_altitude = global_position
	if is_on_floor() and last_altitude != null:
		var fall_distance := abs(last_altitude.y - global_position.y)
		if fall_distance > hard_landing_height:
			hard_landing()
		last_altitude = null

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

func hit(_who, _by_what) -> void:
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
```

- [ ] **Step 2: Verify the script parses without error**

```bash
godot --headless --quit 2>&1 | grep -i "fighter_body"
```

Expected: no parse errors mentioning `fighter_body.gd`. If there are errors about missing `FighterAnimationTree` type, that's expected — it doesn't exist yet. Proceed to Task 2.

- [ ] **Step 3: Commit**

```bash
git add fighter/fighter_body.gd
git commit -m "feat(fighter): fork souls controller into FighterBody with opponent-relative strafing"
```

---

## Task 2: Write `fighter/fighter_animation_tree.gd` — the forked animation tree

**Files:**
- Create: `fighter/fighter_animation_tree.gd`

Fork of `player/souls_animation_tree.gd` (232 lines) stripped to ~140 lines. Removes ladder, interact, item, and gadget handlers. Renames `player_node` → `fighter_node` throughout.

- [ ] **Step 1: Write `fighter/fighter_animation_tree.gd`**

```gdscript
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
var lerp_movement

var guard_value: float = 0.0

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
	var new_blend := lerp(get("parameters/Guarding/blend_amount"), guard_value, 0.2)
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
	var weapon_tree_exists := tree_root.get_node("MovementStates").has_node(str(_new_weapon_type) + "_tree")
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
	lerp_movement = get("parameters/MovementStates/" + weapon_type + "_tree/MoveStrafe/blend_position")
	lerp_movement = lerp(lerp_movement, new_blend, 0.2)
	set("parameters/MovementStates/" + weapon_type + "_tree/MoveStrafe/blend_position", lerp_movement)

func set_free_move() -> void:
	var new_blend := Vector2(0, abs(fighter_node.input_dir.x) + abs(fighter_node.input_dir.y))
	if fighter_node.current_state == fighter_node.state.DYNAMIC_ACTION:
		new_blend *= 0.4
	lerp_movement = get("parameters/MovementStates/" + weapon_type + "_tree/MoveStrafe/blend_position")
	lerp_movement = lerp(lerp_movement, new_blend, 0.2)
	set("parameters/MovementStates/" + weapon_type + "_tree/MoveStrafe/blend_position", lerp_movement)

func _on_animation_started(anim_name: String) -> void:
	anim_length = get_node(anim_player).get_animation(anim_name).length
	animation_measured.emit(anim_length)

func _on_attack_timer_timeout() -> void:
	attack_count = 1
```

- [ ] **Step 2: Verify both scripts parse**

```bash
godot --headless --quit 2>&1 | grep -iE "error|warning" | grep -i fighter
```

Expected: no parse errors for `fighter_body.gd` or `fighter_animation_tree.gd`. Warnings about missing nodes or unset exports are OK at this stage (no scene exists yet).

- [ ] **Step 3: Commit**

```bash
git add fighter/fighter_animation_tree.gd
git commit -m "feat(fighter): fork souls animation tree into FighterAnimationTree"
```

---

## Task 3: Update `fighter/fighter_brain.gd` — type rename + auto-binding fix

**Files:**
- Modify: `fighter/fighter_brain.gd`

- [ ] **Step 1: Update the file**

Replace the entire file with:

```gdscript
# fighter/fighter_brain.gd
# Abstract base for decision-makers attached to a FighterBody.
# Subclasses (PlayerBrain, AIBrain) override _physics_process and call
# intent_* methods on self.fighter. Brains never touch the CharacterBody3D
# directly — they only emit intents.
class_name FighterBrain
extends Node

## The fighter this brain controls. Set in the editor, or auto-resolved
## to the parent if left unset.
@export var fighter: FighterBody

func _ready() -> void:
	if fighter == null:
		var parent := get_parent()
		if parent is FighterBody:
			fighter = parent
	if fighter == null:
		push_error("FighterBrain '%s' has no fighter reference and no FighterBody parent." % name)
```

- [ ] **Step 2: Commit**

```bash
git add fighter/fighter_brain.gd
git commit -m "fix(fighter): update FighterBrain type from Fighter to FighterBody"
```

---

## Task 4: Update `fighter/brains/player_brain.gd` — add stance and strike intents

**Files:**
- Modify: `fighter/brains/player_brain.gd`

- [ ] **Step 1: Update the file**

Replace the entire file with:

```gdscript
# fighter/brains/player_brain.gd
# PlayerBrain — reads prefixed input actions (p<index>_*) and emits intents
# to its fighter. The player_index lets us add a second PlayerBrain later
# for local 2P by just registering p1_* actions — zero changes to this script.
class_name PlayerBrain
extends FighterBrain

## Which input action prefix to use. 0 -> "p0_...", 1 -> "p1_...", etc.
@export_range(0, 3) var player_index: int = 0

var _move_up: StringName
var _move_down: StringName
var _move_left: StringName
var _move_right: StringName
var _sprint: StringName
var _stance_upper: StringName
var _strike: StringName

func _ready() -> void:
	super._ready()
	var p := "p%d_" % player_index
	_move_up      = StringName(p + "move_up")
	_move_down    = StringName(p + "move_down")
	_move_left    = StringName(p + "move_left")
	_move_right   = StringName(p + "move_right")
	_sprint       = StringName(p + "sprint")
	_stance_upper = StringName(p + "stance_upper")
	_strike       = StringName(p + "strike")

func _physics_process(_delta: float) -> void:
	if fighter == null:
		return

	# Movement (continuous)
	var move := Input.get_vector(_move_left, _move_right, _move_up, _move_down)
	fighter.intent_move(move)

	# Sprint (continuous)
	fighter.intent_sprint(Input.is_action_pressed(_sprint))

	# Stance (continuous: held = UPPER, released = MIDDLE)
	if Input.is_action_pressed(_stance_upper):
		fighter.intent_change_stance(FighterBody.Stance.UPPER)
	else:
		fighter.intent_change_stance(FighterBody.Stance.MIDDLE)

	# Strike (rising edge)
	if Input.is_action_just_pressed(_strike):
		fighter.intent_strike()
```

- [ ] **Step 2: Commit**

```bash
git add fighter/brains/player_brain.gd
git commit -m "feat(fighter): add stance and strike intents to PlayerBrain"
```

---

## Task 5: Add `p0_stance_upper` and `p0_strike` input actions

**Files:**
- Modify: `project.godot` (append to the `[input]` section, before `[layer_names]`)

- [ ] **Step 1: Add the input actions**

Open `project.godot` in a text editor. Find the line `p0_sprint={...}` block (ends with `}` before `[layer_names]`). After the closing `}` of `p0_sprint`, insert:

```
p0_stance_upper={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":81,"key_label":0,"unicode":113,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":11,"pressure":0.0,"pressed":true,"script":null)
]
}
p0_strike={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"button_mask":1,"position":Vector2(0, 0),"global_position":Vector2(0, 0),"factor":1.0,"button_index":1,"canceled":false,"pressed":true,"double_click":false,"script":null)
, Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"","device":-1,"axis":5,"axis_value":1.0,"script":null)
]
}
```

Bindings: `p0_stance_upper` = Q (keyboard) + D-pad Up (gamepad). `p0_strike` = Left Mouse Button + RT/R2 (right trigger axis).

- [ ] **Step 2: Verify in Godot**

Open the project in Godot. Go to Project → Project Settings → Input Map. Confirm `p0_stance_upper` and `p0_strike` appear with the correct bindings. Close the settings.

- [ ] **Step 3: Commit**

```bash
git add project.godot
git commit -m "chore: add p0_stance_upper and p0_strike input actions"
```

---

## Task 6: Delete Phase 1 capsule files

**Files:**
- Delete: `fighter/fighter.gd`
- Delete: `fighter/fighter.gd.uid`
- Delete: `fighter/fighter.tscn`

- [ ] **Step 1: Delete the files**

```bash
rm fighter/fighter.gd fighter/fighter.gd.uid fighter/fighter.tscn
```

- [ ] **Step 2: Commit**

```bash
git add -A fighter/fighter.gd fighter/fighter.gd.uid fighter/fighter.tscn
git commit -m "chore: delete Phase 1 capsule fighter (replaced by FighterBody fork)"
```

---

## Task 7: Fork `fighter/fighter_body.tscn` — MANUAL EDITOR STEP

**Files:**
- Create: `fighter/fighter_body.tscn` (via Godot editor save-as)

This task requires the Godot editor. The executor (human or agentic) must perform these steps in the GUI.

- [ ] **Step 1: Save-as**

1. Open the Godot editor for this project.
2. Open `player/character_body_souls_base.tscn`.
3. Scene menu → Save Scene As → navigate to `fighter/` → name it `fighter_body.tscn` → Save.

- [ ] **Step 2: Swap root script**

1. Select the root node (`PlayerCharacterBodySoulsBase`).
2. In the Inspector, click the script property → Load → select `fighter/fighter_body.gd`.
3. Exported properties that no longer exist on `FighterBody` (like `interact_sensor`, `weapon_system`, `gadget_system`, `health_system`, `inventory_system`, `last_spawn_site`) will show as `<invalid>` or disappear. This is expected.
4. Set the `opponent_path` export to empty (it will be overridden per-instance in the demo scene).

- [ ] **Step 3: Swap AnimationTree script**

1. Select the `AnimStateTree` node (the AnimationTree).
2. In the Inspector, click the script property → Load → select `fighter/fighter_animation_tree.gd`.
3. The `fighter_node` export should appear. Drag the root node (`PlayerCharacterBodySoulsBase`) into it, or set the NodePath to `..` (parent).

- [ ] **Step 4: Delete stripped nodes**

Select and delete (right-click → Delete) each of these nodes:
- `GadgetSystem` (and all children)
- `ItemSystem` (and all children)
- `PlayerInteractSensors`
- `FollowCam` (and all children including `PlayerTargetingSystem`)
- `FootstepSoundSystem` (and all children)
- `GUI` (and all children)
- `InventorySystem`
- `HealthSystem`
- `TriggeredSounds` (and all children)

- [ ] **Step 5: Clean up WeaponSystem**

1. Expand `WeaponSystem`.
2. Delete: `BackBone` (Hammer mount), `WeaponHitTarget`, `WeaponHitWorld`, `WeaponStreak` (and their `SignalSwitch` child if present).
3. Keep: `RightHand → HandPivot → Sword`.
4. Select `WeaponSystem` itself. In the Inspector, remove its script (click the script property → click the "x" to clear it).

- [ ] **Step 6: Verify rig plays correctly**

1. Select the `AnimationPlayer` node.
2. In the Animation panel at the bottom, play a few animations: `LightIdle`, `HeavyIdle`, `Slash1`, `Heavy1`.
3. Verify the character mesh animates correctly and the sword tracks the right hand.
4. If animations don't play (bones are broken), the root retype may be needed — but try this first since we kept the root as CharacterBody3D.

- [ ] **Step 7: Save**

File → Save Scene (Ctrl+S). The resulting `fighter/fighter_body.tscn` should be ~1-3 MB (much smaller than the 8 MB source because many nodes are deleted).

- [ ] **Step 8: Commit**

```bash
git add fighter/fighter_body.tscn
git commit -m "feat(fighter): fork souls character scene into fighter_body.tscn"
```

---

## Task 8: Update `fighter/fighter_demo.tscn` — reference new scene

**Files:**
- Modify: `fighter/fighter_demo.tscn`

- [ ] **Step 1: Read the new scene's UID**

```bash
head -1 fighter/fighter_body.tscn
```

Look for the `uid="uid://..."` value in the `[gd_scene]` header. You will need this UID.

- [ ] **Step 2: Update the ext_resource in fighter_demo.tscn**

Open `fighter/fighter_demo.tscn` in a text editor. Find:

```
[ext_resource type="PackedScene" uid="uid://cj4pl4lt6pcw5" path="res://fighter/fighter.tscn" id="1_fighter_scene"]
```

Replace with (using the UID from Step 1):

```
[ext_resource type="PackedScene" uid="<UID_FROM_STEP_1>" path="res://fighter/fighter_body.tscn" id="1_fighter_scene"]
```

The `id` stays the same (`1_fighter_scene`), so all instance references (`ExtResource("1_fighter_scene")`) in the file continue to resolve.

- [ ] **Step 3: Verify the scene loads in Godot**

Open `fighter/fighter_demo.tscn` in the Godot editor. Both fighters should appear as rigged characters (not capsules). The FighterCam, Floor, Sun, and WorldEnv should all be present.

If either fighter shows as a broken instance (red icon), check that `fighter_body.tscn` saved correctly in Task 7 and that the UID matches.

- [ ] **Step 4: Commit**

```bash
git add fighter/fighter_demo.tscn
git commit -m "fix(fighter): update demo scene to reference fighter_body.tscn"
```

---

## Task 9: Update `fighter/tests/test_fighter_states.gd`

**Files:**
- Modify: `fighter/tests/test_fighter_states.gd`

The test file references the deleted `Fighter` class. Update to use `FighterBody`. State enum names change: `STRAFING` → `FREE`, `SPRINTING` → `SPRINT`. Add a stance change test.

- [ ] **Step 1: Rewrite the test file**

```gdscript
# fighter/tests/test_fighter_states.gd
# Runtime tests for FighterBody state transitions. Instantiates two bare
# FighterBodies in a temporary root, pokes their intents, and checks state.
#
# Run headless:  godot --headless --script fighter/tests/test_fighter_states.gd
extends "res://fighter/tests/test_runner.gd"

const FighterBodyScript = preload("res://fighter/fighter_body.gd")

var _ran: bool = false

func _init() -> void:
	print("=== %s ===" % get_script().resource_path.get_file())

func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run_all_tests()
	print("\nResults: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)
	return false

func _run_all_tests() -> void:
	_test_initial_state_is_free()
	_test_sprint_held_transitions_to_sprint()
	_test_sprint_released_in_range_and_facing_reengages()
	_test_sprint_released_far_away_stays_sprint()
	_test_sprint_released_facing_away_stays_sprint()
	_test_stance_change_upper()
	_test_stance_change_middle()
	_test_stance_change_lower_is_noop()

# -- Helpers --------------------------------------------------------------

func _make_fighter_pair(a_pos: Vector3, b_pos: Vector3) -> Array:
	var a: FighterBody = FighterBodyScript.new()
	var b: FighterBody = FighterBodyScript.new()
	a.name = "A"
	b.name = "B"
	get_root().add_child(a)
	get_root().add_child(b)
	a.position = a_pos
	b.position = b_pos
	a.opponent = b
	b.opponent = a
	# Force state to FREE (skip the STATIC_ACTION → FREE startup await)
	a.current_state = FighterBody.state.FREE
	b.current_state = FighterBody.state.FREE
	# Face A toward B
	var to_b := (b_pos - a_pos)
	to_b.y = 0
	a.rotation.y = atan2(to_b.x, to_b.z) + PI
	return [a, b]

func _teardown(pair: Array) -> void:
	for f in pair:
		f.queue_free()

# -- Tests ----------------------------------------------------------------

func _test_initial_state_is_free() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: FighterBody = pair[0]
	# We forced FREE in the helper; the real startup goes STATIC_ACTION → FREE via await.
	assert_eq(a.current_state, FighterBody.state.FREE, "fighter starts in FREE (after forced set)")
	_teardown(pair)

func _test_sprint_held_transitions_to_sprint() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: FighterBody = pair[0]
	a.intent_sprint(true)
	assert_eq(a.current_state, FighterBody.state.SPRINT, "sprint held flips FREE -> SPRINT")
	_teardown(pair)

func _test_sprint_released_in_range_and_facing_reengages() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: FighterBody = pair[0]
	a.current_state = FighterBody.state.SPRINT
	a.intent_sprint(false)
	assert_eq(a.current_state, FighterBody.state.FREE, "sprint released within range, facing -> FREE")
	_teardown(pair)

func _test_sprint_released_far_away_stays_sprint() -> void:
	var pair := _make_fighter_pair(Vector3(-20, 0, 0), Vector3(0, 0, 0))
	var a: FighterBody = pair[0]
	a.current_state = FighterBody.state.SPRINT
	a.intent_sprint(false)
	assert_eq(a.current_state, FighterBody.state.SPRINT, "sprint released far away stays SPRINT")
	_teardown(pair)

func _test_sprint_released_facing_away_stays_sprint() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: FighterBody = pair[0]
	a.rotation.y += PI  # Face away from B
	a.current_state = FighterBody.state.SPRINT
	a.intent_sprint(false)
	assert_eq(a.current_state, FighterBody.state.SPRINT, "sprint released facing away stays SPRINT")
	_teardown(pair)

func _test_stance_change_upper() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: FighterBody = pair[0]
	a.intent_change_stance(FighterBody.Stance.UPPER)
	assert_eq(a.weapon_type, "HEAVY", "stance UPPER sets weapon_type to HEAVY")
	_teardown(pair)

func _test_stance_change_middle() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: FighterBody = pair[0]
	a.intent_change_stance(FighterBody.Stance.UPPER)
	a.intent_change_stance(FighterBody.Stance.MIDDLE)
	assert_eq(a.weapon_type, "SLASH", "stance MIDDLE sets weapon_type back to SLASH")
	_teardown(pair)

func _test_stance_change_lower_is_noop() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: FighterBody = pair[0]
	a.intent_change_stance(FighterBody.Stance.LOWER)
	assert_eq(a.weapon_type, "SLASH", "stance LOWER is a no-op, weapon_type stays SLASH")
	_teardown(pair)
```

- [ ] **Step 2: Run the tests**

```bash
godot --headless --script fighter/tests/test_fighter_states.gd
```

Expected: all tests pass. If any fail, fix the issue in `fighter_body.gd` or the test.

- [ ] **Step 3: Run the camera tests to verify they still pass**

```bash
godot --headless --script fighter/tests/test_fighter_cam.gd
```

Expected: all tests pass (Phase 1 camera tests are unaffected).

- [ ] **Step 4: Commit**

```bash
git add fighter/tests/test_fighter_states.gd
git commit -m "test(fighter): update state tests for FighterBody, add stance tests"
```

---

## Task 10: Write `fighter/tests/test_fighter_anim_wiring.gd`

**Files:**
- Create: `fighter/tests/test_fighter_anim_wiring.gd`

Headless smoke test that loads `fighter_demo.tscn` and verifies the scene wiring is correct. This test can only pass after Task 7 (manual editor) and Task 8 (demo scene update) are complete.

- [ ] **Step 1: Write the test file**

```gdscript
# fighter/tests/test_fighter_anim_wiring.gd
# Headless smoke test for fighter scene wiring. Loads fighter_demo.tscn
# and verifies that FighterBody ↔ FighterAnimationTree references resolve
# and the stance sub-tree parameter paths exist.
#
# Run headless:  godot --headless --script fighter/tests/test_fighter_anim_wiring.gd
extends "res://fighter/tests/test_runner.gd"

var _ran: bool = false

func _init() -> void:
	print("=== %s ===" % get_script().resource_path.get_file())

func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run_all_tests()
	print("\nResults: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)
	return false

func _run_all_tests() -> void:
	var demo_scene := load("res://fighter/fighter_demo.tscn")
	assert_true(demo_scene != null, "fighter_demo.tscn loads")
	if demo_scene == null:
		return

	var demo: Node3D = demo_scene.instantiate()
	get_root().add_child(demo)
	# Allow one frame for _ready() to run on all nodes
	await get_tree().process_frame

	var fighter_a: FighterBody = demo.get_node_or_null("FighterA") as FighterBody
	var fighter_b: FighterBody = demo.get_node_or_null("FighterB") as FighterBody

	assert_true(fighter_a != null, "FighterA resolves as FighterBody")
	assert_true(fighter_b != null, "FighterB resolves as FighterBody")
	if fighter_a == null or fighter_b == null:
		demo.queue_free()
		return

	# Check anim_state_tree references
	assert_true(fighter_a.anim_state_tree != null, "FighterA.anim_state_tree is set")
	assert_true(fighter_b.anim_state_tree != null, "FighterB.anim_state_tree is set")

	if fighter_a.anim_state_tree:
		assert_true(
			fighter_a.anim_state_tree.fighter_node == fighter_a,
			"FighterA.anim_state_tree.fighter_node == FighterA"
		)
		# Verify SLASH_tree (MIDDLE) parameter path exists
		var slash_blend = fighter_a.anim_state_tree.get(
			"parameters/MovementStates/SLASH_tree/MoveStrafe/blend_position")
		assert_true(slash_blend is Vector2, "SLASH_tree MoveStrafe blend_position is a Vector2")
		# Verify HEAVY_tree (UPPER) parameter path exists
		var heavy_blend = fighter_a.anim_state_tree.get(
			"parameters/MovementStates/HEAVY_tree/MoveStrafe/blend_position")
		assert_true(heavy_blend is Vector2, "HEAVY_tree MoveStrafe blend_position is a Vector2")

	# Verify default weapon_type (stance)
	assert_eq(fighter_a.weapon_type, "SLASH", "FighterA defaults to SLASH (MIDDLE stance)")

	# Verify stance change updates weapon_type
	fighter_a.intent_change_stance(FighterBody.Stance.UPPER)
	assert_eq(fighter_a.weapon_type, "HEAVY", "After intent_change_stance(UPPER), weapon_type is HEAVY")

	# Verify PlayerBrain bound to FighterA
	var brain: PlayerBrain = demo.get_node_or_null("FighterA/PlayerBrain") as PlayerBrain
	assert_true(brain != null, "PlayerBrain node exists under FighterA")
	if brain:
		assert_true(brain.fighter == fighter_a, "PlayerBrain.fighter == FighterA")

	demo.queue_free()
```

- [ ] **Step 2: Run the test**

```bash
godot --headless --script fighter/tests/test_fighter_anim_wiring.gd
```

Expected: all assertions pass. If SLASH_tree or HEAVY_tree blend_position returns null, the AnimationTree graph wasn't preserved during the save-as — go back to Task 7 and verify the tree resource is intact.

- [ ] **Step 3: Commit**

```bash
git add fighter/tests/test_fighter_anim_wiring.gd
git commit -m "test(fighter): add headless smoke test for anim tree wiring"
```

---

## Task 11: Manual F5 verification — Phase 2 gate

This is the final gate. Open the Godot editor.

- [ ] **Step 1: Set main scene**

Verify `project.godot` still points `application/run/main_scene` at `res://fighter/fighter_demo.tscn`. If not, set it in Project → Project Settings → Application → Run → Main Scene.

- [ ] **Step 2: Press F5 and run through the checklist**

| # | Check | Pass? |
|---|---|---|
| 1 | Two rigged male characters face each other on the dojo floor (no capsules) | |
| 2 | Stick forward/back → `LightWalking`/`LightRunning` plays, character faces opponent | |
| 3 | Stick side → `LightStrafeL`/`LightStrafeR` plays | |
| 4 | Hold Q (or D-pad Up) → character shifts to `HeavyIdle`. Stick movement plays Heavy strafe set | |
| 5 | Release Q → returns to Light movement set (MIDDLE stance) | |
| 6 | Hold sprint (Shift / B) → `SPRINT_tree` plays, lock breaks. Release + face opponent → re-engages | |
| 7 | Left-click (or RT) in MIDDLE → `Slash1` plays. In UPPER → `Heavy1` plays. Returns to normal after | |
| 8 | Sword stays in right hand throughout | |
| 9 | FighterCam correctly frames both fighters | |
| 10 | No Godot console errors from stripped systems | |

**Gate passes** if all 10 hold.
**Gate fails** if stances are not visibly distinct (MIDDLE/Light and UPPER/Heavy look the same). If the gate fails, stop — do not write a Phase 3 plan until stance legibility is resolved.

- [ ] **Step 3: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix(fighter): Phase 2 gate fixes from manual verification"
```

Only create this commit if changes were made during verification.

---

## Execution notes

**Task ordering constraints:**
- Tasks 1–6 can run sequentially without the Godot editor.
- Task 7 **requires the Godot editor** (manual scene save-as and node deletion).
- Task 8 depends on Task 7 (needs the UID from `fighter_body.tscn`).
- Task 9 can run after Tasks 1, 3 (needs `FighterBody` class to exist, but not the scene).
- Task 10 depends on Tasks 7 and 8 (needs the demo scene to reference the new fighter body).
- Task 11 depends on all prior tasks.

**Parallelizable:** Tasks 1 and 2 are independent and can run concurrently. Tasks 3 and 4 are independent and can run concurrently. Tasks 9 and 5 are independent and can run concurrently.

**The manual step (Task 7) is the serialization point.** Everything before it is CLI-automatable. Everything after it depends on the scene file it produces.
