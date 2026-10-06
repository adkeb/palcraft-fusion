# Unexecuted candidate for review. Uses an already installed compatible Editor.
# This script does not install an engine, create graph assets, or deploy to a game.
param([Parameter(Mandatory=$true)][string]$EditorRoot)
$ErrorActionPreference='Stop'
$project=Join-Path $PSScriptRoot 'Pal.uproject'
$editor=Join-Path $EditorRoot 'Engine\Binaries\Win64\UnrealEditor-Cmd.exe'
$versionFile=Join-Path $EditorRoot 'Engine\Build\Build.version'
if(!(Test-Path -LiteralPath $editor)){throw 'Compatible installed UnrealEditor-Cmd.exe is required.'}
$version=Get-Content -LiteralPath $versionFile -Raw | ConvertFrom-Json
if($version.MajorVersion -ne 5 -or $version.MinorVersion -ne 1 -or $version.PatchVersion -ne 1){throw 'This candidate requires UE5.1.1; engine/shader serialization compatibility remains to be proven.'}
foreach($variant in @('Opaque','Masked','Translucent','Additive')){
 $asset=Join-Path $PSScriptRoot ('Content\PalCraftNative\Materials\M_MCEntity_'+$variant+'.uasset')
 if(!(Test-Path -LiteralPath $asset)){throw ('Native-owned graph asset has not been generated: '+$asset)}
}
# Shader-code-sharing settings are read from this project's isolated config.
# No -CacheShaderFormat limit: both configured SM5/SM6 targets remain requested.
& $editor $project '-run=Cook' '-targetplatform=Windows' '-unattended' '-UTF8Output' '-stdout'
if($LASTEXITCODE -ne 0){throw ('Cook failed: '+$LASTEXITCODE)}
# Inspect actual Cooked outputs and inline shader maps before packaging or deployment.

