# 🐛 PROBLEM: CITIZEN BLEIBT IM RESTAURANT STECKEN

## ❌ DAS PROBLEM

### Was passiert:
```
1. Citizen hat hunger > 60.0
2. Citizen geht zum Restaurant
3. Citizen isst (hunger sinkt von 65 → 30)
4. Jetzt: hunger = 30, energy = 40, keine Arbeitszeit
5. Keine Bedingung trifft zu → IDLE
6. Code macht NICHTS
7. current_location bleibt "Restaurant"
8. ❌ CITIZEN BLEIBT IM RESTAURANT STECKEN!
```

### Code-Analyse (ALTER CODE):

```gdscript
func plan_next_action(world: World) -> void:
    var hour := world.time.get_hour()

    # 1) SCHLAF: wenn müde
    if needs.energy > 80.0 and home != null:
        # ... gehe nach Hause und schlafe
        return

    # 2) ARBEIT: wenn Arbeitszeit
    if job != null and job.workplace != null and hour >= job.start_hour and hour < job.end_hour:
        # ... gehe zur Arbeit
        return

    # 3) ESSEN: wenn hungrig
    if needs.hunger > 60.0 and favorite_restaurant != null:
        # ... gehe zum Restaurant
        return

    # 4) IDLE: ??? NICHTS ???
    # ❌ Hier fehlt Code!
    # ❌ Citizen macht einfach nichts
    # ❌ bleibt wo er ist (im Restaurant)
```

---

## ✅ DIE LÖSUNG

### Was jetzt passiert:

```
1. Citizen hat hunger > 60.0
2. Citizen geht zum Restaurant
3. Citizen isst (hunger sinkt von 65 → 30)
4. Jetzt: hunger = 30, energy = 40, keine Arbeitszeit
5. Keine High-Priority Bedingung trifft zu
6. ✅ IDLE-Fall: Gehe nach Hause!
7. Citizen geht nach Hause
8. ✅ Zu Hause: Entspanne dich (RelaxAtHomeAction)
9. ✅ Fun und Energy sinken langsam
10. ✅ CITIZEN HAT JETZT EIN LEBEN!
```

### Code (NEUER CODE):

```gdscript
func plan_next_action(world: World) -> void:
    var hour := world.time.get_hour()

    # 1) SCHLAF: wenn müde
    if needs.energy > 80.0 and home != null:
        if current_location != home:
            _start_action(GoToBuildingAction.new(home, 20), world)
            return
        _start_action(SleepAction.new(120), world)
        return

    # 2) ARBEIT: wenn Arbeitszeit
    if job != null and job.workplace != null and hour >= job.start_hour and hour < job.end_hour:
        if current_location != job.workplace:
            _start_action(GoToBuildingAction.new(job.workplace, 20), world)
            return
        _start_action(WorkAction.new(job, 60), world)
        return

    # 3) ESSEN: wenn hungrig
    if needs.hunger > 60.0 and favorite_restaurant != null:
        if current_location != favorite_restaurant:
            _start_action(GoToBuildingAction.new(favorite_restaurant, 15), world)
            return
        _start_action(EatAtRestaurantAction.new(favorite_restaurant, 30), world)
        return

    # 4) IDLE / FREIZEIT: ✅ NEUE LOGIK!
    if home != null:
        if current_location != home:
            _start_action(GoToBuildingAction.new(home, 20), world)
            return
        # Zu Hause angekommen -> Entspanne dich
        _start_action(RelaxAtHomeAction.new(30), world)
        return
```

---

## 📊 PRIORITÄTEN-ÜBERSICHT

```
┌─────────────────────────────────────────────────────────┐
│  HÖCHSTE PRIORITÄT                                      │
├─────────────────────────────────────────────────────────┤
│  1. SCHLAF       (energy > 80.0)                        │
│     → Gehe nach Hause und schlafe                       │
├─────────────────────────────────────────────────────────┤
│  2. ARBEIT       (Arbeitszeit 9-17 Uhr)                 │
│     → Gehe zur Arbeit                                   │
├─────────────────────────────────────────────────────────┤
│  3. ESSEN        (hunger > 60.0)                        │
│     → Gehe zum Restaurant                               │
├─────────────────────────────────────────────────────────┤
│  4. FREIZEIT     (sonst)                ✅ NEU!         │
│     → Gehe nach Hause und entspanne dich                │
├─────────────────────────────────────────────────────────┤
│  NIEDRIGSTE PRIORITÄT                                   │
└─────────────────────────────────────────────────────────┘
```

---

## 🎯 TYPISCHER TAGESABLAUF (NACH DEM FIX)

```
08:00 - 09:00  🏠 Zu Hause entspannen (Relax)
09:00 - 12:00  💼 Arbeiten (Work)
12:00 - 12:30  🍔 Mittagessen (Eat)
12:30 - 17:00  💼 Arbeiten (Work)
17:00 - 19:00  🏠 Nach Hause gehen, entspannen (Relax)
19:00 - 19:30  🍔 Abendessen (Eat)
19:30 - 23:00  🏠 Entspannen (Relax)
23:00 - 07:00  😴 Schlafen (Sleep)
```

---

## 📁 NEUE DATEIEN

### 1. **RelaxAtHomeAction.gd** (NEU)
Eine neue Action für Freizeit/Idle-Verhalten:
- Dauer: 30 Minuten (anpassbar)
- Effekt: fun und energy sinken langsam
- Macht den Citizen "menschlicher"

### 2. **Citizen_FINAL.gd** (VERBESSERT)
Die finale Version mit:
- ✅ Automatischer Node-Suche
- ✅ Idle-Verhalten (geht nach Hause)
- ✅ Debug-Ausgaben
- ✅ Verhindert "im Restaurant stecken bleiben"

---

## 🚀 INSTALLATION

### Schritt 1: Neue Action hinzufügen
```
RelaxAtHomeAction.gd → ins Projektverzeichnis kopieren
```

### Schritt 2: Citizen.gd ersetzen
```
Citizen.gd → mit Citizen_FINAL.gd ersetzen
```

### Schritt 3: Testen
```
Starte die Simulation und beobachte die Console:

[Citizen Alex] Starting action: Eat (location: Restaurant)
[Citizen Alex] Starting action: GoTo (location: Restaurant)
[Citizen Alex] Starting action: Relax (location: HomeBlock A)
```

---

## 🎮 ERWEITERTE MÖGLICHKEITEN

Du kannst jetzt weitere Idle-Aktionen hinzufügen:

### WanderAction.gd
```gdscript
extends Action
class_name WanderAction

# Citizen geht spazieren
```

### VisitFriendAction.gd
```gdscript
extends Action
class_name VisitFriendAction

# Citizen besucht einen Freund
```

### ShoppingAction.gd
```gdscript
extends Action
class_name ShoppingAction

# Citizen geht einkaufen
```

Dann kannst du in `plan_next_action()` entscheiden:

```gdscript
# 4) FREIZEIT
if home != null:
    if current_location != home:
        _start_action(GoToBuildingAction.new(home, 20), world)
        return
    
    # Zufällige Aktivität wählen
    var activities = [
        RelaxAtHomeAction.new(30),
        WanderAction.new(60),
        ShoppingAction.new(45)
    ]
    _start_action(activities[randi() % activities.size()], world)
    return
```

---

## ✨ ZUSAMMENFASSUNG

**Problem:** 
- ❌ Citizen blieb im Restaurant stecken
- ❌ Kein Idle-Verhalten definiert

**Lösung:**
- ✅ Neue `RelaxAtHomeAction` erstellt
- ✅ Idle-Fall in `plan_next_action()` hinzugefügt
- ✅ Citizen geht nach Hause wenn nichts zu tun ist
- ✅ Debug-Ausgaben zeigen was passiert

**Ergebnis:**
- 🎉 Citizen hat jetzt einen natürlichen Tagesablauf!
- 🎉 Bewegt sich zwischen Home, Work und Restaurant
- 🎉 Bleibt nicht mehr stecken!
