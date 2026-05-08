# GDScript Review Checklist

Use this checklist when reviewing Godot GDScript code.

## Language and version

- Code is Godot 4.x GDScript.
- No C#, C++, VisualScript, shader code, Python, JavaScript, or pseudocode is introduced unless explicitly requested.

## Style

- File names use `snake_case.gd`.
- Classes use `PascalCase`.
- Functions, variables, signals, groups, and input actions use `snake_case`.
- Constants and enum members use `CONSTANT_CASE`.
- Private helpers and member variables use `_prefix`.
- Code follows Godot ordering: annotations, class, extends, signals, enums, constants, exports, variables, onready variables, lifecycle, public methods, private methods, callbacks.

## Typing

- Functions have return types.
- Parameters are typed.
- Member variables are typed.
- Signal callbacks are typed.
- Typed arrays and dictionaries are used where practical.
- `:=` is used only when inference is obvious.

## Architecture

- Scene responsibilities are clear.
- Signals are used for cross-scene events.
- Autoloads are used only for broad-scoped systems.
- Reusable data is represented by `Resource`.
- Data-only objects are not unnecessarily implemented as nodes.

## Runtime correctness

- Physics logic is in `_physics_process()`.
- Visual/non-physics frame logic is in `_process()`.
- Input is handled with Input Map actions.
- Required child nodes/resources fail early with `assert()` or clear errors.
- Signal connections do not duplicate accidentally.
- Node paths are valid relative to the script owner.

## Performance

- Stable node references are cached.
- Per-frame allocation is avoided when practical.
- Idle processing is disabled.
- Frequent resource loading is not done in performance-sensitive code.
