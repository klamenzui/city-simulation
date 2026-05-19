extends RefCounted
class_name CitizenEmotion

## Pure derived-emotion math (Step 3c). Realizes the `stress` / `loneliness`
## intent from config/citizen_decision_rules.json using only signals that
## actually exist in this sim: needs (hunger/energy/social), is_home,
## is_night. No weather/events/noise inputs (those systems do not exist).
##
## Deliberately a tiny pure function (no rule engine, no state) so it is
## trivially unit-testable and keeps the emotion effect isolated to the
## soft `social` candidate in CitizenPlanner. Hard overrides are untouched.

static func compute(
	hunger: float,
	energy: float,
	social: float,
	is_home: bool,
	is_night: bool,
	cfg: Dictionary
) -> Dictionary:
	var stress := 0.0
	if hunger >= float(cfg.get("stress_hunger_threshold", 75.0)):
		stress += float(cfg.get("stress_hunger_add", 0.30))
	if energy <= float(cfg.get("stress_energy_threshold", 20.0)):
		stress += float(cfg.get("stress_energy_add", 0.30))
	stress = clampf(stress, 0.0, 1.0)

	var loneliness := float(cfg.get("loneliness_base", 0.2))
	if social <= float(cfg.get("loneliness_social_threshold", 30.0)):
		loneliness += float(cfg.get("loneliness_social_add", 0.25))
	if is_home and is_night:
		loneliness += float(cfg.get("loneliness_home_night_add", 0.05))
	loneliness = clampf(loneliness, 0.0, 1.0)

	return {"stress": stress, "loneliness": loneliness}

## Multiplier applied to the soft `social` goal priority: lonelier citizens
## pursue socializing harder; a citizen who is very stressed withdraws
## (mirrors social_visit `stress_gte 0.85 -> mul 0.5` in the rule spec).
static func social_priority_multiplier(emo: Dictionary, cfg: Dictionary) -> float:
	var m := 1.0 + float(emo.get("loneliness", 0.0)) * float(cfg.get("loneliness_social_gain", 0.6))
	if float(emo.get("stress", 0.0)) >= float(cfg.get("stress_social_damp_threshold", 0.85)):
		m *= float(cfg.get("stress_social_damp_mul", 0.5))
	return clampf(
		m,
		float(cfg.get("social_mult_min", 0.3)),
		float(cfg.get("social_mult_max", 2.0)))
