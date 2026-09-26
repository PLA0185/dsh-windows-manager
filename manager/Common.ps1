Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ManagerRoot = $PSScriptRoot
$script:Config = Get-Content -LiteralPath "$PSScriptRoot\config.json" -Raw | ConvertFrom-Json
$script:ProfileRoot = Join-Path $Config.home "profiles\$($Config.profile)"
$env:DSH_HOME = $Config.home
$env:PATH = ((Split-Path $Config.node),(Split-Path $Config.pnpm),(Split-Path $Config.git),$env:PATH) -join ';'
function Get-Sha256([string]$Path) {
    $stream=[IO.File]::OpenRead($Path)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') }
    finally { $sha.Dispose(); $stream.Dispose() }
}
function Get-LegacyBatFiles {
    $names=@('Clean_Old_DSH_Autostart.bat','Disable_DSH_Autostart_FIXED_v2.bat','DSH_Background_Start_FIXED.bat','DSH_Restart_FIXED.bat','DSH_Stop_FIXED.bat','Enable_DSH_Autostart_FIXED_v2.bat')
    @(Get-ChildItem -LiteralPath $Config.home -Filter '*.bat' -File | Where-Object {$_.Name -in $names})
}
function Protect-Text([string]$Text) {
    $Text = $Text -replace '(?i)([?&]token=)[^\s&"<>]+','$1[REDACTED]'
    $Text = $Text -replace '(?i)((?:api[_-]?key|authorization|password|secret|access[_-]?token|refresh[_-]?token)\s*[=:]\s*["'']?)[^\s,"''}]+','$1[REDACTED]'
    $Text = $Text -replace '\bsk-[A-Za-z0-9_-]{12,}','[REDACTED]'
    return $Text
}
function Write-ManagerLog([string]$Message,[string]$Name='manager.log') {
    $path=Join-Path "$ManagerRoot\logs" $Name
    if((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -ge $Config.logMaxBytes) {
        for($i=$Config.logKeep; $i -ge 1; $i--) { $prev=if($i -eq 1){$path}else{"$path.$($i-1)"}; if(Test-Path -LiteralPath $prev){ Move-Item -LiteralPath $prev -Destination "$path.$i" -Force } }
    }
    Add-Content -LiteralPath $path -Value ((Get-Date -Format o)+' '+(Protect-Text $Message)) -Encoding utf8
}
function Get-Listener { @(Get-NetTCPConnection -LocalPort $Config.port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique) }
function Get-HostState {
    $path="$ManagerRoot\state\host.json"
    if(Test-Path -LiteralPath $path) { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
    return $null
}
function Test-OwnedProcess($State) {
    if($null -eq $State){return $false}
    $p=Get-CimInstance Win32_Process -Filter "ProcessId=$($State.nodePid)" -ErrorAction SilentlyContinue
    if($null -eq $p -or $p.Name -ne 'node.exe'){return $false}
    $expected='(?:^|\s)"?'+[regex]::Escape($Config.cliEntry)+'"?\s+--profile\s+"?'+[regex]::Escape($Config.profile)+'"?\s+--no-open(?:\s|$)'
    return $p.CommandLine -match $expected -and ([datetime]$p.CreationDate).ToUniversalTime().Ticks -eq ([datetime]$State.nodeCreated).ToUniversalTime().Ticks
}
function Invoke-DshRpc([string]$Endpoint,[hashtable]$ArgsMap=@{}) {
    $secret="$ManagerRoot\state\launch-url.clixml"
    if(-not (Test-Path -LiteralPath $secret)){throw '尚无认证启动 URL；请先启动 DSH'}
    $secure=Import-Clixml -LiteralPath $secret
    $url=[Net.NetworkCredential]::new('', $secure).Password
    $session=[Microsoft.PowerShell.Commands.WebRequestSession]::new()
    $null=Invoke-WebRequest -Uri $url -WebSession $session -MaximumRedirection 3 -TimeoutSec 10 -UseBasicParsing
    $id=[guid]::NewGuid().ToString()
    $envelope=@{type='client-request';rpcId=$id;method=$Endpoint;payload=@{args=$ArgsMap}} | ConvertTo-Json -Depth 30 -Compress
    $result=Invoke-RestMethod -Uri "http://127.0.0.1:$($Config.port)/api/$Endpoint" -Method Post -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($envelope)) -WebSession $session -TimeoutSec 30
    if($result.rpcId -ne $id){throw 'RPC 响应标识不匹配'}
    if(-not $result.result.ok){throw (Protect-Text ($result.result.error | ConvertTo-Json -Depth 10 -Compress))}
    return $result.result.value
}
function Invoke-Helper([string[]]$HelperArgs) {
    $output=& $Config.node "$ManagerRoot\profile-helper.mjs" $Config.cliEntry $ProfileRoot @HelperArgs
    if($LASTEXITCODE -ne 0){throw "配置辅助程序失败: $(Protect-Text ($output | Out-String))"}
    return ($output | Out-String | ConvertFrom-Json)
}
