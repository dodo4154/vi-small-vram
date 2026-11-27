# Launches a VIctory build at a fixed volume, for unattended runs.
# Usage:
#   powershell -ExecutionPolicy Bypass -File play.ps1 -Exe <victory.exe> -Game <game_scarlett_master.exe> `
#       [-Keys "18:Enter,28:Down,..."] [-Seconds 300] [-Log run.log] [-Extra "K=V;K2=V2"]
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][string]$Game,
    [string]$Cache = "$env:LOCALAPPDATA\vi-notes\cache",
    [string]$Data = "$env:LOCALAPPDATA\vi-notes\data",
    [string]$Log = "$PSScriptRoot\..\run.log",
    [int]$Seconds = 300,
    [string]$LogLevel = "info",
    [string]$Console = "series-x",
    [double]$Volume = 0.2,
    # Alternating Enter and Down walks the menus on a first boot; a single Enter is not enough.
    [string]$Keys = "18:Enter,26:Down,34:Enter,42:Down,50:Enter,58:Down,66:Enter,74:Down,82:Enter,90:Down,98:Enter,106:Down,114:Enter,122:Down,130:Enter,138:Down,146:Enter,154:Down,162:Enter,170:Down,178:Enter,186:Down,194:Enter",
    [string]$Extra = ""
)

$env:VICTORY_LOG = $LogLevel
$env:VICTORY_CACHE_DIR = $Cache
$env:VICTORY_DATA_DIR = $Data
foreach ($pair in ($Extra -split ";" | Where-Object { $_ })) {
    $kv = $pair -split "=", 2
    if ($kv.Count -eq 2) { Set-Item -Path "Env:$($kv[0])" -Value $kv[1] }
}
if ($Keys) { $env:VICTORY_KEYS = $Keys }
New-Item -ItemType Directory -Force $Cache, $Data | Out-Null

$p = Start-Process -FilePath $Exe -ArgumentList @("run", "`"$Game`"", "--execute", "--console", $Console) `
    -RedirectStandardOutput $Log -RedirectStandardError "$Log.err" -PassThru -WindowStyle Normal

for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 3
    if ($p.HasExited) { break }
    $r = & powershell -ExecutionPolicy Bypass -NoProfile -File "$PSScriptRoot\set-game-volume.ps1" -Process victory -Volume $Volume 2>$null
    if ($r -match "sessions set to .*: [1-9]") { Write-Output "volume set at +$((($i + 1) * 3))s"; break }
}

if (-not $p.HasExited) {
    $null = $p.WaitForExit([Math]::Max(1, $Seconds) * 1000)
    if (-not $p.HasExited) { try { $p.Kill() } catch {}; Write-Output "killed after ${Seconds}s" }
}
Write-Output ("exit code: " + $p.ExitCode)
