. "$PSScriptRoot\Common.ps1"
Write-ManagerLog "Host=$PID 已加载 Common；PowerShell=$($PSVersionTable.PSVersion)" 'dsh-host.log'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public sealed class DshJob : IDisposable {
 [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
 [DllImport("kernel32.dll")] public static extern uint GetConsoleProcessList([Out] uint[] ids,uint count);
 [StructLayout(LayoutKind.Sequential)] struct Basic { public long a,b; public uint flags; public UIntPtr min,max; public uint active; public UIntPtr affinity; public uint priority,scheduling; }
 [StructLayout(LayoutKind.Sequential)] struct Io { public ulong a,b,c,d,e,f; }
 [StructLayout(LayoutKind.Sequential)] struct Extended { public Basic basic; public Io io; public UIntPtr a,b,c,d; }
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr a,string b);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr h,int c,IntPtr p,uint n);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr h,IntPtr p);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 IntPtr h;
 public DshJob(){h=CreateJobObject(IntPtr.Zero,null);var e=new Extended();e.basic.flags=0x2000;int n=Marshal.SizeOf(e);IntPtr p=Marshal.AllocHGlobal(n);try{Marshal.StructureToPtr(e,p,false);if(h==IntPtr.Zero||!SetInformationJobObject(h,9,p,(uint)n))throw new System.ComponentModel.Win32Exception();}finally{Marshal.FreeHGlobal(p);}}
 public void Assign(IntPtr process){if(!AssignProcessToJobObject(h,process))throw new System.ComponentModel.Win32Exception();}
 public void Dispose(){if(h!=IntPtr.Zero){CloseHandle(h);h=IntPtr.Zero;}}
}
'@
Write-ManagerLog "Host=$PID Job Object 类型准备完成" 'dsh-host.log'
$consoleWindow=[DshJob]::GetConsoleWindow().ToInt64()
$consoleIds=New-Object uint32[] 64
$consoleCount=[DshJob]::GetConsoleProcessList($consoleIds,64)
Write-ManagerLog "Host=$PID ConsoleWindow=$consoleWindow ConsoleProcessCount=$consoleCount" 'dsh-host.log'
if($Config.backend -eq 'scheduler' -and $consoleWindow -ne 0){throw '后台宿主仍连接控制台窗口，拒绝假后台；请检查计划任务是否调用 DSH-Launcher.exe host'}
$mutex=[Threading.Mutex]::new($false,'Local\DSH-Manager-Web-Host')
$owned=$false; $process=$null; $job=$null
try {
    $owned=$mutex.WaitOne(0)
    if(-not $owned){exit 0}
    if(@(Get-Listener).Count){throw '端口已被占用，拒绝启动第二份实例'}
    Remove-Item -LiteralPath "$ManagerRoot\state\stop.request" -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "$ManagerRoot\state\launch-url.clixml" -ErrorAction SilentlyContinue
    $psi=[Diagnostics.ProcessStartInfo]::new()
    $psi.FileName=$Config.node
    $psi.Arguments='"'+$Config.cliEntry+'" --profile "'+$Config.profile+'" --no-open'
    $psi.WorkingDirectory=$Config.home
    $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $psi.EnvironmentVariables['DSH_HOME']=$Config.home
    $process=[Diagnostics.Process]::new();$process.StartInfo=$psi
    $job=[DshJob]::new()
    if(-not $process.Start()){throw 'DSH 进程创建失败'}
    $job.Assign($process.Handle)
    $cim=Get-CimInstance Win32_Process -Filter "ProcessId=$($process.Id)"
    @{nodePid=$process.Id;nodeCreated=([datetime]$cim.CreationDate).ToUniversalTime().ToString('o');hostPid=$PID;hostCreated=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o');started=(Get-Date).ToString('o');backend=$Config.backend;consoleWindow=$consoleWindow;consoleProcessCount=$consoleCount;consoleProcessIds=@($consoleIds | Select-Object -First $consoleCount)} | ConvertTo-Json | Set-Content -LiteralPath "$ManagerRoot\state\host.json" -Encoding utf8
    Write-ManagerLog "Host=$PID Node=$($process.Id)；已加入独立生命周期 Job Object" 'dsh-host.log'
    $streams=@($process.StandardOutput,$process.StandardError)
    $pending=@($streams[0].ReadLineAsync(),$streams[1].ReadLineAsync())
    while($true){
        for($i=0;$i -lt 2;$i++){
            if($null -ne $pending[$i] -and $pending[$i].IsCompleted){
                $line=$pending[$i].GetAwaiter().GetResult()
                if($null -eq $line){$pending[$i]=$null;continue}
                if($line -match 'dsh web:\s*(http://127\.0\.0\.1:\d+/\?token=\S+)'){
                    ConvertTo-SecureString -String $Matches[1] -AsPlainText -Force | Export-Clixml -LiteralPath "$ManagerRoot\state\launch-url.clixml"
                }
                Write-ManagerLog $line 'dsh-host.log'
                $pending[$i]=$streams[$i].ReadLineAsync()
            }
        }
        if(Test-Path -LiteralPath "$ManagerRoot\state\stop.request"){
            if(-not $process.HasExited){Write-ManagerLog '收到停止请求；Windows 无官方 HTTP 退出接口，关闭仅本 Host 所持有的 DSH Job Object' 'dsh-host.log';$job.Dispose();$process.WaitForExit(10000) | Out-Null}
        }
        if($process.HasExited -and $null -eq $pending[0] -and $null -eq $pending[1]){break}
        Start-Sleep -Milliseconds 50
    }
    Write-ManagerLog "DSH 退出码=$($process.ExitCode)" 'dsh-host.log'
    exit $process.ExitCode
} catch {Write-ManagerLog ($_ | Out-String) 'dsh-host.log';exit 1}
finally {
    if($null -ne $job){$job.Dispose()}
    if($null -ne $process){$process.Dispose()}
    if($owned){Remove-Item -LiteralPath "$ManagerRoot\state\host.json","$ManagerRoot\state\stop.request","$ManagerRoot\state\launch-url.clixml" -ErrorAction SilentlyContinue;$mutex.ReleaseMutex()}
    $mutex.Dispose()
}
