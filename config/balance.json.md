# balance.json — Tuning-Referenz

Zentrale Tuning-Werte der Simulation. Geladen von
`Simulation/Config/BalanceConfig.gd`: Die im Code hinterlegten Defaults
(`_default_data()`) werden beim Start mit dem Inhalt dieser Datei **tief gemerged**
— Werte in `balance.json` überschreiben die Defaults, fehlende Werte fallen auf den
Default zurück. Zugriff im Code über
`BalanceConfig.get_int/get_float/get_bool/get_string("pfad.zur.option", default)`.

Nach Änderungen: Spiel neu starten oder `BalanceConfig.reload()` aufrufen.

> JSON erlaubt keine Kommentare — deshalb steht die Beschreibung hier, die `.json`
> enthält nur Werte. Diese Datei beschreibt **alle** Sektionen und Keys.

**Konventionen:** Geldwerte in EUR. Zeiten meist in Spielminuten (1 Tag = 1440
Spielminuten; reale Dauer siehe [Zeit-Kontext](#zeit-kontext)). Bedürfnisse laufen
0–100: **hunger** hoch = hungrig, **energy/fun/social/health** hoch = gut.

---

## simulation

Bevölkerung und Nachschub an Bürgern.

| Key | Default | Wirkung |
| --- | --- | --- |
| `initial_citizen_count` | `150` | Anzahl Bürger beim Start. |
| `target_citizen_count` | `200` | Zielbevölkerung, bis zu der nachgespawnt wird. |
| `enable_spawn_refill` | `true` | Schaltet das Nachspawnen verstorbener/fehlender Bürger an. |
| `spawn_refill_delay_min` | `30` | Minimale Verzögerung (Spielminuten) bis zum Nachspawnen. |
| `spawn_refill_delay_max` | `180` | Maximale Verzögerung bis zum Nachspawnen. |
| `spawn_refill_max_per_tick` | `1` | Maximal nachgespawnte Bürger pro Tick (Drossel gegen Spikes). |

## debug

Diagnose-Schalter (Performance-relevant — im Normalbetrieb aus).

| Key | Default | Wirkung |
| --- | --- | --- |
| `enable_all_citizen_trace` | `false` | Aktiviert das Trace-Logging für **alle** Bürger (sehr gesprächig). |
| `enable_map_snapshot_log` | `false` | Loggt einen Map-/Navigations-Snapshot beim Start. |

## world

Takt der Simulationsschleife und Stadt-Startkapital.

| Key | Default | Wirkung |
| --- | --- | --- |
| `minutes_per_tick` | `1` | Spielminuten, die pro Tick vergehen. |
| `tick_interval_sec` | `0.5` | Reale Sekunden zwischen zwei Ticks (vor Tempo-Faktor). |
| `speed_multiplier` | `1.0` | Tempo. Effektiver Takt = `tick_interval_sec ÷ speed_multiplier`. HUD-Stufen 1x–4x. |
| `city_reserve_start_balance` | `18000` | Startguthaben der städtischen Rücklage (EUR). |

---

## transport

Vehicle pathing, delivery route-following, and first VehicleBody3D truck tuning.

| Key | Default | Wirkung |
| --- | --- | --- |
| `vehicle_lane_offset` | `0.45` | Offset from RoadGraph centerline to the right-side vehicle lane. |
| `vehicle.max_speed` | `5.0` | Maximum truck speed in world units per second. |
| `vehicle.acceleration` | `2.8` | Truck acceleration. |
| `vehicle.braking_acceleration` | `5.5` | Truck deceleration while slowing down. |
| `vehicle.braking_distance` | `2.2` | Distance before destination where the truck starts slowing down. |
| `vehicle.turn_speed` | `5.0` | Yaw interpolation speed while following route waypoints. |
| `vehicle.waypoint_reach_distance` | `0.45` | Distance at which the next vehicle waypoint is considered reached. |
| `vehicle.forward_yaw_offset` | `0.0` | Optional mesh yaw correction if a vehicle model faces a different local axis. |
| `vehicle.mass` | `35.0` | VehicleBody3D rigid-body mass for the scaled delivery truck. |
| `vehicle.center_of_mass_x/y/z` | `0.0 / 0.12 / -0.45` | Custom center of mass to reduce rollovers and flying. |
| `vehicle.manual_drive_enabled` | `true` | Enables direct player driving after a controlled citizen enters a vehicle. |
| `vehicle.manual_engine_force` | `40.0` | Wheel engine force for player-driven VehicleBody3D trucks. |
| `vehicle.manual_reverse_force_multiplier` | `1.7` | Reverse force multiplier. |
| `vehicle.manual_brake_strength` | `2.2` | Brake force when the driver presses against current motion. |
| `vehicle.manual_parking_brake` | `6.0` | Brake value used when the truck is parked/frozen. |
| `vehicle.manual_steer_speed` | `1.5` | Steering interpolation speed. |
| `vehicle.manual_steer_limit` | `0.42` | Maximum steering angle. |
| `vehicle.manual_max_speed` | `4.5` | Maximum forward speed for player-driven vehicles. |
| `vehicle.manual_reverse_speed` | `2.0` | Maximum reverse speed for player-driven vehicles. |
| `vehicle.manual_low_speed_force_boost` | `2.5` | Extra engine force near zero speed for easier starts. |
| `vehicle.manual_forward_engine_sign` | `1.0` | Direction correction for models whose VehicleBody forward axis differs. |
| `vehicle.wheel_track_half_width` | `0.26` | Half width between left and right VehicleWheel3D nodes. |
| `vehicle.wheel_front_z` | `0.04` | Local Z position of the front axle. |
| `vehicle.wheel_rear_z` | `-1.0` | Local Z position of the rear axle. |
| `vehicle.wheel_mount_y` | `0.16` | Local Y position of wheel suspension mounts. |
| `vehicle.wheel_radius` | `0.155` | Physics wheel radius, matched to the visible scaled tire radius. |
| `vehicle.wheel_roll_influence` | `0.28` | Roll influence for VehicleWheel3D. |
| `vehicle.wheel_friction_slip` | `1.25` | Wheel tire friction. |
| `vehicle.suspension_stiffness` | `20.0` | Wheel suspension stiffness. |
| `vehicle.suspension_travel` | `0.16` | Wheel suspension travel. |
| `vehicle.damping_compression` | `1.0` | Suspension compression damping. |
| `vehicle.damping_relaxation` | `1.8` | Suspension relaxation damping. |
| `vehicle.ground_snap_enabled` | `true` | Keeps parked and route-following vehicles grounded by ray-snapping to static road/world surfaces. |
| `vehicle.ground_probe_up` | `2.0` | Upward ray start offset for vehicle ground probes. |
| `vehicle.ground_probe_down` | `8.0` | Downward ray length for vehicle ground probes. |
| `vehicle.ground_height_offset` | `0.0` | Height added to the probed ground point before placing the vehicle root. |
| `vehicle.ground_snap_speed` | `30.0` | Interpolation speed used when snapping vehicle height during simulation. |
| `vehicle.ground_min_normal_y` | `0.45` | Minimum upward surface normal accepted as vehicle ground. |
| `vehicle.ground_collision_mask` | `1` | Physics mask used by vehicle ground probes. |
| `vehicle.audio_enabled` | `true` | Enables generated EngineSound/ImpactSound players on VehicleAgent scenes. |
| `vehicle.engine_audio_path` | `res://environment/audio/vehicles/engine.wav` | Default looping engine sound used when a vehicle scene has no stream assigned. |
| `vehicle.impact_audio_path` | `res://environment/audio/vehicles/impact_1.wav` | Default impact sound used for sudden speed changes. |
| `vehicle.engine_audio_min_pitch` | `0.05` | Idle pitch for vehicle engine loops. |
| `vehicle.engine_audio_pitch_per_speed` | `0.08` | Extra engine pitch per meter/second of vehicle speed. |
| `vehicle.engine_audio_idle_volume_db` | `-28.0` | Engine volume while idling with a driver. |
| `vehicle.engine_audio_drive_volume_db` | `-11.0` | Engine volume while moving or route-driving. |
| `vehicle.engine_audio_lerp_speed` | `8.0` | Smooth speed for engine pitch/volume changes. |
| `vehicle.impact_speed_delta_threshold` | `1.8` | Speed delta that triggers the impact sound. |
| `vehicle.impact_min_interval` | `0.35` | Minimum seconds between impact sounds. |

---

## economy

Markt, Jobs, Stadtkasse und Gebäude-Finanz-Defaults.

| Key | Default | Wirkung |
| --- | --- | --- |
| `market_account_balance` | `250000` | Startkapital des globalen Markt-Kontos (puffert Käufe/Verkäufe). |

### economy.commodities

Globaler Warenpool je Gut. Gleiche Keys für `food`, `clothes`, `entertainment`,
`fuel`:

| Key | Wirkung |
| --- | --- |
| `stock` | Anfangsbestand der Ware. |
| `target_stock` | Soll-Bestand, auf den Produktion/Nachschub hinarbeitet. |
| `base_price` | Grundpreis pro Einheit (EUR), Basis der Preisbildung. |

Defaults: food `900 / 1200 / 4`, clothes `480 / 700 / 7`,
entertainment `2000 / 2500 / 2`, fuel `680 / 900 / 5`,
medicine `420 / 650 / 6`.

### economy.jobs

| Key | Default | Wirkung |
| --- | --- | --- |
| `wage_per_hour_min` | `10` | Untere Grenze für Stundenlöhne (EUR). |
| `wage_per_hour_max` | `26` | Obere Grenze für Stundenlöhne. |
| `training_offer_score_bonus` | `420.0` | Bonus im Job-Angebots-Score, der einen Bürger zur Weiterbildung (Uni) statt direkter Anstellung schiebt. |
| `training_offer_gap_penalty` | `120.0` | Score-Abzug je fehlender Bildungsstufe für eine Stelle (größere Lücke = unattraktiver). |

- **`wage_per_hour_by_title`** — Stundenlohn (EUR) je Job-Titel. Werte:
  Baecker 12, Kellner 12, Programmierer 24, Fahrer 15, Mechaniker 18, Tankwart 14,
  Verkaeufer 13, Designer 19, Doctor 30, Nurse 22, Pharmacist 25, Therapist 24,
  Mayor 32, Teacher 18, Engineer 26, Professor 28,
  Janitor 13, Gardener 14, MaintenanceWorker 16, Technician 22.
- **`required_education`** — Mindest-`education_level` je Titel (fehlt ein Titel ⇒ 0).
  Doctor 3, Nurse 2, Pharmacist 2, Therapist 2, Mayor 3, Professor 3, Teacher 2,
  Engineer 2, Programmierer 2,
  Mechaniker/Designer/MaintenanceWorker/Technician 1; übrige 0. Lehrjobs verlangen
  einen Abschluss — eine unbesetzte Pflicht-Uni stellt jedoch eine Trainee-Lehrkraft
  trotz Bildungslücke ein (`World._building_needs_emergency_staffing`), damit das
  Bildungssystem nie verklemmt.
- **`allowed_building_types`** — auf welche Gebäudetypen ein Titel beschränkt ist
  (z. B. Doctor/Nurse/Pharmacist/Therapist nur `HOSPITAL`, Mayor nur `CITY_HALL`,
  Teacher/Professor nur `UNIVERSITY`, Gardener nur `PARK`, Technician
  `FACTORY`/`CITY_HALL`/`HOSPITAL`; MaintenanceWorker fast überall). Fehlt ein
  Titel ⇒ keine Beschränkung.

**Effektive Beruf → Arbeitsgebäude.** Schnitt aus `allowed_building_types` (Obergrenze)
und den Kandidatenlisten je Gebäudetyp in `World._get_candidate_job_titles_for_building`.
„Bildung" = `required_education` (siehe oben).

| Beruf | Arbeitsgebäude | Bildung |
| --- | --- | --- |
| Doctor | Hospital | 3 |
| Nurse | Hospital | 2 |
| Pharmacist | Hospital | 2 |
| Therapist | Hospital | 2 |
| Mayor | City Hall | 3 |
| Professor | Universität | 3 |
| Teacher | Universität | 2 |
| Engineer | Fabrik | 2 |
| Programmierer | City Hall | 2 |
| Technician | Fabrik, City Hall, Hospital | 1 |
| Mechaniker | Fabrik, Tankstelle, Farm | 1 |
| Designer | Kino | 1 |
| MaintenanceWorker | alle Gebäude (außer generisch) | 1 |
| Baecker | Restaurant, Café | 0 |
| Kellner | Restaurant, Café | 0 |
| Fahrer | Fabrik, Farm | 0 |
| Tankwart | Tankstelle | 0 |
| Verkaeufer | Laden, Supermarkt, Tankstelle | 0 |
| Janitor | Universität, City Hall, Park, Hospital | 0 |
| Gardener | Park | 0 |

> `allowed_building_types` ist nur die Obergrenze; tatsächlich angeboten werden Berufe
> über die Kandidatenlisten. Daher arbeiten Janitor/Gardener trotz häufiger „Angebote"
> nur an den oben gelisteten Gebäuden — der Rest wird in `_build_job_offer_for_citizen`
> herausgefiltert.

#### economy.jobs.wage_progression — Lohn-Progression

Tageslohn = `wage_per_hour × gearbeitete_Stunden × Multiplikator`.
**Multiplikator = 1 + Bildungsbonus + Erfahrungsbonus**, beide abhängig von der
**Profit-Stufe** des Arbeitsplatzes (schwach/normal/stark). Gilt für Spieler und
NPCs — zentrale Berechnung in `World.get_wage_progression()`. Bei
`education_level == required` und ohne angesparten Erfahrungsbonus ist der
Multiplikator exakt `1.0`.


*Bildungsbonus* = `(education_level − required_education_level) × Satz(Profit-Stufe)`
— nur Stufen über dem Job-Minimum zählen.

| Key | Default | Wirkung |
| --- | --- | --- |
| `education_max_level` | `3` | Obergrenze für `education_level`; Studieren stoppt dort. |
| `education_bonus_per_level_weak` | `0.03` | +3 % je Stufe bei **schwacher** Firmenlage. |
| `education_bonus_per_level_normal` | `0.05` | +5 % je Stufe bei **normaler** Lage. |
| `education_bonus_per_level_strong` | `0.08` | +8 % je Stufe bei **starker** Lage. |

*Erfahrungsbonus* = pro Bürger angesparter Wert (`Citizen.experience_wage_bonus`),
ändert sich je Arbeitstag um das Tages-Delta der Profit-Stufe, begrenzt auf
`[0, experience_bonus_max]`. **Reset auf 0 bei Einstellung/Kündigung.**

| Key | Default | Wirkung |
| --- | --- | --- |
| `experience_daily_weak` | `-0.001` | −0,1 %/Tag → schrumpft bei Verlust. |
| `experience_daily_normal` | `0.00005` | +~0,005 %/Tag → praktisch Stillstand (≈ +1,8 %/Jahr). |
| `experience_daily_strong` | `0.0025` | +0,25 %/Tag → spürbarer Aufstieg bei guter Firma. |
| `experience_bonus_max` | `0.10` | Deckel: maximal +10 %. |

*Profit-Stufe* = aus `Building.profit_average` (geglätteter Tagesgewinn, EMA,
aktualisiert in `begin_new_day`), gemappt von `Building.get_profit_tier()`:

| Key | Default | Wirkung |
| --- | --- | --- |
| `profit_smoothing_alpha` | `0.25` | Glättungsfaktor (≈ 7-Tage-Fenster); höher = reagiert schneller. |
| `profit_weak_max` | `0.0` | `profit_average ≤` Schwelle → **schwach**. |
| `profit_strong_min` | `250.0` | `profit_average ≥` Schwelle → **stark**; dazwischen **normal**. EUR/Tag, absolut. |

Beispiel: `education_level` 3, Job verlangt 1, starke Firma → 2 × 8 % = **+16 %** Bildungsbonus.

### economy.city_hall

Steuern, Förderung und Liquidität der Stadtverwaltung.

| Key | Default | Wirkung |
| --- | --- | --- |
| `business_tax_rate` | `0.1` | Steuersatz auf Gebäude-Gewinne (10 %). |
| `citizen_tax_rate` | `0.02` | Steuersatz auf Bürger-Einkommen (2 %). |
| `infrastructure_cost_per_day` | `70` | Tägliche Infrastrukturkosten der Stadt (EUR). |
| `unemployment_support` | `25` | Arbeitslosengeld pro Tag je unbeschäftigtem Bürger. |
| `start_balance` | `4500` | Startguthaben der Stadtkasse. |
| `min_operating_balance` | `1200` | Mindestkasse; darunter wird aus der Rücklage nachgefüllt. |
| `reserve_transfer_target_balance` | `3500` | Zielkasse, auf die Rücklagen-Transfers auffüllen. |
| `reserve_transfer_daily_limit` | `2000` | Maximaler Rücklagen-Transfer pro Tag. |
| `max_underfunded_days_before_closure` | `3` | Tage in Unterfinanzierung, bis ein öffentliches Gebäude schließt. |
| `underfunded_efficiency_multiplier` | `0.82` | Effizienzfaktor unterfinanzierter Gebäude. |
| `underfunded_service_multiplier` | `0.76` | Service-/Kundendurchsatz-Faktor unterfinanzierter Gebäude. |

### economy.buildings

Finanz-Defaults für gewerbliche Gebäude.

| Key | Default | Wirkung |
| --- | --- | --- |
| `start_balance` | `900` | Startguthaben eines Gebäudekontos. |
| `max_missed_payment_days_before_closure` | `3` | Tage mit verpassten Zahlungen bis zur Zwangsschließung. |
| `struggling_efficiency_multiplier` | `0.72` | Effizienzfaktor eines „angeschlagenen" Gebäudes. |
| `struggling_customer_multiplier` | `0.78` | Kundendurchsatz-Faktor eines angeschlagenen Gebäudes. |

---

## world_setup

Defaults beim Aufbau der Welt.

| Key | Default | Wirkung |
| --- | --- | --- |
| `default_rent_per_day` | `10` | Standardmiete pro Tag, falls ein Wohngebäude keine eigene hat. |
| `default_work_capacity` | `1` | Standard-Arbeitsplätze, falls ein Gebäude keine eigene Vorgabe hat. |
| `university_job_capacity_override` | `8` | Überschreibt die Stellenanzahl von Universitäten. |

## schedule

Tag-/Nacht-Grenzen (Stunde 0–23), genutzt von Planung und Aktionen.

| Key | Default | Wirkung |
| --- | --- | --- |
| `night_start_hour` | `22` | Ab dieser Stunde gilt „Nacht". |
| `day_start_hour` | `6` | Ab dieser Stunde gilt „Tag". |

---

## citizen

Startwerte und Persönlichkeits-Streuung der Bürger.

| Key | Default | Wirkung |
| --- | --- | --- |
| `wallet_start_balance` | `200` | Startguthaben je Bürger (EUR). |
| `home_food_stock_start` | `2` | Vorräte zu Hause beim Start. |
| `education_level_start` | `0` | Start-Bildungsstufe. |

### citizen.thresholds

Persönlichkeit/Schwellen werden je Bürger als `base ± jitter` zufällig gestreut.

| Key | Default | Wirkung |
| --- | --- | --- |
| `hunger_threshold_base` / `_jitter` | `60.0` / `12.0` | Hunger-Wert, ab dem ein Bürger essen will. |
| `low_energy_threshold_base` / `_jitter` | `35.0` / `10.0` | Energie-Wert, ab dem Erholung/Schlaf nötig wird. |
| `work_motivation_base` / `_jitter` | `1.0` / `0.4` | Arbeitsmotivation (Multiplikator auf Arbeits-Priorität). |
| `fun_interest_base` / `_jitter` | `0.35` / `0.2` | Interesse an Freizeit (0–1). |
| `fun_target_base` / `_jitter` | `65.0` / `15.0` | Angestrebter Fun-Wert. |
| `sociability_base` / `_jitter` | `0.5` / `0.2` | Geselligkeit (0–1); beeinflusst Sozialbedarf. |

### citizen.needs

Bedürfnis-Dynamik. `*_rate_per_min` = Veränderung pro Spielminute im Normalzustand;
`target_*` = vom Planner angestrebte Grenzen; `health_*` = Gesundheitseffekte.

| Key | Default | Wirkung |
| --- | --- | --- |
| `target_hunger_max` | `20.0` | Planner will Hunger darunter halten. |
| `target_energy_min` | `80.0` | Planner will Energie darüber halten. |
| `target_fun_min` | `30.0` | Ziel-Untergrenze Fun. |
| `target_social_min` | `30.0` | Ziel-Untergrenze Social. |
| `target_health` | `100.0` | Ziel-Gesundheit. |
| `hunger_rate_per_min` | `0.1` | Hunger steigt pro Minute. |
| `energy_rate_per_min` | `0.08` | Energie sinkt pro Minute. |
| `fun_rate_per_min` | `0.03` | Fun sinkt pro Minute. |
| `social_rate_per_min` | `0.03` | Social sinkt pro Minute. |
| `health_hunger_threshold` | `80.0` | Ab diesem Hunger sinkt Gesundheit. |
| `health_hunger_penalty_per_min` | `0.1` | Gesundheitsverlust/min bei zu viel Hunger. |
| `health_energy_threshold` | `10.0` | Unter dieser Energie sinkt Gesundheit. |
| `health_energy_penalty_per_min` | `0.06` | Gesundheitsverlust/min bei Erschöpfung. |
| `health_fun_threshold` | `0.0` | Unter diesem Fun sinkt Gesundheit. |
| `health_fun_penalty_per_min` | `0.02` | Gesundheitsverlust/min bei zu wenig Fun. |
| `health_recovery_hunger_threshold` | `60.0` | Hunger muss darunter sein, damit Gesundheit heilt. |
| `health_recovery_energy_threshold` | `40.0` | Energie muss darüber sein, damit Gesundheit heilt. |
| `health_recovery_fun_threshold` | `20.0` | Fun muss darüber sein, damit Gesundheit heilt. |
| `health_recovery_per_min` | `0.015` | Gesundheitsregeneration/min, wenn alle Bedingungen erfüllt. |

---

## building

Zustand und Wartung aller Gebäude.

| Key | Default | Wirkung |
| --- | --- | --- |
| `condition_start` | `100.0` | Anfangszustand (0–100). |
| `daily_decay` | `1.0` | Täglicher Zustandsverfall. |
| `maintenance_cost_per_day` | `14` | Wartungskosten pro Tag (EUR). |
| `repair_threshold` | `60.0` | Unter diesem Zustand wird Reparatur ausgelöst. |

---

## actions

Effekt einer laufenden Aktion auf die Bedürfnisse, pro Spielminute. Muster:

- **`*_mul`** — Multiplikator auf die normale Bedürfnis-Rate während der Aktion
  (z. B. `hunger_mul 0.25` = Hunger steigt nur zu 25 % der Normalrate).
- **`*_add`** — additive Änderung pro Minute (negativ senkt: `hunger_add -0.95` =
  Hunger fällt 0,95/min beim Essen).
- **`*_minutes`** — Dauer (Default/Min/Max) der Aktion in Spielminuten.
- **`stop_*_threshold`** — Aktion abbrechen, wenn das Bedürfnis die Schwelle erreicht.

| Aktion | Wesentliche Werte |
| --- | --- |
| `eat_home` | max 70 min; hunger ×0.25 / −0.95, energy ×0.45 / +0.14, fun ×1.0 / −0.02. |
| `eat_restaurant` | max 80 min; hunger ×0.15 / −1.15, energy ×0.35 / +0.22, fun ×0.55 / +0.08 (besser, aber kostet). |
| `eat_cafe` | max 35 min; hunger ×0.25 / −0.72, energy ×0.55 / +0.08, fun ×0.75 / +0.05; stoppt bei Hunger ≤45 als kleiner Snack. |
| `relax_home` | hunger ×1.0, energy +0.1, **fun +0.45**. |
| `relax_park` | 15 (10–20) min; fun +0.22; ohne Bank energy +0.0, mit Bank energy +0.1 & fun-Bonus +0.03; Stop bei energy ≤18 / health ≤35. |
| `relax_bench` | 45 min; energy +0.18; Stop bei hunger ≥70 / health ≤35. |
| `sleep` | Aufwachen ab `wake_hour_min` 6, `night_start_hour` 22; Hunger-Notweckung ab 65 (frühestens nach 30 min); hunger ×0.35, **energy +0.6**, fun ×0. |
| `watch_cinema` | 80 min; fun +0.34, energy −0.01; Stop bei hunger ≥70 / energy ≤18 / health ≤35. |
| `study` | 90 min; Stop bei hunger ≥70 / health ≤35. (Bildungsgewinn: `buildings.university.education_gain`.) |
| `work` | Mittagspause `lunch_start_minute` 690 (11:30) – `lunch_end_minute` 810 (13:30); needs-Mul hunger 1.8 / energy 1.625 / fun 2.0; Extra-Drain/min energy 0.05, hunger 0.04, fun 0.03; Stop bei health ≤35 / hunger ≥75. |
| `socialize` | 30 (20–40) min; **social +1.5/min**; Stop bei hunger ≥70 / health ≤35. |
| `hospital_treatment` | Normal: 20–70 min bis health 75, health +0.95/min × Servicequalität. Notfall: 15–55 min bis health 85, health +1.7/min × Servicequalität. |

---

## planner

GOAP-Zielauswahl: Schwellen, Prioritäts-Skalen und Gewichte.

| Key | Default | Wirkung |
| --- | --- | --- |
| `critical_hunger` | `80.0` | Ab hier ist Hunger ein Notfall (überschreibt Soft-Ziele). |
| `critical_energy` | `10.0` | Ab hier ist Energie ein Notfall. |
| `low_health` | `35.0` | Schwelle „niedrige Gesundheit". |
| `critical_health` | `20.0` | Schwelle „kritische Gesundheit". |
| `work_commute_buffer_min` | `30` | Pufferminuten, um rechtzeitig zur Schicht aufzubrechen. |
| `hunger_priority_scale` | `40.0` | Skalierung der Hunger-Priorität. |
| `energy_priority_scale` | `40.0` | Skalierung der Energie-Priorität. |
| `fun_priority_scale` | `35.0` | Skalierung der Fun-Priorität. |
| `social_priority_scale` | `35.0` | Skalierung der Social-Priorität. |
| `goal_priority_hunger_weight` | `1.25` | Gewicht des Hunger-Ziels in der Endauswahl. |
| `goal_priority_energy_weight` | `1.1` | Gewicht des Energie-Ziels. |
| `goal_priority_education_weight` | `0.95` | Gewicht des Bildungs-Ziels. |
| `goal_priority_work_weight` | `0.9` | Gewicht des Arbeits-Ziels. |
| `goal_priority_fun_weight` | `0.65` | Gewicht des Fun-Ziels. |
| `goal_priority_social_weight` | `0.6` | Gewicht des Social-Ziels. |
| `goal_priority_health_weight` | `1.6` | Gewicht des Health-/Hospital-Ziels. |
| `work_need_base_priority` | `0.45` | Grund-Priorität für Arbeit. |
| `work_need_remaining_weight` | `0.55` | Zusatzgewicht nach verbleibender Schichtzeit. |
| `low_health_hunger_alert_threshold` | `65.0` | Hunger-Alarmschwelle bei niedriger Gesundheit. |
| `low_health_energy_alert_threshold` | `35.0` | Energie-Alarmschwelle bei niedriger Gesundheit. |
| `emergency_energy_threshold` | `8.0` | Energie-Notschwelle (sofort schlafen/erholen). |
| `fun_block_hunger_threshold` | `60.0` | Über diesem Hunger wird Freizeit blockiert. |
| `fun_block_energy_threshold` | `25.0` | Unter dieser Energie wird Freizeit blockiert. |
| `relax_home_min_energy_threshold` | `20.0` | Mindestenergie für „zuhause entspannen". |
| `work_fit_hunger_threshold` | `65.0` | Maximaler Hunger, um eine Schicht überhaupt anzutreten. |
| `fallback_home_travel_minutes` | `20` | Angenommene Heimreisezeit (Fallback-Planung). |
| `survival_home_travel_minutes` | `20` | Heimreisezeit in Überlebensplanung. |
| `survival_restaurant_travel_minutes` | `15` | Restaurant-Reisezeit (Überleben). |
| `survival_cafe_travel_minutes` | `12` | Cafe-Reisezeit (Snack-Fallback im Überleben). |
| `survival_supermarket_travel_minutes` | `18` | Supermarkt-Reisezeit (Überleben). |
| `work_travel_minutes` | `20` | Angenommene Arbeitsweg-Zeit. |

### planner.health

| Key | Default | Wirkung |
| --- | --- | --- |
| `visit_threshold` | `20.0` | Unter dieser Gesundheit plant der Bürger eine Hospital-Behandlung. |
| `emergency_threshold` | `5.0` | Unter dieser Gesundheit wird Notfallbehandlung priorisiert. |
| `priority_scale` | `20.0` | Skaliert, wie schnell das Health-Ziel an Priorität gewinnt. |
| `sick_work_skip_threshold` | `55.0` | Unter dieser Gesundheit kann ein Bürger krankheitsbedingt Arbeit auslassen. |
| `sick_work_skip_base_probability` / `_max_probability` | `0.18` / `0.75` | Tagesstabile Wahrscheinlichkeit fürs Auslassen der Schicht je nach Schwere. |

### planner.emotion

Stress-/Einsamkeitsmodell, das die Sozial-Priorität moduliert.

| Key | Default | Wirkung |
| --- | --- | --- |
| `enabled` | `true` | Emotionsmodell an/aus. |
| `stress_hunger_threshold` | `75.0` | Ab diesem Hunger entsteht Stress. |
| `stress_hunger_add` | `0.30` | Stresszuwachs durch Hunger. |
| `stress_energy_threshold` | `20.0` | Unter dieser Energie entsteht Stress. |
| `stress_energy_add` | `0.30` | Stresszuwachs durch Erschöpfung. |
| `loneliness_base` | `0.2` | Grund-Einsamkeit. |
| `loneliness_social_threshold` | `30.0` | Unter diesem Social wächst Einsamkeit. |
| `loneliness_social_add` | `0.25` | Einsamkeitszuwachs bei Sozialmangel. |
| `loneliness_home_night_add` | `0.05` | Zusatz-Einsamkeit nachts allein zu Hause. |
| `loneliness_social_gain` | `0.6` | Einsamkeitsabbau durch soziale Aktivität. |
| `stress_social_damp_threshold` | `0.85` | Ab diesem Stress wird Sozialbedürfnis gedämpft. |
| `stress_social_damp_mul` | `0.5` | Dämpfungsfaktor in dem Fall. |
| `social_mult_min` | `0.3` | Untergrenze des Sozial-Multiplikators. |
| `social_mult_max` | `2.0` | Obergrenze des Sozial-Multiplikators. |

### planner.personality

Übersetzt die gestreuten Persönlichkeitswerte in Prioritäts-Multiplikatoren.

| Key | Default | Wirkung |
| --- | --- | --- |
| `enabled` | `true` | Persönlichkeitsmodell an/aus. |
| `work_motivation_weight` | `1.0` | Gewicht der Arbeitsmotivation. |
| `work_motivation_min` / `_max` | `0.5` / `1.5` | Spanne des Arbeits-Multiplikators. |
| `fun_interest_midpoint` | `0.35` | Neutralpunkt des Fun-Interesses. |
| `fun_interest_scale` | `0.6` | Empfindlichkeit um den Neutralpunkt. |
| `fun_personality_min` / `_max` | `0.7` / `1.3` | Spanne des Fun-Multiplikators. |
| `sociability_midpoint` | `0.5` | Neutralpunkt der Geselligkeit. |
| `sociability_scale` | `0.6` | Empfindlichkeit der Geselligkeit. |
| `social_personality_min` / `_max` | `0.7` / `1.3` | Spanne des Sozial-Multiplikators. |

### planner.goal_cooldowns

Mindestpause (Spielminuten) zwischen Wiederholungen desselben Ziels; verhindert
Flackern.

| Key | Default | Wirkung |
| --- | --- | --- |
| `enabled` | `true` | Cooldowns an/aus. |
| `hunger` / `energy` / `education` / `health` / `work` | `0` | Keine Pause für überlebens-/pflichtnahe Ziele. |
| `fun` | `20` | 20 min Pause zwischen Freizeit-Zielen. |
| `social` | `25` | 25 min Pause zwischen Sozial-Zielen. |

---

## goap

Pro Bedürfnis-Planer: `*_cost` = relative Kosten einer GOAP-Aktion (niedriger =
bevorzugt), `*_travel_minutes` = angenommene Reisezeit für die Planung,
`safe_*`/`*_min`/`*_max` = Sicherheitsschwellen, ab denen geplant wird.

### goap.education

| Key | Default | Wirkung |
| --- | --- | --- |
| `health_min` | `35.0` | Mindestgesundheit, um Studium zu planen. |
| `hunger_max` | `70.0` | Maximaler Hunger, um Studium zu planen. |
| `go_university_cost` | `1.0` | Kosten „zur Uni gehen". |
| `study_cost` | `0.65` | Kosten „studieren". |
| `travel_minutes` | `24` | Angenommene Reisezeit zur Uni. |

### goap.health

| Key | Default | Wirkung |
| --- | --- | --- |
| `go_hospital_cost` | `0.45` | Wegekosten zum Hospital. |
| `treatment_cost` | `0.25` | Aktionskosten der Behandlung. |
| `travel_minutes` | `18` | Angenommene Reisezeit zum Hospital. |

### goap.work

| Key | Default | Wirkung |
| --- | --- | --- |
| `health_min` | `35.0` | Mindestgesundheit für Arbeit. |
| `hunger_max` | `65.0` | Maximaler Hunger, um Arbeit zu planen. |
| `go_work_cost` | `0.65` | Kosten „zur Arbeit gehen". |
| `work_shift_cost` | `0.5` | Kosten „Schicht arbeiten". |
| `travel_minutes` | `20` | Angenommene Arbeitsweg-Zeit. |

### goap.fun

| Key | Default | Wirkung |
| --- | --- | --- |
| `safe_hunger_max` | `60.0` | Maximaler Hunger für Freizeit. |
| `safe_energy_min` | `25.0` | Mindestenergie für Freizeit. |
| `safe_health_min` | `35.0` | Mindestgesundheit für Freizeit. |
| `energy_ok_min` | `18.0` | Untere Energie-Toleranz. |
| `go_home_cost` / `go_park_cost` / `go_shop_cost` / `go_cinema_cost` | `1.2` / `1.0` / `0.95` / `1.1` | Wegekosten je Freizeitziel. |
| `relax_park_cost` / `buy_clothes_cost` / `watch_cinema_cost` / `relax_home_cost` | `0.75` / `0.65` / `0.7` / `1.8` | Aktionskosten je Freizeitart. |
| `home_/park_/shop_/cinema_travel_minutes` | `20` / `22` / `20` / `24` | Reisezeiten je Ziel. |

### goap.hunger

| Key | Default | Wirkung |
| --- | --- | --- |
| `go_home_cost` / `go_restaurant_cost` / `go_cafe_cost` / `go_supermarket_cost` | `1.3` / `1.0` / `1.15` / `1.1` | Wegekosten je Essensziel. |
| `buy_groceries_cost` / `eat_home_cost` / `eat_restaurant_cost` / `eat_cafe_cost` | `0.8` / `0.9` / `0.8` / `1.0` | Aktionskosten. |
| `home_/restaurant_/cafe_/supermarket_travel_minutes` | `20` / `15` / `12` / `18` | Reisezeiten. |

### goap.energy

| Key | Default | Wirkung |
| --- | --- | --- |
| `go_home_cost` / `go_bench_cost` | `0.9` / `1.0` | Wegekosten zu Erholungsort. |
| `sleep_cost` / `relax_bench_cost` / `relax_home_cost` | `0.6` / `0.85` / `1.1` | Aktionskosten je Erholungsart. |
| `home_travel_minutes` | `20` | Heimreisezeit. |

### goap.social

| Key | Default | Wirkung |
| --- | --- | --- |
| `safe_hunger_max` / `safe_energy_min` / `safe_health_min` | `60.0` / `25.0` / `35.0` | Sicherheitsschwellen für Sozialaktivität. |
| `energy_ok_min` | `18.0` | Untere Energie-Toleranz. |
| `go_park_cost` / `socialize_cost` | `1.0` / `0.75` | Wege-/Aktionskosten. |
| `park_travel_minutes` | `22` | Reisezeit zum Park. |

---

## buildings

Pro Gebäudetyp. Gemeinsame Keys: `capacity` (Besucherplätze), `job_capacity`
(Stellen), `open_hour`/`close_hour` (Öffnung, Stunde 0–23),
`base_operating_cost` (tägliche Betriebskosten öffentlicher Gebäude). Typ-spezifische
Keys sind unten genannt.

| Typ | Werte |
| --- | --- |
| `residential` | capacity 10; `rent_per_day` 15. |
| `restaurant` | capacity 20, jobs 5, 8–22 Uhr; `meal_price` 15; Stock 48, Restock-Ziel 70, Batch 30. |
| `cafe` | capacity 18, jobs 3, 7–20 Uhr; `drink_price` 8; Drink-Stock 45, Ziel 70, Batch 26; `snack_price` 9; Snack-Stock 36, Ziel 60, Batch 22. |
| `shop` | capacity 25, jobs 4, 9–20 Uhr; `item_price` 18; `fun_gain` 5.0; Kleidung-Stock 34, Ziel 56, Batch 20. |
| `supermarket` | capacity 30, jobs 6, 7–22 Uhr; `grocery_price` 10, `groceries_per_purchase` 3, `clothing_price` 24; Lebensmittel-Stock 60, Ziel 90, Batch 35. |
| `cinema` | capacity 35, jobs 5, 12–23 Uhr; `ticket_price` 14. |
| `city_hall` | capacity 15, jobs 5, 6–19 Uhr. |
| `hospital` | capacity 20, jobs 5, 0–24 Uhr; `patient_capacity` 20; `treatment_capacity_per_hour` 6; `service_quality` 1.0; `treatment_price` 25; `emergency_treatment_price` 60; `daily_operating_cost` 250; `patient_wait_timeout_minutes` 180; `charity_care_city_subsidy_ratio` 1.0; `citizen_payment_reserve` 35. |
| `university` | capacity 40, jobs 8, 7–21 Uhr; `base_operating_cost` 110; **`education_gain` 1** (Bildungsstufen pro Studien-Session). |
| `park` | capacity 40, jobs 2, 6–23 Uhr; `base_operating_cost` 32. Navigations-Tuning: `navigation_blocker_margin` 1.35, `entrance_clearance_width` 2.6, `entrance_clearance_depth` 1.9, `entrance_trigger_radius` 0.9, `entrance_trigger_outset` 0.8. |
| `farm` | capacity 8, jobs 6, 5–19 Uhr; `base_food_output_per_day` 60, `production_cost_per_unit` 1; Crops grow for 2 days, then workers harvest into 300 food storage. `Fahrer` workers deliver stored food directly to supermarkets (`direct_delivery_batch_per_supermarket` 35, unload 10 min, price multiplier 0.85); remaining food can fall back to market export. |
| `factory` | capacity 10, jobs 8, 6–21 Uhr; `clothes_output_per_day` 25, `entertainment_output_per_day` 40, `production_cost_per_unit` 2. |
| `gas_station` | capacity 14, jobs 4, 6–23 Uhr; `fuel_price` 7; Stock 90, Ziel 140, Batch 50; `base_vehicle_sales_per_day` 18, `citizen_vehicle_demand_factor` 0.35, `fuel_units_per_vehicle` 2, `base_operating_cost` 36. |

---

## Zeit-Kontext

Es gibt **keine Monate/Jahre** im Code — nur fortlaufende Tage + 7-Tage-Wochentag,
Payday täglich. Reale Dauer eines Spieltags = `720 ÷ speed_multiplier` Sekunden:

| Tempo | 1 Tag real | 1 Woche (7 T) | 1 „Jahr" (365 T) |
| --- | --- | --- | --- |
| 1x | 12 min | 84 min | 73 h |
| 4x | 3 min | 21 min | 18 h |

## Tuning-Rezepte

- **Lohn-Aufstieg zu langsam?** `economy.jobs.wage_progression.experience_daily_strong`
  erhöhen und/oder `experience_bonus_max` anheben.
- **Mehr Firmen sollen Boni geben?** `profit_strong_min` senken.
- **Bürger arbeiten zu selten / zu oft?** `planner.goal_priority_work_weight` bzw.
  `citizen.thresholds.work_motivation_base` anpassen.
- **Bürger verhungern/ermüden?** `citizen.needs.*_rate_per_min` senken oder
  `actions.*` (z. B. `eat_*`, `sleep`) wirksamer machen.
- **Stadt/Gebäude pleite?** `economy.city_hall.*` (Steuern, Förderung) oder
  `building.maintenance_cost_per_day` justieren.

Nach jeder Änderung: Neustart oder `BalanceConfig.reload()`. Die Tests lesen die
Werte aus der Config und bleiben gültig.
