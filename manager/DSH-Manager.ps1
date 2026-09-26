[CmdletBinding(SupportsShouldProcess)]
param(
 [Parameter(Position=0)][string]$Command='menu',
 [Parameter(Position=1)][string]$Action='',
 [Parameter(Position=2)][string]$Target='',
 [string]$Provider='',
 [switch]$Yes,
 [switch]$Apply,
 [switch]$AllowMajor,
 [switch]$AutostartInvocation
)
. "$PSScriptRoot\Common.ps1"
function Invoke-Native([string]$Exe,[string[]]$Arguments,[string]$Log='manager.log') {
    Write-ManagerLog ("执行: $Exe "+($Arguments -join ' ')) $Log
    & $Exe @Arguments 2>&1 | ForEach-Object { $line=Protect-Text ([string]$_);Write-ManagerLog $line $Log;Write-Host $line }
    if($LASTEXITCODE -ne 0){throw "命令失败，退出码 $LASTEXITCODE；日志 $ManagerRoot\logs\$Log"}
}
function Get-DshVersion { (& $Config.dsh --version | Out-String).Trim() }
function Wait-Healthy {
    $deadline=(Get-Date).AddSeconds($Config.startupTimeoutSeconds)
    $stableSince=$null; $lastId=0
    do {
        $state=Get-HostState
        $listener=@(Get-Listener)
        $healthy=$false
        if((Test-OwnedProcess $state) -and $listener.Count -eq 1 -and $listener[0] -eq $state.nodePid -and (Test-Path "$ManagerRoot\state\launch-url.clixml")){
            try{$null=Invoke-DshRpc 'session/modelCatalog';$healthy=$true}catch{}
        }
        if($healthy){
            if($lastId -ne $state.nodePid -or $null -eq $stableSince){$stableSince=Get-Date;$lastId=$state.nodePid}
            if(((Get-Date)-$stableSince).TotalSeconds -ge $Config.stabilitySeconds){return $state}
        }else{$stableSince=$null}
        Start-Sleep -Milliseconds 500
    }while((Get-Date) -lt $deadline)
    if(Test-Path "$ManagerRoot\logs\dsh-host.log"){Get-Content -LiteralPath "$ManagerRoot\logs\dsh-host.log" -Tail 70 -Encoding utf8 | ForEach-Object {Write-Host (Protect-Text $_)}}
    throw 'DSH 未通过持续存活、端口与认证 RPC 联合检查'
}
function Start-Dsh {
    if(-not(Test-Path -LiteralPath $Config.cliEntry) -or -not(Test-Path -LiteralPath "$ProfileRoot\package.json")){throw 'DSH 或 profile 不存在'}
    $current=Get-HostState
    if(Test-OwnedProcess $current){$state=Wait-Healthy;Write-Host "已运行 PID=$($state.nodePid)；未创建第二份";return}
    $listeners=@(Get-Listener)
    if($listeners.Count){throw "端口 $($Config.port) 已被非本管理器实例占用（PID=$($listeners -join ',')）；拒绝启动"}
    if(-not $PSCmdlet.ShouldProcess('DSH Web','启动独立后台宿主')){return}
    if($Config.backend -eq 'scheduler') {
        $task=Get-ScheduledTask -TaskName $Config.taskName
        if(@($task.Actions).Count -ne 1 -or $task.Actions.Execute -ne "$ManagerRoot\DSH-Launcher.exe" -or $task.Actions.Arguments -ne 'host' -or -not(Test-Path -LiteralPath "$ManagerRoot\DSH-Launcher.exe")) {throw '后台任务必须调用 DSH-Launcher.exe host；拒绝通过有窗口的旧入口启动'}
        Start-ScheduledTask -TaskName $Config.taskName
    }
    else {
        $startup=New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0;CreateFlags=[uint32]0x01000008}
        $line='"'+$Config.pwsh+'" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$ManagerRoot+'\DSH-Host.ps1"'
        $created=Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine=$line;CurrentDirectory=$Config.home;ProcessStartupInformation=$startup}
        if($created.ReturnValue -ne 0){throw "WMI 后台创建失败，返回码 $($created.ReturnValue)"}
        Write-ManagerLog "WMI 已创建独立宿主 PID=$($created.ProcessId)"
    }
    $state=Wait-Healthy
    Write-Host "启动验证通过：PID=$($state.nodePid)，Port=$($Config.port)"
}
function Stop-Dsh {
    $state=Get-HostState
    if(-not(Test-OwnedProcess $state)){
        if(@(Get-Listener).Count){throw '监听者不属于本管理器，拒绝停止未知进程'}
        Write-Host 'DSH 已停止';return
    }
    if(-not $PSCmdlet.ShouldProcess("DSH PID=$($state.nodePid)",'停止仅此实例的进程树')){return}
    Set-Content -LiteralPath "$ManagerRoot\state\stop.request" -Value $state.nodePid -Encoding ascii
    $end=(Get-Date).AddSeconds(20)
    while((Get-Date) -lt $end){if(-not(Test-OwnedProcess $state) -and @(Get-Listener).Count -eq 0 -and -not(Test-Path "$ManagerRoot\state\host.json")){Write-Host '停止验证通过：3080 端口释放';return};Start-Sleep -Milliseconds 250}
    throw '停止超时；未终止任何未知进程，请运行 doctor'
}
function Restart-Dsh {Stop-Dsh;if(-not $WhatIfPreference){Start-Dsh}}
function Get-Models {
    if(-not(Test-OwnedProcess (Get-HostState))){$offline=Invoke-Helper @('offline-models');Write-Host '离线结果仅来自 profile 已声明目录；启动后可读取全部实际目录';return $offline.models}
    $catalog=Invoke-DshRpc 'session/modelCatalog'
    $settings=Invoke-DshRpc 'settings/describe'
    $rows=@()
    foreach($group in $catalog.groups){
        foreach($model in $group.models){
            $deep=@($settings.namespaces | Where-Object {$_.ns -match 'llm-deepseek' -and $_.ns -notmatch 'account'}) | Select-Object -First 1
            $value=if($deep){$deep.value}else{$null}
            $known=if($value -and $value.PSObject.Properties['models']){@($value.models | Where-Object id -eq $model.id) | Select-Object -First 1}else{$null}
            $context=$null;$max=$null;$input=$null
            if($group.id -eq 'deepseek-official' -and $value){
                $context=if($known -and $known.PSObject.Properties['contextWindow']){$known.contextWindow}elseif($value.PSObject.Properties['defaultContextWindow']){$value.defaultContextWindow}else{$null}
                $max=if($known -and $known.PSObject.Properties['maxTokens']){$known.maxTokens}elseif($value.PSObject.Properties['maxTokens']){$value.maxTokens}else{$null}
                $input=if($known -and $known.PSObject.Properties['inputModalities']){$known.inputModalities -join ','}else{'text'}
            }
            $rows += [pscustomobject]@{Provider=$group.id;Model=$model.id;Name=$model.name;ContextWindow=$context;MaxTokens=$max;InputTypes=$input;Selected=($catalog.default.provider -eq $group.id -and $catalog.default.model -eq $model.id)}
        }
    }
    if($catalog.failures.Count){Write-Warning (Protect-Text ($catalog.failures | ConvertTo-Json -Compress))}
    return $rows
}
function Get-Plugins { @(Invoke-Helper @('plugins')) }
function Show-Plugins {
    Get-Plugins | Select-Object name,version,bundle,enabled,source,spec,@{n='DisabledRows';e={@($_.rows | Where-Object disabled).Count}},@{n='CompatibilityWarnings';e={@($_.compatibilityWarnings).Count}} | Format-Table -AutoSize | Out-Host
}
function New-Snapshot([string]$Reason='manual') {
    $id=(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+($Reason -replace '[^A-Za-z0-9_-]','_')
    $dest=Join-Path "$ManagerRoot\history" $id
    New-Item -ItemType Directory -Path "$dest\profile","$dest\reports","$dest\manager" | Out-Null
    $files=@()
    foreach($name in @('package.json','pnpm-lock.yaml','cordis.yml','cordis.patch.yml','pnpm-workspace.yaml','compatibility.json')){
        $src=Join-Path $ProfileRoot $name
        if(Test-Path -LiteralPath $src){$null=Invoke-Helper @('safe-copy',$src,"$dest\profile\$name");$files += $name}
    }
    if(Test-Path "$($Config.home)\cordis.patch.yml"){$null=Invoke-Helper @('safe-copy',"$($Config.home)\cordis.patch.yml","$dest\home.cordis.patch.yml")}
    Copy-Item -LiteralPath "$($Config.home)\AGENTS.md" -Destination "$dest\AGENTS.md"
    foreach($name in @('config.json','DSH-Manager.ps1','DSH-Host.ps1','Common.ps1','profile-helper.mjs','DSH-Launcher.cs','DSH-Launcher.exe')){Copy-Item -LiteralPath "$ManagerRoot\$name" -Destination "$dest\manager\$name"}
    Get-Plugins | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath "$dest\reports\plugins.json" -Encoding utf8
    $manifest=[ordered]@{schemaVersion=1;id=$id;reason=$Reason;created=(Get-Date).ToString('o');dshVersion=(Get-DshVersion);nodeVersion=(& $Config.node --version | Out-String).Trim();pnpmVersion=(& $Config.pnpm --version | Out-String).Trim();gitVersion=(& $Config.git --version | Out-String).Trim();profile=$Config.profile;files=$files;managerConfig=$true;hashes=@(Get-ChildItem -LiteralPath "$dest\profile" -File | ForEach-Object {@{file=$_.Name;sha256=(Get-Sha256 $_.FullName)}})}
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath "$dest\manifest.json" -Encoding utf8
    $backup=Join-Path "$($Config.home)\backup" $id
    Copy-Item -LiteralPath $dest -Destination $backup -Recurse
    Write-ManagerLog "快照=$id，备份=$backup"
    Write-Host "快照：$dest"
    return $id
}
function Get-Snapshots {
    foreach($d in Get-ChildItem -LiteralPath "$ManagerRoot\history" -Directory | Sort-Object Name -Descending){$p=Join-Path $d.FullName 'manifest.json';if(Test-Path $p){Get-Content -LiteralPath $p -Raw | ConvertFrom-Json}}
}
function Confirm-Choice([string]$Message) {
    if($Yes){return $true}
    return (Read-Host "$Message（输入 YES 确认）") -ceq 'YES'
}
function Restore-Snapshot([string]$Id) {
    if(-not $Id){Get-Snapshots | Select-Object id,created,reason,dshVersion | Format-Table | Out-Host;$Id=Read-Host '请输入完整快照 ID'}
    $snap=@(Get-Snapshots | Where-Object id -ceq $Id)
    if($snap.Count -ne 1){throw '必须使用列出的精确快照 ID'}
    $m=$snap[0];$dir=Join-Path "$ManagerRoot\history" $Id
    if($m.profile -ne $Config.profile){throw '快照 profile 不匹配'}
    foreach($name in $m.files){if($name -notin @('package.json','pnpm-lock.yaml','cordis.yml','cordis.patch.yml','pnpm-workspace.yaml','compatibility.json')){throw '快照文件名不合法'}}
    if($m.PSObject.Properties['hashes']){foreach($h in $m.hashes){if((Get-Sha256 "$dir\profile\$($h.file)") -ne $h.sha256){throw "快照校验失败: $($h.file)"}}}
    Write-Host "将恢复 $Id，DSH=$($m.dshVersion)；当前凭据、会话与项目保留"
    if(-not $PSCmdlet.ShouldProcess($Id,'保护当前状态后恢复 profile 与锁定依赖')){return}
    if(-not(Confirm-Choice '确认恢复')){return}
    $guard=New-Snapshot 'before-restore'
    try {
        Stop-Dsh
        if((Get-DshVersion) -ne $m.dshVersion){Invoke-Native $Config.npm @('install','--global','--prefix',$Config.npmPrefix,"@deepseek-ai/dsh@$($m.dshVersion)") 'restore.log'}
        foreach($name in $m.files){Copy-Item -LiteralPath "$dir\profile\$name" -Destination "$ProfileRoot\$name" -Force}
        foreach($name in @('compatibility.json','pnpm-workspace.yaml')){if($name -notin $m.files -and (Test-Path "$ProfileRoot\$name")){Remove-Item -LiteralPath "$ProfileRoot\$name"}}
        if(Test-Path "$dir\home.cordis.patch.yml"){Copy-Item -LiteralPath "$dir\home.cordis.patch.yml" -Destination "$($Config.home)\cordis.patch.yml" -Force}
        Invoke-Native $Config.dsh @('plugin','--profile',$Config.profile,'install','--frozen-lockfile','--ignore-scripts') 'restore.log'
        $null=Invoke-Helper @('validate')
        Start-Dsh
        Write-Host "恢复及启动验证通过；保护快照=$guard"
    }catch{Write-ManagerLog ($_ | Out-String) 'restore.log';throw "恢复失败，当前保护快照=$guard。$($_.Exception.Message)"}
}
function Get-RegistryMeta([string]$Spec) {
    $json=& $Config.npm view $Spec --json --registry=https://registry.npmjs.org --fetch-retries=0 --fetch-timeout=20000 2>&1
    if($LASTEXITCODE -ne 0){throw "官方 registry 查询失败: $(Protect-Text ($json | Out-String))"}
    return ($json | Out-String | ConvertFrom-Json)
}
function Test-Peers($Meta) {
    $temp="$ManagerRoot\state\registry-meta.json"
    try{[IO.File]::WriteAllText($temp,($Meta | ConvertTo-Json -Depth 30));$check=Invoke-Helper @('peer-check',$temp,(Get-DshVersion));if(-not $check.compatible){throw "拒绝不兼容更新: $($check.refused | ConvertTo-Json -Compress)"}}finally{[IO.File]::Delete($temp)}
}
function Change-Plugin([string]$Verb,[string]$Name) {
    $plugins=Get-Plugins
    if(-not $Name){Show-Plugins;$Name=Read-Host '请输入列表中的精确 Package name'}
    $p=@($plugins | Where-Object name -ceq $Name)
    if($p.Count -ne 1){throw '必须使用已安装插件的精确 identifier'}
    if($Name.StartsWith('@deepseek-ai/')){throw '管理器保护官方组件，请通过官方管理界面评估'}
    $spec=$Name
    if($Verb -eq 'update'){
        if($p[0].source -ne 'npm'){throw 'Git/local 更新需要明确的新 spec，请使用官方 CLI；管理器不猜测'}
        $meta=Get-RegistryMeta $Name
        Test-Peers $meta
        if($meta.version -eq $p[0].version){Write-Host '已经是当前 registry 版本';return}
        $spec="$Name@$($meta.version)"
    }
    Write-Host "操作=$Verb，目标=$spec；涉及 $($p[0].rows.Count) 个声明行，启用=$($p[0].enabled)"
    if(-not $PSCmdlet.ShouldProcess($spec,"官方插件 $Verb，创建快照并验证启动")){return}
    if(-not(Confirm-Choice "确认 $Verb 插件及其运行贡献")){return}
    $snap=New-Snapshot "before-plugin-$Verb"
    try {
        Stop-Dsh
        if($Verb -eq 'remove'){Invoke-Native $Config.dsh @('plugin','--profile',$Config.profile,'remove',$Name) 'plugin-operations.log'}
        else{Invoke-Native $Config.dsh @('plugin','--profile',$Config.profile,'add',$spec,'--strict-peer-dependencies') 'plugin-operations.log'}
        $null=Invoke-Helper @('validate')
        $remaining=Get-Plugins
        if($Verb -eq 'remove' -and @($remaining | Where-Object name -ceq $Name).Count){throw '卸载后 manifest 仍保留目标'}
        Start-Dsh
        Write-Host "插件 $Verb 与启动验证通过；快照=$snap"
    } catch {
        Write-ManagerLog ($_ | Out-String) 'plugin-operations.log'
        Write-Host "插件操作失败；尝试恢复保护快照 $snap"
        $savedYes=$script:Yes;$script:Yes=$true
        try{Restore-Snapshot $snap}finally{$script:Yes=$savedYes}
        throw '插件操作失败，诊断已保留；已尝试保护恢复'
    }
}
function Check-PluginUpdates {
    foreach($p in Get-Plugins){
        if($p.source -ne 'npm'){Write-Host "$($p.name): $($p.source)，仅列出，不自动更新";continue}
        try{$m=Get-RegistryMeta $p.name;Write-Host "$($p.name) installed=$($p.version) registry=$($m.version)"}catch{Write-Warning $_.Exception.Message}
    }
}
function Update-Dsh {
    $current=Get-DshVersion
    $meta=Get-RegistryMeta "@deepseek-ai/dsh@$($Config.updateChannel)"
    Write-Host "当前=$current，官方 $($Config.updateChannel)=$($meta.version)"
    if($meta.version -eq $current){Write-Host '此渠道无新版本';return}
    if(-not $Apply){Write-Host '仅检查；使用 dsh update -Apply 执行';return}
    if(($current.Split('.')[0..1] -join '.') -ne ($meta.version.Split('.')[0..1] -join '.') -and -not $AllowMajor){throw '兼容版本边界变化；请审阅发布说明后显式使用 -AllowMajor'}
    $official=Invoke-RestMethod -Uri ("https://api.github.com/repos/deepseek-ai/deepseek-harness/contents/package.json?ref=dsh-v"+$meta.version) -TimeoutSec 20
    $temp="$ManagerRoot\state\target-runtime.json"
    try {
        [IO.File]::WriteAllText($temp,[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($official.content)))
        $check=Invoke-Helper @('runtime-check',$temp,(& $Config.node --version | Out-String).Trim(),(& $Config.pnpm --version | Out-String).Trim(),$meta.version)
        if(-not $check.compatible){throw ($check.issues -join '; ')}
    } finally {[IO.File]::Delete($temp)}
    if(-not $PSCmdlet.ShouldProcess($meta.version,'更新 DSH，创建快照并验证')){return}
    if(-not(Confirm-Choice '确认更新 DSH')){return}
    $snap=New-Snapshot 'before-dsh-update'
    try{Stop-Dsh;Invoke-Native $Config.npm @('install','--global','--prefix',$Config.npmPrefix,"@deepseek-ai/dsh@$($meta.version)") 'update.log';if((Get-DshVersion) -ne $meta.version){throw '更新后版本不匹配'};Start-Dsh}
    catch{
        Write-ManagerLog ($_ | Out-String) 'update.log'
        Write-Host "更新失败；保护快照=$snap"
        if(Confirm-Choice '是否恢复更新前快照'){Restore-Snapshot $snap}
        throw "更新未成功；保护快照=$snap，诊断见 update.log"
    }
}
function Set-Autostart([bool]$Enabled) {
    if(-not $PSCmdlet.ShouldProcess('当前用户 DSH 登录自启',$(if($Enabled){'启用'}else{'禁用'}))){return}
    if($Config.backend -eq 'scheduler'){
        $task=Get-ScheduledTask -TaskName $Config.taskName
        if($Enabled){$trigger=New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name);$trigger.Delay='PT30S';Set-ScheduledTask -TaskName $Config.taskName -Trigger $trigger | Out-Null}
        else{$xml=Export-ScheduledTask -TaskName $Config.taskName;[xml]$doc=$xml;$triggers=$doc.SelectSingleNode('//*[local-name()="Triggers"]');if($null -ne $triggers){$triggers.RemoveAll()};Register-ScheduledTask -TaskName $Config.taskName -Xml $doc.OuterXml -Force | Out-Null}
    } else {
        $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        if($Enabled){New-Item -Path $key -Force | Out-Null;New-ItemProperty -LiteralPath $key -Name 'DSH Manager Web' -PropertyType String -Value ('"'+$env:WINDIR+'\System32\wscript.exe" "'+$ManagerRoot+'\DSH-Autostart.vbs"') -Force | Out-Null}
        else{Remove-ItemProperty -LiteralPath $key -Name 'DSH Manager Web' -ErrorAction SilentlyContinue}
    }
    Write-Host ('登录自启 '+$(if($Enabled){'Enabled'}else{'Disabled'}))
}
function Get-Autostart {
    if($Config.backend -eq 'scheduler'){$t=Get-ScheduledTask -TaskName $Config.taskName -ErrorAction SilentlyContinue;return $null -ne $t -and @($t.Triggers | Where-Object {$null -ne $_}).Count -gt 0}
    $v=Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'DSH Manager Web' -ErrorAction SilentlyContinue
    return $null -ne $v
}
function Show-Status {
    $state=Get-HostState;$running=Test-OwnedProcess $state
    $model=Invoke-Helper @('offline-models')
    $latest=Get-Snapshots | Select-Object -First 1
    [pscustomobject]@{Running=$running;PID=$(if($running){$state.nodePid}else{$null});Port=$Config.port;DSHVersion=(Get-DshVersion);DSH_HOME=$Config.home;Profile=$Config.profile;Backend=$Config.backend;Autostart=(Get-Autostart);CurrentModel=($model.default.provider+'/'+$model.default.model);PluginCount=@(Get-Plugins).Count;LastSnapshot=$(if($latest){$latest.id}else{$null});LogPath="$ManagerRoot\logs\dsh-host.log"} | Format-List | Out-Host
}
function Doctor {
    Show-Status
    foreach($name in @('node','dsh','cliEntry','pnpm','git','pwsh')){Write-Host "$name exists=$(Test-Path -LiteralPath $Config.$name)"}
    $validation=Invoke-Helper @('validate');Write-Host "profile / YAML / lockfile parsing=$($validation.valid)"
    Write-Host "Listeners=$(@(Get-Listener) -join ',')"
    $old=@(Get-LegacyBatFiles)
    Write-Host "旧 BAT 数=$($old.Count)"
    $tasks=@(Get-ScheduledTask | Where-Object {$_.TaskName -match 'DSH|Harness'})
    $tasks | Select-Object TaskName,State,@{n='Command';e={$_.Actions.Execute}},@{n='Args';e={$_.Actions.Arguments}} | Format-Table -Wrap | Out-Host
    $plugins=Get-Plugins
    foreach($p in $plugins){if($p.version -eq 'missing'){Write-Warning "缺失插件包 $($p.name)"};foreach($warning in $p.compatibilityWarnings){Write-Warning "$($p.name): $warning"}}
    $instances=@(Get-CimInstance Win32_Process | Where-Object {$_.Name -eq 'node.exe' -and $_.CommandLine -match [regex]::Escape($Config.cliEntry) -and $_.CommandLine -match '--profile\s+"?web"?(?:\s|$)'})
    Write-Host "DSH Web 实例数=$($instances.Count)"
    foreach($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\Run')){
        if(Test-Path $key){$values=Get-ItemProperty -LiteralPath $key;foreach($v in $values.PSObject.Properties | Where-Object Name -notlike 'PS*'){if($v.Value -match 'DSH|Harness'){Write-Host "$key $($v.Name): $(Protect-Text $v.Value)"}}}
    }
    foreach($folder in @([Environment]::GetFolderPath('Startup'),[Environment]::GetFolderPath('CommonStartup'))){if($folder -and(Test-Path -LiteralPath $folder)){Write-Host "Startup=$folder";Get-ChildItem -LiteralPath $folder -File | Select-Object Name | Format-Table | Out-Host}}
    if(Test-Path "$ManagerRoot\logs\dsh-host.log"){Get-Content -LiteralPath "$ManagerRoot\logs\dsh-host.log" -Tail 100 -Encoding utf8 | Select-String '\bError\b|\bWarning\b|Exception|failed [1-9]|pending [1-9]|错误' | ForEach-Object {Write-Host (Protect-Text $_.Line)}}
    if(@($tasks | Where-Object TaskName -eq 'DeepSeek Harness').Count){Write-Warning '旧管理员计划任务仍存在：需要管理员运行 Complete-Migration.ps1'}
}
function Select-Model {
    $models=@(Get-Models)
    if(-not(Test-OwnedProcess (Get-HostState))){throw '请选择启动 DSH 后再切换，以便校验实际官方目录'}
    if(-not $Target){$models | Format-Table -AutoSize | Out-Host;$script:Target=Read-Host '输入精确 Model ID';$script:Provider=Read-Host '输入 Provider ID'}
    $match=@($models | Where-Object {$_.Model -ceq $Target -and (-not $Provider -or $_.Provider -ceq $Provider)})
    if($match.Count -ne 1){throw '模型必须是实际目录中的唯一 Provider / Model 组合'}
    if(-not $PSCmdlet.ShouldProcess("$($match[0].Provider)/$Target",'保存默认模型，下次请求生效')){return}
    $null=New-Snapshot 'before-model-select'
    $s=Invoke-DshRpc 'settings/describe'
    $ns=@($s.namespaces | Where-Object ns -match 'agent-default-model')
    if($ns.Count -ne 1){throw '无法唯一定位官方默认模型设置 namespace'}
    $ops=@(@{op='set';path=@('provider');value=$match[0].Provider},@{op='set';path=@('model');value=$Target})
    $null=Invoke-DshRpc 'settings/mutate' @{ns=$ns[0].ns;ops=$ops;expectedRevision=$ns[0].revision}
    $check=Invoke-DshRpc 'session/modelCatalog'
    if($check.default.model -ne $Target -or $check.default.provider -ne $match[0].Provider){throw '默认模型保存未验证'}
    Write-Host "默认模型已保存并回读验证：$Target；Provider 配置与凭据保留，无需重启"
}
function Invoke-Action {
    switch($Command){
        'status' {Show-Status}
        'start' {if($AutostartInvocation){Start-Sleep -Seconds $Config.autostartDelaySeconds};Start-Dsh}
        'stop' {Stop-Dsh}
        'restart' {Restart-Dsh}
        'doctor' {Doctor}
        'autostart' {switch($Action){'enable'{Set-Autostart $true};'disable'{Set-Autostart $false};'status'{Write-Host "Autostart=$(Get-Autostart)"};default{throw 'autostart enable|disable|status'}}}
        'plugins' {switch($Action){'list'{Show-Plugins};'remove'{Change-Plugin 'remove' $Target};'update'{if($Target){Change-Plugin 'update' $Target}else{Check-PluginUpdates}};default{throw 'plugins list|remove|update'}}}
        'models' {switch($Action){'list'{Get-Models | Format-Table -AutoSize | Out-Host};'select'{Select-Model};'refresh'{$before=@(Get-Models);Update-Dsh;$after=@(Get-Models);Write-Host '目录已重新读取；显式自定义模型覆盖保留；未使用不存在的在线刷新 API';$after | Format-Table -AutoSize | Out-Host};default{throw 'models list|select|refresh'}}}
        'dsh' {if($Action -ne 'update'){throw 'dsh update'};Update-Dsh}
        'snapshot' {switch($Action){'create'{if($PSCmdlet.ShouldProcess('profile 与管理器','创建快照')){$null=New-Snapshot $(if($Target){$Target}else{'manual'})}};'list'{Get-Snapshots | Select-Object id,created,reason,dshVersion | Format-Table | Out-Host};'restore'{Restore-Snapshot $Target};default{throw 'snapshot create|list|restore'}}}
        'logs' {Invoke-Item -LiteralPath "$ManagerRoot\logs"}
        default {throw "未知命令 $Command"}
    }
}
$lock=$null;$locked=$false
try {
    if($Command -eq 'menu'){
        $options=@('status','start','stop','restart','autostart enable','autostart disable','autostart status','models list','models refresh','models select','plugins list','plugins remove','plugins update','snapshot create','snapshot list','snapshot restore','dsh update','doctor','logs')
        $labels=@('查看状态','启动 DSH','停止 DSH','重启 DSH','开启登录自启','关闭登录自启','查看自启','查看模型','刷新模型目录','切换模型','查看插件','卸载插件','检查插件更新','创建快照','查看历史','恢复历史','检查 DSH 更新','Doctor 诊断','打开日志')
        while($true){Write-Host "`nDSH Manager";for($i=0;$i -lt $options.Count;$i++){Write-Host "$($i+1). $($labels[$i])"};Write-Host '0. 退出';$choice=Read-Host '选择';if($choice -eq '0'){break};$index=0;if([int]::TryParse($choice,[ref]$index) -and $index -ge 1 -and $index -le $options.Count){$parts=$options[$index-1].Split(' ');$call=@($parts);& $Config.pwsh -NoProfile -ExecutionPolicy Bypass -File "$ManagerRoot\DSH-Manager.ps1" @call}}
    }else {
        if($Command -notin @('status','doctor','logs') -and -not($Action -eq 'list' -or $Action -eq 'status')){
            $lock=[Threading.Mutex]::new($false,'Local\DSH-Manager-Web-Control');$locked=$lock.WaitOne(1000);if(-not $locked){throw '其他管理操作正在运行'}
        }
        Invoke-Action
    }
    exit 0
}catch{Write-ManagerLog ($_ | Out-String);Write-Error (Protect-Text $_.Exception.Message) -ErrorAction Continue;exit 1}
finally{if($locked){$lock.ReleaseMutex()};if($null -ne $lock){$lock.Dispose()}}
