# fighter/tests/test_hit_resolver.gd
# Headless test for HitResolver — runs via:
#   godot --headless --script fighter/tests/test_hit_resolver.gd
extends SceneTree

func _init() -> void:
	var pass_count := 0
	var fail_count := 0
	var CS := HitResolver.CombatState

	var results: Array[String] = []

	# ================================================================
	# Test group 1: basic gating (carried forward from Phase 3)
	# ================================================================

	var dp_torso := DamageProfile.new()
	dp_torso.hit_region_priority = ["torso"]
	dp_torso.lethal_on_torso = true
	dp_torso.lethal_on_head = true
	dp_torso.limb_cripple = true

	var strike_torso := Strike.new()
	strike_torso.strike_id = "test_torso"
	strike_torso.damage_profile = dp_torso

	var limbs_ok := LimbHealth.new()

	# Test: attacker must be STRIKING
	var r := HitResolver.resolve(strike_torso, CS.WINDING_UP, CS.IDLE, true, limbs_ok)
	if r["type"] == "MISS":
		pass_count += 1
		results.append("PASS: winding_up = MISS")
	else:
		fail_count += 1
		results.append("FAIL: winding_up — got %s" % str(r))

	r = HitResolver.resolve(strike_torso, CS.RECOVERING, CS.IDLE, true, limbs_ok)
	if r["type"] == "MISS":
		pass_count += 1
		results.append("PASS: recovering = MISS")
	else:
		fail_count += 1
		results.append("FAIL: recovering — got %s" % str(r))

	r = HitResolver.resolve(strike_torso, CS.IDLE, CS.IDLE, true, limbs_ok)
	if r["type"] == "MISS":
		pass_count += 1
		results.append("PASS: attacker IDLE = MISS")
	else:
		fail_count += 1
		results.append("FAIL: attacker IDLE — got %s" % str(r))

	# Test: target not hurtable = MISS
	r = HitResolver.resolve(strike_torso, CS.STRIKING, CS.IDLE, false, limbs_ok)
	if r["type"] == "MISS":
		pass_count += 1
		results.append("PASS: target not hurtable = MISS")
	else:
		fail_count += 1
		results.append("FAIL: target not hurtable — got %s" % str(r))

	# ================================================================
	# Test group 2: torso routing
	# ================================================================

	# Torso OK → WOUNDED, non-lethal
	r = HitResolver.resolve(strike_torso, CS.STRIKING, CS.IDLE, true, limbs_ok)
	if r["type"] == "HIT" and r["limb"] == "torso" and r["lethal"] == false and r["new_integrity"] == LimbHealth.Integrity.WOUNDED:
		pass_count += 1
		results.append("PASS: torso OK → WOUNDED, non-lethal")
	else:
		fail_count += 1
		results.append("FAIL: torso OK — got %s" % str(r))

	# Torso WOUNDED → lethal
	var limbs_torso_wounded := LimbHealth.new()
	limbs_torso_wounded.set_integrity("torso", LimbHealth.Integrity.WOUNDED)
	r = HitResolver.resolve(strike_torso, CS.STRIKING, CS.IDLE, true, limbs_torso_wounded)
	if r["type"] == "HIT" and r["limb"] == "torso" and r["lethal"] == true:
		pass_count += 1
		results.append("PASS: torso WOUNDED → lethal")
	else:
		fail_count += 1
		results.append("FAIL: torso WOUNDED — got %s" % str(r))

	# ================================================================
	# Test group 3: head routing
	# ================================================================

	var dp_head := DamageProfile.new()
	dp_head.hit_region_priority = ["head", "torso"]
	dp_head.lethal_on_torso = true
	dp_head.lethal_on_head = true
	dp_head.limb_cripple = true

	var strike_head := Strike.new()
	strike_head.strike_id = "test_head"
	strike_head.damage_profile = dp_head

	r = HitResolver.resolve(strike_head, CS.STRIKING, CS.IDLE, true, limbs_ok)
	if r["type"] == "HIT" and r["limb"] == "head" and r["lethal"] == true:
		pass_count += 1
		results.append("PASS: head hit = lethal")
	else:
		fail_count += 1
		results.append("FAIL: head hit — got %s" % str(r))

	# ================================================================
	# Test group 4: arm cripple
	# ================================================================

	var dp_arm := DamageProfile.new()
	dp_arm.hit_region_priority = ["arm_r", "torso"]
	dp_arm.lethal_on_torso = true
	dp_arm.lethal_on_head = true
	dp_arm.limb_cripple = true

	var strike_arm := Strike.new()
	strike_arm.strike_id = "test_arm"
	strike_arm.damage_profile = dp_arm

	r = HitResolver.resolve(strike_arm, CS.STRIKING, CS.IDLE, true, limbs_ok)
	if r["type"] == "HIT" and r["limb"] == "arm_r" and r["lethal"] == false and r["new_integrity"] == LimbHealth.Integrity.CRIPPLED:
		pass_count += 1
		results.append("PASS: arm hit = CRIPPLED, non-lethal")
	else:
		fail_count += 1
		results.append("FAIL: arm hit — got %s" % str(r))

	# Hitting an already-crippled arm: still CRIPPLED, still non-lethal
	var limbs_arm_crippled := LimbHealth.new()
	limbs_arm_crippled.set_integrity("arm_r", LimbHealth.Integrity.CRIPPLED)
	r = HitResolver.resolve(strike_arm, CS.STRIKING, CS.IDLE, true, limbs_arm_crippled)
	if r["type"] == "HIT" and r["limb"] == "arm_r" and r["lethal"] == false:
		pass_count += 1
		results.append("PASS: already-crippled arm = non-lethal, stays CRIPPLED")
	else:
		fail_count += 1
		results.append("FAIL: already-crippled arm — got %s" % str(r))

	# ================================================================
	# Test group 5: leg cripple
	# ================================================================

	var dp_leg := DamageProfile.new()
	dp_leg.hit_region_priority = ["leg_r"]
	dp_leg.lethal_on_torso = true
	dp_leg.lethal_on_head = true
	dp_leg.limb_cripple = true

	var strike_leg := Strike.new()
	strike_leg.strike_id = "test_leg"
	strike_leg.damage_profile = dp_leg

	r = HitResolver.resolve(strike_leg, CS.STRIKING, CS.IDLE, true, limbs_ok)
	if r["type"] == "HIT" and r["limb"] == "leg_r" and r["lethal"] == false and r["new_integrity"] == LimbHealth.Integrity.CRIPPLED:
		pass_count += 1
		results.append("PASS: leg hit = CRIPPLED, non-lethal")
	else:
		fail_count += 1
		results.append("FAIL: leg hit — got %s" % str(r))

	# ================================================================
	# Test group 6: limb_cripple = false (non-crippling weapon)
	# ================================================================

	var dp_no_cripple := DamageProfile.new()
	dp_no_cripple.hit_region_priority = ["arm_r"]
	dp_no_cripple.lethal_on_torso = true
	dp_no_cripple.lethal_on_head = true
	dp_no_cripple.limb_cripple = false

	var strike_no_cripple := Strike.new()
	strike_no_cripple.strike_id = "test_no_cripple"
	strike_no_cripple.damage_profile = dp_no_cripple

	r = HitResolver.resolve(strike_no_cripple, CS.STRIKING, CS.IDLE, true, limbs_ok)
	if r["type"] == "HIT" and r["limb"] == "arm_r" and r["lethal"] == false and r["new_integrity"] == LimbHealth.Integrity.OK:
		pass_count += 1
		results.append("PASS: limb_cripple=false → no cripple, stays OK")
	else:
		fail_count += 1
		results.append("FAIL: limb_cripple=false — got %s" % str(r))

	# ================================================================
	# Test group 7: upper_horizontal priority routing
	# ================================================================

	var dp_upper := DamageProfile.new()
	dp_upper.hit_region_priority = ["head", "torso", "arm_r", "arm_l"]
	dp_upper.lethal_on_torso = true
	dp_upper.lethal_on_head = true
	dp_upper.limb_cripple = true

	var strike_upper := Strike.new()
	strike_upper.strike_id = "upper_horizontal"
	strike_upper.damage_profile = dp_upper

	r = HitResolver.resolve(strike_upper, CS.STRIKING, CS.IDLE, true, limbs_ok)
	if r["type"] == "HIT" and r["limb"] == "head" and r["lethal"] == true:
		pass_count += 1
		results.append("PASS: upper_horizontal → head (first in priority)")
	else:
		fail_count += 1
		results.append("FAIL: upper_horizontal routing — got %s" % str(r))

	var dp_middle := DamageProfile.new()
	dp_middle.hit_region_priority = ["torso", "arm_r", "arm_l", "head"]
	dp_middle.lethal_on_torso = true
	dp_middle.lethal_on_head = true
	dp_middle.limb_cripple = true

	var strike_middle := Strike.new()
	strike_middle.strike_id = "middle_horizontal"
	strike_middle.damage_profile = dp_middle

	r = HitResolver.resolve(strike_middle, CS.STRIKING, CS.IDLE, true, limbs_ok)
	if r["type"] == "HIT" and r["limb"] == "torso" and r["lethal"] == false:
		pass_count += 1
		results.append("PASS: middle_horizontal → torso OK → WOUNDED, non-lethal")
	else:
		fail_count += 1
		results.append("FAIL: middle_horizontal routing — got %s" % str(r))

	# ================================================================
	# Print results
	# ================================================================

	for line in results:
		print(line)

	print("\n--- HitResolver Tests: %d passed, %d failed ---" % [pass_count, fail_count])
	if fail_count > 0:
		quit(1)
	else:
		quit(0)
