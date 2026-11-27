# Medians of the in-world frame lines of a run.
# Usage: powershell -ExecutionPolicy Bypass -File measure.ps1 -Log run.log
param(
    [Parameter(Mandatory = $true)][string]$Log,
    # Frames above this many ms are counted as the world (menus sit at 33 ms).
    [double]$WorldMs = 100
)
$path = if (Test-Path "$Log.err") { "$Log.err" } else { $Log }
$lines = Select-String -Path $path -Pattern 'fps, ([0-9.]+) ms/frame \(([0-9.]+) preparing: copies ([0-9.]+) ms ([0-9.]+) MB, textures ([0-9.]+) ms [0-9.]+ MB; ([0-9.]+) on the GPU; ([0-9.]+) copying back' -AllMatches |
    ForEach-Object { $_.Matches } | ForEach-Object {
        [pscustomobject]@{
            Frame = [double]$_.Groups[1].Value
            Preparing = [double]$_.Groups[2].Value
            CopiesMs = [double]$_.Groups[3].Value
            CopiesMb = [double]$_.Groups[4].Value
            TexturesMs = [double]$_.Groups[5].Value
            Gpu = [double]$_.Groups[6].Value
            BackMs = [double]$_.Groups[7].Value
        }
    }
$world = $lines | Where-Object { $_.Frame -ge $WorldMs }
if (-not $world) { Write-Output "no in-world frames (all under $WorldMs ms)"; exit 1 }

function Median($values) {
    $sorted = $values | Sort-Object
    $n = $sorted.Count
    if ($n -eq 0) { return $null }
    if ($n % 2 -eq 1) { return $sorted[[int](($n - 1) / 2)] }
    return ($sorted[$n / 2 - 1] + $sorted[$n / 2]) / 2
}

$all = $world.Frame
$tailCount = [Math]::Max(1, [int]($world.Count / 3))
$tail = $world | Select-Object -Last $tailCount

Write-Output ("in-world frames: {0}   median {1:N1} ms ({2:N2} fps)   fastest {3:N1}   slowest {4:N1}" -f `
    $world.Count, (Median $all), (1000.0 / (Median $all)), ($all | Measure-Object -Minimum).Minimum, ($all | Measure-Object -Maximum).Maximum)
Write-Output ("last third: median {0:N1} ms   preparing {1:N1} (copies {2:N1} ms {3:N0} MB, textures {4:N1})   GPU {5:N1}   copy-back {6:N1}" -f `
    (Median $tail.Frame), (Median $tail.Preparing), (Median $tail.CopiesMs), (Median $tail.CopiesMb), (Median $tail.TexturesMs), (Median $tail.Gpu), (Median $tail.BackMs))
