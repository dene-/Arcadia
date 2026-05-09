$ErrorActionPreference = "Stop"

$Godot = $env:GODOT
if ([string]::IsNullOrWhiteSpace($Godot)) {
    $Godot = [Environment]::GetEnvironmentVariable("GODOT", "User")
}
if ([string]::IsNullOrWhiteSpace($Godot)) {
    $Godot = "godot"
}

& $Godot --headless --path . --script res://tests/test_runner.gd
exit $LASTEXITCODE
