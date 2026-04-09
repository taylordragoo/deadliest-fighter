# fighter/fighter_brain.gd
# Abstract base for decision-makers attached to a Fighter.
# Subclasses (PlayerBrain, AIBrain) override _physics_process and call
# intent_* methods on self.fighter. Brains never touch the CharacterBody3D
# directly — they only emit intents.
class_name FighterBrain
extends Node

## The fighter this brain controls. Set in the editor, or auto-resolved
## to the parent if left unset.
@export var fighter: Fighter

func _ready() -> void:
	if fighter == null:
		var parent := get_parent()
		if parent is Fighter:
			fighter = parent
	if fighter == null:
		push_error("FighterBrain '%s' has no fighter reference and no Fighter parent." % name)
