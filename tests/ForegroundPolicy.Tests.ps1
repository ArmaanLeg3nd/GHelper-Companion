#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$worker=Get-Content -LiteralPath (Join-Path $root 'runtime\Worker.ps1') -Raw
$match=[regex]::Match($worker,"(?s)Add-Type @'\r?\n(?<code>.*?)\r?\n'@")
if(-not $match.Success){throw 'Native helper definition was not found'}
Add-Type -TypeDefinition $match.Groups['code'].Value
$cases=@(
    @{Name='same non-target app';Initial=10;Current=10;Events=0;Target=20;Expected=$false},
    @{Name='user switched to another app';Initial=10;Current=30;Events=0;Target=20;Expected=$false},
    @{Name='target remains foreground';Initial=10;Current=20;Events=0;Target=20;Expected=$true},
    @{Name='transient target activation';Initial=10;Current=30;Events=1;Target=20;Expected=$true},
    @{Name='target already foreground';Initial=20;Current=20;Events=1;Target=20;Expected=$false}
)
foreach($case in $cases){
    $actual=[GHNative]::IsUnwantedActivation($case.Initial,$case.Current,$case.Events,$case.Target)
    if($actual -ne $case.Expected){throw "Foreground policy regression: $($case.Name)"}
}
"PASS: $($cases.Count) foreground policy cases; no windows or services changed."
