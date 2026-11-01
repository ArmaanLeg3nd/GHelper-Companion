#requires -Version 7.0
param([switch]$SmokeTest)
$ErrorActionPreference='Stop'
$installRoot=Split-Path $PSScriptRoot -Parent
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$admin=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $admin){throw 'Launch GHelperCompanion.exe to run as administrator.'}
$created=$false
$mutexName=if($SmokeTest){'Local\GHelperCompanion-SmokeTest'}else{'Local\GHelperCompanion'}
$mutex=[Threading.Mutex]::new($true,$mutexName,$([ref]$created))
if(-not $created){$mutex.Dispose();exit}
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$dir=Join-Path $env:LOCALAPPDATA 'GHelperCompanion'
$null=New-Item -ItemType Directory -Path $dir -Force
$settingsPath=Join-Path $dir 'settings.json';$logPath=Join-Path $dir 'activity.log'
$script:continuous=$false
if(Test-Path $settingsPath){try{$script:continuous=[bool](Get-Content $settingsPath -Raw | ConvertFrom-Json).Continuous}catch{}}
$script:busy=$null;$script:nextScan=[DateTime]::UtcNow;$script:status='Ready';$script:quitting=$false
function Log([string]$s){if((Test-Path $logPath) -and (Get-Item $logPath).Length -gt 1MB){Move-Item $logPath "$logPath.previous" -Force};Add-Content $logPath "$(Get-Date -Format o) $s"}
function Save-Settings { @{Continuous=$script:continuous}|ConvertTo-Json|Set-Content $settingsPath }
$ctx=[Windows.Forms.ApplicationContext]::new()
$tray=[Windows.Forms.NotifyIcon]::new();$tray.Icon=[Drawing.SystemIcons]::Shield;$tray.Text='GHelper Companion: ready'
$menu=[Windows.Forms.ContextMenuStrip]::new()
function Item($text){$i=[Windows.Forms.ToolStripMenuItem]::new($text);$null=$menu.Items.Add($i);return $i}
$statusItem=Item 'Ready';$statusItem.Enabled=$false
$auto=Item 'Auto-stop services';$auto.Checked=$script:continuous
$scan=Item 'Scan now'
$startup=Item 'Run at sign-in';$taskName='GHelperCompanion'
$startup.Checked=($null -ne (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue))
$exit=Item 'Exit'
function Notify([string]$s){$tray.BalloonTipTitle='GHelper Companion';$tray.BalloonTipText=$s;$tray.ShowBalloonTip(6000)}
function Start-Check([string]$op,[bool]$manual){
    if($script:busy){return}
    $id=[guid]::NewGuid().ToString('N');$result=Join-Path $dir "$id.json"
    $args='-NoProfile -STA -WindowStyle Hidden -File "'+(Join-Path $PSScriptRoot 'Worker.ps1')+'" -Operation '+$op+' -ResultPath "'+$result+'"'
    $psi=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'),$args);$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $proc=[Diagnostics.Process]::Start($psi)
    $script:busy=@{Process=$proc;Result=$result;Started=[DateTime]::UtcNow;Manual=$manual;Operation=$op}
    $script:status=if($op -eq 'Stop'){'Checking / enforcing…'}else{'Scanning…'}
}
function Scan-Now { Start-Check $(if($script:continuous){'Stop'}else{'Scan'}) $true }
$scan.Add_Click({Scan-Now})
$auto.Add_Click({$script:continuous=-not $script:continuous;$auto.Checked=$script:continuous;$script:nextScan=[DateTime]::UtcNow;$script:status=if($script:continuous){'Watching'}else{'Auto-stop off'};Save-Settings;Log "Continuous=$script:continuous"})
$startup.Add_Click({try{
 if($startup.Checked){Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop;$startup.Checked=$false}
 else {
  $action=New-ScheduledTaskAction -Execute (Join-Path $installRoot 'GHelperCompanion.exe') -WorkingDirectory $installRoot
  $trigger=New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
  $principal=New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Highest
  $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
  $null=Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Tray companion using GHelper own background service stop action.' -ErrorAction Stop
  $startup.Checked=$true
 };Log "Startup=$($startup.Checked)"
}catch{Notify $_.Exception.Message;Log $_.Exception.Message}})
$exit.Add_Click({if($script:busy){Notify 'A scan or stop request is still in progress. Wait for completion before exiting.';return};$script:quitting=$true;$ctx.ExitThread()})
$tray.Add_DoubleClick({Scan-Now})
$tray.ContextMenuStrip=$menu;$tray.Visible=$true
$timer=[Windows.Forms.Timer]::new();$timer.Interval=500
$timer.Add_Tick({try{
 if($script:busy){
  $b=$script:busy
  if($b.Process.HasExited){
   try{
    if(-not(Test-Path $b.Result)){throw 'Worker exited without a result.'}
    $r=Get-Content $b.Result -Raw|ConvertFrom-Json
    $script:status=if($r.Ok){if(@($r.Running).Count -eq 0){'All services stopped'}else{"$(@($r.Running).Count) service(s) running"}}elseif($r.Message -like '*control unavailable*'){'Open GHelper Extra to continue'}else{'Needs attention — auto-stop off'}
    Log "$($b.Operation): $($r.Message)"
    if(-not $r.Ok){$script:continuous=$false;$auto.Checked=$false;Save-Settings;Notify $r.Message}
    elseif($b.Manual){Notify $r.Message}
    elseif($r.ForegroundUnchanged -eq $false){$script:continuous=$false;$auto.Checked=$false;Save-Settings;Notify 'Foreground changed during the stop. Enforcement paused.'}
   }catch{$script:continuous=$false;$auto.Checked=$false;Save-Settings;Notify $_.Exception.Message;Log $_.Exception.Message}
   finally{if(Test-Path $b.Result){Remove-Item -LiteralPath $b.Result};$b.Process.Dispose();$script:busy=$null;$script:nextScan=[DateTime]::UtcNow.AddSeconds(15)}
  }elseif(([DateTime]::UtcNow-$b.Started).TotalSeconds -gt 100){
   $b.Process.Kill();$script:continuous=$false;$auto.Checked=$false;Save-Settings;$script:status='Request timed out; enforcement off';Notify $script:status;Log $script:status
  }
 }elseif($script:continuous -and [DateTime]::UtcNow -ge $script:nextScan){
  if(Get-Process GHelper -ErrorAction SilentlyContinue){Start-Check 'Stop' $false}else{$script:status='Waiting for GHelper';$script:nextScan=[DateTime]::UtcNow.AddSeconds(15)}
 }
 $scan.Enabled=($null -eq $script:busy);$auto.Enabled=$scan.Enabled
 $statusItem.Text=$script:status
 $tray.Text=('GHelper Companion: '+$(if($script:continuous){'auto on'}else{'auto off'}))
}catch{Log $_.Exception.Message;$script:continuous=$false;$auto.Checked=$false}})
Log 'Tray started';$timer.Start()
if($SmokeTest){
 $labels=@($menu.Items | ForEach-Object Text)
 if(($labels -join '|') -cne 'Ready|Auto-stop services|Scan now|Run at sign-in|Exit'){throw 'Unexpected tray menu'}
 # Exercise both scan routes with a stub so smoke testing never changes services.
 $script:requested=$null
 function Start-Check([string]$op,[bool]$manual){$script:requested=$op}
 $savedContinuous=$script:continuous
 $script:continuous=$false;Scan-Now;if($script:requested -ne 'Scan'){throw 'Scan with auto-stop off must be read-only'}
 $script:continuous=$true;Scan-Now;if($script:requested -ne 'Stop'){throw 'Scan with auto-stop on must enforce'}
 $script:continuous=$savedContinuous
 'PASS: four menu options, status line, and both Scan now routes.'
 $smoke=[Windows.Forms.Timer]::new();$smoke.Interval=2000;$smoke.Add_Tick({$smoke.Stop();$ctx.ExitThread()});$smoke.Start()
}
try{[Windows.Forms.Application]::Run($ctx)}finally{$timer.Stop();$timer.Dispose();$tray.Visible=$false;$tray.Dispose();$menu.Dispose();$ctx.Dispose();$mutex.ReleaseMutex();$mutex.Dispose();Log 'Tray exited'}


