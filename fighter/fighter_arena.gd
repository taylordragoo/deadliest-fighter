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