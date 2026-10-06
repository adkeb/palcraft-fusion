$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'Invoke-Bridge.ps1') -LibraryOnly
[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
function Invoke-LiveRest {
    param([string]$Method, $Context, [datetime]$Deadline)
    if ($Method -ceq 'status') { return @{ version = 'mock'; servername = (([char]0x7bb1).ToString() + ([char]0x5b50).ToString()) } }
    return @{ players = @() }
}
$context = New-LiveContext (Join-Path $PSScriptRoot 'stdio-only')
$response = Invoke-LiveBridgeText ([Console]::In.ReadToEnd()) $context
[Console]::Out.WriteLine(($response | ConvertTo-Json -Depth 40 -Compress))
