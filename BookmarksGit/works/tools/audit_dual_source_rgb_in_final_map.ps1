param(
    [string]$RepoRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$reportDir = Join-Path $RepoRoot 'Works/analysis/generated/provinces_duplicate_rgb_audit'
$null = New-Item -ItemType Directory -Path $reportDir -Force

$masterPath = Join-Path $RepoRoot 'Works/analysis/generated/final_master_preserve_old_ids.csv'
$finalPngPath = Join-Path $RepoRoot 'map_data/provinces.png'
$modPngPath = Join-Path $RepoRoot 'Works/map_data_sources/provinces_modlu_kalan.png'
$origPngPath = Join-Path $RepoRoot 'Works/map_data_sources/provinces_orijinal_dogu.png'
$outCsv = Join-Path $reportDir 'dual_source_rgb_presence.csv'
$outMd = Join-Path $reportDir 'dual_source_rgb_presence.md'

$targetRows = Import-Csv -Path $masterPath | Where-Object { $_.source_origin -eq 'both' -and $_.row_type -eq 'candidate' }
if (-not $targetRows) {
    throw 'No source_origin=both candidate rows found in final_master_preserve_old_ids.csv'
}

$targetMap = @{}
foreach ($row in $targetRows) {
    $targetMap[$row.effective_rgb] = $row
}
$targetRgbs = @($targetMap.Keys | Sort-Object)

Add-Type -AssemblyName System.Drawing

$source = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public class DualSourceRgbAuditRow {
    public int Key;
    public long FinalPixels;
    public long ModMatchPixels;
    public long OriginalMatchPixels;
}

public static class DualSourceRgbAudit {
    private static Bitmap LoadAs32bpp(string path) {
        using (var original = new Bitmap(path)) {
            return original.Clone(new Rectangle(0, 0, original.Width, original.Height), PixelFormat.Format32bppArgb);
        }
    }

    public static List<DualSourceRgbAuditRow> Run(string finalPath, string modPath, string originalPath, int[] keys) {
        var rows = new Dictionary<int, DualSourceRgbAuditRow>();
        foreach (var key in keys) {
            rows[key] = new DualSourceRgbAuditRow { Key = key, FinalPixels = 0, ModMatchPixels = 0, OriginalMatchPixels = 0 };
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

                for (int i = 0; i < finalBytes.Length; i += 4) {
                    int finalKey = (finalBytes[i + 2] << 16) | (finalBytes[i + 1] << 8) | finalBytes[i];
                    DualSourceRgbAuditRow row;
                    if (!rows.TryGetValue(finalKey, out row)) {
                        continue;
                    }

                    row.FinalPixels++;
                    int modKey = (modBytes[i + 2] << 16) | (modBytes[i + 1] << 8) | modBytes[i];
                    int origKey = (origBytes[i + 2] << 16) | (origBytes[i + 1] << 8) | origBytes[i];

                    if (modKey == finalKey && modKey != 0) {
                        row.ModMatchPixels++;
                    }
                    if (origKey == finalKey && origKey != 0) {
                        row.OriginalMatchPixels++;
                    }
                }
            }
            finally {
                finalBmp.UnlockBits(finalData);
                modBmp.UnlockBits(modData);
                originalBmp.UnlockBits(origData);
            }
        }

        return new List<DualSourceRgbAuditRow>(rows.Values);
    }
}
"@

Add-Type -TypeDefinition $source -ReferencedAssemblies System.Drawing

$keys = $targetRgbs | ForEach-Object {
    $parts = $_ -split ','
    ([int]$parts[0] -shl 16) -bor ([int]$parts[1] -shl 8) -bor [int]$parts[2]
}

$auditRows = [DualSourceRgbAudit]::Run($finalPngPath, $modPngPath, $origPngPath, $keys)

$outputRows = foreach ($auditRow in $auditRows | Sort-Object Key) {
    $r = ($auditRow.Key -shr 16) -band 255
    $g = ($auditRow.Key -shr 8) -band 255
    $b = $auditRow.Key -band 255
    $rgb = '{0},{1},{2}' -f $r, $g, $b
    $meta = $targetMap[$rgb]
    [pscustomobject]@{
        final_new_id            = [int]$meta.final_new_id
        effective_name          = $meta.effective_name
        rgb                     = $rgb
        source_origin           = $meta.source_origin
        preferred_source_subset = $meta.preferred_source_subset
        modlu_old_id            = $meta.modlu_old_id
        modlu_old_rgb           = $meta.modlu_old_rgb
        modlu_old_name          = $meta.modlu_old_name
        orijinal_old_id         = $meta.orijinal_old_id
        orijinal_old_rgb        = $meta.orijinal_old_rgb
        orijinal_old_name       = $meta.orijinal_old_name
        primary_status          = $meta.primary_status
        rgb_resolution_status   = $meta.rgb_resolution_status
        final_pixels            = $auditRow.FinalPixels
        mod_match_pixels        = $auditRow.ModMatchPixels
        orijinal_match_pixels   = $auditRow.OriginalMatchPixels
        live_contains_both      = ($auditRow.ModMatchPixels -gt 0 -and $auditRow.OriginalMatchPixels -gt 0)
        names_differ            = ($meta.modlu_old_name -ne $meta.orijinal_old_name)
    }
}

$outputRows | Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8

$bothLive = @($outputRows | Where-Object { $_.live_contains_both })
$bothLiveNameDiff = @($bothLive | Where-Object { $_.names_differ })

$md = @(
    '# Dual-Source RGB Presence Audit',
    '',
    '- Target set: `source_origin=both` rows from `final_master_preserve_old_ids.csv`',
    '- final image: `map_data/provinces.png`',
    '- west source: `Works/map_data_sources/provinces_modlu_kalan.png`',
    '- east source: `Works/map_data_sources/provinces_orijinal_dogu.png`',
    '',
    ('- total audited RGB rows: `{0}`' -f $outputRows.Count),
    ('- live RGBs with pixels coming from both sources: `{0}`' -f $bothLive.Count),
    ('- live RGBs with both-source pixels and different source names: `{0}`' -f $bothLiveNameDiff.Count),
    '',
    'Rows with both-source live pixels and different source names:'
)
foreach ($row in $bothLiveNameDiff) {
    $md += ('- `{0}` `{1}` -> mod `{2}` / orijinal `{3}` (mod pixels `{4}`, orijinal pixels `{5}`)' -f $row.final_new_id, $row.rgb, $row.modlu_old_name, $row.orijinal_old_name, $row.mod_match_pixels, $row.orijinal_match_pixels)
}
Set-Content -Path $outMd -Value ($md -join "`r`n") -Encoding UTF8

Write-Host "Wrote $outCsv"
Write-Host "Wrote $outMd"
