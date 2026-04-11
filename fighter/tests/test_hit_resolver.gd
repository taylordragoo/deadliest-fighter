# fighter/tests/test_hit_resolver.gd
# Headless test for HitResolver — runs via:
#   godot --headless --script fighter/tests/test_hit_resolver.gd
extends SceneTree

func _init() -> void:
	var pass_count := 0
	var fail_count := 0

	# Build a test Strike resource
	var dp := DamageProfile.new()
	dp.hit_region_priority = ["torso"]
	dp.lethal_on_torso = true
	dp.lethal_on_head = true

	var strike := Strike.new()
	strike.strike_id = "test_strike"
	strike.hit_line = Strike.HitLine.MID
	strike.wind_up_time = 0.2
	strike.active_time = 0.2
	strike.recover_time = 0.3
	strike.damage_profile = dp

	# Alias for readability
	var CS := HitResolver.CombatState

	# Test 1: STRIKING + hurtable = HIT(torso, lethal)
	var result := HitResolver.resolve(strike, CS.STRIKING, CS.IDLE, true)
	if result["type"] == "HIT" and result["limb"] == "torso" and result["lethal"] == true:
		pass_count += 1
		print("PASS: striking + hurtable = HIT(torso, lethal)")
	else:
		fail_count += 1
		print("FAIL: striking + hurtable — got ", result)

	# Test 2: WINDING_UP = MISS (not in STRIKING)
	result = HitResolver.resolve(strike, CS.WINDING_UP, CS.IDLE, true)
	if result["type"] == "MISS":
		pass_count += 1
		print("PASS: winding_up = MISS")
	else:
		fail_count += 1
		print("FAIL: winding_up — got ", result)

	# Test 3: RECOVERING = MISS
	result = HitResolver.resolve(strike, CS.RECOVERING, CS.IDLE, true)
	if result["type"] == "MISS":
		pass_count += 1
		print("PASS: recovering = MISS")
	else:
		fail_count += 1
		print("FAIL: recovering — got ", result)

	# Test 4: target not hurtable = MISS
	result = HitResolver.resolve(strike, CS.STRIKING, CS.IDLE, false)
	if result["type"] == "MISS":
		pass_count += 1
		print("PASS: target not hurtable = MISS")
	else:
		fail_count += 1
		print("FAIL: target not hurtable — got ", result)

	# Test 5: IDLE attacker = MISS
	result = HitResolver.resolve(strike, CS.IDLE, CS.IDLE, true)
	if result["type"] == "MISS":
		pass_count += 1
		print("PASS: attacker IDLE = MISS")
	else:
		fail_count += 1
		print("FAIL: attacker IDLE — got ", result)

	print("\n--- HitResolver Tests: %d passed, %d failed ---" % [pass_count, fail_count])
	if fail_count > 0:
		quit(1)
	else:
		quit(0)
