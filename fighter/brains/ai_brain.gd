# fighter/brains/ai_brain.gd
# AIBrain — MVP placeholder AI (~5 rules, ~150 lines).
# Validates the brain contract end-to-end. Not a real combat AI.
# Replaced by a proper AI subsystem in a future phase.
class_name AIBrain
extends FighterBrain

## The opponent this AI observes. Set by FighterArena via set_opponent().
var opponent: FighterBody

## Distance at which the AI considers itself "in range" for combat.
@export var combat_range: float = 2.5

## Minimum time between AI decisions (seconds). Adds human-like delay.
@export var decision_interval: float = 0.8

## Chance (0-1) to attempt a parry when opponent starts a strike.
@export var parry_chance: float = 0.4

## Chance (0-1) to attempt a dodge when opponent starts a strike (checked if parry fails).
@export var dodge_chance: float = 0.2

## How long the AI retreats after being crippled (seconds).
@export var retreat_duration: float = 1.5

## Delay before striking after deciding to attack (telegraph, seconds).
@export var strike_telegraph: float = 0.3

var _decision_timer: float = 0.0
var _retreating: bool = false
var _retreat_timer: float = 0.0
var _strike_pending: bool = false
var _strike_delay: float = 0.0

func _ready() -> void:
	super._ready()
	if fighter:
		fighter.limb_state_changed.connect(_on_own_limb_changed)

func _on_own_limb_changed(limb: String, new_state: int) -> void:
	if new_state == LimbHealth.Integrity.CRIPPLED:
		_retreating = true
		_retreat_timer = retreat_duration

func set_opponent(opp: FighterBody) -> void:
	opponent = opp
	if opponent:
		if not opponent.strike_started.is_connected(_on_opponent_strike_started):
			opponent.strike_started.connect(_on_opponent_strike_started)

func _on_opponent_strike_started(_strike: Strike) -> void:
	if fighter == null or fighter.frozen:
		return
	if fighter.current_state != FighterBody.state.FREE:
		return
	var roll := randf()
	if roll < parry_chance:
		fighter.intent_parry()
	elif roll < parry_chance + dodge_chance:
		var away := _get_away_direction()
		fighter.intent_dodge(away)

func _physics_process(delta: float) -> void:
	if fighter == null or opponent == null:
		return
	if fighter.frozen:
		return
	if fighter.is_dead or opponent.is_dead:
		fighter.intent_move(Vector2.ZERO)
		return

	var to_opp := opponent.global_position - fighter.global_position
	to_opp.y = 0.0
	var dist := to_opp.length()

	# Handle pending strike telegraph
	if _strike_pending:
		_strike_delay -= delta
		if _strike_delay <= 0.0:
			_strike_pending = false
			_do_strike()
		fighter.intent_move(Vector2.ZERO)
		return

	# Handle retreat after being crippled
	if _retreating:
		_retreat_timer -= delta
		var away := _get_away_direction()
		fighter.intent_move(away)
		if _retreat_timer <= 0.0:
			_retreating = false
		return

	# Decision timer
	_decision_timer -= delta
	if _decision_timer > 0.0:
		# Keep approaching or holding position between decisions
		if dist > combat_range:
			fighter.intent_move(_get_approach_direction())
		else:
			fighter.intent_move(Vector2.ZERO)
		return

	# --- Decision point ---
	_decision_timer = decision_interval + randf() * 0.4

	if dist > combat_range:
		# Rule 1: Approach
		fighter.intent_move(_get_approach_direction())
	else:
		# In combat range
		var roll := randf()
		if roll < 0.3:
			# Rule 2: Change stance randomly
			_change_stance_random()
			fighter.intent_move(Vector2.ZERO)
		else:
			# Rule 3: Queue a strike with telegraph delay
			_strike_pending = true
			_strike_delay = strike_telegraph
			fighter.intent_move(Vector2.ZERO)

func _do_strike() -> void:
	if fighter.current_state != FighterBody.state.FREE:
		return
	var current_stance: int = FighterBody.STANCE_TO_WEAPON.find_key(fighter.weapon_type)
	if current_stance == null:
		current_stance = FighterBody.Stance.MIDDLE
	fighter.intent_strike(current_stance, Strike.StrikeDir.SLASH_HORIZONTAL)

func _change_stance_random() -> void:
	var stances := [FighterBody.Stance.MIDDLE, FighterBody.Stance.UPPER]
	var pick: int = stances[randi() % stances.size()]
	fighter.intent_change_stance(pick)

func _get_approach_direction() -> Vector2:
	if opponent == null or fighter == null:
		return Vector2.ZERO
	# Move toward opponent. In strafing mode, -Y = forward (toward opponent).
	return Vector2(0, -1)

func _get_away_direction() -> Vector2:
	# In strafing mode, +Y = backward (away from opponent).
	return Vector2(0, 1)

func reset() -> void:
	_decision_timer = 0.5
	_retreating = false
	_retreat_timer = 0.0
	_strike_pending = false
	_strike_delay = 0.0