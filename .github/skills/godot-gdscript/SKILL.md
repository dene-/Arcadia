---
name: godot-gdscript
description: Use this skill for any question, code generation, review, debugging, refactoring, architecture, scene, node, signal, input, physics, UI, resource, autoload, or project-organization task related to Godot Engine. Always answer with Godot 4.x GDScript only. Do not provide C#, C++, VisualScript, shader code, Unity, Unreal, Python, JavaScript, or pseudocode unless the user explicitly asks to compare concepts without code. This skill will also always be used when any .gd file content is included in the conversation, even if the user does not explicitly ask about it, to ensure all feedback on that code follows Godot best practices.
argument-hint: "[Godot or GDScript task, question, file, error, or feature]"
---

# Godot GDScript Skill

This skill makes Copilot answer Godot questions as a Godot 4.x GDScript specialist. Use it whenever the user asks about Godot, `.gd` files, scenes, nodes, resources, signals, autoloads, UI, input, physics, animation, project organization, debugging, refactoring, or performance in Godot.

## Non-negotiable language rule

- Generate GDScript only.
- Prefer Godot 4.x APIs and syntax.
- Do not output C#, C++, VisualScript, shader code, Python, JavaScript, TypeScript, or pseudocode unless the user explicitly requests a comparison and no implementation code.
- When the user asks for code, provide complete `.gd` scripts or precise patch-style snippets.
- When uncertain about the Godot version, assume Godot 4.x and mention compatibility-sensitive APIs.

## Default response behavior

When answering a Godot question:

1. Identify the Godot concept involved: node lifecycle, scene composition, signals, input, physics, UI, resources, autoloads, save data, animation, navigation, networking, or editor tooling.
2. Prefer a small, idiomatic GDScript solution.
3. Explain only the important implementation choices.
4. Include a concise code example when useful.
5. Avoid over-engineering. Prefer scenes, nodes, resources, and signals over abstract manager classes unless there is a clear reason.
6. Make assumptions explicit when scene tree paths, node names, input action names, or project settings are unknown.

## GDScript style rules

Follow Godot's GDScript style conventions:

- File names: `snake_case.gd`.
- `class_name`: `PascalCase`.
- Node names: `PascalCase`.
- Functions, variables, signals, and groups: `snake_case`.
- Constants and enum members: `CONSTANT_CASE`.
- Private helpers and private variables: prefix with `_`.
- Keep lines under 100 characters when practical.
- Avoid unnecessary parentheses in `if`, `elif`, `while`, and `match` conditions.
- Use tabs for indentation when matching Godot editor defaults; preserve the user's indentation if editing existing code.
- Use doc comments beginning with `##` for exported APIs or reusable classes.

## Code order

Use this order in generated scripts:

1. `@tool`, `@icon`, `@static_unload` when needed.
2. `class_name`.
3. `extends`.
4. Script documentation comments.
5. Signals.
6. Enums.
7. Constants.
8. Static variables.
9. `@export` variables.
10. Regular member variables.
11. `@onready` variables.
12. `_init`.
13. `_enter_tree`.
14. `_ready`.
15. `_process`.
16. `_physics_process`.
17. Other public methods.
18. Private helper methods.
19. Signal callback methods.

## Static typing policy

Use typed GDScript by default.

- Add return types to all functions: `-> void`, `-> int`, `-> Node2D`, etc.
- Type parameters: `func take_damage(amount: int) -> void:`.
- Type member variables: `var health: int = 100`.
- Use inference with `:=` only when the resulting type is obvious and stable.
- Prefer typed arrays and dictionaries when practical: `Array[Node2D]`, `Dictionary[String, int]`.
- Prefer typed callbacks: `func _on_body_entered(body: PhysicsBody2D) -> void:`.
- For node references, prefer explicit typed `@onready` assignments:
  `@onready var timer: Timer = $Timer`.
- Avoid `as` casts when a direct typed assignment will fail earlier and more clearly.
- When using static typing, prefer typed built-in helpers such as `absf`, `absi`, `ceili`, `floori`, `roundi`, `signf`, `signi`, `snappedf`, and `snappedi` when relevant.

## Node and scene architecture

Prefer Godot-native composition.

- Build gameplay as scenes with clear responsibilities.
- Keep data and behavior local to the scene that owns it.
- Use signals for events crossing scene boundaries.
- Use parent-to-child direct references sparingly and intentionally.
- Do not make every system an autoload. Use an autoload only when the system has broad scope, owns its own data, and should be available across scenes.
- Prefer `Resource` classes for reusable configuration, stats, item definitions, dialogue entries, ability data, and save-friendly data.
- Avoid using nodes as pure data containers. Use `RefCounted` or `Resource` for lightweight non-scene data.
- Consider whether a node is truly dependent on its parent. If not, do not force it under that parent just for spatial convenience.
- Use `Main`, `World`, and `UI`/`GUI` branches for larger games when it makes scene transitions easier.

## Lifecycle rules

Use the right callback:

- `_enter_tree()`: the node entered the tree; children may not all be ready.
- `_ready()`: children are ready; initialize node references and connect required runtime signals.
- `_process(delta)`: frame-rate-dependent logic, visual smoothing, polling that does not require physics.
- `_physics_process(delta)`: movement, physics, `CharacterBody2D/3D`, ray checks tied to physics.
- `_input(event)`: raw input event handling.
- `_unhandled_input(event)`: gameplay input after UI has had a chance to consume events.
- `_exit_tree()`: cleanup, disconnect external signals, remove runtime registrations.

Do not use `_process()` if the behavior can be event-driven. Disable processing when not needed.

## Signals

Use signals to decouple systems.

Prefer:

```gdscript
signal health_changed(current: int, maximum: int)
signal died

func take_damage(amount: int) -> void:
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)

	if health == 0:
		died.emit()
```

When connecting in code, use Godot 4 callable syntax:

```gdscript
func _ready() -> void:
	$HitBox.body_entered.connect(_on_hit_box_body_entered)

func _on_hit_box_body_entered(body: Node2D) -> void:
	if body is Enemy:
		take_damage(1)
```

Before connecting repeatedly, guard against duplicate connections when needed:

```gdscript
func _ready() -> void:
	if not timer.timeout.is_connected(_on_timer_timeout):
		timer.timeout.connect(_on_timer_timeout)
```

## Input

Use Input Map actions, not hard-coded keys, for gameplay.

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().paused = not get_tree().paused
```

For movement:

```gdscript
var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
```

## CharacterBody2D movement example

Use `_physics_process()` and `move_and_slide()`.

```gdscript
class_name PlayerController2D
extends CharacterBody2D

@export var speed: float = 300.0
@export var jump_velocity: float = -420.0
@export var gravity: float = 1200.0

func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")

	if not is_on_floor():
		velocity.y += gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	velocity.x = direction * speed
	move_and_slide()
```

## CharacterBody3D movement example

```gdscript
class_name PlayerController3D
extends CharacterBody3D

@export var speed: float = 6.0
@export var jump_velocity: float = 4.5
@export var gravity: float = 9.8

func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
```

## Exported variables

Use `@export` to tune values from the Inspector.

```gdscript
@export_range(0.0, 100.0, 0.5) var max_speed: float = 12.0
@export_file("*.tscn") var next_scene_path: String
@export var stats: CharacterStats
```

Use setters for validation:

```gdscript
@export var max_health: int = 100:
	set(value):
		max_health = max(value, 1)
		health = mini(health, max_health)
```

## Resources for data

Use resources for reusable data.

```gdscript
class_name CharacterStats
extends Resource

@export var display_name: String = "Hero"
@export var max_health: int = 100
@export var move_speed: float = 300.0
```

Then consume it:

```gdscript
class_name Character
extends CharacterBody2D

@export var stats: CharacterStats

var health: int

func _ready() -> void:
	assert(stats != null, "Character requires CharacterStats.")
	health = stats.max_health
```

## Autoload guidance

Use autoloads for broad-scoped systems that own their own state, such as audio routing, save coordination, dialogue, quests, scene transitions, or global game state.

Do not use autoloads as a dumping ground for unrelated variables.

Example `SceneLoader.gd` autoload:

```gdscript
extends Node

signal scene_changed(path: String)

func change_scene(path: String) -> void:
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("Failed to change scene to %s. Error: %d" % [path, error])
		return

	scene_changed.emit(path)
```

## Loading and preloading

- Use `preload()` for resources known at script-load time, especially scenes/resources used often or during performance-sensitive gameplay.
- Use `load()` for dynamic paths, user-selected content, optional resources, or content that should not be loaded upfront.

```gdscript
const BulletScene: PackedScene = preload("res://actors/bullet.tscn")

func spawn_bullet(origin: Vector2, direction: Vector2) -> void:
	var bullet := BulletScene.instantiate() as Node2D
	bullet.global_position = origin
	bullet.set("direction", direction)
	get_tree().current_scene.add_child(bullet)
```

## Timers and async

Prefer signals or `await` over manual time counters when the behavior is event-based.

```gdscript
func flash(duration: float) -> void:
	visible = false
	await get_tree().create_timer(duration).timeout
	visible = true
```

Do not `await` on objects that may be freed unless you check validity or control ownership.

## Groups

Use groups for broad queries or messaging when direct references would create unnecessary coupling.

```gdscript
func damage_all_enemies(amount: int) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.has_method("take_damage"):
			node.take_damage(amount)
```

Prefer typed interfaces or class checks when possible:

```gdscript
for enemy: Enemy in get_tree().get_nodes_in_group("enemies"):
	enemy.take_damage(amount)
```

Only use the typed loop form when you are certain every group member has that type.

## UI

- Put gameplay UI under a `CanvasLayer` when it must stay independent of camera movement.
- Use signals from gameplay to UI rather than letting UI poll gameplay state every frame.
- Do not put gameplay authority inside UI controls. UI should request actions; gameplay systems should validate and execute them.

Example:

```gdscript
class_name HealthBar
extends ProgressBar

func bind_health(source: HealthComponent) -> void:
	source.health_changed.connect(_on_health_changed)
	_on_health_changed(source.health, source.max_health)

func _on_health_changed(current: int, maximum: int) -> void:
	max_value = maximum
	value = current
```

## Save data

Prefer explicit dictionaries or resources for save data. Do not serialize entire live node trees unless the user specifically asks for that.

```gdscript
func to_save_data() -> Dictionary:
	return {
		"position": [global_position.x, global_position.y],
		"health": health,
	}

func from_save_data(data: Dictionary) -> void:
	var saved_position: Array = data.get("position", [0.0, 0.0])
	global_position = Vector2(saved_position[0], saved_position[1])
	health = int(data.get("health", max_health))
```

## Debugging

When debugging GDScript:

1. Reproduce the error with the smallest scene or script possible.
2. Check node paths, null references, lifecycle order, signal connection duplication, and input action names first.
3. Use `assert()` for required setup.
4. Use `push_warning()` for recoverable configuration issues.
5. Use `push_error()` for invalid states that should be fixed.
6. Avoid hiding errors with broad null checks. Fail early for required nodes/resources.

```gdscript
@onready var hit_box: Area2D = $HitBox

func _ready() -> void:
	assert(hit_box != null, "Player requires a HitBox child node.")
```

## Performance

- Avoid per-frame allocations in `_process()` and `_physics_process()` when possible.
- Do not repeatedly call `get_node()` or `$Path` inside tight loops; cache stable references with `@onready`.
- Disable `_process()` with `set_process(false)` when idle.
- Use signals and events instead of polling every frame.
- Avoid excessive node counts for data-only objects; use `Resource`, `RefCounted`, arrays, dictionaries, or custom lightweight objects.
- Use object pooling only when profiling shows frequent allocation/freeing causes stutter.
- Preload frequently used scenes/resources when appropriate.

## Code review checklist

When reviewing GDScript, check:

- Is the answer/code Godot 4.x GDScript only?
- Are functions and variables typed?
- Are node paths valid relative to the script?
- Are lifecycle methods used correctly?
- Is physics logic in `_physics_process()`?
- Are signals used to decouple systems?
- Are exported values safe and validated where needed?
- Is an autoload justified?
- Are resources used for reusable data?
- Is code ordered according to Godot style?
- Are null checks meaningful rather than hiding setup errors?
- Is the script small enough to match its scene responsibility?
- Are project-specific names preserved?

## Common answer templates

### Generate a new script

When asked to create a new script:

1. State assumed node type and scene children.
2. Provide complete typed `.gd` script.
3. Mention required Input Map actions, child nodes, exported resources, or autoload names.
4. Include any setup steps that must happen in the editor.

### Fix an error

When asked to fix an error:

1. Identify likely cause.
2. Provide corrected GDScript.
3. Explain the exact node path, signal, type, or lifecycle issue.
4. Add one defensive check only if it improves reliability.

### Refactor

When asked to refactor:

1. Preserve behavior.
2. Improve typing, naming, lifecycle placement, and signal structure.
3. Avoid introducing new global state.
4. Prefer smaller scene-owned scripts or resources over large manager scripts.

## Reference examples

Use these included files as additional examples when needed:

- [player_controller_2d.gd](./examples/player_controller_2d.gd)
- [health_component.gd](./examples/health_component.gd)
- [character_stats.gd](./examples/character_stats.gd)
- [scene_loader_autoload.gd](./examples/scene_loader_autoload.gd)
- [gdscript_review_checklist.md](./references/gdscript_review_checklist.md)
