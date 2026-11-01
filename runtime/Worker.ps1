#requires -Version 7.0
param([ValidateSet('Scan','Stop')][string]$Operation='Scan',[Parameter(Mandatory)][string]$ResultPath)
$ErrorActionPreference='Stop'
$out=[ordered]@{Ok=$false;Operation=$Operation;Message='';Running=@();Preference=$null;Time=(Get-Date).ToString('o')}
$hook=[IntPtr]::Zero;$returnHook=[IntPtr]::Zero;$module=[IntPtr]::Zero;$ownedExtra=[IntPtr]::Zero;$opening=$false;$watching=$false
try {
    $procs=@(Get-Process GHelper -ErrorAction SilentlyContinue)
    if($procs.Count -ne 1){throw 'GHelper must be running as a single instance.'}
    $exe=$procs[0].Path
    if(-not $exe){throw 'Cannot read GHelper path. Run the helper as administrator.'}
    $data=& "$PSScriptRoot\Extract-GHelperServices.ps1" -Path $exe
    $portable=Join-Path (Split-Path $exe) 'config.json'
    $cfgPath=if(Test-Path -LiteralPath $portable){$portable}else{Join-Path $env:APPDATA 'GHelper\config.json'}
    $cfg=Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
    $names=@($data.services)
    if($cfg.stop_ac -eq 1){$names+=@($data.servicesAC)}
    $out.IncludeArmouryCrate=($cfg.stop_ac -eq 1)
    $out.Preference=$cfg.services_disabled
    function Get-Active {
        @(Get-Service -ErrorAction Stop | Where-Object {$_.ServiceName -in $names -and $_.Status -ne 'Stopped'})
    }
    $active=Get-Active
    $out.Running=@($active | ForEach-Object ServiceName)
    if($Operation -eq 'Scan'){
        $out.Ok=$true; $out.Message="$($active.Count) listed service(s) active. Armoury Crate inclusion follows GHelper's setting."
    } elseif($active.Count -eq 0){
        $out.Ok=$true;$out.Message='All listed services are stopped; no toggle sent.'
    } else {
        foreach($svc in $active){
            if(([int]$svc.ServiceType -band 0x30) -eq 0 -or ([int]$svc.ServiceType -band 0xf) -ne 0){throw 'A listed entry is a driver. Stop cancelled.'}
            if(@($svc.DependentServices | Where-Object {$_.Status -ne 'Stopped' -and $_.ServiceName -notin $names}).Count){throw "An unrelated active service depends on $($svc.ServiceName). Stop cancelled."}
        }
        Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Windows.Forms
        Add-Type @'
using System;using System.Collections.Generic;using System.Runtime.InteropServices;
public static class GHNative {
 public delegate bool EnumProc(IntPtr h,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h,EnumProc cb,IntPtr p);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
 [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h); [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h,System.Text.StringBuilder b,int n); public static bool IsToggleCaption(IntPtr h){var b=new System.Text.StringBuilder(100);GetWindowText(h,b,100);return b.ToString()=="Stop" || b.ToString()=="Start";}
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern IntPtr LoadLibraryEx(string p,IntPtr r,uint f);
 [DllImport("kernel32.dll",CharSet=CharSet.Ansi,ExactSpelling=true)] public static extern IntPtr GetProcAddress(IntPtr m,string n);
 [DllImport("kernel32.dll")] public static extern bool FreeLibrary(IntPtr m);
 [DllImport("user32.dll",EntryPoint="SetWindowsHookExW",CharSet=CharSet.Unicode,ExactSpelling=true,SetLastError=true)] public static extern IntPtr SetWindowsHookEx(int k,IntPtr cb,IntPtr m,uint t);
 [DllImport("user32.dll")] public static extern bool UnhookWindowsHookEx(IntPtr h);
 [DllImport("user32.dll",EntryPoint="GetPropW",CharSet=CharSet.Unicode,ExactSpelling=true)] public static extern IntPtr GetProp(IntPtr h,string n);
 [DllImport("dwmapi.dll",ExactSpelling=true)] public static extern int DwmGetWindowAttribute(IntPtr h,int attribute,out int value,int size);
 public delegate void WinEventProc(IntPtr hook,uint evt,IntPtr hwnd,int obj,int child,uint thread,uint time);
 [DllImport("user32.dll",ExactSpelling=true)] static extern IntPtr SetWinEventHook(uint min,uint max,IntPtr m,WinEventProc cb,uint pid,uint thread,uint flags);
 [DllImport("user32.dll",ExactSpelling=true)] static extern bool UnhookWinEvent(IntPtr hook);
 static IntPtr eventHook;static uint watchedPid,initialPid;public static int TargetActivations;
 static WinEventProc eventCallback=(hook,evt,h,obj,child,thread,time)=>{uint p;GetWindowThreadProcessId(h,out p);if(p==watchedPid)TargetActivations++;};
 public static bool StartWatch(uint pid){watchedPid=pid;initialPid=ForegroundPid();TargetActivations=0;eventHook=SetWinEventHook(3,3,IntPtr.Zero,eventCallback,pid,0,0);return eventHook!=IntPtr.Zero;}
 public static uint ForegroundPid(){uint p;GetWindowThreadProcessId(GetForegroundWindow(),out p);return p;}
 public static bool IsUnwantedActivation(uint initial,uint current,int events,uint target){return initial!=target && (events>0 || current==target);}
 public static bool TookFocus(){return IsUnwantedActivation(initialPid,ForegroundPid(),TargetActivations,watchedPid);}
 public static bool EndWatch(){return eventHook==IntPtr.Zero || UnhookWinEvent(eventHook);}
 public static string Text(IntPtr h){var b=new System.Text.StringBuilder(256);GetWindowText(h,b,256);return b.ToString();}
 [DllImport("user32.dll",SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,UIntPtr w,IntPtr l,uint f,uint t,out UIntPtr r);
 public static IntPtr[] Handles(uint pid){var list=new List<IntPtr>();EnumWindows((h,p)=>{uint owner;GetWindowThreadProcessId(h,out owner);if(owner==pid){list.Add(h);EnumChildWindows(h,(c,q)=>{list.Add(c);return true;},IntPtr.Zero);}return true;},IntPtr.Zero);return list.ToArray();}
}
'@
        $before=[GHNative]::GetForegroundWindow()
        $watching=[GHNative]::StartWatch([uint32]$procs[0].Id)
        if(-not $watching){throw 'Cannot monitor GHelper activation; no action taken.'}
        function Pump-FocusEvents { [Windows.Forms.Application]::DoEvents() }
        function Assert-BackgroundFocus {
            Pump-FocusEvents
            if([GHNative]::TookFocus()){throw 'GHelper became the foreground app during the operation; stop cancelled.'}
        }
        function Find-ServiceButton { @(foreach($h in [GHNative]::Handles([uint32]$procs[0].Id)){
            if(-not [GHNative]::IsToggleCaption($h)){continue}; try {$e=[Windows.Automation.AutomationElement]::FromHandle($h);if($e.Current.AutomationId -ceq 'buttonServices'){$e}}catch{}
        }) }
        $buttons=@(Find-ServiceButton)
        if($buttons.Count -eq 0){
            $existingExtras=@([GHNative]::Handles($procs[0].Id) | Where-Object {[GHNative]::Text($_) -ceq 'Extra Settings'})
            if($existingExtras.Count){throw 'An Extra window already exists but its control is unavailable. No reopening attempted.'}
            $openers=@(foreach($h in [GHNative]::Handles($procs[0].Id)){
                if([GHNative]::Text($h) -cne 'Extra'){continue}
                try{$e=[Windows.Automation.AutomationElement]::FromHandle($h);if($e.Current.AutomationId -ceq 'buttonKeyboard'){$e}}catch{}
            })
            if($openers.Count -ne 1 -or -not $openers[0].Current.IsEnabled){throw 'Cannot identify GHelper Extra opener; no action taken.'}
            $hostBytes=[IO.File]::ReadAllBytes($exe)
            if(-not [Environment]::Is64BitProcess -or [BitConverter]::ToUInt16($hostBytes,[BitConverter]::ToInt32($hostBytes,0x3c)+4) -ne 0x8664){throw 'Background Extra hook requires x64 GHelper and x64 PowerShell.'}
            $oh=[IntPtr]$openers[0].Current.NativeWindowHandle
            $owner=0u;$thread=[GHNative]::GetWindowThreadProcessId($oh,[ref]$owner)
            if($owner -ne $procs[0].Id){throw 'Extra opener changed process; cancelled.'}
            $module=[GHNative]::LoadLibraryEx((Join-Path $PSScriptRoot 'ExtraNoActivate-v5.dll'),[IntPtr]::Zero,0x1100)
            if($module -eq [IntPtr]::Zero){throw 'Cannot load background Extra hook. No window opened.'}
            $export=[GHNative]::GetProcAddress($module,'ExtraCbtProc')
            if($export -eq [IntPtr]::Zero){throw 'Background Extra hook export missing.'}
            $returnExport=[GHNative]::GetProcAddress($module,'ExtraCallWndRetProc')
            if($returnExport -eq [IntPtr]::Zero){throw 'Background Extra return hook export missing.'}
            $returnHook=[GHNative]::SetWindowsHookEx(12,$returnExport,$module,$thread)
            if($returnHook -eq [IntPtr]::Zero){throw 'Cannot install background Extra return hook. No window opened.'}
            $hook=[GHNative]::SetWindowsHookEx(5,$export,$module,$thread)
            if($hook -eq [IntPtr]::Zero){throw 'Cannot install background Extra hook. No window opened.'}
            $opening=$true;$openResult=[UIntPtr]::Zero
            $opened=[GHNative]::SendMessageTimeout([GHNative]::GetParent($oh),0x111,[UIntPtr]([GHNative]::GetDlgCtrlID($oh) -band 0xffff),$oh,2,15000,[ref]$openResult)
            if($opened -eq [IntPtr]::Zero){throw 'Opening Extra timed out; no retry sent.'}
            $deadline=[DateTime]::UtcNow.AddSeconds(10)
            do{
                Start-Sleep -Milliseconds 200
                Pump-FocusEvents
                $extras=@([GHNative]::Handles($procs[0].Id)|Where-Object{[GHNative]::Text($_) -ceq 'Extra Settings'})
                if($extras.Count -eq 1){$ownedExtra=$extras[0]}
                $buttons=@(Find-ServiceButton)
            }while(($buttons.Count -ne 1 -or -not $buttons[0].Current.IsEnabled) -and [DateTime]::UtcNow -lt $deadline)
            Assert-BackgroundFocus
            if($ownedExtra -eq [IntPtr]::Zero -or [GHNative]::GetProp($ownedExtra,'GHServiceHelper.Extra') -eq [IntPtr]::Zero -or [GHNative]::GetProp($ownedExtra,'GHServiceHelper.CloakedBeforeShow') -eq [IntPtr]::Zero){throw 'Extra creation/cloaking handshake was not verified; no stop command sent.'}
            $cloaked=0
            if([GHNative]::DwmGetWindowAttribute($ownedExtra,14,[ref]$cloaked,4) -ne 0 -or ($cloaked -band 1) -eq 0){throw 'Windows did not confirm Extra is cloaked; no stop command sent.'}
            $out.CreationHookVerified=$true;$out.CloakedBeforeShow=$true;$out.CloakedByDwm=$true
            $out.OpenedExtraInBackground=$true
        }
        if($buttons.Count -ne 1){throw 'GHelper service control unavailable after background opening.'}
        $button=$buttons[0]
        if($button.Current.Name -cne 'Stop' -or -not $button.Current.IsEnabled){throw 'GHelper does not show an enabled Stop button. No toggle sent; reopen Extra to refresh its display.'}
        if((Get-Active).Count -eq 0){throw 'Services stopped before invocation. No toggle sent.'}
        Assert-BackgroundFocus
        $handle=[IntPtr]$button.Current.NativeWindowHandle
        if(-not [GHNative]::IsWindow($handle) -or $button.Current.ProcessId -ne $procs[0].Id){throw 'GHelper control changed. No toggle sent.'}
        $result=[UIntPtr]::Zero
        $sent=[GHNative]::SendMessageTimeout([GHNative]::GetParent($handle),0x111,[UIntPtr]([GHNative]::GetDlgCtrlID($handle) -band 0xffff),$handle,2,3000,[ref]$result)
        if($sent -eq [IntPtr]::Zero){throw 'Command delivery uncertain. Automatic enforcement must pause; no retry was sent.'}
        $deadline=[DateTime]::UtcNow.AddSeconds(60)
        do {Start-Sleep -Milliseconds 500;Pump-FocusEvents;$active=Get-Active}while(($active.Count -gt 0 -or -not $button.Current.IsEnabled) -and [DateTime]::UtcNow -lt $deadline)
        $out.Running=@($active | ForEach-Object ServiceName)
        if($active.Count -gt 0){throw 'GHelper did not stop all listed services within 60 seconds. No retry was sent.'}
        $deadline=[DateTime]::UtcNow.AddSeconds(8)
        do {Start-Sleep -Milliseconds 500;Pump-FocusEvents;$saved=Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json}while($saved.services_disabled -ne 1 -and [DateTime]::UtcNow -lt $deadline)
        $out.Preference=$saved.services_disabled
        Assert-BackgroundFocus
        if($saved.services_disabled -ne 1){throw 'Services stopped, but GHelper saved enforcement was not verified. Automatic enforcement paused.'}
        $out.Ok=$true;$out.Message='GHelper stopped its listed services and saved startup enforcement.'
    }
} catch {$out.Message=$_.Exception.Message}
finally {
    if($opening -and ('GHNative' -as [type])){
        try {
            if($ownedExtra -eq [IntPtr]::Zero){
                $extras=@([GHNative]::Handles($procs[0].Id)|Where-Object{[GHNative]::Text($_) -ceq 'Extra Settings'})
                if($extras.Count -eq 1){$ownedExtra=$extras[0]}
            }
            if($ownedExtra -ne [IntPtr]::Zero -and [GHNative]::IsWindow($ownedExtra)){
                $closed=[UIntPtr]::Zero
                if([GHNative]::SendMessageTimeout($ownedExtra,0x10,[UIntPtr]::Zero,[IntPtr]::Zero,2,3000,[ref]$closed) -eq [IntPtr]::Zero){throw 'Could not close temporary Extra window.'}
                if([GHNative]::IsWindow($ownedExtra)){throw 'Temporary Extra window was not destroyed.'}
            }
        }catch{$out.Ok=$false;$out.Message+=' Cleanup: '+$_.Exception.Message}
    }
    if($returnHook -ne [IntPtr]::Zero){$out.ReturnHookRemoved=[GHNative]::UnhookWindowsHookEx($returnHook);if(-not $out.ReturnHookRemoved){$out.Ok=$false;$out.Message+=' Could not verify return hook removal.'}}
    if($hook -ne [IntPtr]::Zero){$out.HookRemoved=[GHNative]::UnhookWindowsHookEx($hook);if(-not $out.HookRemoved){$out.Ok=$false;$out.Message+=' Could not verify hook removal.'}}
    if($module -ne [IntPtr]::Zero){$null=[GHNative]::FreeLibrary($module)}
    if($watching){
        Pump-FocusEvents
        $out.ForegroundUnchanged=($before -eq [GHNative]::GetForegroundWindow())
        $out.GHelperActivationEvents=[GHNative]::TargetActivations
        $out.GHelperTookFocus=[GHNative]::TookFocus()
        if($out.GHelperTookFocus){$out.Ok=$false;$out.Message+=' GHelper became foreground; automatic enforcement must pause.'}
        if(-not [GHNative]::EndWatch()){$out.Ok=$false;$out.Message+=' Foreground monitor cleanup failed.'}
    }
}
$out | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ResultPath -Encoding utf8



