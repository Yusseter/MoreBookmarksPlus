param(
    [string]$RepoRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$livePath = Join-Path $RepoRoot 'map_data/provinces.png'
$sourcePath = Join-Path $RepoRoot 'Works/map_data_sources/provinces_birlesim.png'
$reportDir = Join-Path $RepoRoot 'Works/analysis/generated/provinces_live_vs_source'
$outSummary = Join-Path $reportDir 'provinces_live_vs_source_summary.md'
$outTopChanges = Join-Path $reportDir 'provinces_live_vs_source_top_changes.csv'

$null = New-Item -ItemType Directory -Path $reportDir -Force

Add-Type -AssemblyName System.Drawing

$csharp = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class ChangeStat {
    public int FromKey;
    public int ToKey;
    public long Count;
}

public class BitmapComparisonResult {
    public long ChangedPixels;
    public int MinX = int.MaxValue;
    public int MinY = int.MaxValue;
    public int MaxX = -1;
    public int MaxY = -1;
    public string Samples = "";
    public List<ChangeStat> TopChanges = new List<ChangeStat>();
}

public static class ProvinceBitmapComparer {
    private static Bitmap LoadAs32bpp(string path) {
        using (var original = new Bitmap(path)) {
            return original.Clone(new Rectangle(0, 0, original.Width, original.Height), PixelFormat.Format32bppArgb);
        }
    }

    public static BitmapComparisonResult Compare(string sourcePath, string livePath) {
        var result = new BitmapComparisonResult();
        var sampleList = new List<string>();
        var changeMap = new Dictionary<long, ChangeStat>();

        using (var sourceBmp = LoadAs32bpp(sourcePath))
        using (var liveBmp = LoadAs32bpp(livePath)) {
            if (sourceBmp.Width != liveBmp.Width || sourceBmp.Height != liveBmp.Height) {
                throw new InvalidOperationException("Bitmap dimensions do not match.");
            }

            var rect = new Rectangle(0, 0, sourceBmp.Width, sourceBmp.Height);
            var sourceData = sourceBmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            var liveData = liveBmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);

            try {
                var sourceBytes = new byte[Math.Abs(sourceData.Stride) * sourceBmp.Height];
                var liveBytes = new byte[Math.Abs(liveData.Stride) * liveBmp.Height];
                Marshal.Copy(sourceData.Scan0, sourceBytes, 0, sourceBytes.Length);
                Marshal.Copy(liveData.Scan0, liveBytes, 0, liveBytes.Length);

                int width = sourceBmp.Width;
                int stride = sourceData.Stride;
                for (int y = 0; y < sourceBmp.Height; y++) {
                    int rowOffset = y * stride;
                    for (int x = 0; x < width; x++) {
                        int offset = rowOffset + (x * 4);
                        int sourceKey = (sourceBytes[offset + 2] << 16) | (sourceBytes[offset + 1] << 8) | sourceBytes[offset];
                        int liveKey = (liveBytes[offset + 2] << 16) | (liveBytes[offset + 1] << 8) | liveBytes[offset];
                        if (sourceKey == liveKey) {
                            continue;
                        }

                        result.ChangedPixels++;
                        if (x < result.MinX) result.MinX = x;
                        if (y < result.MinY) result.MinY = y;
                        if (x > result.MaxX) result.MaxX = x;
                        if (y > result.MaxY) result.MaxY = y;

                        if (sampleList.Count < 16) {
                            sampleList.Add(x.ToString() + "," + y.ToString() + ":" + sourceKey.ToString() + "->" + liveKey.ToString());
                        }

                        long packed = ((long)sourceKey << 24) ^ (long)liveKey;
                        ChangeStat stat;
                        if (!changeMap.TryGetValue(packed, out stat)) {
                            stat = new ChangeStat { FromKey = sourceKey, ToKey = liveKey, Count = 0 };
                            changeMap[packed] = stat;
                        }
                        stat.Count++;
                    }
                }
            }
            finally {
                sourceBmp.UnlockBits(sourceData);
                liveBmp.UnlockBits(liveData);
            }
        }

        result.Samples = string.Join(" | ", sampleList.ToArray());
        if (result.MaxX < 0) {
            result.MinX = -1;
            result.MinY = -1;
        }

        var top = new List<ChangeStat>(changeMap.Values);
        top.Sort((a, b) => b.Count.CompareTo(a.Count));
        if (top.Count > 40) {
            top = top.GetRange(0, 40);
        }
        result.TopChanges = top;
        return result;
    }
}
"@

Add-Type -TypeDefinition $csharp -ReferencedAssemblies System.Drawing

function Convert-KeyToRgb {
    param([int]$Key)
    $r = ($Key -shr 16) -band 255
    $g = ($Key -shr 8) -band 255
    $b = $Key -band 255
    return '{0},{1},{2}' -f $r, $g, $b
}

$result = [ProvinceBitmapComparer]::Compare($sourcePath, $livePath)

$topChangeRows = foreach ($change in $result.TopChanges) {
    [pscustomobject]@{
        source_rgb = Convert-KeyToRgb -Key $change.FromKey
        live_rgb   = Convert-KeyToRgb -Key $change.ToKey
        pixel_count = $change.Count
    }
}

$topChangeRows | Export-Csv -Path $outTopChanges -NoTypeInformation -Encoding UTF8

$summaryLines = @(
    '# Live vs Source provinces.png Comparison',
    '',
    '- source image: `Works/map_data_sources/provinces_birlesim.png`',
    '- live image: `map_data/provinces.png`',
    '',
    ('- changed pixels: `{0}`' -f $result.ChangedPixels),
    ('- changed bbox: `{0},{1} -> {2},{3}`' -f $result.MinX, $result.MinY, $result.MaxX, $result.MaxY),
    ('- sample changes: `{0}`' -f $result.Samples),
    '',
    'Top color substitutions are in `provinces_live_vs_source_top_changes.csv`.'
)

Set-Content -Path $outSummary -Value ($summaryLines -join "`r`n") -Encoding UTF8

Write-Host "Wrote $outSummary"
Write-Host "Wrote $outTopChanges"
