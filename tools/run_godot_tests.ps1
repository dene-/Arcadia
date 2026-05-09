$ErrorActionPreference = "Stop"

$Godot = $env:GODOT
if ([string]::IsNullOrWhiteSpace($Godot)) {
    $Godot = [Environment]::GetEnvironmentVariable("GODOT", "User")
}
if ([string]::IsNullOrWhiteSpace($Godot)) {
    $Godot = "godot"
}

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

& $Godot --headless --path $ProjectRoot --script res://tests/test_runner.gd
exit $LASTEXITCODE
