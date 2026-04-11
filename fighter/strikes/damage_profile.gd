# fighter/strikes/damage_profile.gd
# DamageProfile — declares what limbs a strike targets and lethality rules.
# Phase 3: only torso matters. Phase 4 adds limb routing.
extends Resource
class_name DamageProfile

## Limbs this strike targets, in priority order.
## Phase 3 ignores this (everything resolves to torso).
## Phase 4 uses it for limb routing.
@export var hit_region_priority: Array[String] = ["torso"]

## Whether a clean hit to the torso is lethal.
@export var lethal_on_torso: bool = true

## Whether a clean hit to the head is lethal.
@export var lethal_on_head: bool = true

## Whether this strike can cripple limbs (Phase 4).
@export var limb_cripple: bool = true
