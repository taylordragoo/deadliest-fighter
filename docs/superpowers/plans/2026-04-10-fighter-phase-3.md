# Fighter Phase 3 — Strike Resources + Sim-Clock Timing

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the souls-template timer-phased `attack()` coroutine with sim-clock authoritative strike states driven by `Strike` resources. Any clean contact during STRIKING = instant kill (torso, lethal=true). Round resets on death.

**Architecture:** Add three new state enum values (`WINDING_UP`, `STRIKING`, `RECOVERING`) alongside the existing souls states. The current `ATTACK` state and `attack()` method are replaced. `Strike` is a Godot `Resource` class declaring authoritative timings. `intent_strike()` looks up the current stance's Strike, enters WINDING_UP, and a timer chain driven by the Strike's declared durations (not `anim_length`) drives the state through STRIKING → RECOVERING → FREE. The weapon's Area3D hitbox is armed only during STRIKING. `HitResolver` is a static pure function with its own `CombatState` enum (decoupled from FighterBody): `resolve(strike, attacker_combat_state, target_combat_state, target_can_be_hurt) → Dictionary` returning MISS or HIT(torso, lethal=true). FighterBody maps its internal states to `HitResolver.CombatState` at the call site. FighterArena handles death → round reset.

**Tech Stack:** Godot 4.7 + GDScript. No external test framework. Visual verification is manual F5.

**Source spec:** `docs/superpowers/specs/2026-04-09-bushido-blade-pivot-design.md` (Phase 3 section + Phase 2 Implementation Notes)

**Commit style:** `type: description` (e.g., `feat:`, `fix:`, `chore:`).

---

## Key design decisions

### 1. State enum: extend with combat-specific states

Add `WINDING_UP`, `STRIKING`, `RECOVERING`, `HURT`, `DEAD` to the existing `state` enum alongside `SPAWN, FREE, STATIC_ACTION, DYNAMIC_ACTION, DODGE, SPRINT`. Remove `ATTACK`.

**Why `HURT` and `DEAD` as explicit states now:** The spec's HitResolver, AI brain, HUD, and round-flow logic all depend on distinguishing `HURT` from generic `STATIC_ACTION`. Keeping `hurt()` and `death()` routed through `STATIC_ACTION` would deepen the dependency on souls-era overloaded naming — exactly what Phase 3 should start unwinding. Adding them now costs two enum values and a few match cases; deferring them costs a state-machine refactor in Phase 4–6 when those systems need explicit leaf states.

The souls-inherited `STATIC_ACTION`/`DYNAMIC_ACTION` remain **only** for `block()`, `hard_landing()`, and `parry()` — action methods that Phase 3 doesn't touch and Phase 5 will migrate. The `_to_combat_state()` mapping function translates both old and new states to `HitResolver.CombatState`, so the resolver is never exposed to the souls naming.

### 2. Sim clock is authoritative

Strike timings come from `Strike.wind_up_time`, `Strike.active_time`, `Strike.recover_time` — not from `anim_length`. The `animation_measured` signal is still connected for dev-time comparison (print a warning if declared vs. measured times diverge by >20%), but runtime behavior is governed entirely by the Strike resource's declared values.

### 3. intent_strike adopts the spec's full signature now

The spec defines `intent_strike(stance: Stance, dir: StrikeDir)` as part of the stable Brain→Fighter contract. Phase 3 adopts the full signature immediately — even though MVP only uses `SLASH_HORIZONTAL`, the `StrikeDir` enum and parameter exist from day one. This avoids a future contract change when directional strikes arrive (the spec explicitly calls out that the intent surface should be stable). Brains pass `StrikeDir.SLASH_HORIZONTAL` at Phase 3; the Strike lookup key becomes `(stance, dir)`.

A `StrikeDir` enum is added to `strike.gd` (not FighterBody) since it's part of the strike vocabulary. Names match the spec exactly:

```gdscript
enum StrikeDir { THRUST, SLASH_HORIZONTAL, SLASH_DIAGONAL }  # MVP: SLASH_HORIZONTAL only
```

### 4. StanceSystem stays inline

Per Phase 2 notes, stance logic stays on FighterBody. The `STANCE_TO_WEAPON` dictionary gains a parallel `STANCE_TO_STRIKE` dictionary mapping `Stance → Strike` resource.

### 5. Hitbox wiring: direct control of the Sword Area3D

The fighter scene's weapon is at `WeaponSystem/RightHand/HandPivot/Sword` (an Area3D with collision shapes, `collision_mask = 5` i.e. layers 1+3). FighterBody directly controls `monitoring` on this Sword Area3D during STRIKING, and connects its `body_entered` signal to route through `HitResolver`. The WeaponSystem node is a plain Node3D (no script) in the current fighter scene — no competing monitoring control exists.

**Critical collision-layer requirement:** FighterBody must be on collision layer 3 (Targets) for the Sword Area3D to detect it. The fighter scene currently has `collision_layer = 2` (Player only). Task 8 Step 1a adds layer 3.

### 6. HitResolver: minimal Phase 3 version, decoupled from FighterBody

Phase 3's resolver is deliberately simple: if the weapon Area3D touches a body in the "Targets" group during STRIKING, resolve as `HIT(torso, lethal=true)`. No limb routing, no parry/dodge checking (those are Phase 4–5).

The resolver defines its own `CombatState` enum (`STRIKING`, `WINDING_UP`, `RECOVERING`, `IDLE`, `DODGING`, `PARRYING`, `HURT`, `DEAD`) — it does **not** import `FighterBody.state`. This keeps it a true standalone pure function: testable without instantiating fighters, no coupling to the fighter's internal state enum (which still carries souls-era states like `STATIC_ACTION`). The caller (FighterBody's `_on_weapon_body_entered`) maps its own state to `HitResolver.CombatState` before calling `resolve()`.

### 7. FighterArena: minimal round reset

A lightweight `FighterArena` node detects `death_started` on either fighter, waits a beat, then respawns both fighters to starting positions and resets state. No round counter, no HUD, no win tracking — just the death → reset loop so you can fight repeatedly.

---

## File map

By the end of this plan, these files exist or are modified:

| File | Status | Responsibility |
|---|---|---|
| `fighter/strikes/strike.gd` | **New** | `Strike` resource class — `strike_id`, `hit_line`, `wind_up_time`, `active_time`, `recover_time`, `damage_profile`, `animation_name` |
| `fighter/strikes/damage_profile.gd` | **New** | `DamageProfile` resource class — `hit_region_priority`, `lethal_on_torso`, `lethal_on_head`, `limb_cripple` |
| `fighter/strikes/upper_horizontal.tres` | **New** | Strike data for UPPER stance horizontal slash |
| `fighter/strikes/middle_horizontal.tres` | **New** | Strike data for MIDDLE stance horizontal slash |
| `fighter/hit_resolver.gd` | **New** | `HitResolver` — static pure function with own `CombatState` enum: `resolve(strike, attacker_combat_state, target_combat_state, target_can_be_hurt) → Dictionary` |
| `fighter/fighter_body.gd` | **Modified** | State enum gains `WINDING_UP/STRIKING/RECOVERING/HURT/DEAD`, removes `ATTACK`. `attack()` replaced by `execute_strike()`. Strike lookup, hitbox arming, HitResolver call, `_to_combat_state()` mapping. |
| `fighter/brains/player_brain.gd` | **Modified** | `intent_strike()` call updated to pass stance and `Strike.StrikeDir.SLASH_HORIZONTAL`. |
| `fighter/fighter_animation_tree.gd` | **Modified** | Replace `_on_attack_started` with `_on_strike_started(strike)` using `strike.animation_name`; remove combo bookkeeping. |
| `fighter/fighter_arena.gd` | **New** | Minimal round reset: detect death, respawn, reset state |
| `fighter/fighter_demo.tscn` | **Modified** | Add FighterArena node |
| `fighter/tests/test_hit_resolver.gd` | **New** | Headless pure-function tests for HitResolver |

---

## Task 1: Create the Strike and DamageProfile resource classes

**Files:**
- Create: `fighter/strikes/strike.gd`
- Create: `fighter/strikes/damage_profile.gd`

- [ ] **Step 1: Write `fighter/strikes/damage_profile.gd`**

```gdscript
# fighter/strikes/damage_profile.gd
# DamageProfile — declares what limbs a strike targets and lethality rules.
# Phase 3: only torso matters. Phase 4 adds limb routing.
extends Resource
class_name DamageProfile

## Limbs this strike targets, in priority order.
## Phase 3 ignores this (everything resolves to torso).
## Phase 4 uses it for limb routing.
@export var hit_region_priority: Array[String] = ["torso"]

## Whether a clean hit to the torso is lethal.
@export var lethal_on_torso: bool = true

## Whether a clean hit to the head is lethal.
@export var lethal_on_head: bool = true

## Whether this strike can cripple limbs (Phase 4).
@export var limb_cripple: bool = true
```

- [ ] **Step 2: Write `fighter/strikes/strike.gd`**

```gdscript
# fighter/strikes/strike.gd
# Strike — a Godot Resource defining a single attack's identity, timing, and damage.
# Timings are sim-clock authoritative: the animation is visualization,
# these values govern state machine transitions.
extends Resource
class_name Strike

## Unique identifier, e.g. "upper_horizontal"
@export var strike_id: String

## Strike direction — part of the Brain→Fighter intent contract.
## Names match the spec's enum exactly (§ Combat vocabulary).
## Phase 3: only SLASH_HORIZONTAL is used. Others are reserved.
enum StrikeDir { THRUST, SLASH_HORIZONTAL, SLASH_DIAGONAL }

## HIGH, MID, or LOW — determines which stance must match to parry (Phase 5).
## Phase 3: unused, kept for forward compatibility.
enum HitLine { HIGH, MID, LOW }
@export var hit_line: HitLine = HitLine.MID

## Sim-clock authoritative durations (seconds).
@export var wind_up_time: float = 0.25
@export var active_time: float = 0.15
@export var recover_time: float = 0.35

## What this strike does on contact.
@export var damage_profile: DamageProfile

## The animation tree oneshot name to trigger. Maps to existing
## AnimationTree oneshot nodes (e.g. "Attack" triggers the Attack oneshot).
@export var animation_name: String = "Attack"
```

---

## Task 2: Author the two Strike `.tres` files

**Files:**
- Create: `fighter/strikes/upper_horizontal.tres`
- Create: `fighter/strikes/middle_horizontal.tres`

These are hand-authored Godot resource files. They reference the `Strike` and `DamageProfile` classes.

- [ ] **Step 1: Write `fighter/strikes/upper_horizontal.tres`**

```ini
[gd_resource type="Resource" script_class="Strike" load_steps=3 format=3]

[ext_resource type="Script" path="res://fighter/strikes/strike.gd" id="1"]
[ext_resource type="Script" path="res://fighter/strikes/damage_profile.gd" id="2"]

[sub_resource type="Resource" id="dp_1"]
script = ExtResource("2")
hit_region_priority = Array[String](["head", "torso", "arm_r", "arm_l"])
lethal_on_torso = true
lethal_on_head = true
limb_cripple = true

[resource]
script = ExtResource("1")
strike_id = "upper_horizontal"
hit_line = 0
wind_up_time = 0.3
active_time = 0.15
recover_time = 0.4
damage_profile = SubResource("dp_1")
animation_name = "Attack"
```

- [ ] **Step 2: Write `fighter/strikes/middle_horizontal.tres`**

```ini
[gd_resource type="Resource" script_class="Strike" load_steps=3 format=3]

[ext_resource type="Script" path="res://fighter/strikes/strike.gd" id="1"]
[ext_resource type="Script" path="res://fighter/strikes/damage_profile.gd" id="2"]

[sub_resource type="Resource" id="dp_1"]
script = ExtResource("2")
hit_region_priority = Array[String](["torso", "arm_r", "arm_l", "head"])
lethal_on_torso = true
lethal_on_head = true
limb_cripple = true

[resource]
script = ExtResource("1")
strike_id = "middle_horizontal"
hit_line = 1
wind_up_time = 0.2
active_time = 0.2
recover_time = 0.3
damage_profile = SubResource("dp_1")
animation_name = "Attack"
```

**Tuning notes:** Upper is slower wind-up (0.3s) but shorter active window (0.15s) — telegraphed, precise. Middle is faster wind-up (0.2s) with longer active window (0.2s) — quicker, more forgiving. These are starting values; Phase 7 tunes them. Total strike durations: upper = 0.85s, middle = 0.7s.

---

## Task 3: Write HitResolver

**Files:**
- Create: `fighter/hit_resolver.gd`

Phase 3's resolver is deliberately minimal. It answers one question: "did the weapon touch a valid target during STRIKING?" If yes → HIT(torso, lethal=true). Phase 4 adds limb routing; Phase 5 adds PARRIED/DODGED outcomes.

- [ ] **Step 1: Write `fighter/hit_resolver.gd`**

```gdscript
# fighter/hit_resolver.gd
# HitResolver — pure static function: strike context → HitOutcome.
# Phase 3: returns MISS or HIT(torso, lethal=true). No limb routing,
# no parry/dodge checking. Phase 4–5 expand the logic.
#
# Returns a Dictionary (tagged union):
#   { "type": "MISS" }
#   { "type": "HIT", "limb": "torso", "lethal": true }
#
# Pure: reads inputs only, mutates nothing. Testable without engine.
# Decoupled: uses its own CombatState enum, NOT FighterBody.state.
class_name HitResolver

## Combat states as understood by the resolver. FighterBody maps its
## internal state enum to these before calling resolve(). This keeps
## the resolver independent of the fighter's souls-era state naming.
enum CombatState {
	IDLE,        ## FREE, STRAFING, SPRINTING — not attacking or defending
	WINDING_UP,  ## Strike started, hitbox not yet active
	STRIKING,    ## Hitbox active, committed
	RECOVERING,  ## Post-strike vulnerability
	PARRYING,    ## Active parry frames (Phase 5)
	DODGING,     ## I-frame dodge (Phase 5)
	HURT,        ## Taking a non-lethal hit
	DEAD,        ## Round over
}

## Resolve a strike hitting a target.
## attacker_combat_state / target_combat_state: CombatState enum values.
## strike: the Strike resource being used.
## target_can_be_hurt: whether the target is currently vulnerable.
static func resolve(
	strike: Strike,
	attacker_combat_state: int,
	target_combat_state: int,
	target_can_be_hurt: bool
) -> Dictionary:
	# Attacker must be in STRIKING state
	if attacker_combat_state != CombatState.STRIKING:
		return { "type": "MISS" }

	# Target must be hurtable
	if not target_can_be_hurt:
		return { "type": "MISS" }

	# Phase 5 will add: if target_combat_state == DODGING → DODGED
	# Phase 5 will add: if target_combat_state == PARRYING → PARRIED check

	# Phase 3: any valid contact = torso hit, always lethal
	return {
		"type": "HIT",
		"limb": "torso",
		"lethal": strike.damage_profile.lethal_on_torso
	}
```

---

## Task 4: Write HitResolver tests

**Files:**
- Create: `fighter/tests/test_hit_resolver.gd`

Runnable via `godot --headless --script fighter/tests/test_hit_resolver.gd`.

- [ ] **Step 1: Write `fighter/tests/test_hit_resolver.gd`**

```gdscript
# fighter/tests/test_hit_resolver.gd
# Headless test for HitResolver — runs via:
#   godot --headless --script fighter/tests/test_hit_resolver.gd
extends SceneTree

func _init() -> void:
	var pass_count := 0
	var fail_count := 0

	# Build a test Strike resource
	var dp := DamageProfile.new()
	dp.hit_region_priority = ["torso"]
	dp.lethal_on_torso = true
	dp.lethal_on_head = true

	var strike := Strike.new()
	strike.strike_id = "test_strike"
	strike.hit_line = Strike.HitLine.MID
	strike.wind_up_time = 0.2
	strike.active_time = 0.2
	strike.recover_time = 0.3
	strike.damage_profile = dp

	# Alias for readability
	var CS := HitResolver.CombatState

	# Test 1: STRIKING + hurtable = HIT(torso, lethal)
	var result := HitResolver.resolve(strike, CS.STRIKING, CS.IDLE, true)
	if result["type"] == "HIT" and result["limb"] == "torso" and result["lethal"] == true:
		pass_count += 1
		print("PASS: striking + hurtable = HIT(torso, lethal)")
	else:
		fail_count += 1
		print("FAIL: striking + hurtable — got ", result)

	# Test 2: WINDING_UP = MISS (not in STRIKING)
	result = HitResolver.resolve(strike, CS.WINDING_UP, CS.IDLE, true)
	if result["type"] == "MISS":
		pass_count += 1
		print("PASS: winding_up = MISS")
	else:
		fail_count += 1
		print("FAIL: winding_up — got ", result)

	# Test 3: RECOVERING = MISS
	result = HitResolver.resolve(strike, CS.RECOVERING, CS.IDLE, true)
	if result["type"] == "MISS":
		pass_count += 1
		print("PASS: recovering = MISS")
	else:
		fail_count += 1
		print("FAIL: recovering — got ", result)

	# Test 4: target not hurtable = MISS
	result = HitResolver.resolve(strike, CS.STRIKING, CS.IDLE, false)
	if result["type"] == "MISS":
		pass_count += 1
		print("PASS: target not hurtable = MISS")
	else:
		fail_count += 1
		print("FAIL: target not hurtable — got ", result)

	# Test 5: IDLE attacker = MISS
	result = HitResolver.resolve(strike, CS.IDLE, CS.IDLE, true)
	if result["type"] == "MISS":
		pass_count += 1
		print("PASS: attacker IDLE = MISS")
	else:
		fail_count += 1
		print("FAIL: attacker IDLE — got ", result)

	print("\n--- HitResolver Tests: %d passed, %d failed ---" % [pass_count, fail_count])
	if fail_count > 0:
		quit(1)
	else:
		quit(0)
```

---

## Task 5: Modify FighterBody — sim-clock strike states and hitbox wiring

**Files:**
- Modify: `fighter/fighter_body.gd`

This is the core task. Replace the `ATTACK` state and `attack()` coroutine with `WINDING_UP/STRIKING/RECOVERING` states driven by Strike resource timings. Wire the weapon hitbox and HitResolver.

- [ ] **Step 1: Update state enum — replace ATTACK, add combat-specific states**

```gdscript
# Replace:
enum state { SPAWN, FREE, STATIC_ACTION, DYNAMIC_ACTION, DODGE, SPRINT, ATTACK }

# With:
enum state { SPAWN, FREE, STATIC_ACTION, DYNAMIC_ACTION, DODGE, SPRINT, WINDING_UP, STRIKING, RECOVERING, HURT, DEAD }
```

Also update `change_state()` to handle HURT and DEAD:
```gdscript
		state.HURT:
			speed = 0.0
		state.DEAD:
			speed = 0.0
```

- [ ] **Step 2: Add Strike-related properties and signals**

Add below the existing `attack_combo_timer` declaration:

```gdscript
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
```

- [ ] **Step 3: Update `_ready()` — build strike lookup, connect hitbox, ensure "Targets" group**

Add after the existing `_ready()` setup (after `attack_combo_timer` is added):

```gdscript
	# Build (stance, dir) → strike lookup. Key is Vector2i(Stance, StrikeDir).
	# Phase 3: only SLASH_HORIZONTAL. Future dirs add more entries, no code change.
	if strike_upper:
		STANCE_TO_STRIKE[Vector2i(Stance.UPPER, Strike.StrikeDir.SLASH_HORIZONTAL)] = strike_upper
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
```

**Why code, not scene edit:** Adding the group in `_ready()` is more robust than relying on the scene file, since both `fighter_body.tscn` instances need it and a scene-level group assignment is easy to forget on one of them.

**Collision layer requirement:** The FighterBody's `collision_layer` must include layer 3 (Targets). Currently the fighter scene has `collision_layer = 2` (Player only). The Sword Area3D has `collision_mask = 5` (binary: layers 1+3), meaning it detects bodies on layer 1 (World) or layer 3 (Targets) — but NOT layer 2 (Player). Without adding layer 3 to the FighterBody, the Sword Area3D's `body_entered` will never fire against opponents. This is fixed in Task 8 Step 1a.

- [ ] **Step 4: Update `change_state()` — handle new states**

Add cases to the match block:

```gdscript
		state.WINDING_UP:
			speed = 0.0
		state.STRIKING:
			speed = 0.0
		state.RECOVERING:
			speed = 0.0
```

Update the strafing flag line to include the new states where strafing should be off:

```gdscript
	strafing = (new_state == state.FREE or new_state == state.DYNAMIC_ACTION)
```

(This already works — WINDING_UP/STRIKING/RECOVERING are not in the list, so strafing = false.)

- [ ] **Step 5: Update `_physics_process()` — add movement for new states**

Add cases for the new strike states. During WINDING_UP, the fighter continues to face the opponent but cannot move. During STRIKING, a short forward lunge (dash). During RECOVERING, no movement.

```gdscript
		state.WINDING_UP:
			if opponent:
				_face_opponent(0.15)

		state.STRIKING:
			dash_movement()

		state.RECOVERING:
			pass  # Frozen in place, vulnerable
```

- [ ] **Step 6: Replace `attack()` with `execute_strike()`**

Remove the old `attack()`, `air_attack()` methods. Replace with:

```gdscript
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
```

- [ ] **Step 6a: Lock stance during strike states**

The current `intent_change_stance()` can be called by the brain every frame, and nothing prevents it from changing `weapon_type` while a strike is in progress. This would desync the active Strike resource from the animation tree's weapon sub-tree mid-animation.

Add a gate at the top of `intent_change_stance()`:

```gdscript
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
```

This is the minimum needed to keep stance coherent with the sim clock. Phase 5 adds the full change-cost transition window.

- [ ] **Step 7: Update `intent_strike()` to the spec's full signature**

The spec defines `intent_strike(stance, dir)` as part of the stable Brain→Fighter contract. Phase 3 adopts it now. Brains pass the current stance and `Strike.StrikeDir.SLASH_HORIZONTAL`; the fighter looks up the Strike by `(stance, dir)`.

```gdscript
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
```

- [ ] **Step 8: Rewrite `hit()` as a pure consequence dispatcher**

The `hit()` contract changes: `_by_what` is now the HitOutcome dictionary from HitResolver (e.g. `{ "type": "HIT", "limb": "torso", "lethal": true }`). HitResolver is the single authority on what happened — `hit()` does not re-check parry/guard state. It purely dispatches consequences from the resolved outcome.

Parry and guard checking move to HitResolver in Phase 5 (it already has `target_state` and `target_can_be_hurt` to make those decisions). Phase 3's resolver doesn't return PARRIED or BLOCKED outcomes, so the old parry/guard branches are removed now. The `_on_weapon_body_entered` callback already gates on `can_be_hurt` via HitResolver.

```gdscript
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
```

**Note:** The old `parry_active`/`guarding` checks are removed from `hit()`. When Phase 5 wires parry, the check happens in HitResolver (which already receives `target_state`), and `hit()` dispatches the PARRIED outcome by calling `parry()` on the target and `parried()` on the attacker. This keeps the ownership boundary clean: resolver decides, fighter dispatches.

- [ ] **Step 8a: Update `hurt()` and `death()` to use explicit states**

Replace `current_state = state.STATIC_ACTION` with the new explicit states:

```gdscript
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
```

This replaces the old `STATIC_ACTION`-based versions. `hurt()` uses `_round_id` guard. `death()` uses the new `DEAD` state so HitResolver, AI, HUD, and arena can all distinguish it from generic `STATIC_ACTION`.

- [ ] **Step 9: Add `reset_for_round()` — single authoritative reset API**

All round-reset logic lives here, called by FighterArena. This increments `_round_id` (invalidating all in-flight coroutines that captured the old value), resets all combat state, restores default stance, and disarms the weapon hitbox.

```gdscript
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
```

**Two layers of stale-action protection:**

1. **`_round_id` guards** — for await-chain coroutines (`execute_strike`, `hurt`, `parry`, `block`, `hard_landing`, `dodge`). Each captures `_round_id` at entry and bails after every `await` if it changed. This is cheap (one int comparison per await) and covers all current and future await-chain methods.

2. **`Timer.stop()` calls** — for callback-driven timers (`dodge_timer`, `sprint_timer`, `attack_combo_timer`). These fire timeout signals that invoke methods directly (e.g., `_on_dodge_timer_timeout`), bypassing the await chain entirely. `_round_id` cannot protect them — they must be explicitly stopped.

Additionally, `_on_dodge_timer_timeout` should guard against stale invocations as belt-and-suspenders:

```gdscript
func _on_dodge_timer_timeout() -> void:
	# Guard: if we're no longer in DODGE (e.g., round reset changed state),
	# don't mutate state.
	if current_state != state.DODGE:
		return
	dodge_ended.emit()
	speed = default_speed
	current_state = state.FREE
	can_be_hurt = true
```

**Existing action methods (`hurt`, `parry`, `block`, `hard_landing`)** also need the round-id guard pattern. Add `var round_at_start := _round_id` at the top of each, and check `if _round_id != round_at_start: return` after each `await`. This is a mechanical change — apply the same pattern to every await-chain method on FighterBody.

---

## Task 6: Update FighterAnimationTree — wire Strike.animation_name, remove combo bookkeeping

**Files:**
- Modify: `fighter/fighter_animation_tree.gd`

The animation tree must use `Strike.animation_name` to select which oneshot to trigger, not hardcode `"Attack"`. This upholds the spec's goal: "adding strikes is a data edit, not a code edit." The old combo-counting logic (`attack_count`, `attack_timer`, `_on_big_attack_started`, `_on_air_attack_started`) is replaced — strikes are now data-driven, not combo-driven.

- [ ] **Step 1: Replace `attack_started` signal with `strike_started(strike)`**

In `_ready()`, replace:
```gdscript
fighter_node.attack_started.connect(_on_attack_started)
fighter_node.big_attack_started.connect(_on_big_attack_started)
fighter_node.air_attack_started.connect(_on_air_attack_started)
```
With:
```gdscript
fighter_node.strike_started.connect(_on_strike_started)
```

- [ ] **Step 2: Replace `_on_attack_started` with `_on_strike_started`**

Remove `_on_attack_started`, `_on_big_attack_started`, `_on_air_attack_started`. Replace with:

```gdscript
func _on_strike_started(strike: Strike) -> void:
	# Set attack_count to select the correct animation in the ATTACK sub-tree.
	# The serialized AnimationTree graph has advance_expressions like
	# "attack_count == 1" on transitions to Slash1/Heavy1, "attack_count == 2"
	# for Slash2/Heavy2, etc. Phase 3 always uses the first attack animation
	# (attack_count = 1). Future phases can add a field to the Strike resource
	# to select a specific animation variant.
	attack_count = 1
	request_oneshot(strike.animation_name)
```

This uses the Strike resource's `animation_name` field (e.g. `"Attack"`) to trigger the correct oneshot. `attack_count` is set to 1 before each request to select Slash1 (MIDDLE) or Heavy1 (UPPER) in the ATTACK sub-tree's advance_expression branches.

- [ ] **Step 3: Keep `attack_count` as a shim; remove stale combo timer**

**`attack_count` must NOT be deleted.** The serialized AnimationTree graph in `fighter_body.tscn` contains 8 `advance_expression` strings that branch on `attack_count` (e.g., `"attack_count == 1"` → Slash1, `"attack_count == 2"` → Slash2, etc.). These are baked into the `.tscn` binary — changing them requires manual AnimationTree graph editing in the Godot editor, which is out of scope for Phase 3.

Keep `attack_count` as a script variable (always set to 1 by `_on_strike_started`). This satisfies the advance_expressions and always selects the first attack animation.

**Do delete:**
- `attack_timer` Timer and its setup in `_ready()`
- `_on_attack_timer_timeout()` method

These are the combo-chaining timer artifacts. With `attack_count` always set to 1 in `_on_strike_started`, the timer that used to cycle it is dead code.

**Future cleanup:** When the AnimationTree graph is manually edited (to simplify the ATTACK sub-tree or add new animations), `attack_count` can be removed from the script and the advance_expressions updated in the graph. This is a Phase 7 polish task.

- [ ] **Step 4: Add `reset_to_idle()` for round resets**

The `death()` method travels the base state machine to `"Death"` (via `base_state_machine.travel("Death")`). On round reset, the animation tree must leave the Death state and return to the movement state machine with the correct stance subtree. Add:

```gdscript
## Called by FighterBody.reset_for_round() to return the animation tree
## from any state (including Death) to idle with the given weapon type.
func reset_to_idle(reset_weapon_type: String) -> void:
	# Travel back to the movement states — this leaves Death, Hurt, or any oneshot.
	base_state_machine.travel(reset_weapon_type + "_tree")
	_on_weapon_change_ended(reset_weapon_type)
```

This explicitly leaves the Death state by traveling to the correct weapon tree (e.g. `"SLASH_tree"`) in the `MovementStates` state machine, then updates the `current_weapon_tree` playback reference.

---

## Task 7: Write FighterArena — minimal round reset

**Files:**
- Create: `fighter/fighter_arena.gd`

Minimal orchestrator: detects death on either fighter, waits, resets both. No round counting, no HUD, no win tracking.

- [ ] **Step 1: Write `fighter/fighter_arena.gd`**

```gdscript
# fighter/fighter_arena.gd
# FighterArena — minimal round reset for Phase 3.
# Detects death_started on either fighter, waits, respawns both.
# Phase 6 adds round counting, HUD, win tracking.
extends Node3D
class_name FighterArena

@export var fighter_a: FighterBody
@export var fighter_b: FighterBody

## Time to wait after a death before resetting (seconds).
@export var reset_delay: float = 2.0

## Spawn positions (captured at _ready from initial transforms).
var _spawn_a: Transform3D
var _spawn_b: Transform3D

var _resetting: bool = false

func _ready() -> void:
	if fighter_a:
		_spawn_a = fighter_a.global_transform
		fighter_a.death_started.connect(_on_fighter_died.bind(fighter_a))
	if fighter_b:
		_spawn_b = fighter_b.global_transform
		fighter_b.death_started.connect(_on_fighter_died.bind(fighter_b))

func _on_fighter_died(_dead_fighter: FighterBody) -> void:
	if _resetting:
		return
	_resetting = true
	await get_tree().create_timer(reset_delay).timeout
	_reset_round()

func _reset_round() -> void:
	if fighter_a:
		fighter_a.reset_for_round(_spawn_a)
	if fighter_b:
		fighter_b.reset_for_round(_spawn_b)
	_resetting = false
```

## Task 7a: Update PlayerBrain — pass stance and StrikeDir

**Files:**
- Modify: `fighter/brains/player_brain.gd`

- [ ] **Step 1: Update the `intent_strike` call to use the fighter's resolved stance**

The spec says intents are requests the fighter may decline — the brain should pass what the *fighter* is currently in, not what the *input* says. This matters once stance change-cost arrives (Phase 5): the player might hold UPPER, but the fighter is still transitioning from MIDDLE. Passing the input state would let the brain request an UPPER strike while the fighter is actually in MIDDLE.

Change line 49 from:
```gdscript
		fighter.intent_strike()
```
To:
```gdscript
		# Read the fighter's resolved stance, not raw input.
		# STANCE_TO_WEAPON maps Stance → weapon_type; invert to get current Stance.
		var current_stance: int = FighterBody.STANCE_TO_WEAPON.find_key(fighter.weapon_type)
		if current_stance == null:
			current_stance = FighterBody.Stance.MIDDLE
		fighter.intent_strike(current_stance, Strike.StrikeDir.SLASH_HORIZONTAL)
```

This reads the fighter's actual `weapon_type` (which reflects the resolved stance after any change-cost delay) rather than the input action state. Phase 3's instant stance changes make this distinction invisible, but it's correct by construction for Phase 5.

---

## Task 8: Wire the demo scene and verify

**Files:**
- Modify: `fighter/fighter_demo.tscn` (in Godot editor)

This task is manual — it involves scene graph edits in the Godot editor.

- [ ] **Step 1a: Fix FighterBody collision layer to include layer 3 (Targets)**

The FighterBody's `collision_layer` is currently `2` (Player only). The Sword Area3D's `collision_mask` is `5` (layers 1+3), so it only detects bodies on layers 1 (World) and 3 (Targets). Without this fix, `body_entered` will never fire when the sword touches the opponent.

In `fighter/fighter_body.tscn`, change the root CharacterBody3D's collision properties:
- `collision_layer`: change from `2` to `6` (binary: layers 2+3, i.e. Player + Targets)
- `collision_mask`: keep as `3` (layers 1+2, i.e. World + Player)

This makes each fighter detectable by the opponent's Sword Area3D (layer 3) while preserving its Player identity (layer 2) for any other systems that check it.

**Alternatively**, in code in `_ready()`:
```gdscript
	# Add collision layer 3 (Targets) so opponent sword Area3Ds can detect this body.
	# Layer 2 (Player) is kept from the scene file.
	collision_layer |= (1 << 2)  # layer 3 (0-indexed bit 2)
```

The code approach is safer if both fighters share the same .tscn — it guarantees the layer is set regardless of scene file state.

- [ ] **Step 1b: Add FighterArena node to fighter_demo.tscn**

In the Godot editor:
1. Open `fighter/fighter_demo.tscn`.
2. Add a new `Node3D` child to the root. Rename it `FighterArena`.
3. Attach `fighter/fighter_arena.gd` as its script.
4. Set `fighter_a` export to the first FighterBody node.
5. Set `fighter_b` export to the second FighterBody node.

- [ ] **Step 2: Set Strike resource exports on each FighterBody**

In the Godot editor, on each FighterBody node:
1. Set `strike_upper` to `res://fighter/strikes/upper_horizontal.tres`.
2. Set `strike_middle` to `res://fighter/strikes/middle_horizontal.tres`.

- [ ] **Step 3: Set weapon_hitbox export on each FighterBody**

The weapon Area3D lives at `WeaponSystem/RightHand/HandPivot/Sword` in the fighter scene tree. In the Godot editor, on each FighterBody node:
1. Set the `weapon_hitbox` export to the `Sword` node (the Area3D at `WeaponSystem/RightHand/HandPivot/Sword`).

**Alternative (if the nested path is hard to export):** Add an `_auto_find_weapon_hitbox()` helper to `_ready()` that walks `$WeaponSystem` to find the first Area3D descendant. This is more robust than a manual export path.

- [ ] **Step 4: Confirm WeaponSystem has no script competing for hitbox control**

The `WeaponSystem` node in the fighter scene is a plain `Node3D` (no script attached) — the `EquipmentSystem` script was already stripped during the Phase 2 fork. Verify this is still the case:
1. Select the `WeaponSystem` node on each FighterBody in the Godot editor.
2. Confirm it has no script and no exported properties like `activate_signal`.

If for any reason an `EquipmentSystem` script is attached, remove it or clear its `activate_signal` export to prevent it from competing with FighterBody's `_arm_weapon()` control of the Sword Area3D's `monitoring`.

- [ ] **Step 5: Verify end-to-end**

Press F5 and verify:
1. Press strike → fighter enters WINDING_UP (brief pause, facing opponent), then STRIKING (forward lunge with armed hitbox), then RECOVERING (frozen, vulnerable), then FREE.
2. Strike hits the opponent → Sword Area3D enters opponent body → `_on_weapon_body_entered` → HitResolver returns `{ "type": "HIT", "limb": "torso", "lethal": true }` → `body.hit(self, outcome)` → `hit()` reads `outcome["lethal"] == true` → `death()` → `state.DEAD` (explicit enum value, not STATIC_ACTION) → `death_started` signal.
3. FighterArena receives `death_started`, waits `reset_delay` (2s), calls `reset_for_round()` on both fighters — restores spawn transforms, MIDDLE stance, increments `_round_id` (invalidating in-flight coroutines), and resets animation tree out of Death state via `reset_to_idle("SLASH")`.
4. Repeat: fight, kill, reset, fight again — no state gets stuck. Both fighters start each round in MIDDLE stance with idle animation (not Death). Any in-flight timers from the previous round bail harmlessly on `_round_id` mismatch.
5. Both stances work: switch to UPPER, strike → upper timing (0.3s wind-up). Switch to MIDDLE, strike → middle timing (0.2s wind-up).
6. Verify "Targets" group: both fighters are in the group (added in `_ready`). Confirm collision layer 3 was added in Step 1a — without it, the Sword Area3D (mask=5, layers 1+3) will not detect opponent bodies (currently layer 2 only).

---

## Exit criteria

Per the design spec's Phase 3 definition:

> Fight the static dummy, hit it, dummy → DEAD, arena resets the round. One-shot kills feel correct.

Specifically:
1. `intent_strike(stance, dir)` from FREE → WINDING_UP → STRIKING → RECOVERING → FREE, timed by Strike resource values (not anim_length).
2. Weapon hitbox armed only during STRIKING; disarmed at all other times.
3. Weapon Area3D touching a Targets-group body during STRIKING → HitResolver (using its own `CombatState`, decoupled from FighterBody) → HIT(torso, lethal=true) → target's `death()` → `state.DEAD`.
4. FighterArena detects death, calls `reset_for_round()` — increments `_round_id`, stops timers, resets animation tree out of Death, restores stance.
5. 5 consecutive kill-reset cycles with no stuck states, no stale timers firing into the next round.
6. Both `upper_horizontal` and `middle_horizontal` strikes work with their respective timings.
7. Getting hit during WINDING_UP interrupts the strike (fighter enters `state.HURT`, not STATIC_ACTION).

---

## Spec divergences

This plan intentionally pulls two items forward from later phases:

- **FighterArena** (spec says Phase 6): Phase 3 needs a death → reset loop to verify the kill chain end-to-end. The Phase 3 version is minimal (no round counting, no HUD, no win tracking). Phase 6 extends it.
- **HitResolver tests** (spec says Phase 7): Writing tests alongside the resolver is better than deferring them. The Phase 3 tests cover only Phase 3's MISS/HIT logic. Phase 7 expands coverage to PARRIED/DODGED/limb routing.

The design spec's phase map should be updated to reflect these pull-forwards so it is not self-contradictory.

### Intentional Phase 3 simplifications (to be addressed in later phases)

- **Stance change-cost is deferred (Phase 5).** The spec describes a ~0.2s transition window during stance changes where the fighter can neither strike nor parry (§ Stance transitions). Phase 3 keeps instant stance changes but adds a gate preventing stance change during strike states (Step 6a). Full change-cost timing is a Phase 5 concern (it interacts with parry matching).
- **Stance is still derived from `weapon_type`, not an authoritative `current_stance` (Phase 5).** The spec says the fighter owns stance and needs a "neither old nor new" transition state for change-cost (§ Subsystem ownership, § Stance transitions). Phase 3 keeps the Phase 2 approach: `weapon_type` is the stance identity, and `STANCE_TO_WEAPON` maps between them. Phase 5 should introduce an authoritative `current_stance` variable with transition tracking when change-cost and parry matching require it. The strike-state stance lock (Step 6a) is sufficient for Phase 3's needs.
- **Signal names stay souls-era, not spec (Phase 6).** The spec defines `state_changed(new, old)`, `hit_taken(outcome)`, and `died` as the Fighter→subscriber surface (§ Fighter → subscribers signals). Phase 3 keeps the inherited names: `changed_state`, `damage_taken`, `death_started`. Renaming is a cross-cutting change that touches FighterBody, FighterAnimationTree, FighterArena, and all future subscribers, with zero functional impact on Phase 3. Phase 6 (AIBrain + HUD + full Arena) is the natural point to migrate to the spec's signal surface, since those are the subscribers that actually need it.
- **`STATIC_ACTION`/`DYNAMIC_ACTION` remain for block/parry/hard_landing (Phase 5/7).** The spec removes these blurry souls-era states entirely in favor of explicit leaf states like PARRYING, BLOCKING (§ Fighter state machine). Phase 3 adds HURT and DEAD but keeps STATIC_ACTION/DYNAMIC_ACTION for `block()`, `parry()`, and `hard_landing()` — methods Phase 3 doesn't modify. Migrating them requires rewriting ~15 `advance_expression` strings in the serialized `.tscn` AnimationTree graph. Phase 5 (parry) should add PARRYING as an explicit state; Phase 7 (hardening) should clean up the remaining STATIC_ACTION/DYNAMIC_ACTION usage.
- **Round reset skips SPAWN (Phase 6).** The spec's round flow starts in SPAWN for ~1.5s before transitioning to READY (§ Round flow). Phase 3's `reset_for_round()` goes directly to FREE for fast iteration. Phase 6 (FighterArena full round flow) will add the SPAWN ceremony.
