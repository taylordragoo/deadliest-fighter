# fighter/tests/test_fighter_cam.gd
# Pure-math tests for FighterCam. Run headless:
#   godot --headless --script fighter/tests/test_fighter_cam.gd
extends "res://fighter/tests/test_runner.gd"

const FighterCam = preload("res://fighter/fighter_cam.gd")

func _run_all_tests() -> void:
	_test_midpoint_is_average()
	_test_midpoint_vertical_preserved()
	_test_target_radius_scales_with_dist()
	_test_target_radius_clamps_to_min()
	_test_target_radius_clamps_to_max()
	_test_orbit_position_is_perpendicular_to_line()
	_test_orbit_position_respects_cam_height()
	_test_orbit_position_at_cam_radius_from_mid()

func _test_midpoint_is_average() -> void:
	var mid = FighterCam.compute_midpoint(Vector3(-2, 0, 0), Vector3(2, 0, 0))
	assert_vec3_near(mid, Vector3.ZERO, 0.0001, "midpoint of (-2,0,0)+(2,0,0) = origin")

func _test_midpoint_vertical_preserved() -> void:
	var mid = FighterCam.compute_midpoint(Vector3(0, 1, 0), Vector3(0, 3, 0))
	assert_vec3_near(mid, Vector3(0, 2, 0), 0.0001, "midpoint preserves y component")

func _test_target_radius_scales_with_dist() -> void:
	# dist=4, ratio=1.2, base=2.5 -> 4*1.2 + 2.5 = 7.3
	var r = FighterCam.compute_target_radius(4.0, 1.2, 2.5, 3.0, 9.0)
	assert_near(r, 7.3, 0.0001, "radius scales linearly with dist before clamp")

func _test_target_radius_clamps_to_min() -> void:
	# tiny dist -> formula would give 2.5, but min=3.0 should clamp
	var r = FighterCam.compute_target_radius(0.0, 1.2, 2.5, 3.0, 9.0)
	assert_near(r, 3.0, 0.0001, "radius clamps to min_radius at dist 0")

func _test_target_radius_clamps_to_max() -> void:
	# dist=20 -> 20*1.2 + 2.5 = 26.5, max=9.0 should clamp
	var r = FighterCam.compute_target_radius(20.0, 1.2, 2.5, 3.0, 9.0)
	assert_near(r, 9.0, 0.0001, "radius clamps to max_radius at large dist")

func _test_orbit_position_is_perpendicular_to_line() -> void:
	# Fighters on x-axis: line direction is +X, line_yaw = atan2(1, 0) = PI/2.
	# The camera should sit on the z-axis (perpendicular to +X).
	var mid := Vector3.ZERO
	var line_yaw := atan2(1.0, 0.0)  # PI/2
	var pos = FighterCam.compute_orbit_position(mid, line_yaw, 5.0, 0.0, 0.0)
	# Perpendicular to +X through origin is the z-axis. |pos.x| should be ~0.
	assert_near(pos.x, 0.0, 0.0001, "perpendicular to X-axis line has x=0")
	assert_near(abs(pos.z), 5.0, 0.0001, "camera sits at cam_radius along perpendicular")

func _test_orbit_position_respects_cam_height() -> void:
	var pos = FighterCam.compute_orbit_position(Vector3(0, 2, 0), 0.0, 5.0, 1.5, 0.0)
	assert_near(pos.y, 3.5, 0.0001, "cam y = mid.y + cam_height")

func _test_orbit_position_at_cam_radius_from_mid() -> void:
	# Distance from camera to mid (horizontal only) should always equal cam_radius.
	var mid := Vector3(3, 0, 4)
	var line_yaw := 0.7
	var pos = FighterCam.compute_orbit_position(mid, line_yaw, 6.0, 0.0, 0.0)
	var horizontal := Vector3(pos.x - mid.x, 0, pos.z - mid.z)
	assert_near(horizontal.length(), 6.0, 0.0001, "horizontal distance from mid = cam_radius")
