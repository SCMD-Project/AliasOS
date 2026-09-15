param(
    [Parameter(Mandatory=$true)][string]$Scmdsim,
    [string]$Build = ''
)
$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $Utf8NoBom
$OutputEncoding = $Utf8NoBom
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $Build) { $Build = Join-Path $Root 'build' }

$Cases = [ordered]@{
    'demo.script' = @('AliasOS 0.1-dev','bin/','root@alias:$','cwd:','home/','hello','world','file created','write mode: enter line tokens, then end to save','saved','line1','line2','AliasFS inodes: 6/16','PID STATE APP','[counter] done','hello from vCS-16/2 userland')
    'fs_mutation.script' = @('directory created','file created','saved','directory not empty','removed','not found')
    'argv_controls.script' = @('args:','cancelled','not found','> line1')
    'real_ui.script' = @('cwd:','bin/','sh','taskkill','/','AliasOS command guide:')
    'path_v2.script' = @('directory created','cwd:','home/','project/','docs/','file created','saved','line1','line2','removed','vCS-16/2 + SCMD alias runtime','AliasFS capacity: 16 inodes, 1024 token cells')
    'raw_alias.script' = @('raw alias slot:','aos_str_1','raw alias ready - type end to commit','saved','这是运行时才输入的字符串','CS2里真的写进去了')
    'raw_alias_transaction.script' = @('OLD_RAW_CONTENT','cancelled','NEW_RAW_CONTENT')
    'raw_alias_missing.script' = @('raw alias not ready - define the shown slot and run rawready before end','cancelled')
    'raw_alias_guard.script' = @('raw alias not ready - define the shown slot and run rawready before end','cancelled','114514,hello world!')
    'raw_history.script' = @('OLD_IMMUTABLE_RAW','NEW_FILE_CONTENT','removed')
    'sysinfo.script' = @('$ sysinfo','AliasOS system information:','AliasOS 0.1-dev','vCS-16/2: flags-free CFG-oriented virtual execution architecture','raw strings: 32 immutable runtime objects','AliasFS inodes: 5/16','PID STATE APP','1 RUNNING sh')
    'raw_gc.script' = @('aos_str_1')
}

function Get-LastScreen([string]$Text) {
    $parts = $Text -split "(?m)^\[screen\]\r?$"
    if ($parts.Count -le 1) { return $Text }
    return $parts[-1]
}

foreach ($entry in $Cases.GetEnumerator()) {
    $script = $entry.Key
    $scriptPath = Join-Path $Root "tests/$script"
    Write-Host "+ $Scmdsim $Build --exec AliasOS --script $scriptPath --no-interactive --no-ansi"
    $output = & $Scmdsim $Build --exec AliasOS --script $scriptPath --no-interactive --no-ansi 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "$script failed ($LASTEXITCODE)`n$output" }
    foreach ($needle in $entry.Value) {
        if (-not $output.Contains($needle)) { throw "$script missing expected output '$needle'`n$output" }
    }
    if ($output.Contains('Unknown command')) { throw "$script hit an unresolved command (stale cfg-to-function reference?)`n$output" }

    $screens = $output -split "(?m)^\[screen\]\r?$"
    if ($screens.Count -gt 1) {
        foreach ($screen in $screens[1..($screens.Count-1)]) {
            $visible = ($screen -split "`r?`n" | Select-Object -First 25)
            foreach ($line in $visible) {
                if ($line.ToLowerInvariant().Contains('[inputservice]') -and $line.ToLowerInvariant().Contains('aliasos/')) {
                    throw "$script leaked AliasOS InputService noise into visible screen: $line"
                }
                if ($line.StartsWith('[Console]')) { throw "$script leaked Source echo/[Console] output: $line" }
            }
        }
    }

    if ($script -eq 'raw_alias_transaction.script') {
        $cancel = $output.IndexOf('cancelled')
        $old = if ($cancel -ge 0) { $output.IndexOf('OLD_RAW_CONTENT',$cancel) } else { -1 }
        $new = if ($cancel -ge 0) { $output.IndexOf('NEW_RAW_CONTENT',$cancel) } else { -1 }
        if ($cancel -lt 0 -or $old -lt 0 -or ($new -ge 0 -and $new -lt $old)) { throw 'raw alias transaction did not preserve old committed content across cancel' }
    }
    if ($script -eq 'raw_history.script') {
        $final = Get-LastScreen $output
        if (-not $final.Contains('OLD_IMMUTABLE_RAW') -or -not $final.Contains('NEW_FILE_CONTENT')) { throw 'immutable raw TTY history did not survive rewrite/removal' }
    }
    if ($script -eq 'raw_gc.script') {
        $final = Get-LastScreen $output
        if (-not $final.Contains('aos_str_1')) { throw 'raw string object was not reclaimed after file removal + cls' }
    }
    Write-Host "PASS $script"
}
Write-Host "AliasOS standalone regression: $($Cases.Count)/$($Cases.Count) PASS"
