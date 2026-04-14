# Fighter Phase 4 — Limb Model + Full HitResolver Routing

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Phase 3 "every hit = torso, lethal=true" placeholder with a full limb-health model and hit-region routing. Strikes resolve against specific limbs based on `DamageProfile.hit_region_priority`. Head hits are lethal (gated by `DamageProfile.lethal_on_head` for future non-lethal training weapons). Torso hits wound then kill. Arm/leg hits cripple with gameplay consequences: leg cripple halves speed and disables dodge/sprint; weapon-arm cripple forces stance loss (locked to MIDDLE). A minimal HUD shows limb state. Round reset restores all limb health.

**Architecture:** A new `LimbHealth` Resource class holds per-limb `Integrity` enums (tiny enumerable state space, no float HP). FighterBody owns one `LimbHealth` instance and exposes a `limb_state_changed` signal. HitResolver.resolve() gains a `target_limb_health: LimbHealth` parameter and reads the Strike's `DamageProfile.hit_region_priority` to pick the target limb, then determines lethality based on limb identity + current integrity. FighterBody.hit() reads the expanded HitOutcome and applies limb state transitions + gameplay effects. A `FighterHUD` Control node subscribes to both fighters' signals and renders limb-state dots.

**Tech Stack:** Godot 4.7 + GDScript. No external test framework. Visual verification is manual F5.

**Source spec:** `docs/superpowers/specs/2026-04-09-bushido-blade-pivot-design.md` (Limb model section ~line 150, HitResolver section ~line 174, Phase 4 bullet ~line 457)

**Commit style:** `type: description` (e.g., `feat:`, `fix:`, `chore:`).

---

## Key design decisions

### 1. LimbHealth is a Resource, not an inner class

`LimbHealth` is a standalone `Resource` class in `fighter/limb_health.gd`. This keeps FighterBody from growing further (already ~780 lines) and makes LimbHealth independently testable — HitResolver can receive it as a parameter without needing a FighterBody instance. The Resource holds six limb slots, each an `Integrity` enum value. It exposes `get_integrity(limb) -> Integrity`, `set_integrity(limb, value)`, and `reset()`.

### 2. Limb names are strings, matching DamageProfile

The spec and existing `.tres` files use string limb names: `"torso"`, `"head"`, `"arm_r"`, `"arm_l"`, `"leg_r"`, `"leg_l"`. LimbHealth stores state in a Dictionary keyed by these strings. This keeps the contract between DamageProfile (which declares `hit_region_priority` as `Array[String]`) and LimbHealth simple — no enum↔string translation layer.

### 3. Hit routing is first-valid-limb from priority list

HitResolver iterates `DamageProfile.hit_region_priority` in order and picks the **first** limb in the list. There is no "skip already-crippled" logic — a crippled arm can be hit again (it's already crippled, so the outcome is a non-lethal hit with no further state change). This matches the spec's abstract hit-region model: the Strike declares what it targets, the first entry wins.

### 4. Lethality rules are in HitResolver, not LimbHealth

LimbHealth is a dumb data container. All lethality logic lives in HitResolver:
- Head → lethal, gated by `dp.lethal_on_head` (true for all MVP weapons; the field exists so future non-lethal training weapons can set it false).
- Torso OK → WOUNDED, non-lethal.
- Torso WOUNDED → lethal.
- Arm → CRIPPLED, non-lethal.
- Leg → CRIPPLED, non-lethal.

HitResolver returns an expanded outcome: `{ "type": "HIT", "limb": "arm_r", "lethal": false, "new_integrity": "CRIPPLED" }`. The `new_integrity` field tells FighterBody what to set without re-deriving the logic.

### 5. Cripple effects live on FighterBody, not LimbHealth

LimbHealth stores state. FighterBody reads that state and applies gameplay consequences:
- **Leg cripple** (either leg): `default_speed` halved, dodge and sprint disabled (intent_dodge/intent_sprint become no-ops). Applied immediately when `limb_state_changed` fires.
- **Weapon-arm cripple** (`arm_r`): force stance to MIDDLE and lock it there. `intent_change_stance` becomes a no-op. This uses the existing `SLASH_tree` (MIDDLE stance) — no new animation sub-tree needed. The fighter can still strike from MIDDLE, just can't switch to UPPER (HEAVY).
- **Off-arm cripple** (`arm_l`): cosmetic at MVP per spec. No gameplay effect.

### 6. No new animation sub-tree for "wounded stance"

The spec mentions a "wounded stance with a reduced strike set." At MVP, weapon-arm cripple simply locks the fighter to MIDDLE stance (the `SLASH_tree`). This reuses existing animations — no new "wounded" animation tree is needed. The restriction is: UPPER strikes become unavailable. If the fighter was in UPPER when crippled, they're forced to MIDDLE immediately. This is the simplest expression of "reduced strike set."

### 7. HUD is a minimal Control node, not a full UI system

`FighterHUD` is a single `Control` node added to the demo scene. It draws colored dots per limb for each fighter using `_draw()` override — no sub-scenes, no themes, no layout containers. Green = OK, yellow = WOUNDED, red = CRIPPLED. Positioned as a simple body-outline diagram (head dot on top, two arm dots, torso dot center, two leg dots bottom). Two diagrams, one per fighter, left and right of screen.

### 8. HitResolver signature expands, stays pure

The resolve() function gains `target_limb_health: LimbHealth` as a parameter. It remains a static pure function — it reads LimbHealth but does not mutate it. The caller (FighterBody) applies the returned outcome.

New signature:
```gdscript
static func resolve(
    strike: Strike,
    attacker_combat_state: int,
    target_combat_state: int,
    target_can_be_hurt: bool,
    target_limb_health: LimbHealth
) -> Dictionary
```

---

## File map

By the end of this plan, these files exist or are modified:

| File | Status | Responsibility |
|---|---|---|
| `fighter/limb_health.gd` | **New** | `LimbHealth` Resource — per-limb `Integrity` enum storage, get/set/reset |
| `fighter/hit_resolver.gd` | **Modified** | Expanded resolve(): reads `hit_region_priority`, routes to limbs, determines lethality by limb + integrity |
| `fighter/fighter_body.gd` | **Modified** | Owns `LimbHealth` instance. `hit()` applies limb state changes + gameplay effects. `reset_for_round()` restores limbs. New signal `limb_state_changed`. Cripple effects on movement/stance. |
| `fighter/fighter_arena.gd` | **Modified** | No code changes needed — `reset_for_round()` already calls `fighter.reset_for_round()` which will now also reset limbs |
| `fighter/fighter_hud.gd` | **New** | Minimal HUD — limb-state dot display for both fighters |
| `fighter/fighter_demo.tscn` | **Modified** | Add FighterHUD node |
| `fighter/tests/test_hit_resolver.gd` | **Modified** | Expanded with limb routing test cases |

---

## Task 1: Create the LimbHealth Resource class

**Files:**
- Create: `fighter/limb_health.gd`

- [ ] **Step 1: Write `fighter/limb_health.gd`**

```gdscript
# fighter/limb_health.gd
# LimbHealth — tiny enumerable state per limb. No float HP.
# Owned by FighterBody, read by HitResolver.
extends Resource
class_name LimbHealth

enum Integrity { OK, WOUNDED, CRIPPLED }

## All valid limb names. Order matches the body-outline HUD layout.
const LIMB_NAMES: Array[String] = ["head", "torso", "arm_r", "arm_l", "leg_r", "leg_l"]

## Internal state. Keyed by limb name string → Integrity enum value.
var _state: Dictionary = {}

func _init() -> void:
    reset()

## Restore all limbs to starting integrity.
func reset() -> void:
    _state = {
        "head": Integrity.OK,
        "torso": Integrity.OK,
        "arm_r": Integrity.OK,
        "arm_l": Integrity.OK,
        "leg_r": Integrity.OK,
        "leg_l": Integrity.OK,
    }

func get_integrity(limb: String) -> int:
    return _state.get(limb, Integrity.OK)

func set_integrity(limb: String, value: int) -> void:
    if limb in _state:
        _state[limb] = value

## Returns true if either leg is crippled.
func has_leg_cripple() -> bool:
    return _state["leg_r"] == Integrity.CRIPPLED or _state["leg_l"] == Integrity.CRIPPLED

## Returns true if the weapon arm (right) is crippled.
func has_weapon_arm_cripple() -> bool:
    return _state["arm_r"] == Integrity.CRIPPLED
```

---

## Task 2: Expand HitResolver with limb routing

**Files:**
- Modify: `fighter/hit_resolver.gd`

The resolver reads the Strike's `DamageProfile.hit_region_priority` to pick which limb gets hit, then determines lethality based on limb identity and current integrity from the target's `LimbHealth`.

- [ ] **Step 1: Add `target_limb_health` parameter to resolve()**

Update the function signature:

```gdscript
static func resolve(
    strike: Strike,
    attacker_combat_state: int,
    target_combat_state: int,
    target_can_be_hurt: bool,
    target_limb_health: LimbHealth = null
) -> Dictionary:
```

The default `null` preserves backward compatibility during the transition — if called without limb health (shouldn't happen after Phase 4 wiring, but safe).

- [ ] **Step 2: Replace the hardcoded torso hit with limb routing logic**

Replace the Phase 3 body (everything after the `target_can_be_hurt` check) with:

```gdscript
    # Phase 5 will add: if target_combat_state == DODGING → DODGED
    # Phase 5 will add: if target_combat_state == PARRYING → PARRIED check

    # --- Limb routing (Phase 4) ---
    var dp := strike.damage_profile
    if dp == null:
        return { "type": "MISS" }

    # Pick the first limb from the priority list.
    # The strike declares what it targets; the first entry is what gets hit.
    var target_limb: String = "torso"
    if dp.hit_region_priority.size() > 0:
        target_limb = dp.hit_region_priority[0]

    # Determine outcome based on limb identity and current integrity.
    var limb_integrity: int = LimbHealth.Integrity.OK
    if target_limb_health != null:
        limb_integrity = target_limb_health.get_integrity(target_limb)

    return _resolve_limb_hit(target_limb, limb_integrity, dp)
```

- [ ] **Step 3: Add the `_resolve_limb_hit` helper**

```gdscript
## Given a limb, its current integrity, and the damage profile,
## determine lethality and new integrity. Pure — no side effects.
static func _resolve_limb_hit(limb: String, integrity: int, dp: DamageProfile) -> Dictionary:
    match limb:
        "head":
            # Head hit is always lethal (unless damage profile says otherwise —
            # reserved for future non-lethal training weapons).
            return {
                "type": "HIT",
                "limb": "head",
                "lethal": dp.lethal_on_head,
                "new_integrity": LimbHealth.Integrity.OK,
            }
        "torso":
            if integrity == LimbHealth.Integrity.OK:
                # First torso hit: OK → WOUNDED, non-lethal.
                return {
                    "type": "HIT",
                    "limb": "torso",
                    "lethal": false,
                    "new_integrity": LimbHealth.Integrity.WOUNDED,
                }
            else:
                # Torso already WOUNDED → lethal.
                return {
                    "type": "HIT",
                    "limb": "torso",
                    "lethal": dp.lethal_on_torso,
                    "new_integrity": LimbHealth.Integrity.WOUNDED,
                }
        "arm_r", "arm_l":
            if not dp.limb_cripple:
                return {
                    "type": "HIT",
                    "limb": limb,
                    "lethal": false,
                    "new_integrity": integrity,
                }
            return {
                "type": "HIT",
                "limb": limb,
                "lethal": false,
                "new_integrity": LimbHealth.Integrity.CRIPPLED,
            }
        "leg_r", "leg_l":
            if not dp.limb_cripple:
                return {
                    "type": "HIT",
                    "limb": limb,
                    "lethal": false,
                    "new_integrity": integrity,
                }
            return {
                "type": "HIT",
                "limb": limb,
                "lethal": false,
                "new_integrity": LimbHealth.Integrity.CRIPPLED,
            }
        _:
            # Unknown limb — treat as miss (shouldn't happen with valid data).
            return { "type": "MISS" }
```

- [ ] **Step 4: Update the file header comment**

Replace the Phase 3 header with:

```gdscript
# fighter/hit_resolver.gd
# HitResolver — pure static function: strike context → HitOutcome.
# Phase 4: routes hits to limbs via DamageProfile.hit_region_priority.
# Determines lethality by limb identity + current integrity.
# Phase 5 will add PARRIED/DODGED outcomes.
#
# Returns a Dictionary (tagged union):
#   { "type": "MISS" }
#   { "type": "HIT", "limb": "arm_r", "lethal": false, "new_integrity": 2 }
#
# Pure: reads inputs only, mutates nothing. Testable without engine.
# Decoupled: uses its own CombatState enum, NOT FighterBody.state.
```

---

## Task 3: Wire LimbHealth into FighterBody

**Files:**
- Modify: `fighter/fighter_body.gd`

FighterBody gains a `LimbHealth` instance, a `limb_state_changed` signal, and gameplay effects for crippled limbs. The `hit()` method is expanded to apply limb state transitions from the HitOutcome. `reset_for_round()` resets limb health. The `_on_weapon_body_entered()` call site passes limb health to HitResolver.

- [ ] **Step 1: Add LimbHealth instance and signal**

Add after the existing health-related declarations (after `var is_dead: bool = false`):

```gdscript
# --- Limb health (Phase 4) ---
var limb_health: LimbHealth = LimbHealth.new()
signal limb_state_changed(limb: String, new_state: int)

## Saved defaults for cripple effect reversal on round reset.
var _base_default_speed: float
var _base_sprint_speed: float
```

- [ ] **Step 2: Capture base speed in `_ready()`**

Add early in `_ready()`, before the spawn animation await:

```gdscript
    _base_default_speed = default_speed
    _base_sprint_speed = sprint_speed
```

This saves the original speeds so `reset_for_round()` can restore them after a leg-cripple speed penalty.

- [ ] **Step 3: Update `_on_weapon_body_entered()` — pass LimbHealth to HitResolver**

In the existing `_on_weapon_body_entered()` method, update the `HitResolver.resolve()` call to pass the target's limb health:

```gdscript
    var target_limbs: LimbHealth = null
    if body is FighterBody:
        target_combat = _to_combat_state(body.current_state)
        target_can_be_hurt = body.can_be_hurt
        target_limbs = body.limb_health

    var outcome := HitResolver.resolve(
        current_strike,
        attacker_combat,
        target_combat,
        target_can_be_hurt,
        target_limbs
    )
```

- [ ] **Step 4: Expand `hit()` — apply limb state changes and cripple effects**

Replace the existing `hit()` method:

```gdscript
## Hit contract — Phase 4.
## _who: the attacking FighterBody.
## _by_what: HitOutcome Dictionary from HitResolver (single source of truth).
## This method dispatches consequences only — it does NOT re-resolve.
func hit(_who: Node, _by_what: Variant) -> void:
    # Interrupt any in-progress strike
    if current_state == state.WINDING_UP:
        _arm_weapon(false)
        current_strike = null

    if not (_by_what is Dictionary):
        return
    match _by_what.get("type"):
        "HIT":
            # Apply limb state change
            var limb: String = _by_what.get("limb", "torso")
            var new_integrity: int = _by_what.get("new_integrity", LimbHealth.Integrity.OK)
            var old_integrity: int = limb_health.get_integrity(limb)
            if new_integrity != old_integrity:
                limb_health.set_integrity(limb, new_integrity)
                limb_state_changed.emit(limb, new_integrity)
                _apply_cripple_effects(limb, new_integrity)

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

- [ ] **Step 5: Add `_apply_cripple_effects()` helper**

```gdscript
## Apply gameplay consequences of limb state changes.
## Called immediately when a limb's integrity changes.
func _apply_cripple_effects(limb: String, new_integrity: int) -> void:
    match limb:
        "leg_r", "leg_l":
            if new_integrity == LimbHealth.Integrity.CRIPPLED:
                default_speed = _base_default_speed * 0.5
                sprint_speed = _base_default_speed * 0.5
                speed = min(speed, default_speed)
                # Force-exit active sprint — sprint_speed comes from
                # change_state(SPRINT), not default_speed, so a fighter
                # hit mid-sprint would keep full sprint speed without this.
                if current_state == state.SPRINT:
                    current_state = state.FREE
        "arm_r":
            if new_integrity == LimbHealth.Integrity.CRIPPLED:
                # Force to MIDDLE stance and lock
                if weapon_type != "SLASH":
                    weapon_type = "SLASH"
                    if anim_state_tree:
                        anim_state_tree._on_weapon_change_ended("SLASH")
```

**Why both `default_speed` and `sprint_speed`:** The state machine sets `speed = sprint_speed` on entering SPRINT (see `change_state()` at `fighter_body.gd:216`). Halving only `default_speed` leaves `sprint_speed` untouched, meaning a leg-crippled fighter who somehow enters SPRINT (e.g., via a race condition or future code path) would move at full sprint speed. Halving both ensures the penalty is enforced regardless of state.

- [ ] **Step 6: Gate `intent_change_stance()` on weapon-arm cripple**

Add a check at the top of `intent_change_stance()`:

```gdscript
func intent_change_stance(stance: int) -> void:
    # Weapon-arm cripple locks stance to MIDDLE
    if limb_health.has_weapon_arm_cripple():
        return
    # Cannot change stance while executing a strike
    if current_state in [state.WINDING_UP, state.STRIKING, state.RECOVERING]:
        return
    # ... rest unchanged
```

- [ ] **Step 6a: Clamp stance in `intent_strike()` on weapon-arm cripple**

The stance gate in `intent_change_stance()` alone is not sufficient — `intent_strike()` accepts a caller-supplied stance parameter and forwards it directly to `execute_strike()`. An AI brain or future code could request `intent_strike(Stance.UPPER, ...)` even after arm_r is crippled. Add a clamp after the sprint-break logic, before the `execute_strike()` call:

```gdscript
func intent_strike(stance: int = -1, dir: int = Strike.StrikeDir.SLASH_HORIZONTAL) -> void:
    # Accept strike from FREE or SPRINT. Sprinting auto-breaks lock
    # and forces re-lock per spec § Movement sub-model.
    if current_state == state.SPRINT:
        current_state = state.FREE  # break sprint, re-lock
    if current_state != state.FREE:
        return
    if stance < 0:
        stance = STANCE_TO_WEAPON.find_key(weapon_type)
        if stance == null:
            stance = Stance.MIDDLE
    # Weapon-arm cripple: force MIDDLE regardless of requested stance
    if limb_health.has_weapon_arm_cripple():
        stance = Stance.MIDDLE
    execute_strike(stance, dir)
```

- [ ] **Step 7: Gate `intent_dodge()` and `intent_sprint()` on leg cripple**

Update `intent_dodge()`:

```gdscript
func intent_dodge(_dir: Vector2) -> void:
    if limb_health.has_leg_cripple():
        return
    # Phase 5 wires the actual dodge
    pass
```

Update `intent_sprint()` — add a leg-cripple check at the top:

```gdscript
func intent_sprint(held: bool) -> void:
    if held:
        if limb_health.has_leg_cripple():
            return
        if current_state == state.FREE:
            current_state = state.SPRINT
            sprint_started.emit()
    else:
        if current_state == state.SPRINT:
            if _should_re_engage_lock():
                current_state = state.FREE
```

- [ ] **Step 8: Update `reset_for_round()` — restore limb health and speed**

Add to the existing `reset_for_round()` method, after the existing state resets and before the animation tree reset:

```gdscript
    # Restore limb health and speeds
    limb_health.reset()
    default_speed = _base_default_speed
    sprint_speed = _base_sprint_speed
    speed = default_speed
    # Emit limb_state_changed for every limb so the HUD redraws to green.
    # Without this, the HUD stays stale after round reset because reset()
    # doesn't go through the normal hit() → set_integrity() → signal path.
    for limb_name in LimbHealth.LIMB_NAMES:
        limb_state_changed.emit(limb_name, LimbHealth.Integrity.OK)
```

---

## Task 4: Expand HitResolver tests with limb routing cases

**Files:**
- Modify: `fighter/tests/test_hit_resolver.gd`

Add test cases covering: head hit lethality, torso OK→WOUNDED (non-lethal), torso WOUNDED→lethal, arm cripple, leg cripple, limb_cripple=false passthrough, and the existing Phase 3 tests updated to pass LimbHealth.

- [ ] **Step 1: Rewrite the test file with expanded cases**

```gdscript
# fighter/tests/test_hit_resolver.gd
# Headless test for HitResolver — runs via:
#   godot --headless --script fighter/tests/test_hit_resolver.gd
extends SceneTree

func _init() -> void:
    var pass_count := 0
    var fail_count := 0
    var CS := HitResolver.CombatState

    # --- Helper: build a Strike with a given hit_region_priority ---
    var results: Array[String] = []

    # ================================================================
    # Test group 1: basic gating (carried forward from Phase 3)
    # ================================================================

    var dp_torso := DamageProfile.new()
    dp_torso.hit_region_priority = ["torso"]
    dp_torso.lethal_on_torso = true
    dp_torso.lethal_on_head = true
    dp_torso.limb_cripple = true

    var strike_torso := Strike.new()
    strike_torso.strike_id = "test_torso"
    strike_torso.damage_profile = dp_torso

    var limbs_ok := LimbHealth.new()

    # Test: attacker must be STRIKING
    var r := HitResolver.resolve(strike_torso, CS.WINDING_UP, CS.IDLE, true, limbs_ok)
    if r["type"] == "MISS":
        pass_count += 1
        results.append("PASS: winding_up = MISS")
    else:
        fail_count += 1
        results.append("FAIL: winding_up — got %s" % str(r))

    r = HitResolver.resolve(strike_torso, CS.RECOVERING, CS.IDLE, true, limbs_ok)
    if r["type"] == "MISS":
        pass_count += 1
        results.append("PASS: recovering = MISS")
    else:
        fail_count += 1
        results.append("FAIL: recovering — got %s" % str(r))

    r = HitResolver.resolve(strike_torso, CS.IDLE, CS.IDLE, true, limbs_ok)
    if r["type"] == "MISS":
        pass_count += 1
        results.append("PASS: attacker IDLE = MISS")
    else:
        fail_count += 1
        results.append("FAIL: attacker IDLE — got %s" % str(r))

    # Test: target not hurtable = MISS
    r = HitResolver.resolve(strike_torso, CS.STRIKING, CS.IDLE, false, limbs_ok)
    if r["type"] == "MISS":
        pass_count += 1
        results.append("PASS: target not hurtable = MISS")
    else:
        fail_count += 1
        results.append("FAIL: target not hurtable — got %s" % str(r))

    # ================================================================
    # Test group 2: torso routing
    # ================================================================

    # Torso OK → WOUNDED, non-lethal
    r = HitResolver.resolve(strike_torso, CS.STRIKING, CS.IDLE, true, limbs_ok)
    if r["type"] == "HIT" and r["limb"] == "torso" and r["lethal"] == false and r["new_integrity"] == LimbHealth.Integrity.WOUNDED:
        pass_count += 1
        results.append("PASS: torso OK → WOUNDED, non-lethal")
    else:
        fail_count += 1
        results.append("FAIL: torso OK — got %s" % str(r))

    # Torso WOUNDED → lethal
    var limbs_torso_wounded := LimbHealth.new()
    limbs_torso_wounded.set_integrity("torso", LimbHealth.Integrity.WOUNDED)
    r = HitResolver.resolve(strike_torso, CS.STRIKING, CS.IDLE, true, limbs_torso_wounded)
    if r["type"] == "HIT" and r["limb"] == "torso" and r["lethal"] == true:
        pass_count += 1
        results.append("PASS: torso WOUNDED → lethal")
    else:
        fail_count += 1
        results.append("FAIL: torso WOUNDED — got %s" % str(r))

    # ================================================================
    # Test group 3: head routing
    # ================================================================

    var dp_head := DamageProfile.new()
    dp_head.hit_region_priority = ["head", "torso"]
    dp_head.lethal_on_torso = true
    dp_head.lethal_on_head = true
    dp_head.limb_cripple = true

    var strike_head := Strike.new()
    strike_head.strike_id = "test_head"
    strike_head.damage_profile = dp_head

    r = HitResolver.resolve(strike_head, CS.STRIKING, CS.IDLE, true, limbs_ok)
    if r["type"] == "HIT" and r["limb"] == "head" and r["lethal"] == true:
        pass_count += 1
        results.append("PASS: head hit = lethal")
    else:
        fail_count += 1
        results.append("FAIL: head hit — got %s" % str(r))

    # ================================================================
    # Test group 4: arm cripple
    # ================================================================

    var dp_arm := DamageProfile.new()
    dp_arm.hit_region_priority = ["arm_r", "torso"]
    dp_arm.lethal_on_torso = true
    dp_arm.lethal_on_head = true
    dp_arm.limb_cripple = true

    var strike_arm := Strike.new()
    strike_arm.strike_id = "test_arm"
    strike_arm.damage_profile = dp_arm

    r = HitResolver.resolve(strike_arm, CS.STRIKING, CS.IDLE, true, limbs_ok)
    if r["type"] == "HIT" and r["limb"] == "arm_r" and r["lethal"] == false and r["new_integrity"] == LimbHealth.Integrity.CRIPPLED:
        pass_count += 1
        results.append("PASS: arm hit = CRIPPLED, non-lethal")
    else:
        fail_count += 1
        results.append("FAIL: arm hit — got %s" % str(r))

    # Hitting an already-crippled arm: still CRIPPLED, still non-lethal
    var limbs_arm_crippled := LimbHealth.new()
    limbs_arm_crippled.set_integrity("arm_r", LimbHealth.Integrity.CRIPPLED)
    r = HitResolver.resolve(strike_arm, CS.STRIKING, CS.IDLE, true, limbs_arm_crippled)
    if r["type"] == "HIT" and r["limb"] == "arm_r" and r["lethal"] == false:
        pass_count += 1
        results.append("PASS: already-crippled arm = non-lethal, stays CRIPPLED")
    else:
        fail_count += 1
        results.append("FAIL: already-crippled arm — got %s" % str(r))

    # ================================================================
    # Test group 5: leg cripple
    # ================================================================

    var dp_leg := DamageProfile.new()
    dp_leg.hit_region_priority = ["leg_r"]
    dp_leg.lethal_on_torso = true
    dp_leg.lethal_on_head = true
    dp_leg.limb_cripple = true

    var strike_leg := Strike.new()
    strike_leg.strike_id = "test_leg"
    strike_leg.damage_profile = dp_leg

    r = HitResolver.resolve(strike_leg, CS.STRIKING, CS.IDLE, true, limbs_ok)
    if r["type"] == "HIT" and r["limb"] == "leg_r" and r["lethal"] == false and r["new_integrity"] == LimbHealth.Integrity.CRIPPLED:
        pass_count += 1
        results.append("PASS: leg hit = CRIPPLED, non-lethal")
    else:
        fail_count += 1
        results.append("FAIL: leg hit — got %s" % str(r))

    # ================================================================
    # Test group 6: limb_cripple = false (non-crippling weapon)
    # ================================================================

    var dp_no_cripple := DamageProfile.new()
    dp_no_cripple.hit_region_priority = ["arm_r"]
    dp_no_cripple.lethal_on_torso = true
    dp_no_cripple.lethal_on_head = true
    dp_no_cripple.limb_cripple = false

    var strike_no_cripple := Strike.new()
    strike_no_cripple.strike_id = "test_no_cripple"
    strike_no_cripple.damage_profile = dp_no_cripple

    r = HitResolver.resolve(strike_no_cripple, CS.STRIKING, CS.IDLE, true, limbs_ok)
    if r["type"] == "HIT" and r["limb"] == "arm_r" and r["lethal"] == false and r["new_integrity"] == LimbHealth.Integrity.OK:
        pass_count += 1
        results.append("PASS: limb_cripple=false → no cripple, stays OK")
    else:
        fail_count += 1
        results.append("FAIL: limb_cripple=false — got %s" % str(r))

    # ================================================================
    # Test group 7: upper_horizontal priority routing
    # ================================================================

    # upper_horizontal has priority ["head", "torso", "arm_r", "arm_l"]
    # First entry = head → should resolve as head hit
    var dp_upper := DamageProfile.new()
    dp_upper.hit_region_priority = ["head", "torso", "arm_r", "arm_l"]
    dp_upper.lethal_on_torso = true
    dp_upper.lethal_on_head = true
    dp_upper.limb_cripple = true

    var strike_upper := Strike.new()
    strike_upper.strike_id = "upper_horizontal"
    strike_upper.damage_profile = dp_upper

    r = HitResolver.resolve(strike_upper, CS.STRIKING, CS.IDLE, true, limbs_ok)
    if r["type"] == "HIT" and r["limb"] == "head" and r["lethal"] == true:
        pass_count += 1
        results.append("PASS: upper_horizontal → head (first in priority)")
    else:
        fail_count += 1
        results.append("FAIL: upper_horizontal routing — got %s" % str(r))

    # middle_horizontal has priority ["torso", "arm_r", "arm_l", "head"]
    # First entry = torso → should resolve as torso hit
    var dp_middle := DamageProfile.new()
    dp_middle.hit_region_priority = ["torso", "arm_r", "arm_l", "head"]
    dp_middle.lethal_on_torso = true
    dp_middle.lethal_on_head = true
    dp_middle.limb_cripple = true

    var strike_middle := Strike.new()
    strike_middle.strike_id = "middle_horizontal"
    strike_middle.damage_profile = dp_middle

    r = HitResolver.resolve(strike_middle, CS.STRIKING, CS.IDLE, true, limbs_ok)
    if r["type"] == "HIT" and r["limb"] == "torso" and r["lethal"] == false:
        pass_count += 1
        results.append("PASS: middle_horizontal → torso OK → WOUNDED, non-lethal")
    else:
        fail_count += 1
        results.append("FAIL: middle_horizontal routing — got %s" % str(r))

    # ================================================================
    # Print results
    # ================================================================

    for line in results:
        print(line)

    print("\n--- HitResolver Tests: %d passed, %d failed ---" % [pass_count, fail_count])
    if fail_count > 0:
        quit(1)
    else:
        quit(0)
```

---

## Task 5: Create FighterHUD — minimal limb-state display

**Files:**
- Create: `fighter/fighter_hud.gd`
- Modify: `fighter/fighter_demo.tscn` (add FighterHUD node)

A minimal `Control` node that draws colored dots per limb for each fighter. Uses `_draw()` for simplicity — no sub-scenes, no theme resources.

- [ ] **Step 1: Write `fighter/fighter_hud.gd`**

```gdscript
# fighter/fighter_hud.gd
# FighterHUD — minimal limb-state dot display for both fighters.
# Draws a simple body-outline diagram per fighter using _draw().
extends Control
class_name FighterHUD

@export var fighter_a_path: NodePath
@export var fighter_b_path: NodePath
var fighter_a: FighterBody
var fighter_b: FighterBody

const DOT_RADIUS: float = 8.0
const DIAGRAM_SPACING: float = 30.0

## Limb name → relative offset from diagram center (body outline).
## Head on top, arms at sides, torso center, legs below.
const LIMB_OFFSETS: Dictionary = {
    "head":  Vector2(0, -40),
    "torso": Vector2(0, 0),
    "arm_r": Vector2(30, -10),
    "arm_l": Vector2(-30, -10),
    "leg_r": Vector2(12, 40),
    "leg_l": Vector2(-12, 40),
}

const COLOR_OK := Color(0.2, 0.8, 0.2)       # green
const COLOR_WOUNDED := Color(0.9, 0.8, 0.1)   # yellow
const COLOR_CRIPPLED := Color(0.9, 0.15, 0.15) # red

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

    # Anchor to top-center for visibility
    set_anchors_preset(Control.PRESET_TOP_WIDE)
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_limb_changed(_limb: String, _new_state: int) -> void:
    queue_redraw()

func _draw() -> void:
    var vp_size := get_viewport_rect().size
    # Fighter A diagram: left side of screen
    if fighter_a:
        _draw_fighter_diagram(Vector2(120, 80), fighter_a.limb_health)
    # Fighter B diagram: right side of screen
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
        # Draw a thin outline for contrast
        draw_arc(center + offset, DOT_RADIUS, 0, TAU, 24, Color(0, 0, 0, 0.5), 1.5)
```

- [ ] **Step 2: Add FighterHUD to `fighter/fighter_demo.tscn`**

Add a `CanvasLayer` with a `FighterHUD` child to the demo scene. The FighterHUD's `fighter_a_path` and `fighter_b_path` exports point to the existing FighterA and FighterB nodes.

This is a scene edit — add the following node structure:
```
fighter_demo (root)
  ├── FighterA
  ├── FighterB
  ├── FighterCam
  ├── PlayerBrain
  ├── FighterArena
  └── HUDLayer (CanvasLayer)          # NEW
      └── FighterHUD (FighterHUD)     # NEW
          fighter_a_path = ../../FighterA
          fighter_b_path = ../../FighterB
```

The CanvasLayer ensures the HUD renders on top of the 3D scene. The FighterHUD script is attached to the FighterHUD Control node.

**Implementation note for subagent:** This requires editing the `.tscn` file. The demo scene is small (~30 lines), so this is safe to hand-edit. Use the Godot MCP tools (`add_node`, `attach_script`, `modify_node_property`) if available, otherwise edit the `.tscn` text directly.

---

## Task 6: Update `.tres` strike files — verify hit_region_priority

**Files:**
- Verify (no changes expected): `fighter/strikes/upper_horizontal.tres`
- Verify (no changes expected): `fighter/strikes/middle_horizontal.tres`

The existing `.tres` files already have correct `hit_region_priority` values:
- `upper_horizontal.tres`: `["head", "torso", "arm_r", "arm_l"]`
- `middle_horizontal.tres`: `["torso", "arm_r", "arm_l", "head"]`

- [ ] **Step 1: Verify both `.tres` files have the expected hit_region_priority arrays**

No code changes needed — this task is verification only. Confirm the priority arrays match the spec's intent:
- **Upper horizontal**: head is first (highest priority) — this is a high strike, it goes for the head.
- **Middle horizontal**: torso is first — this is a mid strike aimed at the body.

If either file is missing `hit_region_priority` or has only `["torso"]`, update it.

---

## Exit criteria

> **From the spec (Phase 4 exit):** Hit the dummy's leg → it moves slower. Hit its arm → it loses stance. Hit torso → wounded, hit again → dies. All three transitions visible, no state gets stuck.
>
> *(The original spec says "Hit torso → dies" because Phase 3's resolver was one-hit-kill. Phase 4's limb model adds the wound-then-kill intermediate state for torso, per the spec's Limb Model section.)*

Manual verification checklist (F5 → play):

1. **Upper horizontal strike at dummy** → head hit → dummy dies immediately (upper_horizontal priority: head first). Round resets.
2. **Middle horizontal strike at dummy** → torso hit → dummy enters HURT, torso becomes WOUNDED (HUD shows yellow torso dot). Second middle strike → dummy dies (torso WOUNDED → lethal).
3. **Leg cripple**: Neither existing strike targets legs, so this requires test data. Temporarily edit `middle_horizontal.tres` to `["leg_r", "torso"]` priority. **Test harness**: add a second `PlayerBrain` (with `player_index = 1`) as a child of FighterB in the demo scene, and register `p1_*` input actions (duplicate the `p0_*` set with different keys — e.g., arrow keys + numpad). This lets one person control both fighters simultaneously. Strike FighterA with FighterB → FighterA's leg dot turns red. Switch to FighterA's controls and verify: movement is visibly slower, sprint input is ignored, dodge input is ignored. Revert the `.tres` and remove the second brain after testing. *(The two-brain setup avoids the unworkable "move PlayerBrain between fighters mid-session" flow — reparenting destroys the state you're trying to observe.)*
4. **Arm cripple**: Same two-brain test harness. Temporarily set a strike's priority to `["arm_r", "torso"]`. Have FighterB strike FighterA → arm dot turns red. Switch to FighterA's controls → stance-switch input is ignored (stuck on MIDDLE), UPPER strikes are rejected. Revert after testing.
5. **Round reset**: After any death, both fighters' limb dots reset to green. Movement speed restored. Stance unlocked.
6. **No state gets stuck**: After a non-lethal hit (torso wound, arm/leg cripple), the fighter returns to FREE and can act again. The hurt stagger animation completes and the fighter recovers.
7. **HUD visible**: Both fighter diagrams show on screen with correct colors throughout a round.

**Test suite**: `godot --headless --script fighter/tests/test_hit_resolver.gd` passes all 13 cases (0 failures).

---

## Spec divergences

### 1. No lower-stance strikes exist yet — leg cripple requires temporary test data

The spec's exit criterion says "hit the dummy's leg → it moves slower." Neither existing strike has legs in its hit_region_priority. Phase 4 does not create new strikes — it wires the limb routing system. Leg cripple is testable by temporarily editing a `.tres` file or by adding a `lower_horizontal.tres` strike. The plan does not prescribe adding a permanent lower strike (that's Phase 5+ when LOWER stance exists), but the implementer should create a temporary test strike or edit an existing one to verify leg routing.

### 2. "Wounded stance" is just MIDDLE-lock, not a visual change

The spec says weapon-arm cripple forces "a wounded stance with a reduced strike set." Phase 4 implements this as locking to MIDDLE stance — the fighter can only use SLASH_tree animations, losing access to HEAVY_tree (UPPER stance). There is no unique "wounded" animation or visual tell beyond the HUD dot. A visual wounded stance (limping, favoring the wound) is future art/animation work.

### 3. Off-arm (left arm) cripple is cosmetic

Per spec: "Off-arm cripple is cosmetic at MVP (future: affects off-hand gadgets/guards)." The HUD shows the dot turning red, but no gameplay effect fires. The code path exists — `_apply_cripple_effects` simply has no case for `arm_l`.

### 4. HitOutcome gains `new_integrity` field (not in spec)

The spec's HitOutcome is `HIT(limb, lethal: bool)`. Phase 4 adds `new_integrity` to the Dictionary so FighterBody.hit() can apply the state change without re-deriving lethality logic. This is an implementation detail, not a contract change — external consumers only read `type`, `limb`, and `lethal`.

### 5. FighterHUD is custom `_draw()`, not a scene-based UI

The spec mentions "limb state dots" without prescribing implementation. Phase 4 uses `Control._draw()` for zero-dependency simplicity. A proper UI with theme support, labels, and layout containers is Phase 6+ polish.
