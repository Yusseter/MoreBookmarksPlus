param(
    [string]$RepoRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$auditCsvPath = Join-Path $RepoRoot 'Works/analysis/generated/provinces_duplicate_rgb_audit/dual_source_rgb_presence.csv'
$finalPngPath = Join-Path $RepoRoot 'map_data/provinces.png'
$modPngPath = Join-Path $RepoRoot 'Works/map_data_sources/provinces_modlu_kalan.png'
$origPngPath = Join-Path $RepoRoot 'Works/map_data_sources/provinces_orijinal_dogu.png'
$reportDir = Join-Path $RepoRoot 'Works/analysis/generated/provinces_duplicate_rgb_diagnostics'
$outCsv = Join-Path $reportDir 'dual_source_conflict_diagnostics.csv'
$outMd = Join-Path $reportDir 'dual_source_conflict_diagnostics.md'

$null = New-Item -ItemType Directory -Path $reportDir -Force

$problemRows = Import-Csv -Path $auditCsvPath |
    Where-Object { $_.live_contains_both -eq 'True' -and $_.names_differ -eq 'True' } |
    Sort-Object { [int]$_.final_new_id }

if (-not $problemRows) {
    throw 'No dual-source conflicting RGB rows found in dual_source_rgb_presence.csv'
}

Add-Type -AssemblyName System.Drawing

$csharp = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class ConflictRequest {
    public int Key;
}

public class ConflictDiagnosticsRow {
    public int Key;
    public long FinalPixels;
    public long ModPixels;
    public long OriginalPixels;
    public long BothPixels;
    public int FinalMinX = int.MaxValue;
    public int FinalMinY = int.MaxValue;
    public int FinalMaxX = -1;
    public int FinalMaxY = -1;
    public int ModMinX = int.MaxValue;
    public int ModMinY = int.MaxValue;
    public int ModMaxX = -1;
    public int ModMaxY = -1;
    public int OriginalMinX = int.MaxValue;
    public int OriginalMinY = int.MaxValue;
    public int OriginalMaxX = -1;
    public int OriginalMaxY = -1;
    public string ModSamples = "";
    public string OriginalSamples = "";

    private List<string> _modSampleList = new List<string>();
    private List<string> _origSampleList = new List<string>();

    public void TrackFinal(int x, int y) {
        if (x < FinalMinX) FinalMinX = x;
        if (y < FinalMinY) FinalMinY = y;
        if (x > FinalMaxX) FinalMaxX = x;
        if (y > FinalMaxY) FinalMaxY = y;
    }

    public void TrackMod(int x, int y) {
        if (x < ModMinX) ModMinX = x;
        if (y < ModMinY) ModMinY = y;
        if (x > ModMaxX) ModMaxX = x;
        if (y > ModMaxY) ModMaxY = y;
        if (_modSampleList.Count < 8) {
            _modSampleList.Add(x.ToString() + "," + y.ToString());
        }
    }

    public void TrackOriginal(int x, int y) {
        if (x < OriginalMinX) OriginalMinX = x;
        if (y < OriginalMinY) OriginalMinY = y;
        if (x > OriginalMaxX) OriginalMaxX = x;
        if (y > OriginalMaxY) OriginalMaxY = y;
        if (_origSampleList.Count < 8) {
            _origSampleList.Add(x.ToString() + "," + y.ToString());
        }
    }

    public void FinalizeSamples() {
        ModSamples = string.Join(" | ", _modSampleList.ToArray());
        OriginalSamples = string.Join(" | ", _origSampleList.ToArray());
        if (FinalMaxX < 0) { FinalMinX = -1; FinalMinY = -1; }
        if (ModMaxX < 0) { ModMinX = -1; ModMinY = -1; }
        if (OriginalMaxX < 0) { OriginalMinX = -1; OriginalMinY = -1; }
    }
}

public static class ConflictDiagnosticsBuilder {
    private static Bitmap LoadAs32bpp(string path) {
        using (var original = new Bitmap(path)) {
            return original.Clone(new Rectangle(0, 0, original.Width, original.Height), PixelFormat.Format32bppArgb);
        }
    }

    public static List<ConflictDiagnosticsRow> Run(string finalPath, string modPath, string originalPath, int[] keys) {
        var rows = new Dictionary<int, ConflictDiagnosticsRow>();
        foreach (var key in keys) {
            rows[key] = new ConflictDiagnosticsRow { Key = key };
        }

        using (var finalBmp = LoadAs32bpp(finalPath))
        using (var modBmp = LoadAs32bpp(modPath))
        using (var originalBmp = LoadAs32bpp(originalPath)) {
            if (finalBmp.Width != modBmp.Width || finalBmp.Width != originalBmp.Width || finalBmp.Height != modBmp.Height || finalBmp.Height != originalBmp.Height) {
                throw new InvalidOperationException("Bitmap dimensions do not match.");
            }

            var rect = new Rectangle(0, 0, finalBmp.Width, finalBmp.Height);
            var finalData = finalBmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            var modData = modBmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            var origData = originalBmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);

            try {
                var finalBytes = new byte[Math.Abs(finalData.Stride) * finalBmp.Height];
                var modBytes = new byte[Math.Abs(modData.Stride) * modBmp.Height];
                var origBytes = new byte[Math.Abs(origData.Stride) * originalBmp.Height];
                Marshal.Copy(finalData.Scan0, finalBytes, 0, finalBytes.Length);
                Marshal.Copy(modData.Scan0, modBytes, 0, modBytes.Length);
                Marshal.Copy(origData.Scan0, origBytes, 0, origBytes.Length);

                int width = finalBmp.Width;
                int stride = finalData.Stride;
                for (int y = 0; y < finalBmp.Height; y++) {
                    int rowOffset = y * stride;
                    for (int x = 0; x < width; x++) {
                        int offset = rowOffset + (x * 4);
                        int finalKey = (finalBytes[offset + 2] << 16) | (finalBytes[offset + 1] << 8) | finalBytes[offset];
                        ConflictDiagnosticsRow row;
                        if (!rows.TryGetValue(finalKey, out row)) {
                            continue;
                        }

                        row.FinalPixels++;
                        row.TrackFinal(x, y);

                        int modKey = (modBytes[offset + 2] << 16) | (modBytes[offset + 1] << 8) | modBytes[offset];
                        int origKey = (origBytes[offset + 2] << 16) | (origBytes[offset + 1] << 8) | origBytes[offset];

                        bool modMatch = modKey == finalKey && modKey != 0;
                        bool origMatch = origKey == finalKey && origKey != 0;
                        if (modMatch) {
                            row.ModPixels++;
                            row.TrackMod(x, y);
                        }
                        if (origMatch) {
                            row.OriginalPixels++;
                            row.TrackOriginal(x, y);
                        }
                        if (modMatch && origMatch) {
                            row.BothPixels++;
                        }
                    }
                }
            }
            finally {
                finalBmp.UnlockBits(finalData);
                modBmp.UnlockBits(modData);
                originalBmp.UnlockBits(origData);
            }
        }

        var list = new List<ConflictDiagnosticsRow>(rows.Values);
        foreach (var row in list) {
            row.FinalizeSamples();
        }
        return list;
    }
}
"@

Add-Type -TypeDefinition $csharp -ReferencedAssemblies System.Drawing

function Convert-RgbStringToInt {
    param([string]$Rgb)
    $parts = $Rgb -split ','
    return (([int]$parts[0] -shl 16) -bor ([int]$parts[1] -shl 8) -bor [int]$parts[2])
}

$keys = $problemRows | ForEach-Object { Convert-RgbStringToInt -Rgb $_.rgb }
$nativeRows = [ConflictDiagnosticsBuilder]::Run($finalPngPath, $modPngPath, $origPngPath, $keys)
$nativeLookup = @{}
foreach ($row in $nativeRows) {
    $nativeLookup[$row.Key] = $row
}

$outputRows = foreach ($problem in $problemRows) {
    $key = Convert-RgbStringToInt -Rgb $problem.rgb
    $native = $nativeLookup[$key]
    [pscustomobject]@{
        final_new_id            = [int]$problem.final_new_id
        effective_name          = $problem.effective_name
        rgb                     = $problem.rgb
        preferred_source_subset = $problem.preferred_source_subset
        modlu_old_id            = $problem.modlu_old_id
        modlu_old_rgb           = $problem.modlu_old_rgb
        modlu_old_name          = $problem.modlu_old_name
        orijinal_old_id         = $problem.orijinal_old_id
        orijinal_old_rgb        = $problem.orijinal_old_rgb
        orijinal_old_name       = $problem.orijinal_old_name
        final_pixels            = $native.FinalPixels
        mod_match_pixels        = $native.ModPixels
        orijinal_match_pixels   = $native.OriginalPixels
        both_match_pixels       = $native.BothPixels
        final_bbox              = if ($native.FinalMaxX -ge 0) { '{0},{1} -> {2},{3}' -f $native.FinalMinX, $native.FinalMinY, $native.FinalMaxX, $native.FinalMaxY } else { '' }
        mod_bbox                = if ($native.ModMaxX -ge 0) { '{0},{1} -> {2},{3}' -f $native.ModMinX, $native.ModMinY, $native.ModMaxX, $native.ModMaxY } else { '' }
        orijinal_bbox           = if ($native.OriginalMaxX -ge 0) { '{0},{1} -> {2},{3}' -f $native.OriginalMinX, $native.OriginalMinY, $native.OriginalMaxX, $native.OriginalMaxY } else { '' }
        mod_sample_coords       = $native.ModSamples
        orijinal_sample_coords  = $native.OriginalSamples
        names_differ            = ($problem.modlu_old_name -ne $problem.orijinal_old_name)
    }
}

$outputRows | Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8

$md = @(
    '# Dual-Source Conflict Diagnostics',
    '',
    '- Scope: only `live_contains_both = True` and `names_differ = True` rows',
    '- Final image: `map_data/provinces.png`',
    '- West source image: `Works/map_data_sources/provinces_modlu_kalan.png`',
    '- East source image: `Works/map_data_sources/provinces_orijinal_dogu.png`',
    '',
    ('- conflict rows: `{0}`' -f $outputRows.Count),
    '',
    'Rows:'
)
foreach ($row in $outputRows) {
    $md += ('- `{0}` `{1}` `{2}`: mod `{3}` px, orijinal `{4}` px, final bbox `{5}`' -f $row.final_new_id, $row.rgb, $row.effective_name, $row.mod_match_pixels, $row.orijinal_match_pixels, $row.final_bbox)
    $md += ('  mod `{0}` bbox `{1}` samples `{2}`' -f $row.modlu_old_name, $row.mod_bbox, $row.mod_sample_coords)
    $md += ('  orijinal `{0}` bbox `{1}` samples `{2}`' -f $row.orijinal_old_name, $row.orijinal_bbox, $row.orijinal_sample_coords)
}
Set-Content -Path $outMd -Value ($md -join "`r`n") -Encoding UTF8

Write-Host "Wrote $outCsv"
Write-Host "Wrote $outMd"
