$ErrorActionPreference = "Stop"

$Godot = $env:GODOT
if ([string]::IsNullOrWhiteSpace($Godot)) {
    $Godot = [Environment]::GetEnvironmentVariable("GODOT", "User")
}
if ([string]::IsNullOrWhiteSpace($Godot)) {
    $Godot = "godot"
}

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$StdoutPath = [System.IO.Path]::GetTempFileName()
$StderrPath = [System.IO.Path]::GetTempFileName()

try {
    $GodotProcess = Start-Process `
        -FilePath $Godot `
        -ArgumentList @("--headless", "--path", $ProjectRoot, "--script", "res://tests/test_runner.gd") `
        -NoNewWindow `
        -Wait `
        -PassThru `
        -RedirectStandardOutput $StdoutPath `
        -RedirectStandardError $StderrPath

    $Output = @()
    if (Test-Path $StdoutPath) {
        $Output += Get-Content $StdoutPath
    }
    if (Test-Path $StderrPath) {
        $Output += Get-Content $StderrPath
    }
    $Output | Write-Output
    $GodotExitCode = $GodotProcess.ExitCode
}
finally {
    Remove-Item -LiteralPath $StdoutPath, $StderrPath -ErrorAction SilentlyContinue
}

if ($GodotExitCode -ne 0) {
    exit $GodotExitCode
}

$FailurePattern = "Godot tests failed|No Godot tests found|SCRIPT ERROR|Can't load script|Failed to load script"
if (($Output -join "`n") -match $FailurePattern) {
    exit 1
}

exit 0
