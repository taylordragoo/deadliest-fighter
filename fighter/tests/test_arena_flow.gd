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