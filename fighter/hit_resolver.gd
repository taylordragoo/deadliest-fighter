# fighter/hit_resolver.gd
# HitResolver — pure static function: strike context → HitOutcome.
# Phase 3: returns MISS or HIT(torso, lethal=true). No limb routing,
# no parry/dodge checking. Phase 4–5 expand the logic.
#
# Returns a Dictionary (tagged union):
#   { "type": "MISS" }
#   { "type": "HIT", "limb": "torso", "lethal": true }
#
# Pure: reads inputs only, mutates nothing. Testable without engine.
# Decoupled: uses its own CombatState enum, NOT FighterBody.state.
class_name HitResolver

## Combat states as understood by the resolver. FighterBody maps its
## internal state enum to these before calling resolve(). This keeps
## the resolver independent of the fighter's souls-era state naming.
enum CombatState {
	IDLE,        ## FREE, STRAFING, SPRINTING — not attacking or defending
	WINDING_UP,  ## Strike started, hitbox not yet active
	STRIKING,    ## Hitbox active, committed
	RECOVERING,  ## Post-strike vulnerability
	PARRYING,    ## Active parry frames (Phase 5)
	DODGING,     ## I-frame dodge (Phase 5)
	HURT,        ## Taking a non-lethal hit
	DEAD,        ## Round over
}

## Resolve a strike hitting a target.
## attacker_combat_state / target_combat_state: CombatState enum values.
## strike: the Strike resource being used.
## target_can_be_hurt: whether the target is currently vulnerable.
static func resolve(
	strike: Strike,
	attacker_combat_state: int,
	target_combat_state: int,
	target_can_be_hurt: bool
) -> Dictionary:
	# Attacker must be in STRIKING state
	if attacker_combat_state != CombatState.STRIKING:
		return { "type": "MISS" }

	# Target must be hurtable
	if not target_can_be_hurt:
		return { "type": "MISS" }

	# Phase 5 will add: if target_combat_state == DODGING → DODGED
	# Phase 5 will add: if target_combat_state == PARRYING → PARRIED check

	# Phase 3: any valid contact = torso hit, always lethal
	return {
		"type": "HIT",
		"limb": "torso",
		"lethal": strike.damage_profile.lethal_on_torso
	}
