# Phase 2 — Animation Tree Integration (Fork-and-Wrap)

**Date:** 2026-04-09
**Parent spec:** `docs/superpowers/specs/2026-04-09-bushido-blade-pivot-design.md`
**Phase 0-1 plan:** `docs/superpowers/plans/2026-04-09-fighter-phase-0-and-1.md`
**Status:** Design approved; implementation plan pending.

## Summary

Replace Phase 1's capsule fighter with a **fork of the souls character controller + scene + animation tree**, stripped of souls-specific systems (ladders, inventory, items, gadgets, interactables) and wrapped with the brain abstraction from Phase 1. Wire stance-switching through the existing weapon-swap machinery (SLASH sub-tree = MIDDLE stance, HEAVY sub-tree = UPPER stance) and fire strike animations through the existing attack signal chain. Close the stance-legibility risk: the phase passes only if MIDDLE and UPPER stances are visibly distinct on screen.

No combat resolution, no HitResolver, no LimbHealth, no damage. Those arrive in Phases 3–4. This phase proves that stances look right before we build gameplay on top of them.

## Strategy: Fork-and-Wrap

The original pivot spec called for a parallel `fighter/` module built from scratch, with the souls `player/` directory untouched. Phases 0–1 shipped this way. Phase 2 revises the strategy:

**Fork:** Copy the souls character controller (`character_body_souls_base.gd`), animation tree script (`souls_animation_tree.gd`), and scene (`character_body_souls_base.tscn`) into `fighter/`. Edit the copies; never touch the originals.

**Wrap:** Bolt the Phase 1 brain abstraction (`FighterBrain` / `PlayerBrain`) on top of the forked controller. The brain translates high-level intents (`intent_move`, `intent_change_stance`, `intent_strike`) into calls on the forked controller's existing methods and fields.

**Rationale:** The souls controller already has working strafe movement, rotate-to-target, 2D blend-space animation math, weapon-swap sub-tree machinery, parry kernel, dodge i-frames, and attack signal phasing. Reimplementing these in a parallel controller — which Phase 1's `fighter.gd` had begun doing — duplicates proven code without improving it. Forking reuses maximum existing functionality while maintaining isolation from the souls demo.

**What Phase 1 work survives:**
- `fighter_cam.gd` — untouched, still works.
- `fighter_brain.gd` — kept; export type and auto-binding guard updated from `Fighter` to `FighterBody`.
- `brains/player_brain.gd` — kept, intent calls rewired to the fork's methods.
- `fighter_demo.tscn` — kept, scene references updated.
- `tests/test_runner.gd` — untouched.
- `tests/test_fighter_cam.gd` — untouched.
- `tests/test_fighter_states.gd` — updated to test `FighterBody` instead of `Fighter`.
- **Phase 1's opponent-relative movement math** (`_compute_strafe_velocity`, `_face_opponent`) — ported into the fork's `fighter_body.gd`, replacing the souls template's camera-relative strafing. See the "Movement Rewrite" section.

**What Phase 1 work is replaced:**
- `fighter/fighter.gd` — deleted; replaced by `fighter/fighter_body.gd` (the souls fork).
- `fighter/fighter.tscn` — deleted; replaced by `fighter/fighter_body.tscn` (the souls scene fork).

## Exit Criterion

Open `fighter_demo.tscn`, press F5:

1. Two rigged male characters face each other on the dojo floor (no capsules).
2. Stick forward/back → `LightWalking` or `LightRunning` plays, character faces opponent.
3. Stick side → `LightStrafeL` / `LightStrafeR` plays.
4. Hold stance-upper button → character shifts to `HeavyIdle`. Stick movement plays `HeavyWalking`, `HeavyStrafeL/R`.
5. Release stance-upper → returns to Light movement set (MIDDLE stance).
6. Sprint button breaks lock; shared `SPRINT_tree` animation plays regardless of held stance. Release + face opponent within range → lock re-engages, correct stance movement set resumes.
7. Strike button in MIDDLE → `Slash1` oneshot plays. Strike button in UPPER → `Heavy1` oneshot plays. The existing souls attack flow runs (state transitions to ATTACK and back to FREE) but no damage resolves — purely cosmetic. Fighter returns to normal movement when the attack animation completes.
8. Sword stays in right hand throughout all of the above.
9. FighterCam correctly frames both fighters throughout.
10. No Godot console errors from stripped souls systems.

**Gate passes** if all 10 hold in the same play session.
**Gate fails** if stances are not visibly distinct — this is the risk the phase exists to close. If the gate fails, we stop and source stance animations before writing any Phase 3 plan.

## Files — The Fork

### Source → destination

| Source (never modified) | Destination (edited in place) |
|---|---|
| `player/character_body_souls_base.gd` | `fighter/fighter_body.gd` |
| `player/souls_animation_tree.gd` | `fighter/fighter_animation_tree.gd` |
| `player/character_body_souls_base.tscn` | `fighter/fighter_body.tscn` |

### Class renames

- `CharacterBodySoulsBase` → `FighterBody` (in `fighter_body.gd`)
- `AnimationTreeSoulsBase` → `FighterAnimationTree` (in `fighter_animation_tree.gd`)

## Strip List — `fighter/fighter_body.gd`

**Delete entirely:**
- All ladder-related state, methods, and signals (`LADDER` state enum value, `ladder_movement`, `ladder_started`, `ladder_finished`, any ladder-specific `_physics_process` branch).
- All interact-related code (`_on_interact_*`, `interact_started`, interact sensor handling, `interact_type` fields).
- All inventory / item-use code (`use_item_*`, `item_change_*`, `current_item`, item signals).
- All gadget-system signals and handlers (`gadget_change_*`, `gadget_started`, gadget signals).
- All equipment-swap-from-input handling (the `_input` code that reads `"change_weapon"` / `"change_gadget"` actions). **Keep** the underlying `weapon_type` string and any method that fires `weapon_change_ended` — this is the stance-swap mechanism.
- All direct `Input.*` reads (the controller will receive input exclusively through the brain's intent methods; any `_input()` or `_unhandled_input()` that reads built-in souls actions like `"move_up"`, `"attack"`, `"dodge"` is deleted).
- Any hard `$`-path references to stripped scene nodes (`$GUI`, `$HealthSystem`, `$InventorySystem`, `$PlayerInteractSensors`, `$FootstepSoundSystem`, `$GadgetSystem`, `$ItemSystem`). These will crash at runtime if left in.
- Footstep-related controller-side hooks if any exist.
- Death screen / life-card animation references if any exist in the controller.

**Keep (used now or in later phases):**
- State enum (pruned: drop `LADDER`; keep `FREE`, `SPRINT`, `STATIC_ACTION`, `DYNAMIC_ACTION`, `DODGE`, `ATTACK`, `SPAWN` and any others that serve combat states). Phase 3 may rename these to match the spec's fighter state names.
- The `strafing` bool and the `strafe_cross_product` / `move_dot_product` fields — but the computation of these values is **rewritten** to be opponent-relative instead of camera-relative (see "Movement Rewrite" section).
- `rotate_player()` — **rewritten** in its strafing branch to face the opponent instead of the camera's forward (see "Movement Rewrite"). The freelook/sprint branch stays camera-relative.
- `free_movement()` — **rewritten** in its strafing path to use opponent-relative direction instead of `calc_direction()` (see "Movement Rewrite"). The sprint/freelook path stays camera-relative via `calc_direction()`.
- `dash_movement()` / sprint movement methods.
- `input_dir` field (the brain writes to it via `intent_move`).
- `hit(who, by_what)` and `parried()` — the hit contract.
- `start_guard()` and the parry window mechanism — parry kernel for Phase 5.
- The attack signal chain (`attack_started` → timer phasing → `attack_activated` → `attack_ended`). Phase 3 replaces the timer phasing with sim-clock-authoritative timings; Phase 2 uses it as-is.
- `health` / HP field — left alone so the controller compiles. Phase 4 replaces it with `LimbHealth`.
- `weapon_type` string + the method that triggers `weapon_change_ended` on the animation tree.
- `anim_state_tree` reference (the animation tree node).
- `change_state()` and the `current_state` setter.
- Gravity handling.

## Strip List — `fighter/fighter_animation_tree.gd`

**Delete:**
- `_on_ladder_*`, `set_ladder()`.
- `_on_interact_started()`.
- `_on_item_change_*`, `_on_use_item_started()`.
- `_on_gadget_*`, `_on_gadget_change_*`.

**Rename:**
- `@export var player_node: CharacterBodySoulsBase` → `@export var fighter_node: FighterBody`.
- All references from `player_node` → `fighter_node` throughout the file.

**Keep:**
- `set_strafe()` / `set_free_move()` — the 2D blend-space math. These read `fighter_node.strafing`, `fighter_node.strafe_cross_product`, `fighter_node.move_dot_product`, `fighter_node.input_dir`, and `fighter_node.current_state` — all of which exist on the forked controller.
- `request_oneshot()` / `abort_oneshot()`.
- `_on_weapon_change_ended()` — the stance-swap mechanism.
- `_on_weapon_change_started()` — kept so weapon_change_started signal still has a handler; may be unused at Phase 2.
- `_on_attack_started()`, `_on_big_attack_started()`, `_on_air_attack_started()`, `attack_count`, `attack_timer`.
- `_on_parry_started()`, `_on_hurt_started()`, `_on_block_started()`, `_on_death_started()`.
- `_on_sprint_started()`, `_on_dodge_started()`, `_on_jump_started()`, `_on_landed_hard()`.
- `set_guarding()` + `guard_value` — Phase 5.
- `animation_measured` signal + `_on_animation_started()`.

## Strip List — `fighter/fighter_body.tscn`

**Source:** `player/character_body_souls_base.tscn` (8.2 MB, ~44,000 lines).

**Delete entirely (node + all children):**
- `GadgetSystem` (LeftHand, Shield, HipBone, Torch, audio, streak).
- `ItemSystem` (HandBone, StorageBone, audio).
- `PlayerInteractSensors`.
- `FollowCam` (spring-arm cam + nested `PlayerTargetingSystem`).
- `FootstepSoundSystem` (BoneAttachments + raycasts).
- `GUI` CanvasLayer (HealthBar, CurrentItem, ItemSlot, inventory display).
- `InventorySystem` node.
- `HealthSystem` node.
- `TriggeredSounds` (all audio players + `LifeCardAnimations` death screen).

**Keep, edit in place:**
- **`WeaponSystem`**: Detach its script. Delete `BackBone` (Hammer mount), `WeaponHitTarget`, `WeaponHitWorld`, `WeaponStreak`. **Keep** `RightHand → HandPivot → Sword`. Result: script-less Node3D holding only the right-hand mount with sword.
- **`AnimStateTree`** (AnimationTree node): Swap its script from `souls_animation_tree.gd` to `fighter_animation_tree.gd`. Update its exported `player_node` property to `fighter_node` pointing at the root.
- **Root node** (`PlayerCharacterBodySoulsBase`, CharacterBody3D): Swap its script from `character_body_souls_base.gd` to `fighter_body.gd`. Remove exported NodePath references to stripped nodes (`weapon_system`, `gadget_system`, `health_system`, `inventory_system`, `interact_sensor`). The root stays a `CharacterBody3D` — no retype needed because `FighterBody extends CharacterBody3D`.
- **`CollisionShape3D`**: Kept (the fighter body needs its own collision).
- **`minnyquin`** (mesh rig): Untouched (`Node3D → godot_rig → GeneralSkeleton → mesh instances`).
- **`AnimationPlayer`**: Untouched.

**Animation sub-trees inside the AnimationTree resource** (NOT renamed at Phase 2):
- `SLASH_tree` stays named `SLASH_tree` (represents MIDDLE stance).
- `HEAVY_tree` stays named `HEAVY_tree` (represents UPPER stance).
- `SPRINT_tree` stays (shared sprint animation).
- `LADDER_tree` — delete if easy (it's inside the AnimationTree graph resource); leave if deletion requires graph surgery that risks corrupting the tree. Decided in the plan.
- The stance vocabulary (`Stance.MIDDLE` → `"SLASH"`, `Stance.UPPER` → `"HEAVY"`) lives only in the brain layer, not in sub-tree node names.

## Brain Wiring

The brain abstraction from Phase 1 wraps the forked controller. Each intent translates to an existing souls mechanism:

| Intent | Translation |
|---|---|
| `intent_move(dir: Vector2)` | `fighter.input_dir = dir` — but the souls controller's `calc_direction()` and `free_movement()` consume `input_dir` in **camera space**, not opponent space. See the "Movement Rewrite" section below for how this is resolved. |
| `intent_sprint(held: bool)` | Calls the souls fork's sprint state entry/exit. Concrete method names confirmed in the plan after reading `character_body_souls_base.gd`. |
| `intent_change_stance(stance)` | Maps `Stance.MIDDLE → "SLASH"`, `Stance.UPPER → "HEAVY"`. Assigns to `fighter.weapon_type`, then calls `fighter.anim_state_tree._on_weapon_change_ended(weapon_type)` **directly** to perform the sub-tree swap without playing the WeaponChange sheath/draw animation. `intent_change_stance(LOWER)` and `intent_change_stance(SHEATHED)` are silent no-ops. |
| `intent_strike(stance, dir)` | Calls the souls fork's attack-start method, which emits `attack_started`, transitions state to ATTACK, and drives the existing timer-phased animation flow. The animation tree picks the strike animation from the current weapon_type's combo sub-tree — so MIDDLE stance plays `Slash1` and UPPER stance plays `Heavy1` automatically. No damage resolves at Phase 2 because the hitbox Area3D's `monitoring` is not armed (WeaponSystem script is stripped). |
| `intent_parry()` | No-op at Phase 2. Wired in Phase 5. |
| `intent_dodge(dir)` | No-op at Phase 2. Wired in Phase 5. |
| `intent_sheathe(sheathed)` | No-op. Reserved per spec. |

## Movement Rewrite — Opponent-Relative Strafing

The souls controller's movement is **camera-relative**, not opponent-relative. This is the one area where the fork is NOT a drop-in from the souls template.

**The problem:** `calc_direction()` computes movement direction from `current_camera.global_rotation.y`. `rotate_player()` in strafing mode slerps rotation toward `orientation_target.global_rotation.y + PI`, where `orientation_target` defaults to `current_camera`. With FighterCam's side-on orbit, the camera's forward is perpendicular to the line between fighters — so stick-up would push the fighter sideways (toward the camera) instead of toward the opponent. Exit criteria 2, 3, and 6 cannot pass without fixing this.

**The fix:** Replace the strafing path in the fork with **Phase 1's opponent-relative movement math**, which was already correct:

1. **Replace `calc_direction()` for the strafing case** with Phase 1's `_compute_strafe_velocity()` logic: build a forward axis from self-to-opponent (horizontal), a right axis from `forward.cross(Vector3.UP)`, and compute velocity as `forward * (-input_dir.y) + right * input_dir.x`. This makes stick-up = approach opponent, stick-down = retreat, stick-left/right = orbit.

2. **Replace `rotate_player()` strafing branch** (which slerps to `orientation_target.global_rotation.y + PI`) with Phase 1's `_face_opponent()` logic: compute `atan2(to_opp.x, to_opp.z) + PI` and `lerp_angle` to it. The fighter faces the opponent, not the camera.

3. **Recompute `strafe_cross_product` and `move_dot_product`** from the opponent-relative basis instead of the camera-relative one. Since `input_dir.x` IS the strafe component and `-input_dir.y` IS the approach component in the opponent-relative frame, these become simple pass-throughs of `input_dir`, matching what Phase 1 had.

4. **Keep `calc_direction()` for the sprint/freelook case** — sprint movement should remain camera-relative (stick-up = run away from camera, which is correct for free movement with FighterCam's orbit). Either branch `calc_direction()` on `strafing` state, or keep two separate movement methods.

5. **`orientation_target` becomes the opponent reference**, not the camera, for the strafing path. The fork adds an `@export var opponent: Node3D` (or reuses whatever targeting reference the souls controller has) and uses it as the rotation target when `strafing=true`.

**What this means for the "reuse" story:** The fork reuses the souls template's sprint movement, animation tree integration, attack flow, parry kernel, dodge flow, and state machine. It does NOT reuse the souls strafing movement or rotation — those are replaced with Phase 1's opponent-relative versions. This is honest: the camera-relative movement was the right design for a souls-like third-person game, but it's the wrong design for a side-on fighting game where the player needs to approach/retreat relative to the opponent, not the camera.

### Stance input (Phase 2 provisional)

Single action `p0_stance_upper` bound to `[D-pad Up, Q]`. PlayerBrain polls per frame: pressed → `intent_change_stance(Stance.UPPER)`; not pressed → `intent_change_stance(Stance.MIDDLE)`.

This is a **Phase 2 provisional binding**. The spec's full LT-held-as-modifier + D-pad-as-selector control scheme replaces this when LOWER stance lands and a direction chooser is actually needed. The intent surface (`intent_change_stance(stance: int)`) does not change; only the brain's polling logic does.

### Strike input

Single action `p0_strike` bound to `[RT / R2, Left Mouse]`. PlayerBrain fires on rising edge: `intent_strike(current_stance, StrikeDir.SLASH_HORIZONTAL)`. The `StrikeDir` argument is unused at Phase 2 but present so the intent surface is stable.

### FighterBrain base class update

`fighter_brain.gd` requires two changes beyond a type rename:

1. **Export type:** `@export var fighter: Fighter` → `@export var fighter: FighterBody`.
2. **Auto-binding guard:** `_ready()` currently checks `if parent is Fighter:` to auto-resolve the fighter reference from the scene tree. This must change to `if parent is FighterBody:`. Without this fix, `PlayerBrain` will never bind to its parent in `fighter_demo.tscn` and all player intents become no-ops — the game will not accept input.

Both changes are required; either one alone is insufficient. The export type change lets the editor wire the reference, and the auto-binding guard lets scene-tree resolution work at runtime.

## Stance System — Deferred

The spec's `fighter/stance_system.gd` (owns stance transition rules, `(stance, strike_dir) → Strike` lookup, parry stance-match) is **not created at Phase 2**. Stance state at Phase 2 lives as the `weapon_type` string on the forked controller, with the `Stance → weapon_type_string` mapping in the brain layer. `stance_system.gd` arrives in Phase 3 when it has an actual job.

## `weapon_change_started` Bypass

Calling `_on_weapon_change_ended(weapon_type)` directly on the animation tree **skips** the souls flow that normally emits `weapon_change_started` first (which triggers a sheath/draw animation via the `WeaponChange` oneshot). This is deliberate: a stance change should be a visual snap to the new movement set, not a sheath/draw animation.

**Risk:** If the souls code expects `weapon_change_started` to have been emitted first (e.g., state machine invariants, a guard that prevents action during weapon swap), the bypass could produce an inconsistent state. The plan will verify this by reading the controller's `weapon_change_started` handler and checking whether it sets flags that `_on_weapon_change_ended` depends on. If it does, we emit a synthetic `weapon_change_started` first, then immediately call `_on_weapon_change_ended`.

## Tests

### `test_fighter_states.gd` (updated)

Updated to assert against `FighterBody` instead of the deleted `Fighter` class. Coverage:

- State initializes correctly at spawn.
- `intent_move(dir)` updates `fighter.input_dir`.
- `intent_sprint(true)` flips state to `SPRINT` (or equivalent souls state name).
- `intent_change_stance(Stance.UPPER)` sets `fighter.weapon_type` to `"HEAVY"`.
- `intent_change_stance(Stance.MIDDLE)` sets `fighter.weapon_type` to `"SLASH"`.
- `intent_change_stance(Stance.LOWER)` is a no-op (weapon_type unchanged).

### `test_fighter_anim_wiring.gd` (new)

Headless smoke test. Loads `fighter_demo.tscn` into a SceneTree and asserts:

1. Both fighters' `anim_state_tree` nodes resolve to a non-null `AnimationTree`.
2. `anim_state_tree.fighter_node == fighter` (reverse reference wired).
3. `get("parameters/MovementStates/SLASH_tree/MoveStrafe/blend_position")` returns a `Vector2` (proves the sub-tree parameter path exists).
4. Same for `HEAVY_tree`.
5. `fighter.weapon_type == "SLASH"` at spawn (default MIDDLE stance).
6. Calling the brain's `intent_change_stance(Stance.UPPER)` and asserting `fighter.weapon_type == "HEAVY"` afterward.

### `test_fighter_cam.gd` (unchanged)

Pure-math tests for FighterCam orbit. No Phase 2 changes.

### Manual F5 checklist

Items 1–10 from the Exit Criterion section above.

## Risks and Open Questions

1. **Souls controller method names.** The plan will read `character_body_souls_base.gd` line-by-line and name exact method signatures for `intent_sprint`, `intent_strike`, and `intent_change_stance` translation. Those details are intentionally not in this spec because they are implementation specifics, not design decisions.

2. **Strip surface in `fighter_body.gd`.** The souls controller is ~700 lines with cross-referencing methods. The plan will list each function to delete with its line number, not delegate the judgment to the executor.

3. **HP field coexistence.** The souls HP field and the spec's `LimbHealth` are incompatible. Phase 2 leaves HP alone so the controller compiles. Phase 4 replaces it. Until Phase 4, taking damage would decrement an unused HP field and the souls death flow could trigger — Phase 2 is pre-combat so this should not fire in practice.

4. **`weapon_change_started` bypass safety.** See the dedicated section above.

5. **Hard `$`-path references to stripped nodes.** If `fighter_body.gd` retains `$GUI`, `$HealthSystem`, etc. references after stripping, they crash at runtime. The plan will grep the controller for all `$`-paths and add matches that point at stripped nodes to the delete list.

6. **`LADDER_tree` inside the AnimationTree graph.** Deleting a sub-state-machine from an AnimationTree resource in a `.tscn` file via text edits is risky — the graph resource is a single serialized blob with internal index-based references. If deleting `LADDER_tree` cleanly is not feasible from text, it stays (orphaned but harmless — no code references it after the ladder handler is stripped from the animation tree script).

7. **Phase 1 test compatibility.** `test_fighter_states.gd` references the deleted `Fighter` class. Updated to use `FighterBody`. State enum names may differ (`STRAFING` vs `FREE`, `SPRINTING` vs `SPRINT`); the plan maps these when it reads the souls controller.

8. **Stance legibility** — the fundamental risk this phase exists to close. The gate criterion is binary: if MIDDLE (Light movement set) and UPPER (Heavy movement set) are not visibly distinct when playing the game, Phase 2 fails. No Phase 3 plan is written until this gate passes.

## What This Spec Does NOT Cover

- Sim-clock-authoritative strike timing (Phase 3).
- Strike resources / `.tres` authoring (Phase 3).
- HitResolver / LimbHealth / damage model (Phase 4).
- Parry wiring / dodge i-frames (Phase 5, though the fork includes the souls kernels for both).
- AIBrain / round flow (Phase 6).
- Sub-tree rename (`SLASH_tree` → `MIDDLE_tree`) — deferred unless it becomes confusing in practice.
- LOWER stance — requires new animations, no timeline.
- The full LT+D-pad stance-select chord — arrives when LOWER stance exists.
