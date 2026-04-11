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
