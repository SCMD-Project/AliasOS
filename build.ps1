param(
    [ValidateSet('Debug','Release','Sanitize')]
    [string]$Config = 'Release',
    [string]$ToolchainDir = '',
    [string]$Scmdc = '',
    [string]$Scmdsim = '',
    [string]$Vcs16scmd = '',
    [switch]$NoTest,
    [switch]$Clean
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root
$Flavor = switch ($Config) { 'Release' {'release'} 'Sanitize' {'sanitize'} default {'debug'} }
$ExeSuffix = if ($env:OS -eq 'Windows_NT') { '.exe' } else { '' }

function Resolve-Tool {
    param([Parameter(Mandatory=$true)][string]$Name,[string]$Explicit='')
    if ($Explicit) {
        $p = Resolve-Path -LiteralPath $Explicit -ErrorAction SilentlyContinue
        if ($p) { return $p.Path }
        $cmd = Get-Command $Explicit -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        throw "Tool not found: $Explicit"
    }
    $candidates = @()
    if ($ToolchainDir) {
        $base = if ([IO.Path]::IsPathRooted($ToolchainDir)) { [IO.Path]::GetFullPath($ToolchainDir) } else { [IO.Path]::GetFullPath((Join-Path $Root $ToolchainDir)) }
        $candidates += (Join-Path $base "dist/$Flavor/$Name$ExeSuffix")
        $candidates += (Join-Path $base "dist/release/$Name$ExeSuffix")
        $candidates += (Join-Path $base "$Name$ExeSuffix")
    }
    foreach ($sibling in @('scmd-toolchain','SCMD','scmd')) {
        $base = Join-Path (Split-Path $Root -Parent) $sibling
        $candidates += (Join-Path $base "dist/$Flavor/$Name$ExeSuffix")
        $candidates += (Join-Path $base "dist/release/$Name$ExeSuffix")
    }
    foreach ($candidate in $candidates) { if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path } }
    $cmd = Get-Command ($Name+$ExeSuffix) -ErrorAction SilentlyContinue
    if (-not $cmd) { $cmd = Get-Command $Name -ErrorAction SilentlyContinue }
    if ($cmd) { return $cmd.Source }
    throw "Could not find $Name. Build SCMD 0.11.1 first, pass -ToolchainDir, or put it on PATH."
}
function Invoke-NativeChecked {
    param([Parameter(Mandatory=$true)][string]$Program,[Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    Write-Host ("+ {0} {1}" -f $Program,($Arguments -join ' '))
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Native command failed ($LASTEXITCODE): $Program $($Arguments -join ' ')" }
}
if ($Clean) {
    foreach ($dir in @('build','dist','src/generated')) { $p=Join-Path $Root $dir; if (Test-Path $p) { Remove-Item -Recurse -Force $p } }
}
$ScmdcPath = Resolve-Tool 'scmdc' $Scmdc
$ScmdsimPath = Resolve-Tool 'scmdsim' $Scmdsim
$Vcs16scmdPath = Resolve-Tool 'vcs16scmd' $Vcs16scmd
Write-Host "[AliasOS] scmdc:     $ScmdcPath"
Write-Host "[AliasOS] scmdsim:   $ScmdsimPath"
Write-Host "[AliasOS] vcs16scmd: $Vcs16scmdPath"

$Generated = Join-Path $Root 'src/generated'
New-Item -ItemType Directory -Force -Path $Generated | Out-Null
Get-ChildItem -LiteralPath $Generated -File -Filter '*.scmd' -ErrorAction SilentlyContinue | Remove-Item -Force
Invoke-NativeChecked -Program $Vcs16scmdPath -Arguments @((Join-Path $Root 'vcs/kernel.vcs'), '-o', (Join-Path $Generated 'kernel_vcs.scmd'), '--prefix', 'aos_kernel')
Invoke-NativeChecked -Program $Vcs16scmdPath -Arguments @((Join-Path $Root 'vcs/hello.vcs'), '-o', (Join-Path $Generated 'hello_vcs.scmd'), '--prefix', 'aos_hello')
Invoke-NativeChecked -Program $Vcs16scmdPath -Arguments @((Join-Path $Root 'vcs/sysinfo.vcs'), '-o', (Join-Path $Generated 'sysinfo_vcs.scmd'), '--prefix', 'aos_sysinfo')
Invoke-NativeChecked -Program $ScmdcPath -Arguments @('build', (Join-Path $Root 'AliasOS.scmdproj'))

$BuildAlias = Join-Path $Root 'build/aliasos'
New-Item -ItemType Directory -Force -Path $BuildAlias | Out-Null
Copy-Item -Force (Join-Path $Root 'cfg/public.cfg') (Join-Path $BuildAlias 'public.cfg')
Copy-Item -Force (Join-Path $Root 'cfg/boot_show.cfg') (Join-Path $BuildAlias 'boot_show.cfg')
Copy-Item -Force (Join-Path $Root 'cfg/AliasOS.cfg') (Join-Path $Root 'build/AliasOS.cfg')
if (-not $NoTest) { & (Join-Path $Root 'tests/run.ps1') -Scmdsim $ScmdsimPath -Build (Join-Path $Root 'build'); if ($LASTEXITCODE -ne 0) { throw 'AliasOS regression failed' } }

$Dist = Join-Path $Root 'dist/cs2'
if (Test-Path $Dist) { Remove-Item -Recurse -Force $Dist }
New-Item -ItemType Directory -Force -Path $Dist | Out-Null
Copy-Item -Force (Join-Path $Root 'build/AliasOS.cfg') $Dist
Copy-Item -Recurse -Force (Join-Path $Root 'build/aliasos') $Dist
Write-Host "`n[AliasOS] Build complete."
Write-Host "[AliasOS] Deploy directory: $Dist"
Write-Host '[AliasOS] Copy its contents to game/csgo/cfg/, then run:'
Write-Host '          sv_cheats 1'
Write-Host '          exec AliasOS'
