# fighter/fighter_cam.gd
# FighterCam — midpoint-orbit camera. NOT a SpringArm3D.
# Its position is computed every physics frame from the positions of the
# two fighters it tracks. It sits on a ring around their midpoint, always
# side-on to the line between them.
#
# The actual orbit math lives in static methods so it's testable without
# a scene tree.
class_name FighterCam
extends Camera3D

# --- Tracked fighters ---
## NodePaths to the two tracked fighters, resolved in _ready(). Use these
## from the .tscn (Godot does not auto-resolve typed Node3D exports from
## NodePath strings in scene files). Code can also set fighter_a/fighter_b
## directly via set_fighters() — the resolver only runs when they're null.
@export var fighter_a_path: NodePath
@export var fighter_b_path: NodePath
var fighter_a: Node3D
var fighter_b: Node3D

# --- Orbit tuning (starting values from the spec) ---
@export_group("Orbit tuning")
@export var radius_ratio: float = 1.2
@export var radius_base: float = 2.5
@export var min_radius: float = 3.0
@export var max_radius: float = 9.0
@export var cam_height: float = 1.6
@export var framing_height_offset: float = 0.9
@export var min_tracking_dist: float = 0.5
@export var radius_lerp_weight: float = 0.08
@export var side_bias: float = 0.0

# --- Runtime state ---
var _cam_radius: float
var _last_stable_line_yaw: float = 0.0

func _ready() -> void:
	_cam_radius = radius_base  # fallback if no fighters wired

	# Wait one frame so the sibling fighters have entered the tree before
	# we walk the NodePaths. set_fighters() can also have been called from
	# code, in which case we leave fighter_a/fighter_b alone.
	await get_tree().process_frame
	if fighter_a == null and not fighter_a_path.is_empty():
		fighter_a = get_node_or_null(fighter_a_path) as Node3D
	if fighter_b == null and not fighter_b_path.is_empty():
		fighter_b = get_node_or_null(fighter_b_path) as Node3D

	# Seed orbit state from the current fighter positions so the first
	# rendered frame doesn't pop from radius_base to the real target_radius.
	if fighter_a and fighter_b:
		var line: Vector3 = fighter_b.global_position - fighter_a.global_position
		var dist: float = line.length()
		if dist >= min_tracking_dist:
			_last_stable_line_yaw = atan2(line.x, line.z)
		_cam_radius = compute_target_radius(dist, radius_ratio, radius_base, min_radius, max_radius)
		# Snap the camera into its computed orbit position immediately so
		# the opening shot is properly framed instead of easing in over
		# several frames from the world origin.
		_update_orbit()

func _physics_process(_delta: float) -> void:
	if fighter_a == null or fighter_b == null:
		return
	_update_orbit()

## Assigns the two fighters this camera will track.
## @param a First fighter Node3D.
## @param b Second fighter Node3D.
func set_fighters(a: Node3D, b: Node3D) -> void:
	fighter_a = a
	fighter_b = b

## Called every physics tick when both fighters are set. Combines:
##  - midpoint tracking
##  - line-yaw computation with short-line-protection (clinch case)
##  - target-radius lerp for smooth zoom
##  - camera position on the orbit ring
##  - look-at the midpoint with a small vertical offset
func _update_orbit() -> void:
	var a_pos: Vector3 = fighter_a.global_position
	var b_pos: Vector3 = fighter_b.global_position
	var mid: Vector3 = compute_midpoint(a_pos, b_pos)

	var line: Vector3 = b_pos - a_pos
	var dist: float = line.length()

	var line_yaw: float
	if dist < min_tracking_dist:
		line_yaw = _last_stable_line_yaw
	else:
		line_yaw = atan2(line.x, line.z)
		_last_stable_line_yaw = line_yaw

	var target_radius: float = compute_target_radius(dist, radius_ratio, radius_base, min_radius, max_radius)
	_cam_radius = lerp(_cam_radius, target_radius, radius_lerp_weight)

	global_position = compute_orbit_position(mid, line_yaw, _cam_radius, cam_height, side_bias)
	look_at(mid + Vector3.UP * framing_height_offset, Vector3.UP)

# --- Pure static helpers (testable without a scene tree) ---

## Returns the midpoint between two positions.
## @param a First position.
## @param b Second position.
## @return The average of a and b.
static func compute_midpoint(a: Vector3, b: Vector3) -> Vector3:
	return (a + b) * 0.5

## Computes the target camera radius from the distance between fighters,
## clamped to [mn, mx].
## @param dist Distance between the two fighters.
## @param ratio Scales the contribution of dist to the radius.
## @param base Additive baseline radius.
## @param mn Minimum allowed radius.
## @param mx Maximum allowed radius.
## @return Clamped camera radius.
static func compute_target_radius(dist: float, ratio: float, base: float, mn: float, mx: float) -> float:
	return clamp(dist * ratio + base, mn, mx)

## Computes the camera's world position on the orbit ring.
## The camera sits perpendicular to the line between fighters, offset from mid.
## @param mid Midpoint between the two fighters.
## @param line_yaw Yaw angle (radians) of the line from fighter_a to fighter_b.
## @param cam_radius Horizontal distance from mid to camera.
## @param cam_height Vertical offset from mid.y to camera.y.
## @param side_bias Additional yaw offset (radians) for manual side adjustment.
## @return World-space camera position.
static func compute_orbit_position(mid: Vector3, line_yaw: float, cam_radius: float, cam_height: float, side_bias: float) -> Vector3:
	var cam_yaw := line_yaw + PI * 0.5 + side_bias
	var pos := mid + Vector3(sin(cam_yaw), 0, cos(cam_yaw)) * cam_radius
	pos.y = mid.y + cam_height
	return pos
