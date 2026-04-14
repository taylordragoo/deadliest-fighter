# Fighter Phase 5 — Parry + Dodge Defenses

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the two defensive verbs (parry and dodge) so that the combat loop has both offensive and defensive options. Parry reflects a strike back onto the attacker as extended recovery (the punish window). Dodge grants i-frames throughout its animation, giving positional advantage. HitResolver gains `PARRIED` and `DODGED` outcome types. A `stance_match_required` flag on FighterBody is wired but ships as `false` (timing-only parry at MVP).

**Architecture:** `intent_parry()` enters a new sim-clock-driven coroutine: WINDING_UP-like startup → PARRYING (active parry frames) → brief recovery back to FREE. The parry window is a declared duration on FighterBody, not animation-driven. `intent_dodge()` enters the existing DODGE state with i-frames (can_be_hurt = false) throughout, using sim-clock timing. HitResolver.resolve() adds two checks before limb routing: target DODGING → return DODGED; target PARRYING → check stance match (if enabled) → return PARRIED. FighterBody.hit() dispatches PARRIED outcomes by calling `parried()` on the attacker, which enters extended RECOVERING. PlayerBrain gains `p0_parry` and `p0_dodge` input bindings.

**Tech Stack:** Godot 4.7 + GDScript. No external test framework. Visual verification is manual F5.

**Source spec:** `docs/superpowers/specs/2026-04-09-bushido-blade-pivot-design.md` (Parry matching section ~line 132, HitResolver outcomes ~line 174, Phase 5 bullet ~line 464)

**Commit style:** `type: description` (e.g., `feat:`, `fix:`, `chore:`).

---

## Key design decisions

### 1. Parry uses sim-clock timing, not the souls template's start_guard/end_guard

The souls template's `start_guard()` uses `await create_timer(parry_window)` inside `DYNAMIC_ACTION` state with `guarding = true`. This mixes animation-measured timing with a manual timer and overloads `DYNAMIC_ACTION`. Phase 5 replaces this with a sim-clock authoritative parry coroutine that follows the same pattern as `execute_strike()`: declared timing constants, `_round_id` guards, explicit state transitions.

The old `start_guard()`, `end_guard()`, `block()`, and `parry()` methods remain as dead code for now — they're still referenced by the AnimationTree's Parry/Block oneshots and will be cleaned up when those sub-graphs are pruned. Phase 5's new parry goes through `execute_parry()`, a new coroutine.

### 2. Parry has three phases: startup → active → recovery

```
intent_parry() → execute_parry()
  ├─ STATIC_ACTION (parry startup, ~0.1s, vulnerable, cannot act)
  ├─ STATIC_ACTION + parry_active=true (active parry frames, ~0.3s, strikes resolve as PARRIED)
  ├─ STATIC_ACTION + parry_active=false (parry recovery, ~0.15s, vulnerable, cannot act)
  └─ FREE
```

The startup window is the commitment cost — you can be hit during it and take damage normally. The active window is when incoming strikes resolve as PARRIED. The recovery is the parry's own vulnerability — a missed parry (whiffed timing) leaves you open. This is the spec's "risk/reward" design: parry grants openings but the parrying fighter is briefly vulnerable during recovery.

**Why not a dedicated PARRYING state?** Adding PARRYING to the state enum would require updating `change_state()`, the animation tree's advance_expressions in the serialized .tscn, and the `_to_combat_state()` mapper. Instead, we use a boolean flag `parry_active` (already exists on FighterBody) checked by `_to_combat_state()`. When `parry_active == true`, `_to_combat_state()` returns `CombatState.PARRYING` regardless of the underlying state. This avoids touching the AnimationTree .tscn while still giving HitResolver the PARRYING combat state it needs.

### 3. Dodge uses sim-clock timing with a declared duration

The souls template's `dodge()` uses `animation_measured` to time i-frames. Phase 5 replaces this with a declared `dodge_duration` constant (matching the strike timing pattern). The dodge direction is opponent-relative when strafing (backward = away from opponent) and camera-relative when in free movement, using the existing `_calc_cam_direction()` helper.

Dodge i-frames cover the entire animation per spec: "Dodge has i-frames throughout its animation. A successful dodge does not create a counter-stagger — it grants positional advantage only."

### 4. HitResolver checks DODGED before PARRIED before limb routing

The resolve() check order matters:
1. Attacker must be STRIKING (existing)
2. Target must be hurtable (existing)
3. **Target DODGING → DODGED** (new)
4. **Target PARRYING → PARRIED** (new, with optional stance match)
5. Limb routing (existing Phase 4)

DODGED is checked first because dodge i-frames are unconditional — no stance matching, no timing subtlety. PARRIED is checked second with the optional stance-match gate.

### 5. PARRIED outcome: attacker enters extended recovery

When HitResolver returns PARRIED, the target (the one who parried) calls `attacker.parried()`. The `parried()` method forces the attacker into RECOVERING with an extended duration (`parried_recover_time`, default ~1.0s) — this is the punish window. The attacker's current strike coroutine is interrupted (weapon disarmed, strike cleared), and the extended recovery begins.

The target (parrying fighter) completes their parry recovery phase normally — they are NOT invulnerable after a successful parry, but the attacker's extended recovery gives them time to land a free strike.

### 6. stance_match_required is a FighterBody export, default false

The spec says: "MVP ships with `false`; we flip it to `true` when stances are visually distinct enough to be read." This is an `@export var stance_match_required: bool = false` on FighterBody. HitResolver receives it as a parameter. When true, PARRIED requires `fighter.weapon_type` (mapped to a hit_line) to match `strike.hit_line`. When false, any parry in the active window succeeds.

### 7. Dodge timing constants live on FighterBody as exports

```gdscript
@export var dodge_startup: float = 0.05
@export var dodge_duration: float = 0.4
@export var dodge_recovery: float = 0.15
```

These are short — dodge is meant to be fast and reactive, granting positional advantage. The entire dodge (startup + duration + recovery) is ~0.6s.

### 8. PlayerBrain input: parry on `p0_parry`, dodge on `p0_dodge`

Two new input actions added to `project.godot`. Parry is a rising-edge press. Dodge is a rising-edge press with direction from current input_dir.

---

## File map

By the end of this plan, these files exist or are modified:

| File | Status | Responsibility |
|---|---|---|
| `fighter/hit_resolver.gd` | **Modified** | Add DODGED and PARRIED checks before limb routing. New parameter: `stance_match_required`, `target_stance_hit_line`. |
| `fighter/fighter_body.gd` | **Modified** | New `execute_parry()` and `execute_dodge()` coroutines. Wire `intent_parry()` and `intent_dodge()`. Expand `hit()` for PARRIED/DODGED dispatch. Expand `parried()` with extended recovery. Add `stance_match_required` export. Update `_to_combat_state()` for parry_active. Update `reset_for_round()`. |
| `fighter/brains/player_brain.gd` | **Modified** | Add `p0_parry` and `p0_dodge` input reads. |
| `project.godot` | **Modified** | Add `p0_parry` and `p0_dodge` input actions. |
| `fighter/tests/test_hit_resolver.gd` | **Modified** | Add DODGED and PARRIED test cases. |

---

## Task 1: Add DODGED and PARRIED outcomes to HitResolver

**Files:**
- Modify: `fighter/hit_resolver.gd`

### Overview

Expand `resolve()` with two new parameters and two new checks before limb routing. The DODGED check is unconditional (target in DODGING = dodge). The PARRIED check optionally gates on stance matching.

- [ ] **Step 1: Update the resolve() signature**

Add three new parameters after `target_limb_health`:

```gdscript
static func resolve(
	strike: Strike,
	attacker_combat_state: int,
	target_combat_state: int,
	target_can_be_hurt: bool,
	target_limb_health: LimbHealth = null,
	stance_match_required: bool = false,
	target_stance_hit_line: int = -1
) -> Dictionary:
```

`target_stance_hit_line` is the target's current stance mapped to `Strike.HitLine` (HIGH for UPPER, MID for MIDDLE). When `stance_match_required == true`, PARRIED only succeeds if `target_stance_hit_line == strike.hit_line`. When `-1` (default), the check is skipped (backward compat).

- [ ] **Step 2: Add DODGED and PARRIED checks**

Replace the Phase 5 placeholder comments with actual checks. Insert between the `target_can_be_hurt` check and the `var dp := strike.damage_profile` line:

```gdscript
	# Dodge: unconditional i-frame defense
	if target_combat_state == CombatState.DODGING:
		return { "type": "DODGED" }

	# Parry: active parry frames, optionally gated by stance match
	if target_combat_state == CombatState.PARRYING:
		if stance_match_required:
			if target_stance_hit_line >= 0 and target_stance_hit_line == strike.hit_line:
				return { "type": "PARRIED" }
			# Stance mismatch: parry fails, strike resolves normally (fall through to limb routing)
		else:
			return { "type": "PARRIED" }
```

- [ ] **Step 3: Update the file header comment**

Replace the Phase 4 header with:

```gdscript
# fighter/hit_resolver.gd
# HitResolver — pure static function: strike context → HitOutcome.
# Phase 5: DODGED and PARRIED outcomes before limb routing.
# DODGED: target in DODGING → unconditional.
# PARRIED: target in PARRYING → optionally gated by stance_match_required.
# Limb routing via DamageProfile.hit_region_priority (Phase 4).
#
# Returns a Dictionary (tagged union):
#   { "type": "MISS" }
#   { "type": "DODGED" }
#   { "type": "PARRIED" }
#   { "type": "HIT", "limb": "arm_r", "lethal": false, "new_integrity": 2 }
#
# Pure: reads inputs only, mutates nothing. Testable without engine.
# Decoupled: uses its own CombatState enum, NOT FighterBody.state.
```

---

## Task 2: Wire parry into FighterBody

**Files:**
- Modify: `fighter/fighter_body.gd`

### Overview

Implement `intent_parry()` and `execute_parry()`. Update `_to_combat_state()` to return PARRYING when `parry_active == true`. Add the `stance_match_required` export. Add parry timing exports. Update the `_on_weapon_body_entered()` call to pass stance match parameters. Expand `hit()` to dispatch PARRIED by calling `attacker.parried()`. Implement `parried()` as extended recovery.

- [ ] **Step 1: Add parry and dodge timing exports and stance_match_required**

Add after the existing `var parry_window: float = 0.3` declaration (around line 64):

```gdscript
# --- Parry timing (Phase 5, sim-clock authoritative) ---
@export var parry_startup: float = 0.1
@export var parry_active_time: float = 0.3
@export var parry_recovery: float = 0.15
## Extended recovery imposed on the attacker when their strike is parried.
@export var parried_recover_time: float = 1.0
## When true, parry only succeeds if the parrying fighter's stance matches
## the incoming strike's hit_line. MVP ships false (timing-only parry).
@export var stance_match_required: bool = false

# --- Dodge timing (Phase 5, sim-clock authoritative) ---
@export var dodge_startup: float = 0.05
@export var dodge_active_time: float = 0.4
@export var dodge_recovery_time: float = 0.15
```

- [ ] **Step 2: Add `_stance_to_hit_line()` helper**

Add a static helper near `_to_combat_state()` that maps the current weapon_type to a Strike.HitLine value for stance-match parry checking:

```gdscript
## Map current weapon_type to Strike.HitLine for parry stance matching.
## SLASH (MIDDLE) → MID, HEAVY (UPPER) → HIGH.
func _stance_to_hit_line() -> int:
	match weapon_type:
		"HEAVY":
			return Strike.HitLine.HIGH
		"SLASH":
			return Strike.HitLine.MID
		_:
			return Strike.HitLine.MID
```

- [ ] **Step 3: Update `_to_combat_state()` to return PARRYING when parry_active**

The current mapper has a comment `# Phase 5: add PARRYING mapping when parry state exists`. Replace the wildcard `_` catch-all:

```gdscript
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
		_:
			return HitResolver.CombatState.IDLE
```

This is a static function and can't read `parry_active`. Instead, the call site in `_on_weapon_body_entered()` will override the combat state when `parry_active` is true. See Step 5.

- [ ] **Step 4: Implement `execute_parry()`**

Add a new coroutine after `execute_strike()`:

```gdscript
func execute_parry() -> void:
	var round_at_start := _round_id

	# --- Parry startup (vulnerable, cannot act) ---
	current_state = state.STATIC_ACTION
	parry_started.emit()

	await get_tree().create_timer(parry_startup).timeout
	if _round_id != round_at_start or current_state != state.STATIC_ACTION:
		return

	# --- Active parry frames ---
	# Stay in STATIC_ACTION but set parry_active so _to_combat_state
	# reports PARRYING to HitResolver. The fighter cannot move or act
	# during active frames — this is the commitment.
	parry_active = true
	can_be_hurt = true  # Can be "hit" — but HitResolver will resolve as PARRIED

	await get_tree().create_timer(parry_active_time).timeout
	if _round_id != round_at_start:
		parry_active = false
		return

	parry_active = false

	# --- Parry recovery (vulnerable, cannot act) ---
	# If we were hit during parry (state changed by hit()), don't override
	if current_state != state.STATIC_ACTION:
		return

	await get_tree().create_timer(parry_recovery).timeout
	if _round_id != round_at_start:
		return
	if current_state == state.STATIC_ACTION:
		current_state = state.FREE
```

- [ ] **Step 5: Update `_on_weapon_body_entered()` — pass stance match params and parry_active override**

Update the section that builds the HitResolver call. The target's combat state needs to account for `parry_active`, and the stance match params need to be passed:

```gdscript
func _on_weapon_body_entered(body: Node3D) -> void:
	if body == self:
		return
	if not body.is_in_group("Targets"):
		return
	if current_strike == null:
		return
	if current_state != state.STRIKING:
		return

	var attacker_combat := _to_combat_state(current_state)
	var target_combat := HitResolver.CombatState.IDLE
	var target_can_be_hurt := true
	var target_limbs: LimbHealth = null
	var target_stance_match := false
	var target_hit_line: int = -1
	if body is FighterBody:
		target_combat = _to_combat_state(body.current_state)
		# Override: if the target has parry_active, report PARRYING
		# regardless of their underlying state enum value.
		if body.parry_active:
			target_combat = HitResolver.CombatState.PARRYING
		target_can_be_hurt = body.can_be_hurt
		target_limbs = body.limb_health
		target_stance_match = body.stance_match_required
		target_hit_line = body._stance_to_hit_line()

	var outcome := HitResolver.resolve(
		current_strike,
		attacker_combat,
		target_combat,
		target_can_be_hurt,
		target_limbs,
		target_stance_match,
		target_hit_line
	)

	match outcome["type"]:
		"HIT":
			if body.has_method("hit"):
				body.hit(self, outcome)
			_arm_weapon(false)
		"PARRIED":
			if body.has_method("hit"):
				body.hit(self, outcome)
			_arm_weapon(false)
		"DODGED":
			# Attacker keeps their recovery; no effect on target.
			# Weapon stays armed — the dodge avoids the hit, but the
			# strike continues its arc (could hit a third body in theory).
			pass
		"MISS":
			pass
```

Note: this replaces the current `_on_weapon_body_entered()` method entirely. The key changes are:
- Added `parry_active` override for target combat state
- Added `target_stance_match` and `target_hit_line` extraction
- Expanded the outcome handling from a simple `if outcome["type"] == "HIT"` to a match statement
- PARRIED dispatches to `body.hit(self, outcome)` so the target can call `attacker.parried()`
- DODGED does nothing (attacker keeps their arc)

- [ ] **Step 6: Wire `intent_parry()`**

Replace the stub:

```gdscript
func intent_parry() -> void:
	if current_state != state.FREE:
		return
	execute_parry()
```

- [ ] **Step 7: Expand `hit()` for PARRIED dispatch**

Update the PARRIED case in `hit()`:

```gdscript
		"PARRIED":
			# This fighter successfully parried. Call parried() on the attacker
			# to impose extended recovery.
			if _who is FighterBody:
				_who.parried()
```

- [ ] **Step 8: Implement `parried()` — extended recovery**

Replace the stub:

```gdscript
func parried() -> void:
	# Attacker's strike was parried. Interrupt the strike and enter
	# extended RECOVERING — this is the punish window.
	_arm_weapon(false)
	current_strike = null
	current_state = state.RECOVERING

	var round_at_start := _round_id
	await get_tree().create_timer(parried_recover_time).timeout
	if _round_id != round_at_start:
		return
	if current_state == state.RECOVERING:
		current_state = state.FREE
```

- [ ] **Step 9: Update `reset_for_round()` — clear parry state**

The existing `reset_for_round()` already sets `parry_active = false`. Verify this is present (it is, at line 809). No changes needed — just confirm.

---

## Task 3: Wire dodge into FighterBody

**Files:**
- Modify: `fighter/fighter_body.gd`

### Overview

Replace the soul-template's `dodge()` with a sim-clock authoritative `execute_dodge()`. Wire `intent_dodge()` to call it. Dodge has i-frames throughout its active duration. Direction is opponent-relative when strafing, camera-relative otherwise.

- [ ] **Step 1: Implement `execute_dodge()`**

Add a new coroutine. This replaces the souls template's `dodge()` method — the old `dodge()` can be left as dead code (the animation tree's `_on_dodge_started` handler still fires from the signal).

```gdscript
func execute_dodge(dir: Vector2) -> void:
	var round_at_start := _round_id

	# --- Dodge startup (tiny, committed) ---
	current_state = state.DODGE
	can_be_hurt = false  # i-frames throughout
	dodge_started.emit()

	# Compute dodge direction
	if dir.length_squared() > 0.01:
		if opponent and strafing:
			# Opponent-relative: dir.y negative = toward opponent, positive = away
			var to_opp := (opponent.global_position - global_position).normalized()
			to_opp.y = 0.0
			var right := to_opp.cross(Vector3.UP).normalized()
			direction = (to_opp * (-dir.y) + right * dir.x).normalized()
		else:
			direction = _calc_cam_direction().normalized()
	else:
		# No input: dodge backward (away from opponent if strafing)
		if opponent:
			direction = (global_position - opponent.global_position).normalized()
			direction.y = 0.0
		else:
			direction = -global_transform.basis.z
	speed = dodge_speed

	await get_tree().create_timer(dodge_startup).timeout
	if _round_id != round_at_start:
		can_be_hurt = true
		return

	# --- Active dodge (i-frames, movement) ---
	await get_tree().create_timer(dodge_active_time).timeout
	if _round_id != round_at_start:
		can_be_hurt = true
		return

	# --- Dodge recovery (slow down, still invulnerable per spec) ---
	direction = Vector3.ZERO
	speed = default_speed

	await get_tree().create_timer(dodge_recovery_time).timeout
	if _round_id != round_at_start:
		can_be_hurt = true
		return

	can_be_hurt = true
	if current_state == state.DODGE:
		dodge_ended.emit()
		current_state = state.FREE
```

- [ ] **Step 2: Wire `intent_dodge()`**

Replace the current stub:

```gdscript
func intent_dodge(_dir: Vector2) -> void:
	if limb_health.has_leg_cripple():
		return
	if current_state != state.FREE:
		return
	execute_dodge(_dir)
```

- [ ] **Step 3: Disable the old dodge_timer-based flow**

The old `dodge()` method uses `dodge_timer.start(anim_length * 0.7)` and `_on_dodge_timer_timeout()` to end the dodge. The new `execute_dodge()` uses sim-clock timers and manages its own state transitions. The old `dodge()` is no longer called by anything, but `_on_dodge_timer_timeout()` could still fire if a stale timer is running from a prior code path.

Add a safety check: in `execute_dodge()`, stop the old dodge_timer at entry:

```gdscript
func execute_dodge(dir: Vector2) -> void:
	dodge_timer.stop()  # Cancel any stale souls-template dodge timer
	var round_at_start := _round_id
	# ... rest unchanged
```

---

## Task 4: Add parry and dodge input actions + PlayerBrain wiring

**Files:**
- Modify: `project.godot`
- Modify: `fighter/brains/player_brain.gd`

- [ ] **Step 1: Add `p0_parry` and `p0_dodge` input actions to `project.godot`**

Add two new input action entries in the `[input]` section. Use `Q` for parry and `E` for dodge (temporary key bindings — these are easy to rebind later):

```ini
p0_parry={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":81,"key_label":0,"unicode":113,"location":0,"echo":false,"script":null)
]
}
p0_dodge={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":69,"key_label":0,"unicode":101,"location":0,"echo":false,"script":null)
]
}
```

- [ ] **Step 2: Update PlayerBrain — add parry and dodge action names**

Add to the variable declarations:

```gdscript
var _parry: StringName
var _dodge: StringName
```

Add to `_ready()`:

```gdscript
	_parry        = StringName(p + "parry")
	_dodge        = StringName(p + "dodge")
```

- [ ] **Step 3: Add parry and dodge input reads to `_physics_process()`**

Add after the strike input block:

```gdscript
	# Parry (rising edge)
	if Input.is_action_just_pressed(_parry):
		fighter.intent_parry()

	# Dodge (rising edge, with direction from current movement input)
	if Input.is_action_just_pressed(_dodge):
		fighter.intent_dodge(move)
```

---

## Task 5: Expand HitResolver tests with DODGED and PARRIED cases

**Files:**
- Modify: `fighter/tests/test_hit_resolver.gd`

- [ ] **Step 1: Add DODGED test cases**

Add after test group 7 (upper_horizontal priority routing):

```gdscript
	# ================================================================
	# Test group 8: DODGED outcome
	# ================================================================

	# Target is DODGING → DODGED regardless of strike or stance
	r = HitResolver.resolve(strike_torso, CS.STRIKING, CS.DODGING, true, limbs_ok)
	if r["type"] == "DODGED":
		pass_count += 1
		results.append("PASS: target DODGING = DODGED")
	else:
		fail_count += 1
		results.append("FAIL: target DODGING — got %s" % str(r))
```

- [ ] **Step 2: Add PARRIED test cases (stance_match_required = false)**

```gdscript
	# ================================================================
	# Test group 9: PARRIED outcome (timing-only, no stance match)
	# ================================================================

	# Target is PARRYING, stance_match_required = false → always PARRIED
	r = HitResolver.resolve(strike_torso, CS.STRIKING, CS.PARRYING, true, limbs_ok, false, -1)
	if r["type"] == "PARRIED":
		pass_count += 1
		results.append("PASS: target PARRYING, no stance match = PARRIED")
	else:
		fail_count += 1
		results.append("FAIL: target PARRYING, no stance match — got %s" % str(r))
```

- [ ] **Step 3: Add PARRIED test cases (stance_match_required = true)**

```gdscript
	# ================================================================
	# Test group 10: PARRIED with stance match
	# ================================================================

	# strike_torso has hit_line = MID (default). Target stance = MID → PARRIED
	var strike_mid := Strike.new()
	strike_mid.strike_id = "test_mid"
	strike_mid.hit_line = Strike.HitLine.MID
	strike_mid.damage_profile = dp_torso

	r = HitResolver.resolve(strike_mid, CS.STRIKING, CS.PARRYING, true, limbs_ok, true, Strike.HitLine.MID)
	if r["type"] == "PARRIED":
		pass_count += 1
		results.append("PASS: stance match MID == MID = PARRIED")
	else:
		fail_count += 1
		results.append("FAIL: stance match MID == MID — got %s" % str(r))

	# Stance mismatch: strike HIGH, target MID → falls through to HIT (not PARRIED)
	var strike_high := Strike.new()
	strike_high.strike_id = "test_high"
	strike_high.hit_line = Strike.HitLine.HIGH
	strike_high.damage_profile = dp_torso

	r = HitResolver.resolve(strike_high, CS.STRIKING, CS.PARRYING, true, limbs_ok, true, Strike.HitLine.MID)
	if r["type"] == "HIT":
		pass_count += 1
		results.append("PASS: stance mismatch HIGH vs MID = HIT (parry fails)")
	else:
		fail_count += 1
		results.append("FAIL: stance mismatch HIGH vs MID — got %s" % str(r))
```

- [ ] **Step 4: Update the test count in the final summary**

The test file should now have 17 test cases (13 from Phase 4 + 4 new: DODGED, PARRIED no-match, PARRIED match-success, PARRIED match-fail). Update the count expectation if present, or just verify the print shows the correct number.

---

## Task 6: Verify .tres strike files have correct hit_line values

**Files:**
- Verify: `fighter/strikes/upper_horizontal.tres`
- Verify: `fighter/strikes/middle_horizontal.tres`

The existing `.tres` files already have `hit_line` values:
- `upper_horizontal.tres`: `hit_line = 0` (which is `Strike.HitLine.HIGH`)
- `middle_horizontal.tres`: `hit_line = 1` (which is `Strike.HitLine.MID`)

- [ ] **Step 1: Verify hit_line values are correct for stance-match parry**

Confirm:
- `upper_horizontal` → `hit_line = 0` (HIGH) — correct, upper stance = high strike
- `middle_horizontal` → `hit_line = 1` (MID) — correct, middle stance = mid strike

No code changes expected. If either value is wrong, update the `.tres` file.

---

## Exit criteria

> **From the spec (Phase 5 exit):** Parry a strike → attacker enters RECOVERING with a punish window. Dodge a strike with i-frames → keep positional advantage.

Manual verification checklist (F5 → play):

1. **Parry a strike**: Press parry (Q) just before the dummy's strike lands → the dummy enters extended RECOVERING (~1.0s). The player recovers from parry quickly and can land a free strike during the punish window.
2. **Parry too early**: Press parry (Q) well before the strike → parry active window expires → the strike lands normally (HIT, not PARRIED). The player takes damage.
3. **Parry too late**: Press parry (Q) after the strike has already landed → the player takes damage, then enters a parry that whiffs.
4. **Dodge a strike**: Press dodge (E) when a strike is incoming → i-frames prevent the hit → DODGED outcome. The player rolls away and recovers at a distance. No punish window — the attacker recovers normally.
5. **Dodge with direction**: Hold a movement direction + press dodge → the fighter dodges in that direction. No input → dodge backward (away from opponent).
6. **Leg cripple blocks dodge**: Cripple a leg (temporary test data) → dodge input is ignored.
7. **Round reset**: After a death, parry_active resets to false, can_be_hurt resets to true.
8. **stance_match_required = false (default)**: Any stance can parry any strike in the active window.
9. **stance_match_required = true (manual toggle)**: Set `stance_match_required = true` on one FighterBody in the editor. A MID-stance parry blocks a middle_horizontal strike (hit_line = MID) but NOT an upper_horizontal strike (hit_line = HIGH). Revert after testing.

**Test suite**: `godot --headless --script fighter/tests/test_hit_resolver.gd` passes all 17 cases (0 failures).

---

## Spec divergences

### 1. No dedicated PARRYING state in the enum

The spec's state machine lists PARRYING as a leaf state. The implementation uses `parry_active` boolean + `STATIC_ACTION` state. `_to_combat_state()` is overridden at the call site to return `CombatState.PARRYING` when `parry_active == true`. This avoids touching the serialized AnimationTree .tscn advance_expressions while giving HitResolver the correct combat state.

### 2. Dodge i-frames extend through recovery

The spec says "i-frames throughout its animation." The implementation keeps `can_be_hurt = false` through startup + active + recovery (the entire dodge duration). This is slightly generous — the recovery phase could arguably be vulnerable. For MVP, full i-frames match the spec's wording and feel better. If playtesting reveals dodge is too safe, the recovery phase can be made vulnerable by moving `can_be_hurt = true` earlier.

### 3. Parry animation uses the existing Parry oneshot

The souls template has a Parry oneshot in the AnimationTree that's connected to `parry_started`. Phase 5 emits `parry_started` from `execute_parry()`, which triggers `_on_parry_started()` in the animation tree, which calls `request_oneshot("Parry")`. This reuses the existing animation. No new animation is needed.

### 4. DODGED outcome is a no-op in weapon_body_entered

When HitResolver returns DODGED, the attacking fighter does nothing special — the weapon stays armed and the strike continues its normal arc. This matches the spec: "A successful dodge does not create a counter-stagger — it grants positional advantage only." The attacker finishes their strike normally (STRIKING → RECOVERING at normal duration).

### 5. Block is not implemented

The spec mentions `BLOCKED(by_stance)` as a future outcome. Phase 5 does not implement blocking — only parry and dodge. The `block()` and `block_started` infrastructure from the souls template remains as dead code.
