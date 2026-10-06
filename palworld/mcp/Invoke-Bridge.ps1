param([switch]$LibraryOnly)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function New-LiveContext {
    param([string]$Root = 'D:\PalworldServer-LAN\BridgeLab')
    return @{
        Root = $Root
        RpcRoot = Join-Path $Root 'rpc'
        ConfigPath = Join-Path $Root 'Pal\Saved\Config\WindowsServer\PalWorldSettings.ini'
        RestBase = 'http://127.0.0.1:8322/v1/api'
        MutexName = 'Global\PalworldLiveControl_BridgeLab_RPC'
        MaxWaitSeconds = 25.0
        HeartbeatFreshnessSeconds = 10.0
    }
}

$script:LiveMethods = @{
    'capabilities' = $true; 'status' = $true; 'players' = $true
    'bases.list' = $true; 'storage.list' = $true; 'storage.plan' = $true
    'storage.apply' = $false; 'build.preview' = $true; 'build.apply' = $false
    'workers.list' = $true; 'workers.plan' = $true; 'workers.assign' = $false
    'operations.get' = $true
}
$script:LiveUuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
$script:LiveTokenPattern = '^[A-Za-z0-9_.:-]+$'
$script:LiveUtf8 = New-Object System.Text.UTF8Encoding($false)

function Throw-LiveError {
    param([string]$Code, [string]$Message, [bool]$OutcomeUnknown = $false)
    $errorObject = New-Object System.InvalidOperationException($Message)
    $errorObject.Data['bridge_code'] = $Code
    $errorObject.Data['outcome_unknown'] = $OutcomeUnknown
    throw $errorObject
}

function Get-LiveField {
    param($Object, [string]$Name, $Default = $null)
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return ,($Object[$Name]) }
    } elseif ($null -ne $Object) {
        $property = $Object.PSObject.Properties[$Name]
        if ($null -ne $property) { return ,($property.Value) }
    }
    return ,$Default
}

function Test-LiveObject {
    param($Value)
    return ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject])
}

function Test-LiveField {
    param($Object, [string]$Name)
    if ($Object -is [System.Collections.IDictionary]) { return (@($Object.Keys) -ccontains $Name) }
    return (@($Object.PSObject.Properties | ForEach-Object { $_.Name }) -ccontains $Name)
}

function Assert-LiveFields {
    param($Object, [string[]]$Allowed, [string[]]$Required = @())
    if (-not (Test-LiveObject $Object)) { Throw-LiveError 'invalid_request' 'Expected a JSON object' }
    $names = @($Object.PSObject.Properties | ForEach-Object { $_.Name })
    if ($Object -is [System.Collections.IDictionary]) { $names = @($Object.Keys) }
    foreach ($name in $names) {
        if ($Allowed -cnotcontains $name) { Throw-LiveError 'invalid_request' 'Unknown request field' }
    }
    foreach ($name in $Required) {
        if ($names -cnotcontains $name) { Throw-LiveError 'invalid_request' 'Missing required request field' }
    }
}

function Assert-LiveUuid {
    param($Value)
    if ($Value -isnot [string] -or $Value -cnotmatch $script:LiveUuidPattern) {
        Throw-LiveError 'invalid_request' 'Expected a canonical UUID'
    }
}

function Assert-LiveToken {
    param($Value, [int]$Maximum = 128)
    if ($Value -isnot [string] -or $Value.Length -lt 1 -or $Value.Length -gt $Maximum -or $Value -cnotmatch $script:LiveTokenPattern) {
        Throw-LiveError 'invalid_request' 'Invalid identifier or revision'
    }
}

function Assert-LiveVector {
    param($Value, [string[]]$Axes, [double]$Minimum, [double]$Maximum)
    Assert-LiveFields $Value $Axes $Axes
    foreach ($axis in $Axes) {
        $number = Get-LiveField $Value $axis
        if (($number -isnot [int] -and $number -isnot [long] -and $number -isnot [double] -and $number -isnot [decimal]) -or
            [double]::IsNaN([double]$number) -or [double]::IsInfinity([double]$number) -or
            $number -lt $Minimum -or $number -gt $Maximum) {
            Throw-LiveError 'invalid_request' 'Invalid coordinate or rotation'
        }
    }
}

function Assert-LiveArray {
    param($Value, [int]$Minimum, [int]$Maximum)
    if ($Value -isnot [array] -or $Value.Count -lt $Minimum -or $Value.Count -gt $Maximum) {
        Throw-LiveError 'invalid_request' 'Invalid list length or type'
    }
}

function Assert-LiveParams {
    param([string]$Method, $Params)
    switch -CaseSensitive ($Method) {
        { $_ -in @('capabilities', 'status', 'players') } { Assert-LiveFields $Params @(); break }
        'bases.list' {
            Assert-LiveFields $Params @('guild_id')
            $guild = Get-LiveField $Params 'guild_id'
            if (Test-LiveField $Params 'guild_id') { Assert-LiveUuid $guild }
            break
        }
        'storage.list' {
            Assert-LiveFields $Params @('base_id', 'include_empty') @('base_id')
            Assert-LiveUuid (Get-LiveField $Params 'base_id')
            $include = Get-LiveField $Params 'include_empty'
            if ((Test-LiveField $Params 'include_empty') -and $include -isnot [bool]) { Throw-LiveError 'invalid_request' 'include_empty must be boolean' }
            break
        }
        'storage.plan' {
            Assert-LiveFields $Params @('base_id', 'policy', 'container_ids', 'include_shared') @('base_id', 'policy')
            Assert-LiveUuid (Get-LiveField $Params 'base_id')
            if (@('category', 'item_type') -cnotcontains (Get-LiveField $Params 'policy')) { Throw-LiveError 'invalid_request' 'Unknown storage policy' }
            $containers = Get-LiveField $Params 'container_ids'
            if (Test-LiveField $Params 'container_ids') {
                Assert-LiveArray $containers 1 100
                foreach ($container in $containers) { Assert-LiveUuid $container }
            }
            $include = Get-LiveField $Params 'include_shared'
            if ((Test-LiveField $Params 'include_shared') -and $include -isnot [bool]) { Throw-LiveError 'invalid_request' 'include_shared must be boolean' }
            break
        }
        { $_ -in @('storage.apply', 'build.apply', 'workers.assign') } {
            Assert-LiveFields $Params @('plan_id', 'expected_revision', 'idempotency_key') @('plan_id', 'expected_revision', 'idempotency_key')
            Assert-LiveToken (Get-LiveField $Params 'plan_id')
            Assert-LiveToken (Get-LiveField $Params 'expected_revision') 256
            Assert-LiveUuid (Get-LiveField $Params 'idempotency_key')
            break
        }
        'build.preview' {
            Assert-LiveFields $Params @('guild_id', 'base_id', 'player_uid', 'structures') @('guild_id', 'base_id', 'player_uid', 'structures')
            Assert-LiveUuid (Get-LiveField $Params 'guild_id')
            Assert-LiveUuid (Get-LiveField $Params 'base_id')
            Assert-LiveUuid (Get-LiveField $Params 'player_uid')
            $structures = Get-LiveField $Params 'structures'
            Assert-LiveArray $structures 1 1
            foreach ($structure in $structures) {
                Assert-LiveFields $structure @('build_id', 'position', 'rotation', 'support_model_id') @('build_id', 'position', 'rotation', 'support_model_id')
                Assert-LiveToken (Get-LiveField $structure 'build_id')
                Assert-LiveUuid (Get-LiveField $structure 'support_model_id')
                Assert-LiveVector (Get-LiveField $structure 'position') @('x', 'y', 'z') -10000000 10000000
                $rotation = Get-LiveField $structure 'rotation'
                Assert-LiveVector $rotation @('pitch', 'yaw', 'roll') -360 360
                if ((Get-LiveField $rotation 'pitch') -ne 0 -or (Get-LiveField $rotation 'roll') -ne 0) {
                    Throw-LiveError 'invalid_request' 'Only yaw rotation is currently supported'
                }
            }
            break
        }
        'workers.list' {
            Assert-LiveFields $Params @('base_id') @('base_id')
            Assert-LiveUuid (Get-LiveField $Params 'base_id')
            break
        }
        'workers.plan' {
            Assert-LiveFields $Params @('base_id', 'assignments') @('base_id', 'assignments')
            Assert-LiveUuid (Get-LiveField $Params 'base_id')
            $assignments = Get-LiveField $Params 'assignments'
            Assert-LiveArray $assignments 1 50
            foreach ($assignment in $assignments) {
                Assert-LiveFields $assignment @('pal_id', 'task_id') @('pal_id', 'task_id')
                Assert-LiveUuid (Get-LiveField $assignment 'pal_id')
                Assert-LiveToken (Get-LiveField $assignment 'task_id')
            }
            break
        }
        'operations.get' {
            Assert-LiveFields $Params @('request_id') @('request_id')
            Assert-LiveUuid (Get-LiveField $Params 'request_id')
            break
        }
        default { Throw-LiveError 'unsupported' 'Method is not allowlisted' }
    }
}

function ConvertTo-LiveUtc {
    param($Value)
    if ($Value -isnot [string] -or $Value.Length -gt 64 -or $Value -notmatch 'Z$') {
        Throw-LiveError 'invalid_request' 'Expected an ISO UTC timestamp ending Z'
    }
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) {
        Throw-LiveError 'invalid_request' 'Invalid UTC timestamp'
    }
    return $parsed.UtcDateTime
}

function Invoke-LiveRest {
    param([string]$Method, $Context, [datetime]$Deadline)
    if (@('status', 'players') -cnotcontains $Method) { Throw-LiveError 'unsupported' 'REST method is not allowlisted' }
    $remaining = ($Deadline - [DateTime]::UtcNow).TotalSeconds
    if ($remaining -le 0) { Throw-LiveError 'timeout' 'Request deadline passed before REST lookup' }
    try {
        $ini = [IO.File]::ReadAllText($Context.ConfigPath)
        $match = [regex]::Match($ini, 'AdminPassword="([^"\r\n]+)"')
        if (-not $match.Success) { Throw-LiveError 'backend_unavailable' 'Private REST credentials are not configured' }
        $credential = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:' + $match.Groups[1].Value))
        $route = if ($Method -ceq 'status') { '/info' } else { '/players' }
        $timeout = [Math]::Min(5, [Math]::Floor(($Deadline - [DateTime]::UtcNow).TotalSeconds))
        if ($timeout -lt 1) { Throw-LiveError 'timeout' 'Insufficient time remains for REST lookup' }
        $result = Invoke-RestMethod -Uri ($Context.RestBase + $route) -Method Get -Headers @{ Authorization = 'Basic ' + $credential } -TimeoutSec $timeout
        if (-not (Test-LiveObject $result)) { Throw-LiveError 'invalid_response' 'Private REST returned an invalid object' }
        return $result
    } catch {
        Throw-LiveError 'backend_unavailable' 'Private REST is unavailable or authentication failed'
    }
}

function Read-LiveJsonFile {
    param([string]$Path, [int]$MaximumBytes = 8388608)
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.Length -gt $MaximumBytes) { Throw-LiveError 'invalid_response' 'Bridge file exceeded size limit' }
    return ([IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop)
}

function Read-LiveMetadata {
    param($Context)
    try {
        $metadata = Read-LiveJsonFile (Join-Path $Context.RpcRoot 'capabilities.json') 262144
        if ((Get-LiveField $metadata 'protocol_version') -isnot [int] -or (Get-LiveField $metadata 'protocol_version') -ne 1) { return $null }
        Assert-LiveUuid (Get-LiveField $metadata 'server_instance_id')
        $heartbeat = ConvertTo-LiveUtc (Get-LiveField $metadata 'heartbeat_utc')
        $age = ([DateTime]::UtcNow - $heartbeat).TotalSeconds
        if ($age -lt -2 -or $age -gt $Context.HeartbeatFreshnessSeconds) { return $null }
        if (-not (Test-LiveObject (Get-LiveField $metadata 'capabilities'))) { return $null }
        return $metadata
    } catch { return $null }
}

function Test-LiveCapability {
    param($Manifest, [string]$Method)
    if (-not $script:LiveMethods.ContainsKey($Method)) { return $false }
    $record = Get-LiveField (Get-LiveField $Manifest 'capabilities') $Method
    $supported = Get-LiveField $record 'supported'
    $verified = Get-LiveField $record 'verified'
    $readOnly = Get-LiveField $record 'read_only'
    $valid = $supported -is [bool] -and $supported -eq $true -and $verified -is [bool] -and $verified -eq $true -and
        $readOnly -is [bool] -and $readOnly -eq $script:LiveMethods[$Method]
    if ($valid -and -not $script:LiveMethods[$Method]) {
        $valid = Test-LiveCapability $Manifest 'operations.get'
    }
    return $valid
}

function Get-LiveCapabilities {
    param($Context, [datetime]$Deadline)
    $caps = @{}
    $info = $null
    foreach ($method in @('status', 'players')) {
        try {
            $result = Invoke-LiveRest $method $Context $Deadline
            if ($method -ceq 'status') { $info = $result }
            $caps[$method] = @{ supported = $true; verified = $true; read_only = $true }
        } catch {
            $caps[$method] = @{ supported = $false; verified = $false; read_only = $true }
        }
    }
    $metadata = Read-LiveMetadata $Context
    foreach ($method in $script:LiveMethods.Keys) {
        if (@('capabilities', 'status', 'players') -contains $method) { continue }
        $verified = $null -ne $metadata -and (Test-LiveCapability $metadata $method)
        $caps[$method] = @{ supported = [bool]$verified; verified = [bool]$verified; read_only = $script:LiveMethods[$method] }
    }
    $gameVersion = Get-LiveField $metadata 'game_version'
    if ($null -eq $gameVersion) { $gameVersion = Get-LiveField $info 'version' }
    return @{
        bridge_version = 'powershell-adapter-0.1.0'
        game_version = $gameVersion
        server_instance_id = Get-LiveField $metadata 'server_instance_id'
        heartbeat_utc = Get-LiveField $metadata 'heartbeat_utc'
        runtime_connected = ($null -ne $metadata)
        capabilities = $caps
    }
}

function Assert-LiveResponse {
    param($Response, [string]$RequestId)
    if (-not (Test-LiveObject $Response) -or (Get-LiveField $Response 'protocol_version') -isnot [int] -or (Get-LiveField $Response 'protocol_version') -ne 1 -or
        (Get-LiveField $Response 'request_id') -cne $RequestId -or (Get-LiveField $Response 'ok') -isnot [bool]) {
        Throw-LiveError 'invalid_response' 'Runtime response does not match request'
    }
    if (Get-LiveField $Response 'ok') {
        if (-not (Test-LiveObject (Get-LiveField $Response 'result'))) { Throw-LiveError 'invalid_response' 'Runtime result must be an object' }
    } else {
        $errorBody = Get-LiveField $Response 'error'
        if ((Get-LiveField $errorBody 'code') -isnot [string] -or (Get-LiveField $errorBody 'message') -isnot [string]) {
            Throw-LiveError 'invalid_response' 'Runtime error is malformed'
        }
    }
}

function Invoke-LiveQueue {
    param($Request, $Context, [datetime]$Deadline)
    $method = [string](Get-LiveField $Request 'method')
    $requestId = [string](Get-LiveField $Request 'request_id')
    $mutation = -not $script:LiveMethods[$method]
    $submitted = $false
    $locked = $false
    $mutex = $null
    $temporaryPath = $null
    try {
        $mutex = New-Object Threading.Mutex($false, $Context.MutexName)
        $remaining = ($Deadline - [DateTime]::UtcNow).TotalMilliseconds
        if ($remaining -le 0) { Throw-LiveError 'timeout' 'Request deadline passed before acquiring queue' }
        try { $locked = $mutex.WaitOne([int][Math]::Min(25000, [Math]::Ceiling($remaining))) }
        catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { Throw-LiveError 'busy' 'Another bridge request is still running' }

        # Re-read fresh capabilities after waiting; an earlier manifest may be
        # stale or from a different server instance by now.
        $metadata = Read-LiveMetadata $Context
        if ($null -eq $metadata -or -not (Test-LiveCapability $metadata $method)) {
            Throw-LiveError 'unsupported' 'Runtime capability is unverified or heartbeat expired'
        }
        if ([DateTime]::UtcNow -ge $Deadline) { Throw-LiveError 'timeout' 'Request expired before queue submission' }
        $requestPath = Join-Path $Context.RpcRoot 'request.json'
        if ([IO.File]::Exists($requestPath)) {
            Throw-LiveError 'busy' 'A queued request is awaiting runtime acknowledgement; it was not overwritten'
        }
        $responseDir = Join-Path $Context.RpcRoot 'responses'
        [void][IO.Directory]::CreateDirectory($responseDir)
        $responsePath = Join-Path $responseDir ($requestId + '.json')
        if ([IO.File]::Exists($responsePath)) {
            $old = Read-LiveJsonFile $responsePath
            Assert-LiveResponse $old $requestId
            return $old
        }
        $queued = @{
            protocol_version = 1; request_id = $requestId; method = $method
            params = Get-LiveField $Request 'params'
            deadline_utc = $Deadline.ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture)
        }
        $temporaryPath = Join-Path $Context.RpcRoot ('.request-' + $requestId + '.tmp')
        [IO.File]::WriteAllText($temporaryPath, ($queued | ConvertTo-Json -Depth 30 -Compress), $script:LiveUtf8)
        # File.Move does not replace existing request.json. Both paths share
        # the same directory/filesystem, so the runtime sees a complete file.
        [IO.File]::Move($temporaryPath, $requestPath)
        $temporaryPath = $null
        $submitted = $true
        while ([DateTime]::UtcNow -lt $Deadline) {
            if ([IO.File]::Exists($responsePath)) {
                $response = Read-LiveJsonFile $responsePath
                Assert-LiveResponse $response $requestId
                return $response
            }
            $remaining = ($Deadline - [DateTime]::UtcNow).TotalMilliseconds
            if ($remaining -gt 0) { Start-Sleep -Milliseconds ([int][Math]::Min(100, [Math]::Ceiling($remaining))) }
        }
        Throw-LiveError 'timeout' 'Runtime response deadline exceeded; request was not resent' ($mutation -and $submitted)
    } catch {
        if ($_.Exception.Data.Contains('bridge_code')) {
            if ($mutation -and $submitted -and $_.Exception.Data['bridge_code'] -ne 'conflict') {
                $_.Exception.Data['outcome_unknown'] = $true
            }
            throw
        }
        Throw-LiveError 'backend_unavailable' 'Runtime queue could not complete the request' ($mutation -and $submitted)
    } finally {
        if ($null -ne $temporaryPath -and [IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) }
        if ($locked -and $null -ne $mutex) { $mutex.ReleaseMutex() }
        if ($null -ne $mutex) { $mutex.Dispose() }
    }
}

function Invoke-LiveBridgeRequest {
    param($Request, $Context = (New-LiveContext))
    $requestId = Get-LiveField $Request 'request_id'
    try {
        Assert-LiveFields $Request @('protocol_version', 'request_id', 'method', 'params', 'deadline_utc') @('protocol_version', 'request_id', 'method', 'params', 'deadline_utc')
        if ((Get-LiveField $Request 'protocol_version') -isnot [int] -or (Get-LiveField $Request 'protocol_version') -ne 1) {
            Throw-LiveError 'invalid_request' 'Unsupported bridge protocol version'
        }
        Assert-LiveUuid $requestId
        $method = Get-LiveField $Request 'method'
        if ($method -isnot [string] -or @($script:LiveMethods.Keys) -cnotcontains $method) {
            Throw-LiveError 'unsupported' 'Method is not allowlisted'
        }
        Assert-LiveParams $method (Get-LiveField $Request 'params')
        $deadline = ConvertTo-LiveUtc (Get-LiveField $Request 'deadline_utc')
        $maximum = [DateTime]::UtcNow.AddSeconds($Context.MaxWaitSeconds)
        if ($deadline -gt $maximum) { $deadline = $maximum }
        if ([DateTime]::UtcNow -ge $deadline) { Throw-LiveError 'timeout' 'Request deadline already expired' }
        if ($method -ceq 'capabilities') {
            $result = Get-LiveCapabilities $Context $deadline
        } elseif (@('status', 'players') -ccontains $method) {
            $result = Invoke-LiveRest $method $Context $deadline
        } else {
            return (Invoke-LiveQueue $Request $Context $deadline)
        }
        return @{ protocol_version = 1; request_id = $requestId; ok = $true; result = $result }
    } catch {
        $code = 'backend_unavailable'; $message = 'Bridge request failed'; $outcomeUnknown = $false
        if ($_.Exception.Data.Contains('bridge_code')) {
            $code = [string]$_.Exception.Data['bridge_code']
            $message = $_.Exception.Message
            $outcomeUnknown = [bool]$_.Exception.Data['outcome_unknown']
        }
        $errorBody = @{ code = $code; message = $message }
        if ($outcomeUnknown) { $errorBody['outcome_unknown'] = $true }
        return @{ protocol_version = 1; request_id = $requestId; ok = $false; error = $errorBody }
    }
}

function Invoke-LiveBridgeText {
    param([string]$Text, $Context = (New-LiveContext))
    if ($Text.Length -gt 1048576) {
        return @{ protocol_version = 1; request_id = $null; ok = $false; error = @{ code = 'invalid_request'; message = 'Request exceeds size limit' } }
    }
    try { $request = ConvertFrom-Json -InputObject $Text -ErrorAction Stop }
    catch {
        return @{ protocol_version = 1; request_id = $null; ok = $false; error = @{ code = 'invalid_request'; message = 'Input must be one JSON object' } }
    }
    return (Invoke-LiveBridgeRequest $request $Context)
}

if (-not $LibraryOnly) {
    [Console]::InputEncoding = [Text.Encoding]::UTF8
    [Console]::OutputEncoding = $script:LiveUtf8
    try {
        $text = [Console]::In.ReadToEnd()
        $response = Invoke-LiveBridgeText $text
    } catch {
        $response = @{ protocol_version = 1; request_id = $null; ok = $false; error = @{ code = 'backend_unavailable'; message = 'Bridge input could not be processed' } }
    }
    [Console]::Out.WriteLine(($response | ConvertTo-Json -Depth 40 -Compress))
}
