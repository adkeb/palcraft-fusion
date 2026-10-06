param(
    [Parameter(Mandatory=$true)][string]$PythonInterpreter,
    [ValidateSet('Status','WitnessOnce','Watch','Enroll')][string]$Mode='Status',
    [string]$McpRoot='D:/PalworldServer-LAN/PalCraft-Dev/mcp',
    [string]$ExchangeRoot='D:/PalworldServer-LAN/PalCraft-Dev/bridge/exchange',
    [string]$Level,
    [string]$ParserVendor,
    [string]$SetupId,
    [switch]$LabCandidate
)
$ErrorActionPreference='Stop'
# This wrapper uses the existing registrar/watcher. It never starts/stops a
# server, initiates an MC transaction or supplies material/receipt evidence.
$server='D:/PalworldServer-LAN/BridgeLab'
$scripts=$server+'/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts'
if($ExchangeRoot.Replace('\','/').TrimEnd('/').ToLowerInvariant() -ne 'd:/palworldserver-lan/palcraft-dev/bridge/exchange'){
    throw 'Use the existing shared BridgeLab exchange root'
}
if(!(Test-Path -LiteralPath $PythonInterpreter -PathType Leaf)){throw 'Existing backend Python interpreter is required'}
if($Mode -eq 'Status'){
    $cli=@((Join-Path $McpRoot 'exchange_recovery.py'),'status','--root',$ExchangeRoot)
}else{
    if(!$Level){
        # Select the actual installed path from the existing real boot receipt;
        # never invent a world or create a missing save.
        $certificate=Get-Content -LiteralPath (Join-Path $ExchangeRoot 'escrow-boot-certificate.json') -Raw | ConvertFrom-Json
        $Level=[string]$certificate.installed_level_path
    }
    if(!$Level -or !(Test-Path -LiteralPath $Level -PathType Leaf)){throw 'Actual installed Level.sav is required'}
    $normalizedLevel=$Level.Replace('\','/').ToLowerInvariant()
    if(!$normalizedLevel.StartsWith($server.ToLowerInvariant()+'/pal/saved/savegames/0/') -or !($normalizedLevel.EndsWith('/level.sav'))){
        throw 'Only the existing installed BridgeLab Level.sav is in scope'
    }
    if($Mode -eq 'Enroll'){
        [Guid]$parsed=[Guid]::Empty
        if(![Guid]::TryParse($SetupId,[ref]$parsed)){throw 'Actual completed paid setup ID is required'}
        $cli=@((Join-Path $McpRoot 'escrow_enroll.py'),'--root',$ExchangeRoot,
            '--server-root',$server,'--level',$Level,'--setup-id',$parsed.ToString(),
            '--durable-dll',($scripts+'/PalCraftExchangeDurable-v3.dll'),
            '--credit-dll',($scripts+'/palcraft_escrow_credit_v1.dll'))
        if($LabCandidate){$cli+='--lab-candidate'}
    }else{
        $cli=@((Join-Path $McpRoot 'exchange_recovery.py'),'witness','--root',$ExchangeRoot,
            '--level',$Level,'--pal-server-root',$server,'--rpc-root',($server+'/rpc'))
        if($Mode -eq 'Watch'){$cli+=@('--watch','--interval','1')}
    }
    if($ParserVendor){$cli+=@('--parser-vendor',$ParserVendor)}
}
# The existing watcher reads the Lab REST credential internally. No password
# or credential-file contents are copied, printed or passed on the command line.
& $PythonInterpreter @cli
exit $LASTEXITCODE
