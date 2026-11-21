<#
  Packages a Release build of Glance for Windows as a portable zip.

    powershell -ExecutionPolicy Bypass -File GlanceWin\package.ps1 [-Version 0.1.0]

  Output: GlanceWin\dist\Glance-<version>-win-x64.zip (self-contained x64; no .NET install
  needed). Runs the tests first and stops if they fail. The installer and update feed are
  Phase 7 (Velopack).
#>
param(
    [string]$Version = "",
    [switch]$SkipTests
)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if (-not $Version) {
    $Version = ([xml](Get-Content (Join-Path $root "Directory.Build.props"))).Project.PropertyGroup.Version
}
$name = "Glance-$Version-win-x64"
$dist = Join-Path $root "dist"
$out = Join-Path $dist $name
$zip = Join-Path $dist "$name.zip"

if (-not $SkipTests) {
    Write-Host "Running tests..."
    dotnet test (Join-Path $root "tests\Glance.Tests\Glance.Tests.csproj") -c Release -nologo -v q
    if ($LASTEXITCODE -ne 0) { throw "Tests failed; nothing was packaged." }
}

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
if (Test-Path $zip) { Remove-Item $zip -Force }

Write-Host "Publishing $name..."
dotnet publish (Join-Path $root "src\Glance.App\Glance.App.csproj") -c Release -r win-x64 --self-contained true `
    -p:Version=$Version -p:PublishReadyToRun=true -p:DebugType=none -p:GenerateDocumentationFile=false `
    -o $out -nologo -v q
if ($LASTEXITCODE -ne 0) { throw "Publish failed." }
if (-not (Test-Path (Join-Path $out "Glance.exe"))) { throw "Glance.exe is missing from the publish output." }

Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -CompressionLevel Optimal
$size = "{0:N1} MB" -f ((Get-Item $zip).Length / 1MB)
Write-Host "Done: $zip ($size)"
