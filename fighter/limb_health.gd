# fighter/limb_health.gd
extends Resource
class_name LimbHealth

enum Integrity { OK, WOUNDED, CRIPPLED }

const LIMB_NAMES: Array[String] = ["head", "torso", "arm_r", "arm_l", "leg_r", "leg_l"]

var _state: Dictionary = {}

func _init() -> void:
    reset()

func reset() -> void:
    _state = {
        "head": Integrity.OK,
        "torso": Integrity.OK,
        "arm_r": Integrity.OK,
        "arm_l": Integrity.OK,
        "leg_r": Integrity.OK,
        "leg_l": Integrity.OK,
    }

func get_integrity(limb: String) -> int:
    return _state.get(limb, Integrity.OK)

func set_integrity(limb: String, value: int) -> void:
    if limb in _state:
        _state[limb] = value

func has_leg_cripple() -> bool:
    return _state["leg_r"] == Integrity.CRIPPLED or _state["leg_l"] == Integrity.CRIPPLED

func has_weapon_arm_cripple() -> bool:
    return _state["arm_r"] == Integrity.CRIPPLED
