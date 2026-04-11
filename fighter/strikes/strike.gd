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
