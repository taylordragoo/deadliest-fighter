# fighter/brains/player_brain.gd
# PlayerBrain — reads prefixed input actions (p<index>_*) and emits intents
# to its fighter. The player_index lets us add a second PlayerBrain later
# for local 2P by just registering p1_* actions — zero changes to this script.
class_name PlayerBrain
extends FighterBrain

## Which input action prefix to use. 0 -> "p0_...", 1 -> "p1_...", etc.
@export_range(0, 3) var player_index: int = 0

var _move_up: StringName
var _move_down: StringName
var _move_left: StringName
var _move_right: StringName
var _sprint: StringName

func _ready() -> void:
	super._ready()
	var p := "p%d_" % player_index
	_move_up    = StringName(p + "move_up")
	_move_down  = StringName(p + "move_down")
	_move_left  = StringName(p + "move_left")
	_move_right = StringName(p + "move_right")
	_sprint     = StringName(p + "sprint")

func _physics_process(_delta: float) -> void:
	if fighter == null:
		return
	var move := Input.get_vector(_move_left, _move_right, _move_up, _move_down)
	fighter.intent_move(move)
	fighter.intent_sprint(Input.is_action_pressed(_sprint))
