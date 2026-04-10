# fighter/tests/test_fighter_states.gd
# Runtime tests for Fighter state transitions. Unlike test_fighter_cam.gd,
# these need a SceneTree because Fighter is a CharacterBody3D. We instantiate
# two bare Fighters in a temporary root, poke their intents, and check state.
#
# Run headless:  godot --headless --script fighter/tests/test_fighter_states.gd
#
# NOTE: Tests run in _process (not _init) because CharacterBody3D nodes only
# enter the tree after the SceneTree has finished initializing — add_child
# during _init leaves nodes with is_inside_tree()=false, so global_transform
# reads return identity and the facing/distance predicates break. _process
# fires after the tree is live, so global_position and global_transform.basis
# work correctly.
extends "res://fighter/tests/test_runner.gd"

const FighterScript = preload("res://fighter/fighter.gd")

var _ran: bool = false

func _init() -> void:
	# Do not call super._init(): it would run tests immediately (before the
	# SceneTree is live) and then quit. We defer test execution to _process.
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
	# Use position (local) not global_position: for root-level nodes local == world.
	# global_position's setter internally reads get_global_transform() which can
	# fail with "!is_inside_tree()" during _init; _process avoids that, but
	# position is still the safe choice.
	a.position = a_pos
	b.position = b_pos
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
