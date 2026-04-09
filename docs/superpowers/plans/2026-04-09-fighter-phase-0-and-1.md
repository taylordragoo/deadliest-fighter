# Fighter Phase 0 + Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `fighter/` module scaffolding and ship a playable prototype where a single human-controlled Fighter can move around a static dummy opponent on a flat dojo floor, auto-face the opponent while locked on, and sprint to break lock and retreat in free movement — with the midpoint-orbit camera correctly framing both fighters the whole time.

**Architecture:** New parallel top-level `fighter/` directory (the souls `player/` / `enemy/` / `cameras/` directories are untouched). One `Fighter` class (CharacterBody3D) with a state enum and seven intent methods. An abstract `FighterBrain` base plus a concrete `PlayerBrain` that reads prefixed `p0_*` input actions and calls intent methods. A `FighterCam` (Camera3D subclass, **not** a SpringArm3D) that computes its position per frame from the midpoint of two tracked fighters and sits side-on to the line between them. A `fighter_demo.tscn` with a flat floor, two Fighter instances, and the FighterCam.

**Tech Stack:** Godot 4.7 + GDScript. No external test framework — pure-math tests run via `godot --headless --script <path>`. All other verification is manual F5 with explicit pass/fail criteria.

**Source spec:** `docs/superpowers/specs/2026-04-09-bushido-blade-pivot-design.md` (design approved).

**Scope of this plan:** Phase 0 (Scaffolding) + Phase 1 (Fighter body + brain contract, no combat). Phases 2–7 will each be written as their own plan after the previous has been executed, because each has risk that benefits from hands-on knowledge we don't yet have.

**Testing convention in this plan:**
- **Pure math (FighterCam orbit)** → GDScript unit tests in `fighter/tests/`, runnable headless.
- **Scene / physics / input** → manual F5 verification with an explicit checklist of observed behavior.
- **State transitions (Fighter intent → state)** → GDScript runtime test where the test instantiates a Fighter in a scene tree and pokes it. Runs via `godot --headless`.

This pragmatic split is a departure from dogmatic TDD; it's calibrated for the realities of Godot integration code where the "test" of a scene file is "does it load and do the right thing when you press F5." Tests exist where they're cheap and high-value.

**Commit style:** Follow the existing repo's `type: description` convention (e.g., `feat:`, `chore:`, `docs:`). Each task ends with a commit.

---

## File map (what gets created)

By the end of this plan, these files exist (all new; zero existing files modified except `project.godot`):

| File | Responsibility |
|---|---|
| `fighter/fighter.gd` | `Fighter` class — state enum, intent methods, movement, rotation, signals |
| `fighter/fighter.tscn` | Minimal Fighter scene: CharacterBody3D + capsule collision + capsule mesh. No skeleton/anim-tree yet (Phase 2). |
| `fighter/fighter_brain.gd` | Abstract `FighterBrain` base — holds a reference to its fighter, subclasses override `_physics_process` to emit intents |
| `fighter/brains/player_brain.gd` | `PlayerBrain` — reads `p<idx>_*` input actions, calls fighter intents |
| `fighter/fighter_cam.gd` | `FighterCam` — Camera3D subclass with midpoint-orbit math; pure-math helpers as static funcs for testability |
| `fighter/fighter_demo.tscn` | Playable demo scene — floor, two Fighter instances, FighterCam |
| `fighter/tests/test_runner.gd` | Minimal SceneTree-based test harness: assert helpers, pass/fail counting, exit code |
| `fighter/tests/test_fighter_cam.gd` | Pure-math tests for FighterCam (midpoint, target radius, orbit position) |
| `fighter/tests/test_fighter_states.gd` | Runtime tests for Fighter state transitions (intent_sprint flips state, etc.) |
| `project.godot` | **Modified** — add `p0_move_up/down/left/right` and `p0_sprint` input actions; temporarily point `run/main_scene` at `fighter/fighter_demo.tscn` |

---

## Task 1: Scaffold directories and test runner

**Files:**
- Create: `fighter/` (directory)
- Create: `fighter/brains/` (directory)
- Create: `fighter/tests/` (directory)
- Create: `fighter/tests/test_runner.gd`

**Exit criterion:** Directories exist; `godot --headless --script fighter/tests/test_runner.gd` runs without error and prints the runner header.

- [ ] **Step 1: Create the directories**

```bash
mkdir -p fighter/brains fighter/tests
```

- [ ] **Step 2: Create `fighter/tests/test_runner.gd`**

This is a reusable base that later test files will `extends` from. It provides assertion helpers and a pass/fail counter, and exits with a non-zero code if any assertion fails.

```gdscript
# fighter/tests/test_runner.gd
# Minimal SceneTree-based test harness for the fighter module.
# Subclasses override _run_all_tests() and call the assert_* helpers.
# Run headless:  godot --headless --script fighter/tests/test_runner.gd
extends SceneTree

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("=== %s ===" % get_script().resource_path.get_file())
	_run_all_tests()
	print("\nResults: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)

# Override in subclasses.
func _run_all_tests() -> void:
	print("(base test_runner has no tests; override _run_all_tests in a subclass)")

func assert_true(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
		print("  PASS  " + label)
	else:
		_fail_count += 1
		printerr("  FAIL  " + label)

func assert_near(actual: float, expected: float, eps: float, label: String) -> void:
	if abs(actual - expected) <= eps:
		_pass_count += 1
		print("  PASS  %s  (got %f, expected %f ± %f)" % [label, actual, expected, eps])
	else:
		_fail_count += 1
		printerr("  FAIL  %s  (got %f, expected %f ± %f)" % [label, actual, expected, eps])

func assert_vec3_near(actual: Vector3, expected: Vector3, eps: float, label: String) -> void:
	if actual.distance_to(expected) <= eps:
		_pass_count += 1
		print("  PASS  %s  (got %s, expected %s ± %f)" % [label, actual, expected, eps])
	else:
		_fail_count += 1
		printerr("  FAIL  %s  (got %s, expected %s ± %f)" % [label, actual, expected, eps])

func assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_pass_count += 1
		print("  PASS  %s  (got %s)" % [label, actual])
	else:
		_fail_count += 1
		printerr("  FAIL  %s  (got %s, expected %s)" % [label, actual, expected])
```

- [ ] **Step 3: Verify the test runner loads and runs without error**

```bash
godot --headless --script fighter/tests/test_runner.gd
```

Expected output:
```
=== test_runner.gd ===
(base test_runner has no tests; override _run_all_tests in a subclass)

Results: 0 passed, 0 failed
```

Exit code 0. If Godot prints parse errors, fix them before continuing.

- [ ] **Step 4: Commit**

```bash
git add fighter/tests/test_runner.gd
git commit -m "chore: scaffold fighter module directories and test runner base"
```

---

## Task 2: Add `p0_*` input actions for Phase 1

Phase 1 uses only move and sprint. Later plans (Phase 3+) will add strike, parry, dodge, and stance-select. Adding only what this plan exercises keeps the input map free of dead actions.

**Files:**
- Modify: `project.godot` (the `[input]` section)

**Exit criterion:** The Godot editor's Project Settings → Input Map shows the new `p0_*` actions with the correct keyboard bindings. F5 loads the project without warnings about missing actions.

- [ ] **Step 1: Open the project in Godot editor**

```bash
# From the repo root:
open -a Godot /Users/tdragoo/Documents/01_gamedev/deadliest-fighter/project.godot
```

(Or open Godot and load the project manually.)

- [ ] **Step 2: Add the actions via Project Settings → Input Map**

Project → Project Settings → Input Map tab. Enable "Show Built-in Actions" is not required. Add the following five actions and bindings:

| Action name | Keyboard key | Gamepad binding |
|---|---|---|
| `p0_move_up` | W | Left stick Y- (axis 1, value -1) |
| `p0_move_down` | S | Left stick Y+ (axis 1, value +1) |
| `p0_move_left` | A | Left stick X- (axis 0, value -1) |
| `p0_move_right` | D | Left stick X+ (axis 0, value +1) |
| `p0_sprint` | Shift | B / Circle (button index 1) |

For each action: type the action name into the "Add New Action" field, click Add, then click the `+` on that row and choose "Key" (press W/S/A/D/Shift when prompted) and "Joypad Axis" / "Joypad Button" for the gamepad binding.

- [ ] **Step 3: Save the project**

Project → Save All, or just close the editor (Godot writes on close).

- [ ] **Step 4: Verify the actions were written to `project.godot`**

Use Grep to confirm each action now exists in the file:

```
Grep: pattern="p0_move_up|p0_move_down|p0_move_left|p0_move_right|p0_sprint" path="project.godot"
```

Expected: all 5 action names appear as top-level keys under `[input]`.

- [ ] **Step 5: Commit**

```bash
git add project.godot
git commit -m "feat(fighter): add p0_* input actions for Phase 1 (move + sprint)"
```

---

## Task 3: Fighter scene — visual capsule placeholder

No skeleton, no animation tree, no sword. Just a capsule body that can stand on the floor. Phase 2 will replace this with a rigged character.

**Files:**
- Create: `fighter/fighter.tscn`

**Exit criterion:** The scene opens in Godot without errors. The 3D viewport shows a single capsule.

- [ ] **Step 1: Create the scene in the Godot editor**

Scene → New Scene → Other Node → `CharacterBody3D`. Name the root node `Fighter`.

Add these children to the `Fighter` root:
1. `CollisionShape3D` named `Collision`
   - Set its `Shape` property to a new `CapsuleShape3D`
   - `CapsuleShape3D.height = 1.8`
   - `CapsuleShape3D.radius = 0.4`
   - Position `Collision` at `(0, 0.9, 0)` so the capsule's feet are at the origin (the capsule is centered on its shape origin, so lifting by half its height sits it on the floor).
2. `MeshInstance3D` named `Mesh`
   - Set its `Mesh` property to a new `CapsuleMesh`
   - `CapsuleMesh.height = 1.8`
   - `CapsuleMesh.radius = 0.4`
   - Position `Mesh` at `(0, 0.9, 0)` (same offset logic as Collision)

On the `Fighter` root:
- Collision Layer: enable only layer 2 (`Player`) — this matches the existing template's convention.
- Collision Mask: enable layer 1 (`World`) — we only care about colliding with the floor for now.

Save the scene as `res://fighter/fighter.tscn`.

- [ ] **Step 2: Verify it opens and looks right**

Close and reopen the scene. Viewport should show a capsule standing on the world origin. No errors in the editor console.

- [ ] **Step 3: Commit**

```bash
git add fighter/fighter.tscn
git commit -m "feat(fighter): add placeholder Fighter scene (capsule body)"
```

---

## Task 4: Demo scene — floor, two Fighters, placeholder camera

**Files:**
- Create: `fighter/fighter_demo.tscn`
- Modify: `project.godot` (change `application/run/main_scene`)

**Exit criterion:** Press F5. Two capsules are visible standing on a floor, viewed from a static camera at (0, 3, 8). No errors, no physics weirdness.

- [ ] **Step 1: Create the demo scene**

Scene → New Scene → Other Node → `Node3D`. Name the root `FighterDemo`. Add these children:

1. `DirectionalLight3D` named `Sun`
   - Rotation: `(-45, -45, 0)` degrees
   - `shadow_enabled = true`
2. `WorldEnvironment` named `WorldEnv`
   - Environment: create a new `Environment` resource
   - `Environment.background_mode = Sky`
   - `Environment.sky = ` new `Sky` resource with default `ProceduralSkyMaterial`
   - `Environment.ambient_light_source = Sky`
3. `StaticBody3D` named `Floor`
   - Collision Layer: layer 1 (`World`)
   - Child: `CollisionShape3D` with a new `BoxShape3D`, size `(20, 1, 20)`, positioned at `(0, -0.5, 0)` so the top of the box is at `y=0`
   - Child: `MeshInstance3D` with a new `BoxMesh`, size `(20, 1, 20)`, positioned at `(0, -0.5, 0)`
4. Instance of `res://fighter/fighter.tscn` — drag it from the FileSystem dock into the scene tree.
   - Rename to `FighterA`
   - Position: `(-2, 0, 0)`
5. Another instance of `res://fighter/fighter.tscn`.
   - Rename to `FighterB`
   - Position: `(2, 0, 0)`
6. `Camera3D` named `PlaceholderCam`
   - Position: `(0, 3, 8)`
   - Rotation: `(-15, 0, 0)` degrees — tilted down slightly
   - `current = true`

Save as `res://fighter/fighter_demo.tscn`.

- [ ] **Step 2: Point the project's main scene at the demo**

In the Godot editor: Project → Project Settings → General → Application → Run → Main Scene. Click the folder icon, choose `res://fighter/fighter_demo.tscn`. Save.

(Verify: `project.godot` now has `run/main_scene="res://fighter/fighter_demo.tscn"` instead of the castle scene.)

- [ ] **Step 3: F5 verify**

Press F5. Expected:
- Two capsules visible on a gray floor.
- Both capsules are stationary (no Fighter script yet — they're just CharacterBody3Ds with gravity inactive until a script provides it, so they should sit where placed).
- No error output in the Godot console.
- Pressing Esc closes the window.

If a capsule falls through the floor, check its position Y ≥ 0 and the floor collision shape sits at `y = -0.5` (top at 0).

- [ ] **Step 4: Commit**

```bash
git add fighter/fighter_demo.tscn project.godot
git commit -m "feat(fighter): add demo scene with floor and two fighters"
```

---

## Task 5: Fighter class skeleton — state enum, intent stubs, gravity

This task lays down the full intent surface as stubs and a minimal `_physics_process` that only applies gravity. No movement yet; that comes in Task 7. The point is to get the class shape right and attach it to the scene so later tasks just fill bodies in.

**Files:**
- Create: `fighter/fighter.gd`
- Modify: `fighter/fighter.tscn` (attach the script to the root)

**Exit criterion:** F5 runs. Both capsules stay upright on the floor (gravity is applied; they don't fall through). Godot console prints no errors. The class compiles.

- [ ] **Step 1: Write `fighter/fighter.gd`**

```gdscript
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
	# Phase 1: actual movement/rotation added in Tasks 7-10.
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
```

- [ ] **Step 2: Attach the script to `fighter.tscn`**

In the Godot editor, open `fighter/fighter.tscn`, select the `Fighter` root node, click the "Attach Script" button (scroll icon) in the inspector, and pick `res://fighter/fighter.gd`. Save the scene.

- [ ] **Step 3: Set `opponent` references in `fighter_demo.tscn`**

Open `fighter/fighter_demo.tscn`. Select `FighterA`, and in the inspector set its `Opponent` export to `FighterB` (drag `FighterB` from the scene tree into the field, or use the picker). Select `FighterB` and set its `Opponent` to `FighterA`. Save.

- [ ] **Step 4: F5 verify**

Press F5. Expected:
- Two capsules are visible on the floor.
- No parse errors in the Godot console.
- Both capsules stay upright and motionless (no movement code yet).
- Gravity is applied (if you temporarily raise a fighter's Y in the editor to 2 and re-run, it should fall and settle on the floor).

- [ ] **Step 5: Commit**

```bash
git add fighter/fighter.gd fighter/fighter.tscn fighter/fighter_demo.tscn
git commit -m "feat(fighter): add Fighter class skeleton with intent stubs"
```

---

## Task 6: FighterBrain base + PlayerBrain

We build the brain layer *before* filling in movement, so when we add movement in Task 7 we can immediately F5-test it with WASD.

**Files:**
- Create: `fighter/fighter_brain.gd`
- Create: `fighter/brains/player_brain.gd`
- Modify: `fighter/fighter_demo.tscn` (attach a `PlayerBrain` child to `FighterA`)

**Exit criterion:** F5 runs, no errors. The brain runs every physics tick and calls `intent_move` / `intent_sprint` on its fighter (verifiable by adding a temporary print, though Task 7 will verify visually).

- [ ] **Step 1: Write `fighter/fighter_brain.gd`**

```gdscript
# fighter/fighter_brain.gd
# Abstract base for decision-makers attached to a Fighter.
# Subclasses (PlayerBrain, AIBrain) override _physics_process and call
# intent_* methods on self.fighter. Brains never touch the CharacterBody3D
# directly — they only emit intents.
class_name FighterBrain
extends Node

## The fighter this brain controls. Set in the editor, or auto-resolved
## to the parent if left unset.
@export var fighter: Fighter

func _ready() -> void:
	if fighter == null:
		var parent := get_parent()
		if parent is Fighter:
			fighter = parent
	if fighter == null:
		push_error("FighterBrain '%s' has no fighter reference and no Fighter parent." % name)
```

- [ ] **Step 2: Write `fighter/brains/player_brain.gd`**

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

func _ready() -> void:
	super._ready()
	var p := "p%d_" % player_index
	_move_up    = StringName(p + "move_up")
	_move_down  = StringName(p + "move_down")
	_move_left  = StringName(p + "move_left")
	_move_right = StringName(p + "move_right")
	_sprint     = StringName(p + "sprint")

func _physics_process(_delta: float) -> void:
	if fighter == null:
		return
	var move := Input.get_vector(_move_left, _move_right, _move_up, _move_down)
	fighter.intent_move(move)
	fighter.intent_sprint(Input.is_action_pressed(_sprint))
```

- [ ] **Step 3: Attach a `PlayerBrain` to `FighterA` in the demo scene**

Open `fighter/fighter_demo.tscn`. Right-click `FighterA` → Add Child Node → `Node`. On the new node, attach the script `res://fighter/brains/player_brain.gd`. Rename the node to `PlayerBrain`.

Leave `player_index = 0` (the default). The `fighter` export can be left empty — `_ready` auto-resolves it to the parent.

Save the scene.

- [ ] **Step 4: F5 verify**

Press F5. Expected:
- No script errors.
- Pressing WASD does nothing visible yet (movement is implemented in Task 7), but the brain is running. To sanity-check, you may temporarily add `print(move)` in `_physics_process` in `player_brain.gd` and confirm the console shows non-zero values when you press WASD. **Remove the print before committing.**

- [ ] **Step 5: Commit**

```bash
git add fighter/fighter_brain.gd fighter/brains/player_brain.gd fighter/fighter_demo.tscn
git commit -m "feat(fighter): add FighterBrain base and PlayerBrain for p0_* input"
```

---

## Task 7: Fighter STRAFING movement (facing opponent, strafe + approach/retreat)

Fill in the STRAFING branch. When in STRAFING, movement is relative to the line between the fighter and the opponent:
- `input_dir.x` strafes perpendicular to that line (orbiting)
- `input_dir.y` (negated because Godot's input Y points down) moves along the line (approach / retreat)

Rotation follows in Task 8; this task is just the translational movement. For now the capsule will slide around without turning — that's expected.

**Files:**
- Modify: `fighter/fighter.gd`

**Exit criterion:** F5, press WASD. `FighterA` moves: W approaches `FighterB`, S retreats, A/D strafe around. Movement is in world space (capsule doesn't rotate yet). `FighterB` is stationary.

- [ ] **Step 1: Add the STRAFING movement branch to `_physics_process`**

Replace the existing `_physics_process` in `fighter/fighter.gd` with:

```gdscript
func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	match current_state:
		State.STRAFING:
			_strafing_movement(delta)
		_:
			pass  # other states added in later tasks
	move_and_slide()
```

- [ ] **Step 2: Implement `_strafing_movement`**

Add this method at the bottom of `fighter/fighter.gd`:

```gdscript
# Movement while locked on. Builds a desired horizontal velocity from
# input_dir in a frame of reference defined by the opponent's direction:
#   forward axis = unit vector from self to opponent (horizontal)
#   right axis   = UP cross forward
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
	var right := Vector3.UP.cross(forward).normalized()
	var approach := -input_dir.y    # W (stick up = -y) means "approach"
	var strafe := input_dir.x
	return forward * approach + right * strafe
```

- [ ] **Step 3: F5 verify**

Press F5. Expected:
- Hold W: `FighterA` slides toward `FighterB`.
- Hold S: `FighterA` slides away from `FighterB`.
- Hold A: `FighterA` strafes one direction perpendicular to the line between the fighters.
- Hold D: `FighterA` strafes the other direction.
- `FighterA` does **not** rotate yet — it slides around facing its spawn rotation. This is expected; Task 8 adds rotation.
- `FighterB` remains stationary (no brain attached).

If movement feels inverted (W retreats instead of approaches), the `approach = -input_dir.y` line needs its sign flipped. The convention depends on your input bindings — check that `p0_move_up` is bound to W and produces `input_dir.y = -1` when held.

- [ ] **Step 4: Commit**

```bash
git add fighter/fighter.gd
git commit -m "feat(fighter): implement STRAFING movement (strafe + approach/retreat)"
```

---

## Task 8: Fighter face-opponent rotation during STRAFING

Add the slerp-to-face-opponent rotation. With this in place, the Fighter always faces its opponent while in STRAFING, so W/S/A/D movement is always relative to a visible "forward."

**Files:**
- Modify: `fighter/fighter.gd`

**Exit criterion:** F5, hold A or D. `FighterA` strafes around `FighterB` and is always facing `FighterB` (its capsule doesn't visually rotate because it's round, but its local -Z axis points at the opponent — verifiable via Task 9's visual forward indicator or by trusting the code).

- [ ] **Step 1: Add rotation to the STRAFING branch**

Update `_physics_process` in `fighter/fighter.gd`:

```gdscript
func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	match current_state:
		State.STRAFING:
			_face_opponent(rotation_lerp_weight)
			_strafing_movement(delta)
		_:
			pass
	move_and_slide()
```

- [ ] **Step 2: Implement `_face_opponent`**

Add this method to `fighter/fighter.gd`:

```gdscript
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
```

- [ ] **Step 3: Add a visual forward indicator to the Fighter scene** *(so rotation is visible)*

A capsule is rotationally symmetric so you can't see it face anything. Add a small visible "nose" to make facing observable.

In the Godot editor, open `fighter/fighter.tscn`:
1. Right-click the `Fighter` root → Add Child Node → `MeshInstance3D`. Rename it `ForwardIndicator`.
2. Set its Mesh to a new `BoxMesh` with size `(0.2, 0.2, 0.5)`.
3. Position: `(0, 1.2, -0.5)` — in front of the capsule's upper body (remember Godot forward is -Z).
4. Optional: give it a bright color via a new `StandardMaterial3D` on the mesh's `Material Override`, `Albedo Color` red.

Save the scene.

- [ ] **Step 4: F5 verify**

Press F5. Expected:
- `FighterA` has a small red box sticking out the front.
- On spawn, the red box points away from `FighterB` briefly (initial rotation) and then slerps to point at `FighterB`.
- Move `FighterA` around with WASD — the red box always points at `FighterB`.
- Strafe with A/D — `FighterA` orbits `FighterB` while its red nose continuously tracks the opponent.

- [ ] **Step 5: Commit**

```bash
git add fighter/fighter.gd fighter/fighter.tscn
git commit -m "feat(fighter): auto-face opponent during STRAFING via lerp_angle"
```

---

## Task 9: Fighter SPRINTING state — free movement + break-lock

When the player holds sprint, transition to SPRINTING. In SPRINTING, movement is in camera/world space (not opponent-relative), rotation follows the move direction (not the opponent), and speed is `sprint_speed`.

**Files:**
- Modify: `fighter/fighter.gd`

**Exit criterion:** F5, press WASD to strafe, then hold Shift. The Fighter transitions to free movement — WASD now moves in world space (camera-relative directions), capsule rotates to face movement direction, and it moves faster. Release Shift → Task 10 handles re-engaging lock.

- [ ] **Step 1: Wire sprint transition into `_physics_process`**

Update `_physics_process` so that the held-sprint intent flips the state:

```gdscript
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
			pass
	move_and_slide()
```

- [ ] **Step 2: Implement `_update_lock_state`**

Add this method. Phase 1 rule: if the player is holding sprint, we're in SPRINTING; otherwise we're in STRAFING. Task 10 will make the exit condition smarter (the "re-engage only when facing opponent" check).

```gdscript
# Decides between STRAFING and SPRINTING based on the sprint intent.
# Task 10 will extend the release condition.
func _update_lock_state() -> void:
	if sprint_held:
		if current_state == State.STRAFING:
			current_state = State.SPRINTING
	else:
		if current_state == State.SPRINTING:
			current_state = State.STRAFING
```

- [ ] **Step 3: Implement `_sprinting_movement`**

```gdscript
# Movement while lock is broken. Velocity is in world space, speed is sprint_speed.
# Direction comes from input_dir interpreted as (X = right, -Y = forward)
# in a frame defined by the camera's yaw so the player's "forward on the stick"
# always moves toward the top of the screen.
func _sprinting_movement(delta: float) -> void:
	var desired := _compute_sprint_velocity() * sprint_speed
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)

func _compute_sprint_velocity() -> Vector3:
	if input_dir.length_squared() < 0.0001:
		return Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		# Fallback: world-space movement in case no camera is current.
		return Vector3(input_dir.x, 0, input_dir.y).normalized()
	# Use the camera yaw so "up on stick" means "away from the camera."
	var cam_yaw := cam.global_rotation.y
	var forward := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	# In Godot, forward in camera space is -Z. Stick up (input_dir.y = -1) should move forward.
	var move := -forward * input_dir.y + right * input_dir.x
	return move.normalized()
```

- [ ] **Step 4: Implement `_face_movement`**

While sprinting, rotate the fighter to face the direction of movement instead of the opponent.

```gdscript
func _face_movement(weight: float) -> void:
	var horizontal_vel := Vector3(velocity.x, 0, velocity.z)
	if horizontal_vel.length_squared() < 0.04:
		return  # don't snap facing when nearly stopped
	var target_yaw := atan2(horizontal_vel.x, horizontal_vel.z) + PI
	rotation.y = lerp_angle(rotation.y, target_yaw, weight)
```

- [ ] **Step 5: F5 verify**

Press F5. Expected:
- WASD strafes around `FighterB` as before.
- Hold Shift: Fighter enters SPRINTING.
  - Moves faster.
  - WASD is world-relative (approximately camera-relative — camera is still the placeholder static cam, so "up" on stick means "away from the placeholder camera," which is -Z).
  - Red forward indicator now turns to face movement direction, not the opponent.
- Release Shift: Fighter returns to STRAFING immediately (regardless of where it's facing — Task 10 will refine this). Red indicator re-locks to the opponent.

- [ ] **Step 6: Commit**

```bash
git add fighter/fighter.gd
git commit -m "feat(fighter): add SPRINTING state with free movement and break-lock"
```

---

## Task 10: Sprint-release re-engage gate

Refine the sprint-release rule per spec: on release, we only transition back to STRAFING if the fighter is **both** within `engage_range` of the opponent and facing them closely enough (dot product of forward vs. to-opponent ≥ `engage_facing_dot`). Otherwise, we stay in SPRINTING-without-held-sprint (i.e., free movement at walk speed) until one of those conditions becomes true.

This means "sprint away, release, keep running away" doesn't instantly re-engage lock while you're still facing away from your opponent. Lock only snaps back when you turn around.

For Phase 1 simplicity, "free movement at walk speed" is modeled by adding a new sub-state. I'll reuse SPRINTING as the free-movement state but add a `is_free_moving` flag that just changes the speed used. This keeps the state enum small.

Actually, simpler: keep the two states we have. When sprint is released but we don't qualify to re-engage, we stay in SPRINTING conceptually but the movement speed drops to `default_speed`. That's a conditional inside `_sprinting_movement` based on `sprint_held`.

**Files:**
- Modify: `fighter/fighter.gd`

**Exit criterion:** F5, sprint away from `FighterB` (hold Shift + S or W depending on orientation). Release Shift while still facing away — the fighter slows to walk speed but stays in free movement (red indicator still follows movement direction). Turn back to face `FighterB` — the fighter snaps to STRAFING (red indicator re-locks to opponent). This is the "graceful re-engage" feel.

- [ ] **Step 1: Refine `_update_lock_state`**

Replace the body of `_update_lock_state` with:

```gdscript
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
```

- [ ] **Step 2: Implement `_should_re_engage_lock`**

```gdscript
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
```

- [ ] **Step 3: Change `_sprinting_movement` to use walk speed when sprint is not held**

Only one line changes — the speed multiplier:

```gdscript
func _sprinting_movement(delta: float) -> void:
	var speed := sprint_speed if sprint_held else default_speed
	var desired := _compute_sprint_velocity() * speed
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
```

- [ ] **Step 4: F5 verify — the graceful re-engage test**

Press F5. Test sequence:
1. Tap W to approach `FighterB`; the Fighter strafes/approaches and auto-faces the opponent. ✅
2. Hold Shift + S to sprint away from `FighterB` in free movement. The Fighter runs away, facing the movement direction (away from `FighterB`). ✅
3. Release Shift while still facing away. The Fighter slows to walk speed but stays in free movement — red indicator still points in movement direction, not at `FighterB`. ✅
4. Rotate by pushing the stick back toward `FighterB` (S becomes W if the camera is behind you — or just swing around). Once the Fighter is facing `FighterB` within the engage range, it snaps to STRAFING — red indicator locks on. ✅

The critical observation: releasing sprint while facing away does **not** instantly snap you back to lock. That's the spec behavior.

- [ ] **Step 5: Commit**

```bash
git add fighter/fighter.gd
git commit -m "feat(fighter): gate sprint-release re-engage on range and facing"
```

---

## Task 11: FighterCam pure-math helpers + unit tests

Build the FighterCam as a Camera3D subclass whose orbit math lives in **static** methods on the class, so the pure math is testable without a scene tree. Then write the test file and run it headless.

TDD order: write the failing tests first, then fill in the static methods until they pass.

**Files:**
- Create: `fighter/fighter_cam.gd` (partial — static math + empty Camera3D wrapper)
- Create: `fighter/tests/test_fighter_cam.gd`

**Exit criterion:** `godot --headless --script fighter/tests/test_fighter_cam.gd` runs, prints multiple PASS lines, and exits with code 0.

- [ ] **Step 1: Write the test file (failing first)**

Create `fighter/tests/test_fighter_cam.gd`:

```gdscript
# fighter/tests/test_fighter_cam.gd
# Pure-math tests for FighterCam. Run headless:
#   godot --headless --script fighter/tests/test_fighter_cam.gd
extends "res://fighter/tests/test_runner.gd"

const FighterCam = preload("res://fighter/fighter_cam.gd")

func _run_all_tests() -> void:
	_test_midpoint_is_average()
	_test_midpoint_vertical_preserved()
	_test_target_radius_scales_with_dist()
	_test_target_radius_clamps_to_min()
	_test_target_radius_clamps_to_max()
	_test_orbit_position_is_perpendicular_to_line()
	_test_orbit_position_respects_cam_height()
	_test_orbit_position_at_cam_radius_from_mid()

func _test_midpoint_is_average() -> void:
	var mid = FighterCam.compute_midpoint(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	assert_vec3_near(mid, Vector3.ZERO, 0.0001, "midpoint of (-2,0,0)+(2,0,0) = origin")

func _test_midpoint_vertical_preserved() -> void:
	var mid = FighterCam.compute_midpoint(Vector3(0, 1, 0), Vector3(0, 3, 0))
	assert_vec3_near(mid, Vector3(0, 2, 0), 0.0001, "midpoint preserves y component")

func _test_target_radius_scales_with_dist() -> void:
	# dist=4, ratio=1.2, base=2.5 -> 4*1.2 + 2.5 = 7.3
	var r = FighterCam.compute_target_radius(4.0, 1.2, 2.5, 3.0, 9.0)
	assert_near(r, 7.3, 0.0001, "radius scales linearly with dist before clamp")

func _test_target_radius_clamps_to_min() -> void:
	# tiny dist -> formula would give 2.5, but min=3.0 should clamp
	var r = FighterCam.compute_target_radius(0.0, 1.2, 2.5, 3.0, 9.0)
	assert_near(r, 3.0, 0.0001, "radius clamps to min_radius at dist 0")

func _test_target_radius_clamps_to_max() -> void:
	# dist=20 -> 20*1.2 + 2.5 = 26.5, max=9.0 should clamp
	var r = FighterCam.compute_target_radius(20.0, 1.2, 2.5, 3.0, 9.0)
	assert_near(r, 9.0, 0.0001, "radius clamps to max_radius at large dist")

func _test_orbit_position_is_perpendicular_to_line() -> void:
	# Fighters on x-axis: line direction is +X, line_yaw = atan2(1, 0) = PI/2.
	# The camera should sit on the z-axis (perpendicular to +X).
	var mid := Vector3.ZERO
	var line_yaw := atan2(1.0, 0.0)  # PI/2
	var pos = FighterCam.compute_orbit_position(mid, line_yaw, 5.0, 0.0, 0.0)
	# Perpendicular to +X through origin is the z-axis. |pos.x| should be ~0.
	assert_near(pos.x, 0.0, 0.0001, "perpendicular to X-axis line has x=0")
	assert_near(abs(pos.z), 5.0, 0.0001, "camera sits at cam_radius along perpendicular")

func _test_orbit_position_respects_cam_height() -> void:
	var pos = FighterCam.compute_orbit_position(Vector3(0, 2, 0), 0.0, 5.0, 1.5, 0.0)
	assert_near(pos.y, 3.5, 0.0001, "cam y = mid.y + cam_height")

func _test_orbit_position_at_cam_radius_from_mid() -> void:
	# Distance from camera to mid (horizontal only) should always equal cam_radius.
	var mid := Vector3(3, 0, 4)
	var line_yaw := 0.7
	var pos = FighterCam.compute_orbit_position(mid, line_yaw, 6.0, 0.0, 0.0)
	var horizontal := Vector3(pos.x - mid.x, 0, pos.z - mid.z)
	assert_near(horizontal.length(), 6.0, 0.0001, "horizontal distance from mid = cam_radius")
```

- [ ] **Step 2: Create a minimal `fighter/fighter_cam.gd` with failing placeholders**

Create the file just well enough that the tests can load it. The static functions should exist but return wrong values (so tests fail).

```gdscript
# fighter/fighter_cam.gd
# FighterCam — midpoint-orbit camera. NOT a SpringArm3D.
# Its position is computed every physics frame from the positions of the
# two fighters it tracks. It sits on a ring around their midpoint, always
# side-on to the line between them.
#
# The actual orbit math lives in static methods so it's testable without
# a scene tree.
class_name FighterCam
extends Camera3D

# --- Pure static helpers (testable without a scene tree) ---

static func compute_midpoint(a: Vector3, b: Vector3) -> Vector3:
	return Vector3.ZERO  # placeholder — will fail tests

static func compute_target_radius(dist: float, ratio: float, base: float, mn: float, mx: float) -> float:
	return 0.0  # placeholder

static func compute_orbit_position(mid: Vector3, line_yaw: float, cam_radius: float, cam_height: float, side_bias: float) -> Vector3:
	return Vector3.ZERO  # placeholder
```

- [ ] **Step 3: Run the tests — verify they fail**

```bash
godot --headless --script fighter/tests/test_fighter_cam.gd
```

Expected: most or all assertions FAIL with mismatches. Exit code 1. Good — we have a failing baseline.

- [ ] **Step 4: Implement the static functions to make the tests pass**

Replace the three `return` placeholders in `fighter/fighter_cam.gd` with real implementations:

```gdscript
static func compute_midpoint(a: Vector3, b: Vector3) -> Vector3:
	return (a + b) * 0.5

static func compute_target_radius(dist: float, ratio: float, base: float, mn: float, mx: float) -> float:
	return clamp(dist * ratio + base, mn, mx)

static func compute_orbit_position(mid: Vector3, line_yaw: float, cam_radius: float, cam_height: float, side_bias: float) -> Vector3:
	var cam_yaw := line_yaw + PI * 0.5 + side_bias
	var pos := mid + Vector3(sin(cam_yaw), 0, cos(cam_yaw)) * cam_radius
	pos.y = mid.y + cam_height
	return pos
```

- [ ] **Step 5: Run the tests — verify they pass**

```bash
godot --headless --script fighter/tests/test_fighter_cam.gd
```

Expected:
```
=== test_fighter_cam.gd ===
  PASS  midpoint of (-2,0,0)+(2,0,0) = origin  (...)
  PASS  midpoint preserves y component  (...)
  PASS  radius scales linearly with dist before clamp  (...)
  PASS  radius clamps to min_radius at dist 0  (...)
  PASS  radius clamps to max_radius at large dist  (...)
  PASS  perpendicular to X-axis line has x=0  (...)
  PASS  camera sits at cam_radius along perpendicular  (...)
  PASS  cam y = mid.y + cam_height  (...)
  PASS  horizontal distance from mid = cam_radius  (...)

Results: 9 passed, 0 failed
```

Exit code 0.

- [ ] **Step 6: Commit**

```bash
git add fighter/fighter_cam.gd fighter/tests/test_fighter_cam.gd
git commit -m "feat(fighter): add FighterCam orbit math with headless unit tests"
```

---

## Task 12: FighterCam runtime wrapper — per-frame orbit update

Add the actual per-frame update logic to FighterCam: call the static helpers, maintain `_cam_radius` as a lerped value, implement the short-line protection for the clinch case.

**Files:**
- Modify: `fighter/fighter_cam.gd`

**Exit criterion:** The class compiles; tests from Task 11 still pass; nothing visible changes yet (the demo scene still uses the placeholder `Camera3D`).

- [ ] **Step 1: Add exports, state, and `_physics_process` to `fighter/fighter_cam.gd`**

Add the following **above** the `# --- Pure static helpers ---` comment in the existing file, right after the `extends Camera3D` line:

```gdscript
# --- Tracked fighters ---
@export var fighter_a: Node3D
@export var fighter_b: Node3D

# --- Orbit tuning (starting values from the spec) ---
@export_group("Orbit tuning")
@export var radius_ratio: float = 1.2
@export var radius_base: float = 2.5
@export var min_radius: float = 3.0
@export var max_radius: float = 9.0
@export var cam_height: float = 1.6
@export var framing_height_offset: float = 0.9
@export var min_tracking_dist: float = 0.5
@export var radius_lerp_weight: float = 0.08
@export var side_bias: float = 0.0

# --- Runtime state ---
var _cam_radius: float
var _last_stable_line_yaw: float = 0.0

func _ready() -> void:
	_cam_radius = radius_base
	# Seed _last_stable_line_yaw from initial positions if both are set,
	# so the first frame has a sensible starting heading.
	if fighter_a and fighter_b:
		var line: Vector3 = fighter_b.global_position - fighter_a.global_position
		if line.length() >= min_tracking_dist:
			_last_stable_line_yaw = atan2(line.x, line.z)

func _physics_process(_delta: float) -> void:
	if fighter_a == null or fighter_b == null:
		return
	_update_orbit()

func set_fighters(a: Node3D, b: Node3D) -> void:
	fighter_a = a
	fighter_b = b

# Called every physics tick when both fighters are set. Combines:
#  - midpoint tracking
#  - line-yaw computation with short-line-protection (clinch case)
#  - target-radius lerp for smooth zoom
#  - camera position on the orbit ring
#  - look-at the midpoint with a small vertical offset
func _update_orbit() -> void:
	var a_pos: Vector3 = fighter_a.global_position
	var b_pos: Vector3 = fighter_b.global_position
	var mid: Vector3 = compute_midpoint(a_pos, b_pos)

	var line: Vector3 = b_pos - a_pos
	var dist: float = line.length()

	var line_yaw: float
	if dist < min_tracking_dist:
		line_yaw = _last_stable_line_yaw
	else:
		line_yaw = atan2(line.x, line.z)
		_last_stable_line_yaw = line_yaw

	var target_radius: float = compute_target_radius(dist, radius_ratio, radius_base, min_radius, max_radius)
	_cam_radius = lerp(_cam_radius, target_radius, radius_lerp_weight)

	global_position = compute_orbit_position(mid, line_yaw, _cam_radius, cam_height, side_bias)
	look_at(mid + Vector3.UP * framing_height_offset, Vector3.UP)
```

- [ ] **Step 2: Re-run the unit tests to confirm nothing broke**

```bash
godot --headless --script fighter/tests/test_fighter_cam.gd
```

Expected: still 9 passed, 0 failed. (The runtime additions don't affect the static functions.)

- [ ] **Step 3: Commit**

```bash
git add fighter/fighter_cam.gd
git commit -m "feat(fighter): add FighterCam runtime wrapper with short-line protection"
```

---

## Task 13: Swap FighterCam into the demo scene

Replace the placeholder `Camera3D` in `fighter_demo.tscn` with a FighterCam, wire it to the two fighters, and verify the camera correctly orbits as the player moves.

**Files:**
- Modify: `fighter/fighter_demo.tscn`

**Exit criterion:** F5. The camera frames both fighters from the side. When `FighterA` strafes around `FighterB`, the camera sweeps around to maintain its side-on framing. When `FighterA` sprints away, the camera zooms out (up to `max_radius`). When `FighterA` approaches closely, the camera zooms in (down to `min_radius`).

- [ ] **Step 1: Delete the placeholder Camera3D from the demo scene**

Open `fighter/fighter_demo.tscn` in the Godot editor. Select the `PlaceholderCam` node and delete it.

- [ ] **Step 2: Add a FighterCam to the demo scene**

Right-click the `FighterDemo` root → Add Child Node → type "Camera3D" and select it. In the Inspector, click the script icon (scroll icon with `s`) → Load → `res://fighter/fighter_cam.gd`.

(Alternative that's equivalent: create a plain `Node` and attach the script, but `Camera3D` as the base is correct because `FighterCam extends Camera3D`.)

Rename the node to `FighterCam`.

Set these properties in the Inspector:
- `Current = true` (so it becomes the active camera on scene start)
- `Fighter A = FighterA` (drag FighterA from the tree)
- `Fighter B = FighterB` (drag FighterB from the tree)

Leave all the orbit tuning exports at their defaults.

Save the scene.

- [ ] **Step 3: F5 verify — the full camera test**

Press F5. Run through this checklist:

- [ ] Camera is side-on to the two fighters at scene start. Both fighters visible, roughly equal sizes on screen.
- [ ] The camera is **not** behind the player's shoulder — it's on the side of the line between the fighters.
- [ ] Hold D to strafe right around `FighterB`. As `FighterA` orbits, the camera sweeps around the midpoint to keep the same side-on framing. Both fighters stay visible.
- [ ] Hold A to strafe left. Same but the other direction.
- [ ] Hold W to approach `FighterB`. Camera zooms in smoothly (cam_radius lerps down).
- [ ] Hold S to retreat. Camera zooms out smoothly.
- [ ] Hold Shift + a direction away from `FighterB` to sprint away. Camera zooms out until it hits `max_radius` (9.0) and then keeps tracking midpoint and heading without zooming further.
- [ ] Release Shift while far away and facing away. Fighter keeps free-moving at walk speed (per Task 10). Camera continues tracking.
- [ ] Turn back to face `FighterB` and walk within `engage_range` (8.0 units). Fighter snaps back to STRAFING; camera re-engages smoothly.

If any of these fail, note which and check the relevant task's code before proceeding. Common issues:
- **Camera looks over a shoulder instead of side-on**: the `PI/2` in `compute_orbit_position` may need its sign flipped based on your spawn orientations. Flip `side_bias` to `PI` to orbit to the opposite side.
- **Camera is upside down or tilted**: the `look_at` is using a wrong up vector; confirm it's `Vector3.UP`.
- **Camera jitters badly when fighters are close**: `min_tracking_dist` may be too small; try 1.0 instead of 0.5.

- [ ] **Step 4: Commit**

```bash
git add fighter/fighter_demo.tscn
git commit -m "feat(fighter): wire FighterCam into fighter_demo scene"
```

---

## Task 14: Fighter state transition runtime test

Now that we have several state transitions (STRAFING ↔ SPRINTING based on sprint intent + re-engage predicate), write a small runtime test that verifies them without relying on Input. This catches regressions when later tasks touch the state machine.

This test needs a SceneTree (because Fighter is a CharacterBody3D), so it's a SceneTree-based test that spawns fighters in code.

**Files:**
- Create: `fighter/tests/test_fighter_states.gd`

**Exit criterion:** `godot --headless --script fighter/tests/test_fighter_states.gd` runs, prints all PASS lines, exits 0.

- [ ] **Step 1: Write the runtime state test**

Create `fighter/tests/test_fighter_states.gd`:

```gdscript
# fighter/tests/test_fighter_states.gd
# Runtime tests for Fighter state transitions. Unlike test_fighter_cam.gd,
# these need a SceneTree because Fighter is a CharacterBody3D. We instantiate
# two bare Fighters in a temporary root, poke their intents, and check state.
#
# Run headless:  godot --headless --script fighter/tests/test_fighter_states.gd
extends "res://fighter/tests/test_runner.gd"

const FighterScript = preload("res://fighter/fighter.gd")

func _run_all_tests() -> void:
	_test_initial_state_is_strafing()
	_test_sprint_held_transitions_to_sprinting()
	_test_sprint_released_in_range_and_facing_reengages()
	_test_sprint_released_far_away_does_not_reengage()
	_test_sprint_released_facing_away_does_not_reengage()

# -- Helpers --------------------------------------------------------------

func _make_fighter_pair(a_pos: Vector3, b_pos: Vector3) -> Array:
	var a: Fighter = FighterScript.new()
	var b: Fighter = FighterScript.new()
	a.name = "A"
	b.name = "B"
	get_root().add_child(a)
	get_root().add_child(b)
	a.global_position = a_pos
	b.global_position = b_pos
	a.opponent = b
	b.opponent = a
	# Face A toward B manually so the re-engage predicate has a defined forward.
	var to_b := (b_pos - a_pos)
	to_b.y = 0
	a.rotation.y = atan2(to_b.x, to_b.z) + PI
	return [a, b]

func _teardown(pair: Array) -> void:
	for f in pair:
		f.queue_free()

# -- Tests ----------------------------------------------------------------

func _test_initial_state_is_strafing() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: Fighter = pair[0]
	assert_eq(a.current_state, Fighter.State.STRAFING, "new Fighter starts in STRAFING")
	_teardown(pair)

func _test_sprint_held_transitions_to_sprinting() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: Fighter = pair[0]
	a.intent_sprint(true)
	a._update_lock_state()
	assert_eq(a.current_state, Fighter.State.SPRINTING, "sprint held flips STRAFING -> SPRINTING")
	_teardown(pair)

func _test_sprint_released_in_range_and_facing_reengages() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: Fighter = pair[0]
	a.current_state = Fighter.State.SPRINTING
	a.intent_sprint(false)
	a._update_lock_state()
	assert_eq(a.current_state, Fighter.State.STRAFING, "sprint released within range, facing opponent -> STRAFING")
	_teardown(pair)

func _test_sprint_released_far_away_does_not_reengage() -> void:
	# Put A far outside engage_range (default 8.0).
	var pair := _make_fighter_pair(Vector3(-20, 0, 0), Vector3(0, 0, 0))
	var a: Fighter = pair[0]
	a.current_state = Fighter.State.SPRINTING
	a.intent_sprint(false)
	a._update_lock_state()
	assert_eq(a.current_state, Fighter.State.SPRINTING, "sprint released far away stays in SPRINTING")
	_teardown(pair)

func _test_sprint_released_facing_away_does_not_reengage() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: Fighter = pair[0]
	# Rotate A to face AWAY from B (opposite of what _make_fighter_pair set).
	a.rotation.y += PI
	a.current_state = Fighter.State.SPRINTING
	a.intent_sprint(false)
	a._update_lock_state()
	assert_eq(a.current_state, Fighter.State.SPRINTING, "sprint released facing away stays in SPRINTING")
	_teardown(pair)
```

- [ ] **Step 2: Run the test and verify**

```bash
godot --headless --script fighter/tests/test_fighter_states.gd
```

Expected:
```
=== test_fighter_states.gd ===
  PASS  new Fighter starts in STRAFING  (got 1)
  PASS  sprint held flips STRAFING -> SPRINTING  (got 2)
  PASS  sprint released within range, facing opponent -> STRAFING  (got 1)
  PASS  sprint released far away stays in SPRINTING  (got 2)
  PASS  sprint released facing away stays in SPRINTING  (got 2)

Results: 5 passed, 0 failed
```

Exit code 0.

If `_update_lock_state` is reported as inaccessible (private-by-convention), note that GDScript doesn't actually enforce privacy for leading-underscore names — the test can still call it. If you see a type error, check that the Fighter class name is correctly referenced.

- [ ] **Step 3: Commit**

```bash
git add fighter/tests/test_fighter_states.gd
git commit -m "test(fighter): add runtime tests for state transitions"
```

---

## Task 15: Phase 1 end-to-end verification + cleanup

Final pass. Run both test suites and the manual F5 checklist to confirm Phase 1's exit criterion from the spec is met.

**Files:**
- None modified (verification only)

**Exit criterion:** Both headless test scripts pass. Manual F5 matches the spec's Phase 1 exit criterion: "Move with stick; strafe around a static dummy Fighter; sprint breaks lock; releasing re-engages. Camera follows correctly."

- [ ] **Step 1: Run the headless test suites**

```bash
godot --headless --script fighter/tests/test_fighter_cam.gd
echo "---"
godot --headless --script fighter/tests/test_fighter_states.gd
```

Expected: both exit 0, all assertions pass.

- [ ] **Step 2: Run the manual F5 checklist**

Press F5 in the Godot editor. Verify every item:

- [ ] F5 loads `fighter/fighter_demo.tscn` directly (not the castle).
- [ ] Two capsules on a floor, each with a red forward indicator.
- [ ] `FighterA` is the leftmost one; `FighterB` is on the right; camera is side-on.
- [ ] WASD moves `FighterA`. W approaches `FighterB`, S retreats, A/D strafe around.
- [ ] `FighterA`'s red nose always points at `FighterB` while STRAFING.
- [ ] `FighterB` is stationary throughout (no brain attached — expected).
- [ ] Hold Shift: `FighterA` enters SPRINTING; moves faster; red nose now points in movement direction.
- [ ] Sprint away from `FighterB` (Shift + S, for example); release Shift while still facing away; `FighterA` slows to walk speed but stays in free movement.
- [ ] Turn back to face `FighterB` and walk within engage range (8.0 units); `FighterA` snaps back to STRAFING and red nose re-locks.
- [ ] Camera: always side-on, sweeps around the midpoint as `FighterA` orbits `FighterB`, zooms out when they separate (up to max_radius = 9), zooms in as they close (down to min_radius = 3).
- [ ] No errors in the Godot console during any of the above.
- [ ] Esc closes the game.

- [ ] **Step 3: Check the working tree for unintended changes**

```bash
git status
git diff
```

Ensure nothing outside the `fighter/` directory, `docs/`, or `project.godot` has been modified. The pre-existing WIP changes in the working tree (the footstep system rename, castle scene, digest.txt, enemy script, etc.) should remain untouched.

- [ ] **Step 4: Final commit (only if the checklist changed anything)**

If the F5 verification surfaced any small fixes, commit them now:

```bash
git add -- <specific-files>
git commit -m "fix(fighter): <description of what you fixed>"
```

If everything passed cleanly without fixes, there's nothing to commit here — the plan is done.

- [ ] **Step 5: Verify the commit history reads well**

```bash
git log --oneline -20
```

Expected to see roughly 14 commits with clear `type(fighter): ...` messages walking through Tasks 1–15. If any commit message is unclear, that's fine — we don't rewrite history.

---

## Plan complete

At this point:
- `fighter/` module exists with Fighter, FighterBrain, PlayerBrain, FighterCam, demo scene, and two test files.
- The player can move around a static dummy, sprint to break lock, and the camera frames both fighters correctly.
- Two headless test suites run green.
- The souls template directories (`player/`, `enemy/`, `cameras/`, `demo_level/`) are untouched. The souls castle demo still works if you temporarily repoint `run/main_scene` back at it.
- The Phase 1 exit criterion from the spec is met.

**Next plan:** Phase 2 — animation tree integration (the trickiest phase, and the early gate for the "can stances be made visibly distinct on existing animations?" risk). That plan will be written after executing this one, because hands-on knowledge of how the template's animation tree resource behaves in practice is more valuable than speculation.

---

## Self-review notes

I ran the checklist from the writing-plans skill against this plan:

1. **Spec coverage** — Phase 0 and Phase 1 from the spec's phased build plan are fully covered. Later phases are explicitly out of scope for this plan (stated in the header).
2. **Placeholder scan** — No TBD/TODO/"similar to" references. Every step has concrete code or commands.
3. **Type consistency** — `Fighter.State` enum is defined once (Task 5) and referenced consistently. `intent_move` / `intent_sprint` signatures match between `fighter.gd` (Task 5) and `player_brain.gd` (Task 6). `compute_midpoint` / `compute_target_radius` / `compute_orbit_position` signatures match between `fighter_cam.gd` (Tasks 11–12) and `test_fighter_cam.gd` (Task 11).
4. **Ambiguity** — `_update_lock_state` is called from `_physics_process` and also directly from the state tests (Task 14); this is intentional. The `_` prefix is convention-only in GDScript, not enforced.

No issues found that require re-structuring. Small tuning values (`engage_range`, `engage_facing_dot`, camera orbit params) are starting guesses per the spec and will be iterated during Phase 7 tuning.
