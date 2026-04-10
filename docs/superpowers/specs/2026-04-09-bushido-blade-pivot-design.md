# Bushido Blade Pivot — Design Spec

**Date:** 2026-04-09
**Project:** deadliest-fighter (formerly "Cat's Godot 4 Souls-Like Template & Asset Pack")
**Status:** Design approved; implementation plan pending.

## Summary

Pivot the existing Godot 4.7 souls-like template into **deadliest-fighter**, a 1v1 fighting game in the spirit of **Bushido Blade**. Two fighters, locked on by default but free to rotate around each other in 3D; a camera that stays side-on to the line between them; pure-lethality damage where a clean hit to the torso or head ends a round, and limb hits cripple rather than chip; stance-based combat where attack and parry are read-based, not execution-based.

The spec defines a **Playground MVP** that proves the core feel against an AI opponent in a single dojo arena with one weapon. Local 2-player, character select, multiple weapons, full AI, and netplay are explicitly out of scope for MVP but are not blocked by the architecture.

## Pillars (the non-negotiables)

| Pillar | Choice | Rationale |
|---|---|---|
| Lethality | Pure. Hit-location based, limb crippling, no HP bar. | This is the single most identifying feature of Bushido Blade. Without it, the pivot is cosmetic. |
| Combat vocabulary | Stance-based (UPPER / MIDDLE / LOWER with directional strikes); MVP ships with UPPER + MIDDLE only. | Matches the Bushido Blade ideal; scoped down for MVP because stance animations don't yet exist. |
| Movement | Soft-lock with break-lock. Auto-face opponent by default; sprint button breaks lock and enters free movement. | Matches the brief ("locked in but can rotate around") with a discoverable verb — sprint *is* the break-lock action, not a mystery threshold. |
| Camera | Midpoint-orbit (Bushido Blade style). Camera sits on a ring around the midpoint, always side-on to the line between fighters. | The feel the user specifically called out. Not a spring arm; not the template's FollowCam. |
| Parry | Stance-matched as target; timing-only as MVP fallback, gated by a single flag. | Gives MVP an achievable parry while preserving the deeper target. |
| MVP | Playground MVP. 1 player vs 1 AI, 1 arena, 1 weapon. Prove the feel. | Smallest scope that answers the only question that matters: "does this feel right?" |
| Netplay | Future, not MVP. Architecture preserves the option. | The design avoids choices that would corner us — sim clock authoritative, HitResolver pure, intents as the brain→fighter contract — but does not attempt to solve netplay. |

## Architecture

### Directory layout

A new top-level `fighter/` module, parallel to the existing `player/` and `enemy/` directories. The existing souls directories are **not modified**; they remain as a reference implementation that the souls demo scene (`demo_level/world_castle.tscn`) continues to run against.

`fighter_body.gd`, `fighter_body.tscn`, and `fighter_animation_tree.gd` are **forks** of the equivalent files under `player/` (`character_body_souls_base.gd`, `character_body_souls_base.tscn`, `souls_animation_tree.gd`). Forks are maintained as independent copies — souls files are never edited. Future souls-template updates do not propagate. The fork reuses the souls template's proven strafe movement, rotation, 2D blend-space animation math, weapon-swap sub-tree machinery (repurposed as stance swap), parry kernel, dodge i-frames, and attack signal phasing instead of reimplementing them.

```
fighter/
├── fighter_body.gd            # FighterBody — forked from CharacterBodySoulsBase, stripped of souls systems
├── fighter_body.tscn          # Fighter scene — forked from character_body_souls_base.tscn, stripped
├── fighter_brain.gd           # FighterBrain — abstract base for "who drives this fighter"
├── fighter_animation_tree.gd  # FighterAnimationTree — forked from souls_animation_tree.gd, stripped
├── brains/
│   ├── player_brain.gd        # reads Input actions, emits high-level intents
│   └── ai_brain.gd            # runs ~5-rule MVP AI, emits the same high-level intents
├── stance_system.gd           # StanceSystem — owns current stance, stance transitions, stance→strike lookup
├── strikes/
│   ├── strike.gd              # Strike resource class
│   └── *.tres                 # Strike data: upper_horizontal, middle_horizontal, ...
├── hit_resolver.gd            # HitResolver — pure function: strike + target_state → HitOutcome
├── limb_health.gd             # LimbHealth struct and Integrity enum
├── fighter_cam.gd             # FighterCam — midpoint-orbit camera (not a SpringArm3D)
├── fighter_arena.gd           # FighterArena — round state, spawn points, round reset
├── fighter_hud.gd             # FighterHUD — stance readout, limb state, round indicator
├── fighter_demo.tscn          # Minimal dojo scene: Arena + 2 Fighters + Cam + HUD
└── tests/
    └── test_hit_resolver.gd   # Hand-rolled unit test script, runs headless via --script
```

### Fighter + Brain separation (the central idea)

There is **one** `FighterBody` class (forked from the souls `CharacterBodySoulsBase`), representing a combatant's body, state, and simulation. Each FighterBody has exactly one **`FighterBrain`** attached — either a `PlayerBrain` (reads `Input.*`) or an `AIBrain` (runs decision logic). Both emit the same high-level intents through method calls on the fighter.

This wraps a **fork** of the souls `CharacterBodySoulsBase` (copied into `fighter/fighter_body.gd`, stripped of ladder/inventory/item/interact/gadget systems) with a brain abstraction. We reuse the souls template's proven movement, rotation, strafe blending, weapon-swap machinery (repurposed as stance swap), parry kernel, dodge i-frames, and attack signal chain, instead of reimplementing them. The original `player/CharacterBodySoulsBase` is never modified and the souls demo scene continues to function as a reference. This makes local 2P trivial (instantiate two FighterBodies, attach two `PlayerBrain`s), player-vs-AI and AI-vs-AI free, and netplay-friendly (intents are a natural wire format).

### Subsystem ownership

- **Fighter** owns: `CharacterBody3D` movement, current state enum, stance, `LimbHealth`, animation tree hookup, equipment mount points, event signals. Single source of truth for "what is this combatant doing right now."
- **FighterBrain** owns: decision-making. Reads its own fighter's state + an opponent reference; outputs intents. Has no direct access to physics.
- **StanceSystem** owns: stance transition rules, `(stance, strike_dir) → Strike` lookup, stance-match lookup for parries.
- **HitResolver** owns: given a strike and a target's state, return a `HitOutcome`. Pure, stateless.
- **FighterCam** owns: its position/rotation relative to the midpoint of its two tracked fighters. Knows nothing about combat.
- **FighterArena** owns: round state, spawn points, round-reset orchestration, win condition.
- **FighterHUD** owns: UI, reads fighter state via signals only.

**What we are NOT building in this module**: inventory, ladders, interactables, item system, spawn sites, patrol paths, eye-cone targeting system. The opponent is the target, always, held as a direct reference.

### Communication conventions

- **Fighter ↔ subsystems** inside the fighter: signal-driven, matching the template's existing style (it's a good fit for animation-synced actions).
- **Brain → Fighter**: direct method calls (the intent surface below). Brain never holds a physics reference; it calls `fighter.intent_*()` methods.
- **Fighter → Brain / HUD / Arena**: signals.
- **HitResolver**: called directly (it's pure, so signals would be wrong semantics).

## Fighter state machine

```
SPAWN       — brief intro pose at round start, no input accepted
READY       — idle parent; accepts all intents. Leaf states:
  STRAFING    — locked on, walking/jogging around opponent
  SPRINTING   — lock broken, free movement, sprint speed
WINDING_UP  — strike started, hitbox not yet active, interruptible
STRIKING    — hitbox active, committed (no new input)
RECOVERING  — post-strike vulnerability, cannot act but can be hit/parried
PARRYING    — active parry frames
DODGING     — i-frame roll, cannot be hit, cannot act
HURT        — took a non-lethal hit, brief stagger
DEAD        — round over, awaiting arena reset
```

`current_state` holds the leaf value; `READY` is conceptual in prose only. **CRIPPLED is a modifier, not a state** — a fighter can be STRAFING with a crippled arm. The crippled flag changes which strikes/stances are available and how animations blend, but doesn't take over the state machine.

**What's gone from the souls template**: `LADDER`, the blurry `STATIC_ACTION`/`DYNAMIC_ACTION` pair, and the dual-meaning `ATTACK` (used in the template as both a state and a signal).

### Movement sub-model (inside READY)

- **STRAFING** (default, locked): stick X = strafe around opponent; stick Y = close/retreat along the line between fighters. Facing auto-slerps to the opponent every physics tick (reusing the template's slerp-to-target-yaw math from `rotate_player()`). Speed = walk/jog.
- **SPRINTING** (lock broken): stick = free 3D movement relative to camera; fighter rotates to face movement direction; faster. Entered by holding the sprint button, which auto-breaks lock. On sprint release: if the fighter is facing the opponent within a re-engage range, transition back to STRAFING; otherwise stay in free movement until next re-engage opportunity. Attacking while sprinting auto-breaks sprint and forces re-lock.
- **Dodge** is an action that transitions out of either sub-state. Dodge has i-frames throughout its animation. **A successful dodge does not create a counter-stagger** — it grants positional advantage only. Parry grants openings, dodge grants distance. Different mental models by design.

## Combat vocabulary

### Stance system

```
enum Stance    { UPPER, MIDDLE, LOWER, SHEATHED }   # MVP: UPPER + MIDDLE only
enum StrikeDir { THRUST, SLASH_HORIZONTAL, SLASH_DIAGONAL }   # MVP: SLASH_HORIZONTAL only
```

A `Strike` is a Godot `Resource`:

```gdscript
class_name Strike extends Resource

@export var strike_id        : String            # e.g. "upper_horizontal_slash"
@export var hit_line         : HitLine           # HIGH | MID | LOW — what target stance must match to parry
@export var wind_up_time     : float             # authoritative sim-clock duration
@export var active_time      : float
@export var recover_time     : float
@export var damage_profile   : DamageProfile
@export var animation_name   : String            # animation tree oneshot name
```

MVP ships with 2–3 Strike resources hand-authored as `.tres` files. Adding strikes is a data edit, not a code edit.

### Stance transitions and parry matching

Stances have a **change-cost**: switching costs a short transition window (~0.2s) during which you are neither in the old stance nor the new one — you cannot strike, you cannot parry. This is the balancing lever that makes stance-matching meaningful. Without it, a player could react to any incoming strike by flipping to match. With it, feinting becomes possible (show upper stance, flip to lower as the opponent commits to an upper parry).

**Parry succeeds when:** `parrying_fighter.stance.hit_line == incoming_strike.hit_line` AND `parrying_fighter.state == PARRYING`. Otherwise the strike resolves normally.

**MVP fallback wiring:** a single boolean `stance_match_required` on the Fighter. When `false`, parry ignores the hit_line check and parries any strike within its window (classic souls-style timing parry). When `true`, the stance-match rule engages. The code path is the same; only the predicate changes. MVP ships with `false`; we flip it to `true` when stances are visually distinct enough to be read.

### Sim-clock authoritative timing (a departure from the template)

In the souls template, action timings are `anim_length * 0.3`-style fractions computed at runtime from whatever animation happens to be playing. That's fine for prototyping but makes combat impossible to tune or unit-test (the same strike behaves differently if anim length wobbles) and makes cross-client determinism impossible.

**For the fighter, strike timings are declared on the Strike resource and enforced by the Fighter state machine**, with the animation as visualization. The animation tree still drives what's on screen, but the sim clock is authoritative. The existing `animation_measured` pattern is kept as a dev-time tuning aid (so you can see if your declared timings match your animation length), but at runtime the declared values win.

This decision is the single biggest foundational change for netplay viability — the sim needs to be reproducible from intents alone, not from timing that depends on local animation state.

## Damage model — limbs and HitResolver

### Limb model

```
LimbHealth:
    torso  : Integrity   # OK | WOUNDED
    head   : Integrity   # OK
    arm_l  : Integrity   # OK | CRIPPLED
    arm_r  : Integrity   # OK | CRIPPLED
    leg_l  : Integrity   # OK | CRIPPLED
    leg_r  : Integrity   # OK | CRIPPLED
```

No float HP. No damage numbers. Tiny enumerable state space for easy debugging and future testability.

**Effects of limb states:**
- **Head clean hit** → immediate DEAD. Round over.
- **Torso OK → WOUNDED** → not dead, visibly favoring the wound; any further clean torso or head hit kills.
- **Torso WOUNDED → torso or head** → DEAD.
- **Arm CRIPPLED** on dominant (weapon) arm → fighter loses their stance; forced into a "wounded stance" with a reduced strike set. Off-arm cripple is cosmetic at MVP (future: affects off-hand gadgets/guards).
- **Leg CRIPPLED** (either leg) → movement speed halved, dodge disabled, sprint disabled (cannot break lock). Pinned in place.
- **Both legs CRIPPLED** → the classic Bushido Blade "fighting from the ground" state. **Out of MVP scope**; first-leg-crippled fighter just fights standing but slowly for MVP.

Only the torso has a WOUNDED intermediate state — it exists specifically to give the "one more chance" Bushido Blade moment. Every other limb is binary.

### HitResolver — the pure function

```
HitResolver.resolve(strike: Strike, attacker: Fighter, target: Fighter) → HitOutcome
```

`HitOutcome` is a tagged union:

```
HitOutcome:
    MISS
    DODGED                       # target was in DODGING
    PARRIED(by_stance)           # target was in PARRYING with matching hit_line
    BLOCKED(by_stance)           # future, not MVP
    HIT(limb, lethal: bool)      # limb hit; lethal = does this kill the target
```

The resolver is a **pure function**: it reads attacker and target state but does not mutate them. The Fighter that owns the resolution reads the outcome and dispatches the consequences:

- `MISS` → nothing
- `DODGED` → nothing, attacker keeps their recovery
- `PARRIED` → attacker → RECOVERING with *extended* recovery (the punish window); target briefly vulnerable during their parry recover (risk/reward)
- `HIT` → target → HURT (non-lethal) or DEAD (lethal); apply limb state change; emit signals for HUD/animation

**Why pure:**
1. **Testable.** Unit tests without Godot engine: `assert_resolve("upper_horizontal", MIDDLE_stance, all_ok) == HIT(head, lethal=true)`.
2. **Deterministic.** Netplay later: same inputs → same output, no hidden RNG, no anim-timing leaks.
3. **Tunable.** All lethality logic lives in one file a designer can read top-to-bottom.

### Hit location model — strike-declared regions

We use **strike-declared hit regions**, not per-limb Area3D hitboxes. The `Strike` resource declares which limbs it targets, in priority order:

```
DamageProfile:
    hit_region_priority : Array[Limb]
        # examples (illustrative; MVP ships only upper/middle slashes):
        #   upper_slash  = [head, torso, arm_r, arm_l]
        #   middle_slash = [torso, arm_r, arm_l, head]
        #   lower_slash  = [leg_r, leg_l]   # future, once lower stance exists
    lethal_on_torso     : bool
    lethal_on_head      : bool
    limb_cripple        : bool
```

A single weapon Area3D (inherited from the template's equipment-system pattern) asks "did the blade enter the opponent's body volume during STRIKING?" — that's the connection check. Everything else is driven by the Strike resource.

This is abstract rather than physical, but it is the right choice for a lethality game:
- It is **readable**: "I was in MIDDLE stance, you were in UPPER; your slash resolved against my head" is a rule the player can learn.
- It is **deterministic by construction**: no dependence on animation kerning or physics-tick overlap order.
- It is **tunable as data**: changing a strike's hit priorities is editing a `.tres` file.

The rejected alternative (per-limb Area3Ds) has order-of-overlap nondeterminism across physics ticks, couples hit location to animation accuracy, and gives the player a less readable rule.

### Round flow (FighterArena)

1. Fighters spawn in SPAWN pose for ~1.5s.
2. Arena signals round start; fighters → STRAFING/READY.
3. Fighters simulate; any DEAD transition ends the round.
4. Arena resolves winner, shows result for ~2s.
5. Arena resets: respawns fighters, restores limb health, resets stances.

MVP is best-of-1 on an infinite loop. Best-of-N is a trivial layer to add later.

## Camera (FighterCam)

### Node shape

`FighterCam extends Camera3D`. **Not** a `SpringArm3D`. The souls `FollowCam` is a spring arm attached behind one character; this camera is not attached to any character — it's positioned in world space relative to the midpoint of the two fighters.

### Inputs per frame

Only three:
1. Positions of `fighter_a` and `fighter_b` (exported refs set by FighterArena at match start).
2. Arena bounds (optional, reserved for future wall avoidance).
3. Its own tunables.

The camera is a dumb follower of two transforms. It does not read player input. It does not read combat state. It does not care who's winning.

### Orbit math

```
mid       = (a.pos + b.pos) * 0.5
line      = b.pos - a.pos
dist      = line.length()
line_yaw  = atan2(line.x, line.z)

cam_yaw   = line_yaw + PI/2 + side_bias
cam_pos   = mid + Vector3(sin(cam_yaw), 0, cos(cam_yaw)) * cam_radius
cam_pos.y = mid.y + cam_height
cam.look_at(mid + Vector3.UP * framing_height_offset, Vector3.UP)
```

The camera is always side-on to the line between the fighters, at a consistent distance, looking at their midpoint. When either fighter moves, the camera sweeps its orbit angle to keep the same side-on framing. This is the Bushido Blade feel: the fighters rotate around each other and the camera sweeps with them.

### Dynamic distance

```
target_radius = clamp(dist * radius_ratio + radius_base, min_radius, max_radius)
cam_radius    = lerp(cam_radius, target_radius, 0.08)
```

Starting tunables:
- `radius_ratio = 1.2`
- `radius_base  = 2.5`
- `min_radius   = 3.0`
- `max_radius   = 9.0`
- `cam_height   = 1.6`
- `framing_height_offset = 0.9`

When a fighter sprints out far to break lock, the camera pulls back to `max_radius` and stops tracking distance; it keeps tracking midpoint and angle.

### Side bias

`side_bias` picks which side of the line the camera orbits — essentially which fighter is camera-left and which is camera-right. **MVP: side_bias is fixed at match start** based on spawn positions. It does not swap mid-round. A mid-round side swap is cool in theory but disorienting in practice; if playtesting surfaces a real need for it, it will be a future spec.

### Short-line protection (clinch case)

When `dist < min_tracking_dist` (~0.5 units), `line_yaw` becomes noisy. We freeze `line_yaw` at its last stable value until the fighters separate, preventing camera whip on clinches.

### What the camera does NOT do (MVP)

- No shake on hits.
- No zoom on kills.
- No tilt. `up` is always `Vector3.UP`.
- No wall avoidance. The MVP dojo is open; wall avoidance is added later when arenas have walls.

### Relation to the old FollowCam

Zero. `follow_cam_3d.gd` stays in `cameras/follow_cam/` for the souls demo. The two camera systems never touch.

## Input and the Brain contract

### The Brain → Fighter intent surface

Exactly seven intents:

```gdscript
fighter.intent_move(dir: Vector2)
fighter.intent_sprint(held: bool)
fighter.intent_change_stance(stance: Stance)
fighter.intent_strike(stance: Stance, dir: StrikeDir)
fighter.intent_parry()
fighter.intent_dodge(dir: Vector2)
fighter.intent_sheathe(sheathed: bool)
```

**Intents are requests, not commands.** The Fighter decides whether to honor them based on current state. `intent_strike` during RECOVERING is silently ignored — no error, no queue. The Brain never has to check "am I allowed?"; it tries, and the Fighter declines if no.

**Held vs. pressed:** `intent_move` and `intent_sprint` are continuous (called every frame); the rest are rising-edge one-shots.

**Input buffering is off for MVP.** Adding it later is an internal Fighter change, not a contract change.

### Fighter → subscribers signals

```
signal state_changed(new_state, old_state)
signal stance_changed(new_stance)
signal strike_started(strike)
signal strike_activated(strike)   # hitbox armed
signal strike_ended(strike)
signal parried_by(other_fighter)
signal hit_taken(outcome)
signal limb_state_changed(limb, new_state)
signal died
```

`AIBrain` subscribes to the opponent's signals to make decisions; `PlayerBrain` mostly doesn't need them; `FighterHUD` reads them heavily.

### PlayerBrain control scheme — gamepad (Xbox layout)

| Input | Action |
|---|---|
| Left stick | `intent_move(dir)`. STRAFING: X=strafe, Y=approach/retreat. SPRINTING: free movement. |
| Right stick | *unused at MVP* (reserved for right-stick-flick strike direction later) |
| LT (L2) | **Hold** to enter stance-select. D-pad up/down while held → UPPER/LOWER. Release → stay in last selected stance. **At MVP, only D-pad up is bound** (to UPPER); D-pad down is a no-op until LOWER stance animations exist. |
| RT (R2) | `intent_strike(current_stance, SLASH_HORIZONTAL)` |
| LB (L1) | `intent_parry()` |
| RB (R1) | `intent_dodge(move_dir)` |
| B / Circle | `intent_sprint(held)` |
| Y / Triangle | `intent_sheathe(toggle)` (reserved; no-op at MVP — see below) |
| A / X | *unused at MVP* |

Default stance is MIDDLE. Release LT without a direction → return to MIDDLE.

**`intent_sheathe` at MVP**: the intent exists in the contract so the brain→fighter surface is stable from day one, but the Fighter treats it as a no-op at MVP. It's reserved for future flair/round-start/forfeit behavior. No phase implements it. The binding exists so muscle memory is preserved once the feature lands, and so we don't have to change the contract later.

Rejected alternative: left-stick-click to cycle stances — too slow, physically awkward.

### PlayerBrain control scheme — keyboard

| Key | Action |
|---|---|
| WASD | Move |
| Shift (hold) | Sprint / break-lock |
| Space | Dodge |
| Left Mouse | Strike |
| Right Mouse | Parry |
| Q / E | Cycle stance down / up |
| R | Sheathe/draw |

Keyboard has slightly less expressive stance selection than gamepad. Acceptable for MVP.

### Input action namespace (for future local 2P)

`PlayerBrain` takes a `player_index` (0 or 1) and reads input via prefixed action names: `p0_move_up`, `p1_move_up`, etc. MVP registers only `p0_*` actions. When local 2P becomes real, we add `p1_*` actions and spawn a second `PlayerBrain(player_index=1)` — no changes to Fighter or PlayerBrain logic.

The existing souls template's input actions (`move_up`, `use_weapon_light`, etc.) stay unchanged in `project.godot`; we simply add a new `p0_*` set. Zero collision.

### AIBrain — MVP sketch

Minimum viable opponent, approximately 5 rules, approximately 150 lines of GDScript. Not a real AI subsystem; a placeholder to validate the brain contract end-to-end.

1. **Approach** — if not in engagement range, `intent_move` toward the opponent.
2. **Posture** — when in range, randomly change stance every ~1.5s.
3. **Strike** — roll a timer; strike with a small telegraph delay so the player can parry.
4. **React** — on opponent's `strike_started`, ~40% chance to parry, ~20% chance to dodge, else eat it.
5. **Retreat** — when any of its own limbs get crippled, back away briefly before re-engaging.

A real combat AI is a future subsystem.

### Rebindable keys

Not in MVP. Rebinding is a UI layer that doesn't touch Brain or Fighter and has no future cost to defer.

## MVP deliverable

Open Godot, press F5, and `fighter/fighter_demo.tscn` loads directly. The project's main scene is temporarily pointed at it during MVP development; the souls castle scene stays untouched but is not the default. What runs:

1. A flat dojo arena — single StaticBody3D floor, simple skybox, no walls.
2. Two fighters facing each other at 4m. One `PlayerBrain`, one `AIBrain`.
3. Both fighters use the template's existing male character mesh and sword rig. **No new art for MVP.**
4. Midpoint-orbit `FighterCam` frames both fighters.
5. Minimal HUD: player's stance indicator, 6 limb-state dots, a "Round X — Ready/Fight/Slain/Reset" overlay.
6. The full combat loop: move, sprint/break-lock, strafe, change stance, strike, parry, dodge, take lethal/crippling hits, die, round resets.

**MVP "done" criterion:** Play 10 rounds in a row against the AI without any of the following: camera flips sides unexpectedly, fighter gets stuck in a state, parry does the wrong thing, a strike fails to register, a round doesn't reset, controls don't respond. The game does not have to be **fun** yet — fun comes from tuning. It has to be **correct**.

### Explicit non-goals for MVP (deferred, not forgotten)

- More than one arena
- More than one weapon class / character model
- Main menu, pause, settings, options
- Rebindable controls
- Sound effects beyond what the template ships with
- Music, cinematic intros, cinematic kill cams
- Camera juice (hit shake, kill zoom, slo-mo)
- Both-legs-crippled prone fighting
- Local 2P (the next MVP, not this one)
- Best-of-N round system
- Visible wound effects on character models (blood, torn clothing)
- Character select, victory screen, win/loss announcer

## Phased build plan

Each phase ends in a *playable* state. You should be able to stop at any phase end and see progress.

### Phase 0 — Scaffolding
- Create `fighter/` directory; empty stubs for all modules.
- Create `fighter/fighter_demo.tscn`: flat floor, two placeholder CharacterBody3Ds, FighterCam.
- Add `p0_*` input actions to `project.godot`. Temporarily point `application/run/main_scene` at the fighter demo.
- **Do not touch** `player/`, `enemy/`, `demo_level/`, `cameras/`.
- **Exit:** F5 → two boxes on a floor, camera frames them.

### Phase 1 — Fighter body + Brain contract (no combat)
- Implement `Fighter` with movement, STRAFING state, rotation-to-opponent, full state enum (most states are empty stubs).
- Implement `FighterBrain` base + `PlayerBrain` with `intent_move` and `intent_sprint` only.
- Wire FighterCam to track both fighters.
- **Exit:** Move with stick; strafe around a static dummy Fighter; sprint breaks lock; releasing re-engages. Camera follows correctly.

### Phase 2 — Animation tree integration (looks right, no combat yet)
- **Fork** `player/character_body_souls_base.gd` → `fighter/fighter_body.gd`, `player/souls_animation_tree.gd` → `fighter/fighter_animation_tree.gd`, `player/character_body_souls_base.tscn` → `fighter/fighter_body.tscn`. Strip souls-specific systems (ladders, inventory, items, gadgets, interactables) from the copies. Wrap the fork with the Phase 1 brain abstraction.
- **Stance via weapon-swap:** The existing `SLASH_tree` / `HEAVY_tree` sub-trees in the AnimationTree's `MovementStates` become MIDDLE and UPPER stances respectively. The Light movement set (idle, walk, run, strafe) is MIDDLE; the Heavy set is UPPER. `intent_change_stance` maps `Stance.MIDDLE → "SLASH"` and `Stance.UPPER → "HEAVY"` and calls the existing weapon-swap mechanism. No new animations needed — the stance-legibility risk resolves to "yes, immediately."
- **This phase is still the early gate for stance legibility risk.** If MIDDLE and UPPER are not visibly distinct when playing the game, Phase 2 fails and no Phase 3 plan is written.
- **Exit:** Move/sprint as before, plus: press stance-select and see the character visibly shift pose between UPPER (Heavy movement set) and MIDDLE (Light movement set). Press strike and see Slash1 (MIDDLE) or Heavy1 (UPPER) play. Sword held in hand throughout. Full design: `docs/superpowers/specs/2026-04-09-phase-2-animation-tree-integration-design.md`.

### Phase 3 — Strike resources + sim-clock timing
- Create `Strike` resource class; author 2 Strike `.tres` files: `upper_horizontal`, `middle_horizontal`.
- Wire `intent_strike` through the state machine: WINDING_UP → STRIKING → RECOVERING, driven by sim clock with the animation as visualization.
- Connect an EquipmentSystem-style weapon hitbox; arm it during STRIKING.
- `HitResolver` returns only `MISS` or `HIT(torso, lethal=true)` at this phase — any clean contact = death.
- **Exit:** Fight the static dummy, hit it, dummy → DEAD, arena resets the round. One-shot kills feel correct.

### Phase 4 — Limb model + full HitResolver routing
- Implement `LimbHealth` and limb-state effects.
- HitResolver reads `Strike.hit_region_priority`, routes hits to limbs.
- Wire crippling effects: movement speed halved on leg cripple; stance loss on weapon-arm cripple.
- HUD shows limb state dots.
- **Exit:** Hit the dummy's leg → it moves slower. Hit its arm → it loses stance. Hit torso → dies. All three transitions visible, no state gets stuck.

### Phase 5 — Parry + Dodge defenses
- Implement `intent_parry` (timing-based MVP mode: `stance_match_required = false`).
- Implement `intent_dodge` with i-frames throughout.
- HitResolver returns `PARRIED` and `DODGED` outcomes; Fighter dispatches correctly.
- Flip `stance_match_required = true` and verify the wire is in place, even if stances aren't visually distinct enough to feel different yet.
- **Exit:** Parry a strike → attacker enters RECOVERING with a punish window. Dodge a strike with i-frames → keep positional advantage.

### Phase 6 — AIBrain + round flow
- Implement the ~150-line AIBrain from Section 5.
- Implement `FighterArena` round reset / spawn / death detection.
- Wire HUD's round state display.
- **Exit:** Play 10 rounds back-to-back against the AI. Rounds reset cleanly; no state gets stuck; combat loop is complete. **This is MVP done.**

### Phase 7 — Tuning + hardening
- Dedicated tuning pass: strike timings, parry window, dodge i-frame window, AI difficulty, camera radius/height.
- Fix bugs surfaced during Phase 6.
- Write `fighter/tests/test_hit_resolver.gd` — first unit test suite for the resolver.
- **Exit:** The 10-round "does it hold up?" test from the MVP definition passes cleanly.

## Animation tree strategy (the highest-risk integration)

The template's animation tree is the single trickiest piece to integrate. Explicit decisions:

**We copy, not subclass, not extend.** `souls_animation_tree.gd` is copied to `fighter_animation_tree.gd` and stripped. If we subclassed, every fighter animation fix would risk breaking the souls demo and vice versa. Separate files = zero coupling.

**Preserved from the souls tree**: the `MoveStrafe` 2D blend-space math (it's exactly right for a lock-on fighter), the oneshot mechanism for one-off actions, the `animation_measured` signal pattern (kept as a dev-time tuning aid).

**Removed from the souls tree**: per-weapon sub-tree system (`<WEAPON>_tree` nodes and the weapon-type swap logic), LADDER tree, all souls-specific signal handlers (`interact_started`, `ladder_started`, `use_item_started`, etc.).

**Stance legibility is the biggest animation risk.** If stances aren't visibly distinct on the existing rig with existing animations, the combat loop is illegible — players cannot read stance-matching if all stances look the same. Phase 2's exit criterion is designed to surface this risk before we build combat on top of it.

## Testing strategy

This codebase has no test framework today and the spec does **not** propose introducing one. `HitResolver` is designed as a pure function specifically because it is the single subsystem most likely to have subtle bugs and most valuable to test.

**Phase 7 delivers** `fighter/tests/test_hit_resolver.gd` — a `SceneTree` `MainLoop` script runnable via:

```
godot --headless --script fighter/tests/test_hit_resolver.gd
```

It hand-rolls assertions against a list of cases:

```gdscript
assert_resolve("upper_horizontal", MIDDLE, all_ok, HIT(head, lethal=true))
assert_resolve("upper_horizontal", UPPER_PARRYING, all_ok, PARRIED)
# ...
```

No GUT, no gdUnit, no dependencies. Good enough for the one subsystem that most needs it. Everything else is tested by "press F5 and play it," which is fine for MVP scale.

## Risks and open questions (known unknowns)

These are explicit known-unknowns, not things to pretend are solved.

1. **Stance visual legibility.** If MVP stances can't be made visibly distinct on the existing rig, the combat loop is illegible. *Mitigation*: Phase 2 gate. *Escalation*: source stance animations.
2. **Sprint / break-lock feel.** The "lock re-engages when facing opponent within range on sprint release" rule sounds right on paper but will need tuning. May reveal it needs to be smarter (e.g., gradual assisted re-engage).
3. **Camera side-bias fixed for the round.** If playtesting consistently shows players getting disoriented when their fighter sprints behind the opponent, a smart mid-round side-swap heuristic becomes a future spec.
4. **Determinism for netplay.** The sim is designed to *enable* determinism (sim clock authoritative, HitResolver pure, no runtime RNG in combat). But deterministic-across-machines is a higher bar than "no obvious nondeterminism": Godot's physics is not strictly deterministic cross-platform. When netplay becomes real, we will need either rollback with state reconciliation or lockstep with physics tick sync. This spec does not solve netplay; it does not block it.
5. **Template's timer-based animation phasing.** We're rejecting this pattern for the fighter's sim clock, but the AnimationTree still emits `animation_measured`, which our code subscribes to for dev-time tuning only. If animation lengths drift far from declared sim-clock timings, visuals will desync from sim. Flagged as an ongoing tuning concern.
6. **AI quality.** The ~5-rule AIBrain is explicitly a placeholder to validate the brain contract. Real AI that plays convincingly is a full future subsystem; MVP is not trying to solve this.

## What this spec does NOT cover (future specs)

Local 2P; netplay; character select; multiple weapons / character classes; full AI subsystem; arena art direction; sound design and music; UI polish; rebindable controls; monetization; a name for the game. Each of these gets its own spec when the time comes.

## Phase 2 Implementation Notes (2026-04-10)

Phase 0–2 are complete. The following divergences from the original spec were discovered during implementation and are documented here so that Phase 3+ plans account for them.

### State enum: kept souls states, not spec states

The spec prescribes `SPAWN, STRAFING, SPRINTING, WINDING_UP, STRIKING, RECOVERING, PARRYING, DODGING, HURT, DEAD` and explicitly removes `STATIC_ACTION`/`DYNAMIC_ACTION`. The implementation keeps the souls template's state enum: `SPAWN, FREE, STATIC_ACTION, DYNAMIC_ACTION, DODGE, SPRINT, ATTACK`.

**Why:** The forked animation tree's `advance_expression` strings, the action-phasing `await` chains (guard, parry, hurt, block, hard_landing), and the `set_strafe()`/`set_free_move()` branching all key off `STATIC_ACTION`/`DYNAMIC_ACTION`/`FREE`. Renaming to the spec's states would require rewriting ~15 advance_expressions in the serialized `.tscn` AnimationTree graph, plus all action methods. The cost is real; the benefit is naming clarity only.

**Phase 3 impact:** The single `ATTACK` state currently lumps wind-up, active, and recovery into one timer-phased coroutine (the souls template pattern). Phase 3's sim-clock authoritative timing needs to split `ATTACK` into `WINDING_UP`, `STRIKING`, `RECOVERING` — either as new enum values alongside the existing ones, or by refactoring the enum entirely. The Phase 3 plan must decide which approach.

### intent_strike signature simplified

The spec prescribes `intent_strike(stance: Stance, dir: StrikeDir)`. The implementation uses `intent_strike()` with no parameters — it reads the current stance from `weapon_type` implicitly. `StrikeDir` does not exist yet.

**Phase 3 impact:** When Strike resources are introduced, `intent_strike` will need a `dir` parameter (or the Strike lookup reads current stance + a default dir). The Phase 3 plan should define the final signature.

### StanceSystem is inline, not a separate class

The spec describes a dedicated `StanceSystem` node that owns stance transitions, `(stance, dir) → Strike` lookup, and stance-match logic for parries. The implementation puts stance logic directly on `FighterBody`: a `Stance` enum, a `STANCE_TO_WEAPON` dictionary, and `intent_change_stance()` that calls the animation tree's weapon-swap mechanism.

**Phase 3 impact:** Phase 3 can either extract a `StanceSystem` class or keep the logic on `FighterBody`. The current inline approach is simple and works well for 2 stances. If stance transition rules become complex (change-cost timing, cripple-forced stance loss), extraction may be warranted.

### Character mesh forward is +Z, not -Z

The spec's yaw math assumed the standard Godot convention (character forward = `-Z`), which is why `_face_opponent` used `atan2(x, z) + PI`. The forked character mesh's visual forward is actually `+Z`. The `+ PI` offset was removed.

**Impact on future code:** Any new code that computes facing yaw for this mesh should use `atan2(to_target.x, to_target.z)` without the `+ PI` offset. The `_freelook_rotate` quaternion slerp (used during sprint) also omits the offset and works correctly.

### Dormant AnimationTree sub-graphs require shims

The forked `fighter_body.tscn` contains serialized AnimationTree sub-graphs (Gadget, UseItem, Interacts) that are never entered at Phase 2 but whose `advance_expression` strings are evaluated by Godot during tree initialization. These expressions reference properties that were stripped during the fork.

Shims added:
- `FighterBody.gadget_type: String = "SHIELD"` — satisfies `fighter_node.gadget_type == "SHIELD"`
- `FighterBody.current_item: ItemStub` (inner class with `object_type: String = "NONE"`) — satisfies `fighter_node.current_item.object_type == "DRINK"` / `"THROWN"` / `== null`
- `FighterAnimationTree.interact_type: String = "GENERIC"` — satisfies `interact_type == "GENERIC"` (resolves against the tree script, not fighter_node)

These shims can be removed if/when the dormant sub-graphs are pruned from the AnimationTree resource itself (requires manual AnimationTree graph editing in Godot).

### animation_measured race condition in _ready()

The original plan's `_ready()` used `await get_tree().process_frame` for sibling opponent resolution before awaiting `anim_state_tree.animation_measured`. This introduced a 1-frame window during which the AnimationTree would fire `animation_measured` (from its first animation starting), causing the subsequent await to hang forever.

**Fix:** Opponent resolution is now synchronous (`get_node_or_null()` without frame skip). Siblings are already in the tree when `_ready()` runs in Godot 4 (children are added depth-first before any `_ready` fires).

**Lesson for future phases:** Avoid `await` before signal-awaits in `_ready()` — any intermediate frame skip risks missing signals that fire during tree initialization.

## Status

Phases 0–2 complete. Phase 2 gate passed (2026-04-10): two rigged fighters with stance-switching, striking, strafing, sprint break-lock, and midpoint-orbit camera. Next step: Phase 3 plan (Strike resources + sim-clock timing).
