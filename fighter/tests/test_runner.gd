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
