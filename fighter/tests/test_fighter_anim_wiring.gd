# fighter/tests/test_fighter_anim_wiring.gd
# Headless smoke test for fighter scene wiring. Loads fighter_demo.tscn
# and verifies that FighterBody ↔ FighterAnimationTree references resolve
# and the stance sub-tree parameter paths exist.
#
# Run headless:  godot --headless --script fighter/tests/test_fighter_anim_wiring.gd
#
# NOTE: This test uses _process with await. Because _process does not
# propagate the coroutine, we gate the quit behind a _done flag that is
# set only after the awaited assertions complete. _process polls the flag
# each frame and quits when it's true.
extends "res://fighter/tests/test_runner.gd"

var _started: bool = false
var _done: bool = false

func _init() -> void:
	print("=== %s ===" % get_script().resource_path.get_file())

func _process(_delta: float) -> bool:
	if _done:
		print("\nResults: %d passed, %d failed" % [_pass_count, _fail_count])
		quit(0 if _fail_count == 0 else 1)
		return false
	if not _started:
		_started = true
		_run_all_tests_async()
	return false

func _run_all_tests_async() -> void:
	var demo_scene := load("res://fighter/fighter_demo.tscn")
	assert_true(demo_scene != null, "fighter_demo.tscn loads")
	if demo_scene == null:
		_done = true
		return

	var demo: Node3D = demo_scene.instantiate()
	get_root().add_child(demo)
	# Allow one frame for _ready() to run on all nodes
	await get_tree().process_frame

	var fighter_a: FighterBody = demo.get_node_or_null("FighterA") as FighterBody
	var fighter_b: FighterBody = demo.get_node_or_null("FighterB") as FighterBody

	assert_true(fighter_a != null, "FighterA resolves as FighterBody")
	assert_true(fighter_b != null, "FighterB resolves as FighterBody")
	if fighter_a == null or fighter_b == null:
		demo.queue_free()
		_done = true
		return

	# Check anim_state_tree references
	assert_true(fighter_a.anim_state_tree != null, "FighterA.anim_state_tree is set")
	assert_true(fighter_b.anim_state_tree != null, "FighterB.anim_state_tree is set")

	if fighter_a.anim_state_tree:
		assert_true(
			fighter_a.anim_state_tree.fighter_node == fighter_a,
			"FighterA.anim_state_tree.fighter_node == FighterA"
		)
		# Verify SLASH_tree (MIDDLE) parameter path exists
		var slash_blend = fighter_a.anim_state_tree.get(
			"parameters/MovementStates/SLASH_tree/MoveStrafe/blend_position")
		assert_true(slash_blend is Vector2, "SLASH_tree MoveStrafe blend_position is a Vector2")
		# Verify HEAVY_tree (UPPER) parameter path exists
		var heavy_blend = fighter_a.anim_state_tree.get(
			"parameters/MovementStates/HEAVY_tree/MoveStrafe/blend_position")
		assert_true(heavy_blend is Vector2, "HEAVY_tree MoveStrafe blend_position is a Vector2")

	# Verify default weapon_type (stance)
	assert_eq(fighter_a.weapon_type, "SLASH", "FighterA defaults to SLASH (MIDDLE stance)")

	# Verify stance change updates weapon_type
	fighter_a.intent_change_stance(FighterBody.Stance.UPPER)
	assert_eq(fighter_a.weapon_type, "HEAVY", "After intent_change_stance(UPPER), weapon_type is HEAVY")

	# Verify PlayerBrain bound to FighterA
	var brain: PlayerBrain = demo.get_node_or_null("FighterA/PlayerBrain") as PlayerBrain
	assert_true(brain != null, "PlayerBrain node exists under FighterA")
	if brain:
		assert_true(brain.fighter == fighter_a, "PlayerBrain.fighter == FighterA")

	demo.queue_free()
	_done = true
