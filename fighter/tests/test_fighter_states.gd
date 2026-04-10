# fighter/tests/test_fighter_states.gd
# Runtime tests for FighterBody state transitions. Instantiates two bare
# FighterBodies in a temporary root, pokes their intents, and checks state.
#
# Run headless:  godot --headless --script fighter/tests/test_fighter_states.gd
extends "res://fighter/tests/test_runner.gd"

const FighterBodyScript = preload("res://fighter/fighter_body.gd")

var _ran: bool = false

func _init() -> void:
	print("=== %s ===" % get_script().resource_path.get_file())

func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run_all_tests()
	print("\nResults: %d passed, %d failed" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)
	return false

func _run_all_tests() -> void:
	_test_initial_state_is_free()
	_test_sprint_held_transitions_to_sprint()
	_test_sprint_released_in_range_and_facing_reengages()
	_test_sprint_released_far_away_stays_sprint()
	_test_sprint_released_facing_away_stays_sprint()
	_test_stance_change_upper()
	_test_stance_change_middle()
	_test_stance_change_lower_is_noop()

# -- Helpers --------------------------------------------------------------

func _make_fighter_pair(a_pos: Vector3, b_pos: Vector3) -> Array[FighterBody]:
	var a: FighterBody = FighterBodyScript.new()
	var b: FighterBody = FighterBodyScript.new()
	a.name = "A"
	b.name = "B"
	get_root().add_child(a)
	get_root().add_child(b)
	a.position = a_pos
	b.position = b_pos
	a.opponent = b
	b.opponent = a
	# Force state to FREE (skip the STATIC_ACTION → FREE startup await)
	a.current_state = FighterBody.state.FREE
	b.current_state = FighterBody.state.FREE
	# Face A toward B
	var to_b := (b_pos - a_pos)
	to_b.y = 0
	a.rotation.y = atan2(to_b.x, to_b.z) + PI
	return [a, b]

func _teardown(pair: Array[FighterBody]) -> void:
	for f in pair:
		f.queue_free()

# -- Tests ----------------------------------------------------------------

func _test_initial_state_is_free() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: FighterBody = pair[0]
	# We forced FREE in the helper; the real startup goes STATIC_ACTION → FREE via await.
	assert_eq(a.current_state, FighterBody.state.FREE, "fighter starts in FREE (after forced set)")
	_teardown(pair)

func _test_sprint_held_transitions_to_sprint() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: FighterBody = pair[0]
	a.intent_sprint(true)
	assert_eq(a.current_state, FighterBody.state.SPRINT, "sprint held flips FREE -> SPRINT")
	_teardown(pair)

func _test_sprint_released_in_range_and_facing_reengages() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: FighterBody = pair[0]
	a.current_state = FighterBody.state.SPRINT
	a.intent_sprint(false)
	assert_eq(a.current_state, FighterBody.state.FREE, "sprint released within range, facing -> FREE")
	_teardown(pair)

func _test_sprint_released_far_away_stays_sprint() -> void:
	var pair := _make_fighter_pair(Vector3(-20, 0, 0), Vector3(0, 0, 0))
	var a: FighterBody = pair[0]
	a.current_state = FighterBody.state.SPRINT
	a.intent_sprint(false)
	assert_eq(a.current_state, FighterBody.state.SPRINT, "sprint released far away stays SPRINT")
	_teardown(pair)

func _test_sprint_released_facing_away_stays_sprint() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: FighterBody = pair[0]
	a.rotation.y += PI  # Face away from B
	a.current_state = FighterBody.state.SPRINT
	a.intent_sprint(false)
	assert_eq(a.current_state, FighterBody.state.SPRINT, "sprint released facing away stays SPRINT")
	_teardown(pair)

func _test_stance_change_upper() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: FighterBody = pair[0]
	a.intent_change_stance(FighterBody.Stance.UPPER)
	assert_eq(a.weapon_type, "HEAVY", "stance UPPER sets weapon_type to HEAVY")
	_teardown(pair)

func _test_stance_change_middle() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: FighterBody = pair[0]
	a.intent_change_stance(FighterBody.Stance.UPPER)
	a.intent_change_stance(FighterBody.Stance.MIDDLE)
	assert_eq(a.weapon_type, "SLASH", "stance MIDDLE sets weapon_type back to SLASH")
	_teardown(pair)

func _test_stance_change_lower_is_noop() -> void:
	var pair := _make_fighter_pair(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	var a: FighterBody = pair[0]
	a.intent_change_stance(FighterBody.Stance.LOWER)
	assert_eq(a.weapon_type, "SLASH", "stance LOWER is a no-op, weapon_type stays SLASH")
	_teardown(pair)
