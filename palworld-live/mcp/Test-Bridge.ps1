$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
. (Join-Path $PSScriptRoot 'Invoke-Bridge.ps1') -LibraryOnly

$root = Join-Path $PSScriptRoot ('test-' + [guid]::NewGuid().ToString())
$context = New-LiveContext $root
$context.MutexName = 'Global\PalworldBridgeMock_' + [guid]::NewGuid().ToString('N')
$context.MaxWaitSeconds = 7
[void][IO.Directory]::CreateDirectory($context.RpcRoot)
$script:Passed = New-Object Collections.Generic.List[string]
$script:RestCalls = 0

function Invoke-LiveRest {
    param([string]$Method, $Context, [datetime]$Deadline)
    $script:RestCalls++
    if ($Method -ceq 'status') {
        return @{ version = 'mock'; servername = (([char]0x7bb1).ToString() + ([char]0x5b50).ToString()) }
    }
    return @{ players = @() }
}

function Assert-Test {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw ('TEST FAILED: ' + $Name) }
    [void]$script:Passed.Add($Name)
}

function New-TestRequest {
    param([string]$Method = 'status', $Params = @{}, [double]$Seconds = 15)
    return @{
        protocol_version = 1; request_id = [guid]::NewGuid().ToString()
        method = $Method; params = $Params
        deadline_utc = [DateTime]::UtcNow.AddSeconds($Seconds).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    }
}

function Write-TestMetadata {
    param([double]$Age = 0, [bool]$Writable = $false, [bool]$Recovery = $false)
    $capabilities = @{
        'bases.list' = @{ supported = $true; verified = $true; read_only = $true }
        'storage.list' = @{ supported = $true; verified = $true; read_only = $true }
        'storage.apply' = @{ supported = $Writable; verified = $Writable; read_only = $false }
        'operations.get' = @{ supported = $Recovery; verified = $Recovery; read_only = $true }
        'run.shell' = @{ supported = $true; verified = $true; read_only = $false }
    }
    $metadata = @{
        protocol_version = 1; game_version = 'mock'; bridge_version = 'mock'
        server_instance_id = [guid]::NewGuid().ToString()
        heartbeat_utc = [DateTime]::UtcNow.AddSeconds(-$Age).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        capabilities = $capabilities
    }
    [IO.File]::WriteAllText((Join-Path $context.RpcRoot 'capabilities.json'), ($metadata | ConvertTo-Json -Depth 10 -Compress), $script:LiveUtf8)
}

function Start-MockRuntime {
    param([string]$Mode = 'success')
    return (Start-Job -ArgumentList $context.RpcRoot, $Mode -ScriptBlock {
        param($RpcRoot, $Mode)
        $ErrorActionPreference = 'Stop'
        $path = Join-Path $RpcRoot 'request.json'
        $until = [DateTime]::UtcNow.AddSeconds(12)
        while (-not [IO.File]::Exists($path) -and [DateTime]::UtcNow -lt $until) { Start-Sleep -Milliseconds 20 }
        if (-not [IO.File]::Exists($path)) { throw 'Mock received no request' }
        $request = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $responseId = $request.request_id
        if ($Mode -eq 'wrong-id') { $responseId = [guid]::NewGuid().ToString() }
        $response = @{ protocol_version = 1; request_id = $responseId; ok = $true
            result = @{ label = (([char]0x7bb1).ToString() + ([char]0x5b50).ToString()); count = 1 } }
        $temporary = Join-Path $RpcRoot 'response.tmp'
        $responseDir = Join-Path $RpcRoot 'responses'
        [void][IO.Directory]::CreateDirectory($responseDir)
        [IO.File]::WriteAllText($temporary, ($response | ConvertTo-Json -Depth 10 -Compress), (New-Object Text.UTF8Encoding($false)))
        [IO.File]::Move($temporary, (Join-Path $responseDir ($request.request_id + '.json')))
        [IO.File]::Delete($path)
        return 'done'
    })
}

try {
    $cap = Invoke-LiveBridgeRequest (New-TestRequest 'capabilities') $context
    Assert-Test ($cap.ok -and $cap.result.capabilities.status.verified -and $cap.result.capabilities.players.verified -and -not $cap.result.runtime_connected) 'REST-only capabilities without runtime'

    $jsonRequest = New-TestRequest 'status' | ConvertTo-Json -Depth 10 -Compress
    $jsonReply = Invoke-LiveBridgeText $jsonRequest $context
    Assert-Test ($jsonReply.ok -and $jsonReply.result.version -eq 'mock') 'Valid JSON empty params survives PowerShell StrictMode'

    Write-TestMetadata -Age 30
    $cap = Invoke-LiveBridgeRequest (New-TestRequest 'capabilities') $context
    Assert-Test (-not $cap.result.capabilities.'bases.list'.verified) 'Stale heartbeat cannot authorize tools'

    Write-TestMetadata
    $cap = Invoke-LiveBridgeRequest (New-TestRequest 'capabilities') $context
    Assert-Test ($cap.result.runtime_connected -and $cap.result.capabilities.'bases.list'.verified -and -not $cap.result.capabilities.ContainsKey('run.shell')) 'Fresh allowlisted read capability only'

    Write-TestMetadata -Writable $true
    $request = New-TestRequest 'storage.apply' @{ plan_id = 'p1'; expected_revision = 'r1'; idempotency_key = [guid]::NewGuid().ToString() }
    $reply = Invoke-LiveBridgeRequest $request $context
    Assert-Test (-not $reply.ok -and $reply.error.code -eq 'unsupported' -and -not [IO.File]::Exists((Join-Path $context.RpcRoot 'request.json'))) 'Unverified recovery prevents write submission'

    $reply = Invoke-LiveBridgeRequest (New-TestRequest 'run.shell' @{ command = 'anything' }) $context
    Assert-Test (-not $reply.ok -and $reply.error.code -eq 'unsupported') 'Unknown method rejected'
    $reply = Invoke-LiveBridgeRequest (New-TestRequest 'status' @{ extra = 'bad' }) $context
    Assert-Test (-not $reply.ok -and $reply.error.code -eq 'invalid_request') 'Unexpected parameters rejected'
    $reply = Invoke-LiveBridgeRequest (New-TestRequest 'bases.list' @{ guild_id = $null }) $context
    Assert-Test (-not $reply.ok -and $reply.error.code -eq 'invalid_request') 'Optional null does not bypass UUID validation'

    $guid = [guid]::NewGuid().ToString()
    $single = ('{"base_id":"' + $guid + '","policy":"category","container_ids":["' + $guid + '"]}') | ConvertFrom-Json
    Assert-LiveParams 'storage.plan' $single
    [void]$script:Passed.Add('Single-element JSON arrays remain arrays')

    $build = @{ guild_id = $guid; base_id = $guid; player_uid = $guid; structures = @(
        @{ build_id = 'ItemChest'; support_model_id = $guid; position = @{ x = 1; y = -2; z = 3 }
           rotation = @{ pitch = 0; yaw = 90; roll = 0 } }
    ) }
    $buildJson = $build | ConvertTo-Json -Depth 10 -Compress
    Assert-LiveParams 'build.preview' ($buildJson | ConvertFrom-Json)
    [void]$script:Passed.Add('Build JSON accepts real player and one supported placement')
    foreach ($field in @('guild_id', 'base_id', 'player_uid')) {
        $badBuild = $buildJson | ConvertFrom-Json
        $badBuild.PSObject.Properties.Remove($field)
        $reply = Invoke-LiveBridgeRequest (New-TestRequest 'build.preview' $badBuild) $context
        Assert-Test (-not $reply.ok -and $reply.error.code -eq 'invalid_request') ('Build missing ' + $field + ' rejected')
    }
    $badBuild = $buildJson | ConvertFrom-Json
    $badBuild.structures[0].PSObject.Properties.Remove('support_model_id')
    $reply = Invoke-LiveBridgeRequest (New-TestRequest 'build.preview' $badBuild) $context
    Assert-Test (-not $reply.ok -and $reply.error.code -eq 'invalid_request') 'Build missing support model rejected'
    $badBuild = $buildJson | ConvertFrom-Json
    $badBuild.structures = @($badBuild.structures[0], $badBuild.structures[0])
    $reply = Invoke-LiveBridgeRequest (New-TestRequest 'build.preview' $badBuild) $context
    Assert-Test (-not $reply.ok -and $reply.error.code -eq 'invalid_request') 'Multiple build placements rejected'
    foreach ($axis in @('pitch', 'roll')) {
        $badBuild = $buildJson | ConvertFrom-Json
        $badBuild.structures[0].rotation.$axis = 1
        $reply = Invoke-LiveBridgeRequest (New-TestRequest 'build.preview' $badBuild) $context
        Assert-Test (-not $reply.ok -and $reply.error.code -eq 'invalid_request') ('Build nonzero ' + $axis + ' rejected')
    }

    $reply = Invoke-LiveBridgeRequest (New-TestRequest 'status' @{} -1) $context
    Assert-Test (-not $reply.ok -and $reply.error.code -eq 'timeout') 'Expired request rejected before execution'
    $reply = Invoke-LiveBridgeText 'not-json' $context
    Assert-Test (-not $reply.ok -and $reply.error.code -eq 'invalid_request') 'Malformed JSON returns an error object'
    $reply = Invoke-LiveBridgeText '[]' $context
    Assert-Test (-not $reply.ok -and $reply.error.code -eq 'invalid_request') 'Array request returns an error object'

    Write-TestMetadata
    $job = Start-MockRuntime
    $request = New-TestRequest 'bases.list'
    $reply = Invoke-LiveBridgeRequest $request $context
    $null = Wait-Job $job -Timeout 12
    $jobOutput = Receive-Job $job -ErrorAction Stop
    Remove-Job $job -Force
    Assert-Test ($reply.ok -and $reply.result.count -eq 1 -and $reply.result.label.Length -eq 2 -and $jobOutput -eq 'done') 'Atomic queue RPC and Unicode response'

    Write-TestMetadata
    $job = Start-MockRuntime 'wrong-id'
    $reply = Invoke-LiveBridgeRequest (New-TestRequest 'bases.list') $context
    $null = Wait-Job $job -Timeout 12
    $null = Receive-Job $job -ErrorAction Stop
    Remove-Job $job -Force
    Assert-Test (-not $reply.ok -and $reply.error.code -eq 'invalid_response') 'Mismatched runtime response rejected'

    Write-TestMetadata -Writable $true -Recovery $true
    $context.MaxWaitSeconds = 0.3
    $request = New-TestRequest 'storage.apply' @{ plan_id = 'p1'; expected_revision = 'r1'; idempotency_key = [guid]::NewGuid().ToString() }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $reply = Invoke-LiveBridgeRequest $request $context
    $timer.Stop()
    $queueFile = Join-Path $context.RpcRoot 'request.json'
    $queued = [IO.File]::ReadAllText($queueFile) | ConvertFrom-Json
    Assert-Test (-not $reply.ok -and $reply.error.code -eq 'timeout' -and $reply.error.outcome_unknown -and $queued.request_id -eq $request.request_id -and $timer.Elapsed.TotalSeconds -lt 1.5) 'Write timeout preserves single submitted request and unknown outcome'
    Assert-Test (((ConvertTo-LiveUtc $queued.deadline_utc) - [DateTime]::UtcNow).TotalSeconds -lt 0.1) 'Runtime deadline clamped to adapter budget'

    $original = [IO.File]::ReadAllText($queueFile)
    $reply = Invoke-LiveBridgeRequest (New-TestRequest 'bases.list') $context
    Assert-Test (-not $reply.ok -and $reply.error.code -eq 'busy' -and [IO.File]::ReadAllText($queueFile) -ceq $original) 'Pending request is not overwritten or resent'
    Assert-Test (@(Get-ChildItem -LiteralPath $context.RpcRoot -Filter '*.tmp').Count -eq 0) 'No partial request files remain'

    [IO.File]::Delete($queueFile)
    $readyFile = Join-Path $context.RpcRoot 'mutex-ready'
    $job = Start-Job -ArgumentList $context.MutexName, $readyFile -ScriptBlock {
        param($Name, $ReadyFile)
        $ProgressPreference = 'SilentlyContinue'
        $mutex = New-Object Threading.Mutex($false, $Name)
        [void]$mutex.WaitOne()
        try {
            [IO.File]::WriteAllText($ReadyFile, 'ready')
            Start-Sleep -Milliseconds 1800
        } finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
    }
    $readyDeadline = [DateTime]::UtcNow.AddSeconds(8)
    while (-not [IO.File]::Exists($readyFile) -and [DateTime]::UtcNow -lt $readyDeadline) { Start-Sleep -Milliseconds 20 }
    if (-not [IO.File]::Exists($readyFile)) { throw 'Mutex mock failed to start' }
    Write-TestMetadata
    $reply = Invoke-LiveBridgeRequest (New-TestRequest 'bases.list') $context
    $null = Wait-Job $job -Timeout 8
    $null = Receive-Job $job -ErrorAction Stop
    Remove-Job $job -Force
    Assert-Test (-not $reply.ok -and $reply.error.code -eq 'busy' -and -not [IO.File]::Exists($queueFile)) 'Named mutex serializes separate PowerShell processes'

    @{ ok = $true; powershell = $PSVersionTable.PSVersion.ToString(); passed = $script:Passed.Count; tests = @($script:Passed); test_root = $root } | ConvertTo-Json -Depth 10 -Compress
} catch {
    @{ ok = $false; passed = $script:Passed.Count; tests = @($script:Passed); error = $_.Exception.Message; line = $_.InvocationInfo.ScriptLineNumber; test_root = $root } | ConvertTo-Json -Depth 10 -Compress
    exit 1
}
