param(
    [string]$RepoRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$reportDir = Join-Path $RepoRoot 'Works/analysis/generated/provinces_duplicate_rgb_repair'
$null = New-Item -ItemType Directory -Path $reportDir -Force

$auditCsvPath = Join-Path $RepoRoot 'Works/analysis/generated/provinces_duplicate_rgb_audit/dual_source_rgb_presence.csv'
$placeholderInventoryPath = Join-Path $RepoRoot 'Works/analysis/generated/final_placeholder_inventory_preserve_old_ids.csv'
$placeholderPixelMapPath = Join-Path $RepoRoot 'Works/analysis/generated/placeholder_pixel_map_preserve_old.csv'
$finalPngPath = Join-Path $RepoRoot 'map_data/provinces.png'
$testPngPath = Join-Path $RepoRoot 'test_files/map_data/provinces.png'
$modPngPath = Join-Path $RepoRoot 'Works/map_data_sources/provinces_modlu_kalan.png'
$origPngPath = Join-Path $RepoRoot 'Works/map_data_sources/provinces_orijinal_dogu.png'
$definitionPath = Join-Path $RepoRoot 'map_data/definition.csv'
$testDefinitionPath = Join-Path $RepoRoot 'test_files/map_data/definition.csv'

$backupFinalPng = Join-Path $reportDir 'provinces_before_dual_source_split.png'
$backupDefinition = Join-Path $reportDir 'definition_before_dual_source_split.csv'
Copy-Item -Path $finalPngPath -Destination $backupFinalPng -Force
Copy-Item -Path $definitionPath -Destination $backupDefinition -Force

$problemRows = Import-Csv -Path $auditCsvPath |
    Where-Object { $_.live_contains_both -eq 'True' -and $_.names_differ -eq 'True' } |
    Sort-Object { [int]$_.final_new_id }

if (-not $problemRows) {
    throw 'No dual-source duplicate RGB rows requiring repair were found.'
}

$placeholderRows = Import-Csv -Path $placeholderInventoryPath |
    Sort-Object { [int]$_.final_new_id } |
    Select-Object -First $problemRows.Count

if ($placeholderRows.Count -lt $problemRows.Count) {
    throw "Not enough placeholder rows to repair $($problemRows.Count) dual-source duplicates."
}

$placeholderPixelRows = Import-Csv -Path $placeholderPixelMapPath
$placeholderPixelMap = @{}
foreach ($row in $placeholderPixelRows) {
    $placeholderPixelMap[[int]$row.final_new_id] = $row
}

$assignments = New-Object 'System.Collections.Generic.List[object]'
for ($i = 0; $i -lt $problemRows.Count; $i++) {
    $problem = $problemRows[$i]
    $placeholder = $placeholderRows[$i]
    $placeholderId = [int]$placeholder.final_new_id
    if (-not $placeholderPixelMap.ContainsKey($placeholderId)) {
        throw "Missing placeholder pixel coordinates for $placeholderId"
    }
    $pixel = $placeholderPixelMap[$placeholderId]
    $sourceName = $problem.orijinal_old_name
    if ([string]::IsNullOrWhiteSpace($sourceName)) {
        $sourceName = "split_orijinal_$($problem.orijinal_old_id)"
    }

    $assignments.Add([pscustomobject]@{
        kept_final_id           = [int]$problem.final_new_id
        kept_rgb                = $problem.rgb
        kept_name               = $problem.effective_name
        preferred_source_subset = $problem.preferred_source_subset
        modlu_old_id            = $problem.modlu_old_id
        modlu_old_rgb           = $problem.modlu_old_rgb
        modlu_old_name          = $problem.modlu_old_name
        orijinal_old_id         = $problem.orijinal_old_id
        orijinal_old_rgb        = $problem.orijinal_old_rgb
        orijinal_old_name       = $problem.orijinal_old_name
        new_final_id            = $placeholderId
        new_rgb                 = $placeholder.placeholder_rgb
        new_name                = $sourceName
        placeholder_pixel_x     = [int]$pixel.x
        placeholder_pixel_y     = [int]$pixel.y
        changed_pixels          = 0
        cleared_placeholder     = 0
    }) | Out-Null
}

Add-Type -AssemblyName System.Drawing

$source = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class SplitAssignment {
    public int KeptKey;
    public int NewKey;
    public int PlaceholderX;
    public int PlaceholderY;
    public long ChangedPixels;
    public long ClearedPlaceholderPixels;
}

public static class ProvinceDuplicateRepair {
    private static Bitmap LoadAs32bpp(string path) {
        using (var original = new Bitmap(path)) {
            var clone = new Bitmap(original.Width, original.Height, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(clone)) {
                g.DrawImageUnscaled(original, 0, 0);
            }
            return clone;
        }
    }

    public static void Apply(string finalPath, string modPath, string originalPath, string outputPath, SplitAssignment[] assignments) {
        var assignmentMap = new Dictionary<int, SplitAssignment>();
        foreach (var assignment in assignments) {
            assignmentMap[assignment.KeptKey] = assignment;
            assignment.ChangedPixels = 0;
            assignment.ClearedPlaceholderPixels = 0;
        }

        using (var finalBmp = LoadAs32bpp(finalPath))
        using (var modBmp = LoadAs32bpp(modPath))
        using (var originalBmp = LoadAs32bpp(originalPath)) {
            var rect = new Rectangle(0, 0, finalBmp.Width, finalBmp.Height);
            var finalData = finalBmp.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            var modData = modBmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            var originalData = originalBmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);

            try {
                var finalBytes = new byte[Math.Abs(finalData.Stride) * finalBmp.Height];
                var modBytes = new byte[Math.Abs(modData.Stride) * modBmp.Height];
                var origBytes = new byte[Math.Abs(originalData.Stride) * originalBmp.Height];
                Marshal.Copy(finalData.Scan0, finalBytes, 0, finalBytes.Length);
                Marshal.Copy(modData.Scan0, modBytes, 0, modBytes.Length);
                Marshal.Copy(originalData.Scan0, origBytes, 0, origBytes.Length);

                for (int i = 0; i < finalBytes.Length; i += 4) {
                    int finalKey = (finalBytes[i + 2] << 16) | (finalBytes[i + 1] << 8) | finalBytes[i];
                    SplitAssignment assignment;
                    if (!assignmentMap.TryGetValue(finalKey, out assignment)) {
                        continue;
                    }

                    int modKey = (modBytes[i + 2] << 16) | (modBytes[i + 1] << 8) | modBytes[i];
                    int origKey = (origBytes[i + 2] << 16) | (origBytes[i + 1] << 8) | origBytes[i];
                    if (origKey == finalKey && modKey != finalKey) {
                        finalBytes[i] = (byte)(assignment.NewKey & 255);
                        finalBytes[i + 1] = (byte)((assignment.NewKey >> 8) & 255);
                        finalBytes[i + 2] = (byte)((assignment.NewKey >> 16) & 255);
                        assignment.ChangedPixels++;
                    }
                }

                foreach (var assignment in assignments) {
                    int offset = (assignment.PlaceholderY * finalData.Stride) + (assignment.PlaceholderX * 4);
                    if (offset >= 0 && offset + 2 < finalBytes.Length) {
                        finalBytes[offset] = 0;
                        finalBytes[offset + 1] = 0;
                        finalBytes[offset + 2] = 0;
                        assignment.ClearedPlaceholderPixels = 1;
                    }
                }

                Marshal.Copy(finalBytes, 0, finalData.Scan0, finalBytes.Length);
            }
            finally {
                finalBmp.UnlockBits(finalData);
                modBmp.UnlockBits(modData);
                originalBmp.UnlockBits(originalData);
            }

            finalBmp.Save(outputPath, ImageFormat.Png);
        }
    }
}
"@

Add-Type -TypeDefinition $source -ReferencedAssemblies System.Drawing

function Convert-RgbStringToInt {
    param([string]$Rgb)
    $parts = $Rgb -split ','
    return (([int]$parts[0] -shl 16) -bor ([int]$parts[1] -shl 8) -bor [int]$parts[2])
}

$nativeAssignments = @()
foreach ($assignment in $assignments) {
    $native = New-Object SplitAssignment
    $native.KeptKey = Convert-RgbStringToInt -Rgb $assignment.kept_rgb
    $native.NewKey = Convert-RgbStringToInt -Rgb $assignment.new_rgb
    $native.PlaceholderX = [int]$assignment.placeholder_pixel_x
    $native.PlaceholderY = [int]$assignment.placeholder_pixel_y
    $nativeAssignments += $native
}

$tempOutput = Join-Path $reportDir 'provinces_after_dual_source_split.png'
[ProvinceDuplicateRepair]::Apply($finalPngPath, $modPngPath, $origPngPath, $tempOutput, $nativeAssignments)
Copy-Item -Path $tempOutput -Destination $finalPngPath -Force
Copy-Item -Path $tempOutput -Destination $testPngPath -Force

for ($i = 0; $i -lt $assignments.Count; $i++) {
    $assignments[$i].changed_pixels = $nativeAssignments[$i].ChangedPixels
    $assignments[$i].cleared_placeholder = $nativeAssignments[$i].ClearedPlaceholderPixels
}

function Update-DefinitionFile {
    param(
        [string]$Path,
        [System.Collections.Generic.List[object]]$RepairAssignments
    )
    $lines = Get-Content -Path $Path -Encoding UTF8
    $map = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(\d+);') {
            $map[[int]$matches[1]] = $i
        }
    }

    foreach ($assignment in $RepairAssignments) {
        $newRgbParts = $assignment.new_rgb -split ','
        $newLine = '{0};{1};{2};{3};{4};x;' -f $assignment.new_final_id, $newRgbParts[0], $newRgbParts[1], $newRgbParts[2], $assignment.new_name
        if (-not $map.ContainsKey([int]$assignment.new_final_id)) {
            throw "Could not find definition row for placeholder ID $($assignment.new_final_id) in $Path"
        }
        $lines[$map[[int]$assignment.new_final_id]] = $newLine
    }

    Set-Content -Path $Path -Value ($lines -join "`r`n") -Encoding UTF8
}

Update-DefinitionFile -Path $definitionPath -RepairAssignments $assignments
Update-DefinitionFile -Path $testDefinitionPath -RepairAssignments $assignments

$assignmentCsv = Join-Path $reportDir 'dual_source_duplicate_repair_assignments.csv'
$assignments | Export-Csv -Path $assignmentCsv -NoTypeInformation -Encoding UTF8

$summaryMd = Join-Path $reportDir 'dual_source_duplicate_repair_summary.md'
$summaryLines = @(
    '# Dual-Source Duplicate Province Repair Summary',
    '',
    ('- repaired rows: `{0}`' -f $assignments.Count),
    ('- live provinces backup: `{0}`' -f $backupFinalPng),
    ('- live definition backup: `{0}`' -f $backupDefinition),
    '',
    'Assignments:'
)
foreach ($assignment in $assignments) {
    $summaryLines += ('- kept `{0}` `{1}` / split original `{2}` `{3}` -> new final id `{4}`, new rgb `{5}`, changed pixels `{6}`' -f $assignment.kept_final_id, $assignment.kept_name, $assignment.orijinal_old_id, $assignment.new_name, $assignment.new_final_id, $assignment.new_rgb, $assignment.changed_pixels)
}
Set-Content -Path $summaryMd -Value ($summaryLines -join "`r`n") -Encoding UTF8

Write-Host "Wrote $assignmentCsv"
Write-Host "Wrote $summaryMd"
