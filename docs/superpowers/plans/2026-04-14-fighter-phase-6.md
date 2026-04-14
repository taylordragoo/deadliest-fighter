# Fighter Phase 6 — AIBrain + Round Flow

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the ~150-line MVP AIBrain (5-rule opponent) and full round flow (FighterArena spawn/death/reset/round counting + HUD round-state overlay) so that the complete combat loop can be played 10 rounds back-to-back against an AI opponent with clean resets.

**Architecture:** `AIBrain` extends `FighterBrain` and emits the same intents as `PlayerBrain`. It holds a reference to the opponent fighter (set by FighterArena at match start) and subscribes to opponent `strike_started` for reactive parry/dodge, plus its own fighter's `limb_state_changed` for retreat-on-cripple. A simple timer-driven loop (approach → posture → strike → react → retreat) runs in `_physics_process` with timer-gated transitions. `FighterArena` is expanded from its current minimal death-reset stub into a full round manager: PRE_ROUND freeze, COUNTDOWN, FIGHTING phase, death detection, RESULT display, and clean reset. Arena async coroutines use a `_flow_id` guard (mirroring FighterBody's `_round_id`) to prevent stale timer resumes from corrupting later rounds. `FighterHUD` gains a round-state overlay (round number + state text) and per-fighter stance indicators. The demo scene (`fighter_demo.tscn`) is updated to attach `AIBrain` to one fighter.

**Tech Stack:** Godot 4.7 + GDScript. No external test framework. Visual verification is manual F5.

**Source spec:** `docs/superpowers/specs/2026-04-09-bushido-blade-pivot-design.md` (AIBrain section ~line 383, Round flow section ~line 228, Phase 6 bullet ~line 471)

**Commit style:** `type: description` (e.g., `feat:`, `fix:`, `chore:`).

---

## Key design decisions

### 1. AIBrain follows the same FighterBrain contract — no special hooks

AIBrain extends `FighterBrain` exactly like `PlayerBrain` does. It calls `fighter.intent_move()`, `fighter.intent_strike()`, `fighter.intent_parry()`, `fighter.intent_dodge()`, and `fighter.intent_sprint()`. The Fighter does not know or care whether it's controlled by a human or AI. This validates the brain contract end-to-end and confirms that the same seven intents are sufficient for both input sources.

### 2. AIBrain decision-making is timer-gated, not state-machine-driven

The spec describes ~5 rules, ~150 lines. A full state machine would be overbuilt for a placeholder opponent whose only job is to validate the brain contract. Instead, AIBrain uses simple timer-gated branches:

- A `_decision_timer` float counts down each frame. When it hits zero, the AI evaluates what to do next and resets the timer.
- Reactive decisions (parry/dodge in response to `strike_started`) bypass the timer with a random roll.
- Retreat after cripple is a timed impulse that overrides the approach behavior briefly.

This is easy to read, easy to tune, and easy to throw away when a real AI system is built.

### 3. AIBrain gets its opponent reference from FighterArena, not from export

`PlayerBrain` doesn't need an opponent reference (it reads input). AIBrain does — it needs to observe the opponent's position and signals. FighterArena calls `ai_brain.set_opponent(other_fighter)` during `_ready()`. This keeps the demo scene setup clean: the arena is the single orchestrator that knows who fights whom.

### 4. FighterArena gains round phases: WAITING, PRE_ROUND, COUNTDOWN, FIGHTING, RESULT

The current arena is a minimal stub that detects death and resets. Phase 6 expands it into a proper round manager:

```
WAITING    — initial state before first round
PRE_ROUND  — fighters reset and frozen, no input (~1.0s). NOT a spawn pose animation —
             fighters are in state.FREE but frozen. Named PRE_ROUND (not SPAWN) to avoid
             implying a spawn animation that doesn't exist yet.
COUNTDOWN  — "Ready... Fight!" overlay (~1.0s, fighters still frozen)
FIGHTING   — combat active, waiting for death
RESULT     — "Slain!" overlay, delay before reset (~2.0s)
```

FighterArena emits a `round_phase_changed(phase)` signal that FighterHUD subscribes to for the overlay text. FighterArena also calls `fighter.freeze()` / `fighter.unfreeze()` to gate input during PRE_ROUND and COUNTDOWN phases. This uses a simple `frozen` boolean on FighterBody that the intent methods check — the same pattern as `can_be_hurt`.

### 5. Frozen state gates intents AND physics movement

When a round is in PRE_ROUND or COUNTDOWN, the fighters must not act or move. FighterBody gains a `frozen: bool` flag. When `frozen == true`: all `intent_*` methods are no-ops, AND `_physics_process()` early-returns after applying gravity (so the fighter doesn't float, but doesn't move laterally). `freeze()` also clears `input_dir`, `velocity`, and `direction` to prevent stale movement vectors from drifting the fighter. This belt-and-suspenders approach prevents the edge case where a player holds input when freeze begins — intents are gated so `input_dir` won't update, but the physics loop also short-circuits so any stale `input_dir` from the last frame before freeze can't cause drift.

### 6. FighterHUD round overlay uses Label nodes, not _draw()

The limb diagrams use `_draw()` because they're geometric (dots). The round-state overlay is text ("Round 1", "Ready", "Fight!", "Slain!"). A `Label` node centered on screen is the right tool. FighterHUD adds a child `Label` at `_ready()` and updates its text when `round_phase_changed` fires.

### 7. AIBrain signal subscriptions: opponent in set_opponent(), self in _ready()

The opponent reference isn't available at `_ready()` time (the arena sets it after both fighters are ready), so `opponent.strike_started` is connected inside `set_opponent()`. But the AI's own fighter IS available at `_ready()` (FighterBrain auto-resolves it from parent), so `fighter.limb_state_changed` is connected in `_ready()` for the retreat-on-cripple rule. No brain back-reference on FighterBody — coupling flows one direction only (brain → fighter).

### 8. FighterArena uses _flow_id to guard async phase transitions

Both `_start_round()` and `_on_fighter_died()` contain `await` calls. Without a guard, a stale timer resume could corrupt a later round (e.g., two deaths in rapid succession, or a death during PRE_ROUND of the next round). `_flow_id` is incremented at the top of `_start_round()`, and both coroutines capture it at entry and bail after each `await` if it changed. This mirrors FighterBody's `_round_id` pattern.

### 9. Round counter and win tracking are minimal

The spec says "MVP is best-of-1 on an infinite loop." FighterArena tracks `round_number` (increments each round) and `wins_a` / `wins_b` (for HUD display), but there's no victory condition or match-end state. Rounds loop forever.

---

## File map

By the end of this plan, these files exist or are modified:

| File | Status | Responsibility |
|---|---|---|
| `fighter/brains/ai_brain.gd` | **Created** | ~150-line MVP AI opponent. 5-rule decision loop: approach, posture, strike, react (parry/dodge), retreat on own cripple. |
| `fighter/fighter_arena.gd` | **Modified** | Full round manager: phases (WAITING/PRE_ROUND/COUNTDOWN/FIGHTING/RESULT), `_flow_id` async guard, round counting, freeze/unfreeze, win tracking, AIBrain opponent wiring. |
| `fighter/fighter_body.gd` | **Modified** | Add `frozen` flag + `freeze()`/`unfreeze()` methods. All intent methods and `_physics_process` check `frozen`. No brain back-reference. |
| `fighter/fighter_hud.gd` | **Modified** | Add round-state overlay Label + per-fighter stance indicators. Subscribe to arena `round_phase_changed`. Show round number + phase text + score. |
| `fighter/fighter_demo.tscn` | **Modified** | Attach AIBrain to fighter_b. Wire arena's fighter paths + HUD arena_path. |
| `fighter/tests/test_arena_flow.gd` | **Created** | Headless smoke test for arena phase progression and round reset. |
| `project.godot` | **Not modified** | No new input actions needed. |

---

## Task 1: Add frozen flag to FighterBody

**Files:**
- Modify: `fighter/fighter_body.gd`

### Overview

Add a `frozen` boolean that gates all intent methods AND the physics movement loop. FighterArena will call `freeze()` and `unfreeze()` to control when fighters can act during PRE_ROUND/COUNTDOWN phases. `freeze()` clears `input_dir`, `velocity`, and `direction` to prevent stale drift. `_physics_process()` early-returns when frozen (after gravity, so the fighter doesn't float). `reset_for_round()` clears frozen state.

- [ ] **Step 1: Add the frozen flag and methods**

Add after the `is_dead` declaration (around line 89 in `fighter_body.gd`):

```gdscript
var frozen: bool = false
```

Add two methods in the intent surface section (after `intent_sheathe`):

```gdscript
func freeze() -> void:
	frozen = true
	input_dir = Vector2.ZERO
	velocity = Vector3.ZERO
	direction = Vector3.ZERO

func unfreeze() -> void:
	frozen = false
```

- [ ] **Step 2: Add frozen early-return to _physics_process**

Add at the top of `_physics_process()`, before the `match current_state` block (fighter_body.gd:336):

```gdscript
func _physics_process(_delta: float) -> void:
	if frozen:
		apply_gravity(_delta)
		fall_check()
		move_and_slide()
		return

	match current_state:
```

This prevents stale `input_dir` from causing lateral drift during freeze. Gravity still applies so the fighter doesn't hover if frozen mid-air. `fall_check()` is included so that `_tracking_fall` doesn't go stale and landing cleanup still fires if the fighter was airborne when frozen.

- [ ] **Step 3: Gate all intent methods on frozen**

Add `if frozen: return` as the first line of each intent method:

In `intent_move(dir: Vector2)`:
```gdscript
func intent_move(dir: Vector2) -> void:
	if frozen:
		return
	input_dir = dir
```

In `intent_sprint(held: bool)`:
```gdscript
func intent_sprint(held: bool) -> void:
	if frozen:
		return
	if held:
```

In `intent_change_stance(stance: int)`:
```gdscript
func intent_change_stance(stance: int) -> void:
	if frozen:
		return
	if limb_health.has_weapon_arm_cripple():
```

In `intent_strike(stance, dir)`:
```gdscript
func intent_strike(stance: int = -1, dir: int = Strike.StrikeDir.SLASH_HORIZONTAL) -> void:
	if frozen:
		return
	# Accept strike from FREE or SPRINT...
```

In `intent_parry()`:
```gdscript
func intent_parry() -> void:
	if frozen:
		return
	if current_state != state.FREE:
```

In `intent_dodge(_dir: Vector2)`:
```gdscript
func intent_dodge(_dir: Vector2) -> void:
	if frozen:
		return
	if limb_health.has_leg_cripple():
```

- [ ] **Step 4: Clear frozen in reset_for_round()**

Add `frozen = false` inside `reset_for_round()`, after `is_dead = false`:

```gdscript
	is_dead = false
	frozen = false
	can_be_hurt = true
```

- [ ] **Step 5: Commit**

```bash
git add fighter/fighter_body.gd
git commit -m "feat: add frozen flag to FighterBody — gates intents and physics movement"
```

---

## Task 2: Create AIBrain

**Files:**
- Create: `fighter/brains/ai_brain.gd`

### Overview

A ~150-line MVP AI opponent that validates the brain contract. Five rules: approach when far, randomly change stance when in range, strike on a timer with a small telegraph delay, reactively parry/dodge when the opponent strikes, and retreat briefly when crippled.

- [ ] **Step 1: Create the AIBrain script**

Create `fighter/brains/ai_brain.gd`:

```gdscript
# fighter/brains/ai_brain.gd
# AIBrain — MVP placeholder AI (~5 rules, ~150 lines).
# Validates the brain contract end-to-end. Not a real combat AI.
# Replaced by a proper AI subsystem in a future phase.
class_name AIBrain
extends FighterBrain

## The opponent this AI observes. Set by FighterArena via set_opponent().
var opponent: FighterBody

## Distance at which the AI considers itself "in range" for combat.
@export var combat_range: float = 2.5

## Minimum time between AI decisions (seconds). Adds human-like delay.
@export var decision_interval: float = 0.8

## Chance (0-1) to attempt a parry when opponent starts a strike.
@export var parry_chance: float = 0.4

## Chance (0-1) to attempt a dodge when opponent starts a strike (checked if parry fails).
@export var dodge_chance: float = 0.2

## How long the AI retreats after being crippled (seconds).
@export var retreat_duration: float = 1.5

## Delay before striking after deciding to attack (telegraph, seconds).
@export var strike_telegraph: float = 0.3

var _decision_timer: float = 0.0
var _retreating: bool = false
var _retreat_timer: float = 0.0
var _strike_pending: bool = false
var _strike_delay: float = 0.0

func set_opponent(opp: FighterBody) -> void:
	opponent = opp
	if opponent:
		if not opponent.strike_started.is_connected(_on_opponent_strike_started):
			opponent.strike_started.connect(_on_opponent_strike_started)

func _on_opponent_strike_started(_strike: Strike) -> void:
	if fighter == null or fighter.frozen:
		return
	if fighter.current_state != FighterBody.state.FREE:
		return
	var roll := randf()
	if roll < parry_chance:
		fighter.intent_parry()
	elif roll < parry_chance + dodge_chance:
		var away := _get_away_direction()
		fighter.intent_dodge(away)

func _physics_process(delta: float) -> void:
	if fighter == null or opponent == null:
		return
	if fighter.frozen:
		return
	if fighter.is_dead or opponent.is_dead:
		fighter.intent_move(Vector2.ZERO)
		return

	var to_opp := opponent.global_position - fighter.global_position
	to_opp.y = 0.0
	var dist := to_opp.length()

	# Handle pending strike telegraph
	if _strike_pending:
		_strike_delay -= delta
		if _strike_delay <= 0.0:
			_strike_pending = false
			_do_strike()
		fighter.intent_move(Vector2.ZERO)
		return

	# Handle retreat after being crippled
	if _retreating:
		_retreat_timer -= delta
		var away := _get_away_direction()
		fighter.intent_move(away)
		if _retreat_timer <= 0.0:
			_retreating = false
		return

	# Decision timer
	_decision_timer -= delta
	if _decision_timer > 0.0:
		# Keep approaching or holding position between decisions
		if dist > combat_range:
			fighter.intent_move(_get_approach_direction())
		else:
			fighter.intent_move(Vector2.ZERO)
		return

	# --- Decision point ---
	_decision_timer = decision_interval + randf() * 0.4

	if dist > combat_range:
		# Rule 1: Approach
		fighter.intent_move(_get_approach_direction())
	else:
		# In combat range
		var roll := randf()
		if roll < 0.3:
			# Rule 2: Change stance randomly
			_change_stance_random()
			fighter.intent_move(Vector2.ZERO)
		else:
			# Rule 3: Queue a strike with telegraph delay
			_strike_pending = true
			_strike_delay = strike_telegraph
			fighter.intent_move(Vector2.ZERO)

func _do_strike() -> void:
	if fighter.current_state != FighterBody.state.FREE:
		return
	var current_stance: int = FighterBody.STANCE_TO_WEAPON.find_key(fighter.weapon_type)
	if current_stance == null:
		current_stance = FighterBody.Stance.MIDDLE
	fighter.intent_strike(current_stance, Strike.StrikeDir.SLASH_HORIZONTAL)

func _change_stance_random() -> void:
	var stances := [FighterBody.Stance.MIDDLE, FighterBody.Stance.UPPER]
	var pick: int = stances[randi() % stances.size()]
	fighter.intent_change_stance(pick)

func _get_approach_direction() -> Vector2:
	if opponent == null or fighter == null:
		return Vector2.ZERO
	# Move toward opponent. In strafing mode, -Y = forward (toward opponent).
	return Vector2(0, -1)

func _get_away_direction() -> Vector2:
	# In strafing mode, +Y = backward (away from opponent).
	return Vector2(0, 1)

func reset() -> void:
	_decision_timer = 0.5
	_retreating = false
	_retreat_timer = 0.0
	_strike_pending = false
	_strike_delay = 0.0
```

- [ ] **Step 2: Commit**

```bash
git add fighter/brains/ai_brain.gd
git commit -m "feat: create AIBrain — 5-rule MVP opponent validating the brain contract"
```

---

## Task 3: AIBrain subscribes to own fighter's limb_state_changed for retreat

**Files:**
- Modify: `fighter/brains/ai_brain.gd`

### Overview

AIBrain needs to retreat when its own fighter's limb is crippled. Rather than adding a brain back-reference to FighterBody (which would duplicate the ownership that already flows from `FighterBrain.fighter`), AIBrain subscribes to `fighter.limb_state_changed` in its own `_ready()`. FighterBody is not modified — the coupling stays one-directional (brain → fighter). FighterBrain base class is not modified either (PlayerBrain doesn't need this).

- [ ] **Step 1: Add limb_state_changed subscription to AIBrain._ready()**

Add a `_ready()` override in `ai_brain.gd` after the variable declarations:

```gdscript
func _ready() -> void:
	super._ready()
	if fighter:
		fighter.limb_state_changed.connect(_on_own_limb_changed)

func _on_own_limb_changed(limb: String, new_state: int) -> void:
	if new_state == LimbHealth.Integrity.CRIPPLED:
		_retreating = true
		_retreat_timer = retreat_duration
```

- [ ] **Step 2: Commit**

```bash
git add fighter/brains/ai_brain.gd
git commit -m "feat: AIBrain subscribes to own fighter limb_state_changed for retreat"
```

---

## Task 4: Expand FighterArena with round phases

**Files:**
- Modify: `fighter/fighter_arena.gd`

### Overview

Replace the current minimal death-reset stub with a full round manager that handles PRE_ROUND → COUNTDOWN → FIGHTING → RESULT phases, round counting, win tracking, and AIBrain opponent wiring.

- [ ] **Step 1: Rewrite fighter_arena.gd**

Replace the entire contents of `fighter/fighter_arena.gd`:

```gdscript
# fighter/fighter_arena.gd
# FighterArena — round manager for the MVP combat loop.
# Phases: WAITING → PRE_ROUND → COUNTDOWN → FIGHTING → RESULT → (loop)
# Owns spawn positions, round counting, freeze/unfreeze, win tracking.
# Wires AIBrain opponent references at match start.
extends Node3D
class_name FighterArena

enum Phase { WAITING, PRE_ROUND, COUNTDOWN, FIGHTING, RESULT }

@export var fighter_a_path: NodePath
@export var fighter_b_path: NodePath
var fighter_a: FighterBody
var fighter_b: FighterBody

@export var pre_round_duration: float = 1.0
@export var countdown_duration: float = 1.0
@export var result_duration: float = 2.0

var round_number: int = 0
var wins_a: int = 0
var wins_b: int = 0
var current_phase: int = Phase.WAITING

## Incremented at the start of each round flow. Async coroutines
## (_start_round, _on_fighter_died) capture this at entry and bail
## after each await if it changed — same pattern as FighterBody._round_id.
var _flow_id: int = 0

signal round_phase_changed(phase: int, round_number: int)
signal round_result(winner: FighterBody, loser: FighterBody)

var _spawn_a: Transform3D
var _spawn_b: Transform3D

func _ready() -> void:
	if fighter_a == null and not fighter_a_path.is_empty():
		fighter_a = get_node_or_null(fighter_a_path) as FighterBody
	if fighter_b == null and not fighter_b_path.is_empty():
		fighter_b = get_node_or_null(fighter_b_path) as FighterBody

	if fighter_a:
		_spawn_a = fighter_a.global_transform
		fighter_a.death_started.connect(_on_fighter_died.bind(fighter_a))
	if fighter_b:
		_spawn_b = fighter_b.global_transform
		fighter_b.death_started.connect(_on_fighter_died.bind(fighter_b))

	_wire_ai_brains()

	# Start first round after a brief delay so the scene is fully loaded.
	await get_tree().create_timer(0.1).timeout
	_start_round()

func _wire_ai_brains() -> void:
	if fighter_a and fighter_b:
		var brain_a := _find_brain(fighter_a)
		var brain_b := _find_brain(fighter_b)
		if brain_a is AIBrain:
			brain_a.set_opponent(fighter_b)
		if brain_b is AIBrain:
			brain_b.set_opponent(fighter_a)

func _find_brain(fighter: FighterBody) -> FighterBrain:
	for child in fighter.get_children():
		if child is FighterBrain:
			return child
	return null

func _start_round() -> void:
	_flow_id += 1
	var flow_at_start := _flow_id
	round_number += 1

	# Reset fighters to spawn positions
	if fighter_a:
		fighter_a.reset_for_round(_spawn_a)
		fighter_a.freeze()
	if fighter_b:
		fighter_b.reset_for_round(_spawn_b)
		fighter_b.freeze()

	# Reset AI state
	var brain_a := _find_brain(fighter_a) if fighter_a else null
	var brain_b := _find_brain(fighter_b) if fighter_b else null
	if brain_a is AIBrain:
		brain_a.reset()
	if brain_b is AIBrain:
		brain_b.reset()

	# --- PRE_ROUND phase (fighters frozen, no input) ---
	current_phase = Phase.PRE_ROUND
	round_phase_changed.emit(current_phase, round_number)

	await get_tree().create_timer(pre_round_duration).timeout
	if _flow_id != flow_at_start:
		return

	# --- COUNTDOWN phase ---
	current_phase = Phase.COUNTDOWN
	round_phase_changed.emit(current_phase, round_number)

	await get_tree().create_timer(countdown_duration).timeout
	if _flow_id != flow_at_start:
		return

	# --- FIGHTING phase ---
	current_phase = Phase.FIGHTING
	round_phase_changed.emit(current_phase, round_number)

	if fighter_a:
		fighter_a.unfreeze()
	if fighter_b:
		fighter_b.unfreeze()

func _on_fighter_died(dead_fighter: FighterBody) -> void:
	if current_phase != Phase.FIGHTING:
		return

	var flow_at_start := _flow_id

	# Determine winner
	var winner: FighterBody = null
	var loser: FighterBody = dead_fighter
	if dead_fighter == fighter_a:
		winner = fighter_b
		wins_b += 1
	elif dead_fighter == fighter_b:
		winner = fighter_a
		wins_a += 1

	# Freeze the surviving fighter
	if winner:
		winner.freeze()

	# --- RESULT phase ---
	current_phase = Phase.RESULT
	round_phase_changed.emit(current_phase, round_number)
	if winner:
		round_result.emit(winner, loser)

	await get_tree().create_timer(result_duration).timeout
	if _flow_id != flow_at_start:
		return

	# Loop: start next round
	_start_round()
```

- [ ] **Step 2: Commit**

```bash
git add fighter/fighter_arena.gd
git commit -m "feat: expand FighterArena with round phases, counting, freeze/unfreeze, AI wiring"
```

---

## Task 5: Add round-state overlay and stance indicators to FighterHUD

**Files:**
- Modify: `fighter/fighter_hud.gd`

### Overview

Add a centered `Label` for round phase text ("Round 1", "Ready...", "Fight!", "Slain!"), a score label, and per-fighter stance indicators. The stance indicator shows the fighter's current stance ("MID" / "UP") next to their limb diagram — this is required by the spec ("player's stance indicator, 6 limb-state dots"). Subscribe to FighterArena's `round_phase_changed` signal. Stance labels update every frame by reading `fighter.weapon_type`.

- [ ] **Step 1: Rewrite fighter_hud.gd**

Replace the entire contents of `fighter/fighter_hud.gd`:

```gdscript
# fighter/fighter_hud.gd
extends Control
class_name FighterHUD

@export var fighter_a_path: NodePath
@export var fighter_b_path: NodePath
@export var arena_path: NodePath

var fighter_a: FighterBody
var fighter_b: FighterBody
var arena: FighterArena

const DOT_RADIUS: float = 8.0

const LIMB_OFFSETS: Dictionary = {
	"head":  Vector2(0, -40),
	"torso": Vector2(0, 0),
	"arm_r": Vector2(30, -10),
	"arm_l": Vector2(-30, -10),
	"leg_r": Vector2(12, 40),
	"leg_l": Vector2(-12, 40),
}

const COLOR_OK := Color(0.2, 0.8, 0.2)
const COLOR_WOUNDED := Color(0.9, 0.8, 0.1)
const COLOR_CRIPPLED := Color(0.9, 0.15, 0.15)

const WEAPON_TO_STANCE_LABEL: Dictionary = {
	"SLASH": "MID",
	"HEAVY": "UP",
}

var _phase_label: Label
var _score_label: Label
var _stance_label_a: Label
var _stance_label_b: Label
var _phase_timer: float = 0.0
var _showing_fight_text: bool = false

func _ready() -> void:
	if not fighter_a_path.is_empty():
		fighter_a = get_node_or_null(fighter_a_path) as FighterBody
	if not fighter_b_path.is_empty():
		fighter_b = get_node_or_null(fighter_b_path) as FighterBody
	if not arena_path.is_empty():
		arena = get_node_or_null(arena_path) as FighterArena

	if fighter_a:
		fighter_a.limb_state_changed.connect(_on_limb_changed)
		fighter_a.death_started.connect(func(): queue_redraw())
	if fighter_b:
		fighter_b.limb_state_changed.connect(_on_limb_changed)
		fighter_b.death_started.connect(func(): queue_redraw())

	if arena:
		arena.round_phase_changed.connect(_on_round_phase_changed)

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Phase overlay label (centered, large)
	_phase_label = Label.new()
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_phase_label.set_anchors_preset(Control.PRESET_CENTER)
	_phase_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_phase_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_phase_label.custom_minimum_size = Vector2(400, 100)
	_phase_label.position = Vector2(-200, -50)
	_phase_label.add_theme_font_size_override("font_size", 48)
	_phase_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_phase_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_phase_label.add_theme_constant_override("shadow_offset_x", 2)
	_phase_label.add_theme_constant_override("shadow_offset_y", 2)
	_phase_label.text = ""
	add_child(_phase_label)

	# Score label (top center)
	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_score_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_score_label.custom_minimum_size = Vector2(300, 30)
	_score_label.position = Vector2(-150, 10)
	_score_label.add_theme_font_size_override("font_size", 24)
	_score_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_score_label.add_theme_constant_override("shadow_offset_x", 1)
	_score_label.add_theme_constant_override("shadow_offset_y", 1)
	_score_label.text = ""
	add_child(_score_label)

	# Stance indicator labels (below each limb diagram)
	_stance_label_a = _create_stance_label()
	add_child(_stance_label_a)
	_stance_label_b = _create_stance_label()
	add_child(_stance_label_b)

func _create_stance_label() -> Label:
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(60, 24)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	return lbl

func _process(delta: float) -> void:
	if _showing_fight_text:
		_phase_timer -= delta
		if _phase_timer <= 0.0:
			_showing_fight_text = false
			_phase_label.text = ""

	# Update stance labels every frame (simple, no signal needed)
	if fighter_a:
		_stance_label_a.text = WEAPON_TO_STANCE_LABEL.get(fighter_a.weapon_type, "?")
		_stance_label_a.position = Vector2(120 - 30, 135)
	if fighter_b:
		var vp_w := get_viewport_rect().size.x
		_stance_label_b.text = WEAPON_TO_STANCE_LABEL.get(fighter_b.weapon_type, "?")
		_stance_label_b.position = Vector2(vp_w - 120 - 30, 135)

func _on_round_phase_changed(phase: int, round_num: int) -> void:
	_showing_fight_text = false
	match phase:
		FighterArena.Phase.PRE_ROUND:
			_phase_label.text = "Round %d" % round_num
			_update_score()
		FighterArena.Phase.COUNTDOWN:
			_phase_label.text = "Ready..."
		FighterArena.Phase.FIGHTING:
			_phase_label.text = "Fight!"
			_showing_fight_text = true
			_phase_timer = 1.0
		FighterArena.Phase.RESULT:
			_phase_label.text = "Slain!"
	queue_redraw()

func _update_score() -> void:
	if arena:
		_score_label.text = "P1  %d - %d  P2" % [arena.wins_a, arena.wins_b]

func _on_limb_changed(_limb: String, _new_state: int) -> void:
	queue_redraw()

func _draw() -> void:
	var vp_size := get_viewport_rect().size
	if fighter_a:
		_draw_fighter_diagram(Vector2(120, 80), fighter_a.limb_health)
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
		draw_arc(center + offset, DOT_RADIUS, 0, TAU, 24, Color(0, 0, 0, 0.5), 1.5)
```

- [ ] **Step 2: Commit**

```bash
git add fighter/fighter_hud.gd
git commit -m "feat: add round-state overlay, score, and stance indicators to FighterHUD"
```

---

## Task 6: Update fighter_demo.tscn — attach AIBrain and wire arena

**Files:**
- Modify: `fighter/fighter_demo.tscn` (scene file, edited in Godot or via MCP)

### Overview

The demo scene needs three changes:
1. Add an AIBrain child to fighter_b (the opponent).
2. Add an `arena_path` export on the FighterHUD pointing to the FighterArena.
3. Verify fighter_a has a PlayerBrain child and both fighters have brain exports set.

This task requires editing the `.tscn` file. The `.tscn` is large (embedded meshes) so edits should be done via the Godot editor or MCP scene tools.

- [ ] **Step 1: Add AIBrain node to fighter_b**

In the Godot editor (or via MCP `add_node`):
- Select the fighter_b node (the second FighterBody in the scene).
- Add a child node of type `Node`, set its script to `res://fighter/brains/ai_brain.gd`.
- Name it `AIBrain`.
- The `fighter` export on AIBrain can be left unset — FighterBrain's `_ready()` auto-resolves to the parent.

- [ ] **Step 2: Wire FighterHUD arena_path**

In the Godot editor:
- Select the FighterHUD node.
- Set the `arena_path` export to point to the FighterArena node in the scene.

- [ ] **Step 3: Verify scene structure**

The scene tree should look like:

```
FighterDemo (Node3D)
├── FighterArena
│   ├── (floor StaticBody3D, etc.)
├── FighterA (FighterBody)
│   ├── PlayerBrain
│   ├── (mesh, skeleton, animation tree, weapon system...)
├── FighterB (FighterBody)
│   ├── AIBrain          ← NEW
│   ├── (mesh, skeleton, animation tree, weapon system...)
├── FighterCam
├── FighterHUD
│   ├── (arena_path → FighterArena)  ← WIRED
```

- [ ] **Step 4: Commit**

```bash
git add fighter/fighter_demo.tscn
git commit -m "feat: attach AIBrain to fighter_b and wire arena path on HUD"
```

---

## Task 7: Headless smoke test for arena phase flow

**Files:**
- Create: `fighter/tests/test_arena_flow.gd`

### Overview

A minimal headless test that verifies FighterArena phase progression and round reset without needing the full scene. Creates a SceneTree with two stub FighterBodies and a FighterArena, triggers a death, and checks that phases advance correctly and state resets. Same hand-rolled assert pattern as `test_hit_resolver.gd`.

This test cannot verify animation or physics, but it exercises the async round flow, `_flow_id` guards, freeze/unfreeze, and reset sequencing — the new failure modes that manual F5 testing alone doesn't cover reliably.

- [ ] **Step 1: Create test_arena_flow.gd**

Create `fighter/tests/test_arena_flow.gd`:

```gdscript
# fighter/tests/test_arena_flow.gd
# Headless smoke test for FighterArena phase progression.
# Runs via: godot --headless --script fighter/tests/test_arena_flow.gd
#
# Creates a minimal scene: FighterArena + 2 FighterBodies (no mesh/anim).
# Verifies: phase transitions, freeze/unfreeze, round reset, _flow_id guards.
# Cannot verify animation or physics — those require manual F5.
extends SceneTree

var pass_count := 0
var fail_count := 0
var results: Array[String] = []

func _assert(condition: bool, label: String) -> void:
	if condition:
		pass_count += 1
		results.append("PASS: %s" % label)
	else:
		fail_count += 1
		results.append("FAIL: %s" % label)

func _init() -> void:
	# Build minimal scene
	var root := Node3D.new()

	var fighter_a := FighterBody.new()
	fighter_a.name = "FighterA"
	root.add_child(fighter_a)

	var fighter_b := FighterBody.new()
	fighter_b.name = "FighterB"
	root.add_child(fighter_b)

	var arena := FighterArena.new()
	arena.name = "Arena"
	arena.fighter_a = fighter_a
	arena.fighter_b = fighter_b
	root.add_child(arena)

	# Add to tree so timers and signals work
	get_root().add_child(root)

	# Give arena's _ready() a moment to run (it awaits 0.1s then starts round)
	await _wait(0.3)

	# ================================================================
	# Test 1: Arena should be in PRE_ROUND after startup
	# ================================================================
	_assert(arena.current_phase == FighterArena.Phase.PRE_ROUND, "arena starts in PRE_ROUND")
	_assert(arena.round_number == 1, "round_number == 1")
	_assert(fighter_a.frozen, "fighter_a frozen during PRE_ROUND")
	_assert(fighter_b.frozen, "fighter_b frozen during PRE_ROUND")

	# ================================================================
	# Test 2: Wait for FIGHTING phase
	# ================================================================
	await _wait(arena.pre_round_duration + arena.countdown_duration + 0.2)

	_assert(arena.current_phase == FighterArena.Phase.FIGHTING, "arena reaches FIGHTING")
	_assert(not fighter_a.frozen, "fighter_a unfrozen during FIGHTING")
	_assert(not fighter_b.frozen, "fighter_b unfrozen during FIGHTING")

	# ================================================================
	# Test 3: Trigger death → RESULT phase
	# ================================================================
	fighter_b.death()
	await _wait(0.1)

	_assert(arena.current_phase == FighterArena.Phase.RESULT, "death triggers RESULT phase")
	_assert(arena.wins_a == 1, "wins_a incremented")
	_assert(fighter_a.frozen, "winner frozen during RESULT")

	# ================================================================
	# Test 4: Wait for round reset → PRE_ROUND of round 2
	# ================================================================
	await _wait(arena.result_duration + 0.3)

	_assert(arena.current_phase == FighterArena.Phase.PRE_ROUND, "new round starts PRE_ROUND")
	_assert(arena.round_number == 2, "round_number == 2")
	_assert(not fighter_b.is_dead, "fighter_b reset (not dead)")
	_assert(fighter_a.frozen, "fighter_a frozen in new PRE_ROUND")
	_assert(fighter_b.frozen, "fighter_b frozen in new PRE_ROUND")

	# ================================================================
	# Print results
	# ================================================================
	for line in results:
		print(line)

	print("\n--- Arena Flow Tests: %d passed, %d failed ---" % [pass_count, fail_count])
	if fail_count > 0:
		quit(1)
	else:
		quit(0)

func _wait(seconds: float) -> void:
	await get_root().get_tree().create_timer(seconds).timeout
```

- [ ] **Step 2: Run the test**

Run: `godot --headless --script fighter/tests/test_arena_flow.gd`

Expected: All tests pass. If FighterBody requires scene-tree nodes (AnimationTree, weapon hitbox) that don't exist in this minimal setup, the test may need null guards. The existing FighterBody code already null-checks `anim_state_tree` and `weapon_hitbox`, so this should work. If `reset_for_round()` fails because `global_transform` requires a spatial parent, the test's `Node3D` root should satisfy that.

- [ ] **Step 3: Commit**

```bash
git add fighter/tests/test_arena_flow.gd
git commit -m "test: headless smoke test for arena phase progression and round reset"
```

---

## Task 8: Integration test — play 10 rounds

**Files:**
- No file changes. Manual F5 verification.

### Overview

This is the spec's MVP "done" criterion: "Play 10 rounds in a row against the AI without any of the following: camera flips sides unexpectedly, fighter gets stuck in a state, parry does the wrong thing, a strike fails to register, a round doesn't reset, controls don't respond."

- [ ] **Step 1: Run the game and play 10 rounds**

Press F5 in Godot. The `fighter_demo.tscn` should load. Verify each of the following:

1. **Round start**: Both fighters spawn in position. HUD shows "Round 1". After ~1s, "Ready..." appears. After ~1s more, "Fight!" appears and both fighters can move.
2. **AI approaches**: The AI walks toward the player when out of range.
3. **AI strikes**: The AI telegraphs and swings. The player can parry (F) or dodge (Space).
4. **Player strikes**: LMB lands a hit. AI reacts (sometimes parries, sometimes dodges, sometimes eats it).
5. **Cripple effects**: Hitting the AI's leg slows it. Hitting its arm locks it to MIDDLE stance.
6. **Death and round reset**: A lethal hit → "Slain!" → ~2s delay → next round starts clean. HUD limb dots reset to green. Score updates.
7. **Camera**: Midpoint-orbit camera tracks both fighters throughout. No side flips.
8. **10 rounds**: Complete 10 full rounds. No state gets stuck. No errors in the output console.

- [ ] **Step 2: Fix any bugs found**

If any issues are found during the 10-round test, fix them and re-test. Common issues to watch for:

- AI not approaching (check `combat_range` vs actual fighter distance)
- AI not striking (check `_decision_timer` reset, `fighter.current_state` guard)
- Round not resetting (check `death_started` signal connection, `_on_fighter_died` phase guard)
- Fighter stuck after round reset (check `frozen` is cleared, `current_state` set to FREE)
- HUD not updating (check `arena_path` is wired, `round_phase_changed` signal connected)

- [ ] **Step 3: Commit any bug fixes**

```bash
git add -A
git commit -m "fix: integration fixes from 10-round playtest"
```

---

## Exit criteria

> **From the spec (Phase 6 exit):** Play 10 rounds back-to-back against the AI. Rounds reset cleanly; no state gets stuck; combat loop is complete. **This is MVP done.**

Manual verification checklist (F5 → play):

1. **Round flow**: PRE_ROUND → "Round N" → "Ready..." → "Fight!" → combat → death → "Slain!" → next round. All transitions visible.
2. **AI behavior**: AI approaches when far, changes stance occasionally, strikes with telegraph, sometimes parries or dodges player strikes, retreats briefly when crippled.
3. **Player controls**: WASD move, Shift sprint, LMB strike, F parry, Space dodge, Q stance — all responsive during FIGHTING phase. All ignored during PRE_ROUND/COUNTDOWN.
4. **Frozen prevents drift**: Hold movement input, then a round ends. During PRE_ROUND/COUNTDOWN, the fighter must not slide or drift despite stale input.
5. **Parry works both ways**: Player can parry AI strikes. AI can parry player strikes. Parried attacker enters extended recovery.
6. **Dodge works both ways**: Player can dodge AI strikes. AI can dodge player strikes. Dodger keeps positional advantage.
7. **Limb effects**: Leg cripple → slower. Arm cripple → locked stance. Head hit → lethal. Torso OK → wound, torso wounded → lethal.
8. **HUD**: Limb dots update correctly. Stance indicators show "MID"/"UP" per fighter. Round number increments. Score shows P1 vs P2 wins. Phase text displays correctly.
9. **Camera**: No unexpected side flips. Follows midpoint throughout.
10. **Round reset**: All state clears. Limb dots green. Stance labels reset. Fighters at spawn positions. No leftover velocity or animation artifacts.
11. **10 rounds**: Complete 10 full rounds without crashes, stuck states, or console errors.

**Headless test suites** (both must pass):
- `godot --headless --script fighter/tests/test_hit_resolver.gd` — all 17 cases (no Phase 6 changes to HitResolver).
- `godot --headless --script fighter/tests/test_arena_flow.gd` — all arena phase/reset cases (new in Phase 6).

---

## Spec divergences

### 1. Frozen flag + _physics_process guard instead of SPAWN state for input gating

The spec's state machine has a SPAWN state where "no input accepted." The implementation uses a `frozen` boolean on FighterBody that gates both intent methods AND `_physics_process()` movement. `freeze()` clears `input_dir`, `velocity`, and `direction`; `_physics_process()` early-returns (after gravity) when frozen. This belt-and-suspenders approach prevents stale-input drift. Fighters are in `state.FREE` but `frozen = true` during PRE_ROUND/COUNTDOWN.

### 2. PRE_ROUND phase instead of SPAWN

The spec describes a "spawn pose" at round start. No spawn pose animation exists, so the arena phase is named `PRE_ROUND` (not `SPAWN`) to avoid implying an animation that doesn't ship. If a spawn pose is added later, the phase can be renamed.

### 3. AIBrain retreat is signal-subscription, no brain back-reference on FighterBody

The spec says "when any of its own limbs get crippled, back away briefly before re-engaging." AIBrain subscribes to `fighter.limb_state_changed` in its own `_ready()` to trigger retreat. FighterBody has no knowledge of its brain — coupling flows one direction only (brain → fighter). This avoids a back-reference that would duplicate the ownership already expressed by `FighterBrain.fighter`.

### 4. No READY conceptual state in FighterArena

The spec mentions "fighters → STRAFING/READY" at round start. The implementation uses `current_state = state.FREE` (which is the READY equivalent) after unfreeze. There is no separate READY state — FREE is the idle state that accepts all intents.

### 5. Best-of-1 on infinite loop, as spec prescribes

The round manager loops forever with no victory condition. `wins_a` and `wins_b` are tracked for the HUD but never trigger a match-end state. This matches the spec: "MVP is best-of-1 on an infinite loop."

### 6. No state_changed signal alias

The spec defines `signal state_changed(new_state, old_state)` on the Fighter. The current code only has `signal changed_state` (no old_state parameter). Phase 6 does not add or alias this signal because no Phase 6 code subscribes to it. AIBrain reads `fighter.current_state` directly rather than subscribing to state transitions. If a future phase needs the spec's two-argument signal, it can be added then.
