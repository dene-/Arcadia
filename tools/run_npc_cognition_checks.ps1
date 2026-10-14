# Runs every NPC cognition check: the Godot unit runner, the fixed list of integration scripts and
# the backend tests (with GODOT exported so the Godot-driven server tests run instead of skipping).
# Every step runs even after a failure; a summary table follows and the exit status is non-zero
# when any step failed.
$ErrorActionPreference = "Stop"

$Godot = $env:GODOT
if ([string]::IsNullOrWhiteSpace($Godot)) {
    $Godot = [Environment]::GetEnvironmentVariable("GODOT", "User")
}
if ([string]::IsNullOrWhiteSpace($Godot)) {
    $Godot = "godot"
}

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$FailurePattern = "Godot tests failed|No Godot tests found|SCRIPT ERROR|Can't load script|Failed to load script"

$IntegrationTests = @(
    "town_emergency_flow_test",
    "npc_safety_world_test",
    "town_watch_test",
    "town_life_world_test",
    "town_interiors_test",
    "town_traffic_test",
    "actor_navigation_test",
    "actor_contacts_test",
    "combat_contact_test",
    "npc_combat_position_test",
    "pixel_camera_test",
    "npc_reset_world_test",
    "npc_cognition_scenarios_test",
    "npc_cognition_matrix_test",
    "npc_cognition_soak_test",
    "npc_runtime_smoke_test"
)

$Results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param([string]$Name, [string]$Result, [int]$Seconds)
    $Results.Add([pscustomobject]@{ Step = $Name; Result = $Result; Seconds = $Seconds })
}

# Fails the step on a non-zero exit or a failure pattern in the output.
function Invoke-GodotStep {
    param([string]$Name, [string[]]$Arguments)
    Write-Output "==> $Name"
    $Started = Get-Date
    $StdoutPath = [System.IO.Path]::GetTempFileName()
    $StderrPath = [System.IO.Path]::GetTempFileName()
    $Output = @()
    try {
        $GodotProcess = Start-Process `
            -FilePath $Godot `
            -ArgumentList (@("--headless", "--path", "`"$ProjectRoot`"") + $Arguments) `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $StdoutPath `
            -RedirectStandardError $StderrPath

        if (Test-Path $StdoutPath) {
            $Output += Get-Content $StdoutPath
        }
        if (Test-Path $StderrPath) {
            $Output += Get-Content $StderrPath
        }
        $Output | Write-Output
        $GodotExitCode = $GodotProcess.ExitCode
    }
    catch {
        Write-Output "Could not start ${Godot}: $_"
        $GodotExitCode = 127
    }
    finally {
        Remove-Item -LiteralPath $StdoutPath, $StderrPath -ErrorAction SilentlyContinue
    }

    $Result = "PASS"
    if ($GodotExitCode -ne 0) {
        $Result = "FAIL (exit $GodotExitCode)"
    }
    elseif (($Output -join "`n") -match $FailurePattern) {
        $Result = "FAIL (error output)"
    }
    Add-Result $Name $Result ([int]((Get-Date) - $Started).TotalSeconds)
}

Invoke-GodotStep "unit tests" @("--script", "res://tests/test_runner.gd")

foreach ($Test in $IntegrationTests) {
    if (-not (Test-Path (Join-Path $ProjectRoot "tests/integration/$Test.gd"))) {
        Write-Output "==> $Test"
        Write-Output "Missing tests/integration/$Test.gd"
        Add-Result $Test "FAIL (missing)" 0
        continue
    }
    Invoke-GodotStep $Test @("--fixed-fps", "60", "--script", "res://tests/integration/$Test.gd")
}

Write-Output "==> backend tests"
$Started = Get-Date
$PreviousGodot = $env:GODOT
$env:GODOT = $Godot
try {
    & npm --prefix (Join-Path $ProjectRoot "tools/server") test
    $NpmExitCode = $LASTEXITCODE
}
catch {
    Write-Output "Could not run npm: $_"
    $NpmExitCode = 127
}
finally {
    $env:GODOT = $PreviousGodot
}
$BackendResult = "PASS"
if ($NpmExitCode -ne 0) {
    $BackendResult = "FAIL (exit $NpmExitCode)"
}
Add-Result "backend tests" $BackendResult ([int]((Get-Date) - $Started).TotalSeconds)

Write-Output ""
$Results | Format-Table -AutoSize Step, Result, Seconds | Out-String -Width 120 | Write-Output

if (@($Results | Where-Object { $_.Result -ne "PASS" }).Count -gt 0) {
    Write-Output "NPC cognition checks failed"
    exit 1
}
Write-Output "NPC cognition checks passed"
exit 0
