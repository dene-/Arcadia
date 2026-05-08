# Tests

Validation and test scripts live here.

Use this folder for temporary or permanent Godot validation scripts that load scenes, exercise resource behavior, or check gameplay systems. Temporary scripts should be removed after the validation run unless they are useful as repeatable tests.

Prefer headless validation commands:

```powershell
& ([Environment]::GetEnvironmentVariable('GODOT','User')) --headless --path . --script res://tests/example_test.gd
```
