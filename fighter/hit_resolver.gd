# fighter/hit_resolver.gd
# HitResolver — pure static function: strike context → HitOutcome.
# Phase 5: DODGED and PARRIED outcomes before limb routing.
# DODGED: target in DODGING → unconditional.
# PARRIED: target in PARRYING → optionally gated by stance_match_required.
# Limb routing via DamageProfile.hit_region_priority (Phase 4).
#
# Returns a Dictionary (tagged union):
#   { "type": "MISS" }
#   { "type": "DODGED" }
#   { "type": "PARRIED" }
#   { "type": "HIT", "limb": "arm_r", "lethal": false, "new_integrity": 2 }
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
## target_limb_health: optional LimbHealth to read current limb integrity.
## stance_match_required: when true, PARRIED only fires if target_stance_hit_line matches strike.hit_line.
## target_stance_hit_line: target's current stance mapped to Strike.HitLine. -1 = skip stance check.
static func resolve(
	strike: Strike,
	attacker_combat_state: int,
	target_combat_state: int,
	target_can_be_hurt: bool,
	target_limb_health: LimbHealth = null,
	stance_match_required: bool = false,
	target_stance_hit_line: int = -1
) -> Dictionary:
	# Attacker must be in STRIKING state
	if attacker_combat_state != CombatState.STRIKING:
		return { "type": "MISS" }

	# Target must be hurtable
	if not target_can_be_hurt:
		return { "type": "MISS" }

	# Dodge: unconditional i-frame defense
	if target_combat_state == CombatState.DODGING:
		return { "type": "DODGED" }

	# Parry: active parry frames, optionally gated by stance match
	if target_combat_state == CombatState.PARRYING:
		if stance_match_required:
			if target_stance_hit_line >= 0 and target_stance_hit_line == strike.hit_line:
				return { "type": "PARRIED" }
			# Stance mismatch: parry fails, strike resolves normally (fall through to limb routing)
		else:
			return { "type": "PARRIED" }

	var dp := strike.damage_profile
	if dp == null:
		return { "type": "MISS" }

	var target_limb: String = "torso"
	if dp.hit_region_priority.size() > 0:
		target_limb = dp.hit_region_priority[0]

	var limb_integrity: int = LimbHealth.Integrity.OK
	if target_limb_health != null:
		limb_integrity = target_limb_health.get_integrity(target_limb)

	return _resolve_limb_hit(target_limb, limb_integrity, dp)


static func _resolve_limb_hit(limb: String, integrity: int, dp: DamageProfile) -> Dictionary:
	match limb:
		"head":
			return {
				"type": "HIT",
				"limb": "head",
				"lethal": dp.lethal_on_head,
				"new_integrity": LimbHealth.Integrity.OK,
			}
		"torso":
			if integrity == LimbHealth.Integrity.OK:
				return {
					"type": "HIT",
					"limb": "torso",
					"lethal": false,
					"new_integrity": LimbHealth.Integrity.WOUNDED,
				}
			else:
				return {
					"type": "HIT",
					"limb": "torso",
					"lethal": dp.lethal_on_torso,
					"new_integrity": LimbHealth.Integrity.WOUNDED,
				}
		"arm_r", "arm_l":
			if not dp.limb_cripple:
				return {
					"type": "HIT",
					"limb": limb,
					"lethal": false,
					"new_integrity": integrity,
				}
			return {
				"type": "HIT",
				"limb": limb,
				"lethal": false,
				"new_integrity": LimbHealth.Integrity.CRIPPLED,
			}
		"leg_r", "leg_l":
			if not dp.limb_cripple:
				return {
					"type": "HIT",
					"limb": limb,
					"lethal": false,
					"new_integrity": integrity,
				}
			return {
				"type": "HIT",
				"limb": limb,
				"lethal": false,
				"new_integrity": LimbHealth.Integrity.CRIPPLED,
			}
		_:
			return { "type": "MISS" }
