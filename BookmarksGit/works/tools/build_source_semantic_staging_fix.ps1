[CmdletBinding()]
param(
    [string]$RepoRoot = '.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -ReferencedAssemblies 'System.Drawing.dll' -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public sealed class RegionApplyStat {
    public int MappingIndex;
    public string Role;
    public string SourceSubset;
    public int MaskRgb;
    public int TargetRgb;
    public int TargetSubsetPixels;
    public int ChangedPixels;
}

public sealed class PixelApplyStat {
    public int MappingIndex;
    public int X;
    public int Y;
    public int TargetRgb;
    public bool Changed;
}

public static class SourceSemanticStagingMapper {
    public static object[] Apply(
        string basePath,
        string modPath,
        string oriPath,
        string outputPath,
        string[] regionSpecs,
        string[] pixelSpecs
    ) {
        var modMap = new Dictionary<int, List<RegionApplyStat>>();
        var oriMap = new Dictionary<int, List<RegionApplyStat>>();
        var regionStats = new List<RegionApplyStat>();
        var pixelStats = new List<PixelApplyStat>();

        foreach (var spec in regionSpecs) {
            var parts = spec.Split('|');
            if (parts.Length < 5) {
                continue;
            }

            var stat = new RegionApplyStat();
            stat.MappingIndex = int.Parse(parts[0]);
            stat.Role = parts[1];
            stat.SourceSubset = parts[2];
            stat.MaskRgb = int.Parse(parts[3]);
            stat.TargetRgb = int.Parse(parts[4]);
            regionStats.Add(stat);

            var targetMap = string.Equals(stat.SourceSubset, "modlu_kalan", StringComparison.OrdinalIgnoreCase) ? modMap : oriMap;
            List<RegionApplyStat> bucket;
            if (!targetMap.TryGetValue(stat.MaskRgb, out bucket)) {
                bucket = new List<RegionApplyStat>();
                targetMap[stat.MaskRgb] = bucket;
            }
            bucket.Add(stat);
        }

        var pixelOps = new List<Tuple<int, int, int, int>>();
        foreach (var spec in pixelSpecs) {
            var parts = spec.Split('|');
            if (parts.Length < 4) {
                continue;
            }
            pixelOps.Add(Tuple.Create(
                int.Parse(parts[0]),
                int.Parse(parts[1]),
                int.Parse(parts[2]),
                int.Parse(parts[3])
            ));
        }

        using (var baseBmp = new Bitmap(basePath))
        using (var modBmp = new Bitmap(modPath))
        using (var oriBmp = new Bitmap(oriPath))
        using (var outBmp = new Bitmap(baseBmp)) {
            if (baseBmp.Width != modBmp.Width || baseBmp.Height != modBmp.Height ||
                baseBmp.Width != oriBmp.Width || baseBmp.Height != oriBmp.Height) {
                throw new InvalidOperationException("Input images must have identical dimensions.");
            }

            var rect = new Rectangle(0, 0, outBmp.Width, outBmp.Height);
            var outData = outBmp.LockBits(rect, ImageLockMode.ReadWrite, outBmp.PixelFormat);
            var modData = modBmp.LockBits(rect, ImageLockMode.ReadOnly, modBmp.PixelFormat);
            var oriData = oriBmp.LockBits(rect, ImageLockMode.ReadOnly, oriBmp.PixelFormat);

            try {
                int outBpp = Image.GetPixelFormatSize(outData.PixelFormat) / 8;
                int modBpp = Image.GetPixelFormatSize(modData.PixelFormat) / 8;
                int oriBpp = Image.GetPixelFormatSize(oriData.PixelFormat) / 8;

                if (outBpp < 3 || modBpp < 3 || oriBpp < 3) {
                    throw new InvalidOperationException("Expected image formats with at least 24 bits per pixel.");
                }

                byte[] outBuffer = new byte[outData.Stride * outBmp.Height];
                byte[] modBuffer = new byte[modData.Stride * modBmp.Height];
                byte[] oriBuffer = new byte[oriData.Stride * oriBmp.Height];

                Marshal.Copy(outData.Scan0, outBuffer, 0, outBuffer.Length);
                Marshal.Copy(modData.Scan0, modBuffer, 0, modBuffer.Length);
                Marshal.Copy(oriData.Scan0, oriBuffer, 0, oriBuffer.Length);

                for (int y = 0; y < outBmp.Height; y++) {
                    int outRow = y * outData.Stride;
                    int modRow = y * modData.Stride;
                    int oriRow = y * oriData.Stride;

                    for (int x = 0; x < outBmp.Width; x++) {
                        int outIdx = outRow + x * outBpp;
                        int modIdx = modRow + x * modBpp;
                        int oriIdx = oriRow + x * oriBpp;

                        int modKey = (modBuffer[modIdx + 2] << 16) | (modBuffer[modIdx + 1] << 8) | modBuffer[modIdx];
                        int oriKey = (oriBuffer[oriIdx + 2] << 16) | (oriBuffer[oriIdx + 1] << 8) | oriBuffer[oriIdx];

                        List<RegionApplyStat> statsToApply;
                        if (modKey != 0 && modMap.TryGetValue(modKey, out statsToApply)) {
                            foreach (var stat in statsToApply) {
                                stat.TargetSubsetPixels += 1;
                                int currentKey = (outBuffer[outIdx + 2] << 16) | (outBuffer[outIdx + 1] << 8) | outBuffer[outIdx];
                                if (currentKey != stat.TargetRgb) {
                                    outBuffer[outIdx] = (byte)(stat.TargetRgb & 255);
                                    outBuffer[outIdx + 1] = (byte)((stat.TargetRgb >> 8) & 255);
                                    outBuffer[outIdx + 2] = (byte)((stat.TargetRgb >> 16) & 255);
                                    stat.ChangedPixels += 1;
                                }
                            }
                        }

                        if (oriKey != 0 && oriMap.TryGetValue(oriKey, out statsToApply)) {
                            foreach (var stat in statsToApply) {
                                stat.TargetSubsetPixels += 1;
                                int currentKey = (outBuffer[outIdx + 2] << 16) | (outBuffer[outIdx + 1] << 8) | outBuffer[outIdx];
                                if (currentKey != stat.TargetRgb) {
                                    outBuffer[outIdx] = (byte)(stat.TargetRgb & 255);
                                    outBuffer[outIdx + 1] = (byte)((stat.TargetRgb >> 8) & 255);
                                    outBuffer[outIdx + 2] = (byte)((stat.TargetRgb >> 16) & 255);
                                    stat.ChangedPixels += 1;
                                }
                            }
                        }
                    }
                }

                foreach (var pixelOp in pixelOps) {
                    int mappingIndex = pixelOp.Item1;
                    int x = pixelOp.Item2;
                    int y = pixelOp.Item3;
                    int targetRgb = pixelOp.Item4;

                    if (x < 0 || y < 0 || x >= outBmp.Width || y >= outBmp.Height) {
                        continue;
                    }

                    int outIdx = y * outData.Stride + x * outBpp;
                    int currentKey = (outBuffer[outIdx + 2] << 16) | (outBuffer[outIdx + 1] << 8) | outBuffer[outIdx];
                    bool changed = currentKey != targetRgb;
                    if (changed) {
                        outBuffer[outIdx] = (byte)(targetRgb & 255);
                        outBuffer[outIdx + 1] = (byte)((targetRgb >> 8) & 255);
                        outBuffer[outIdx + 2] = (byte)((targetRgb >> 16) & 255);
                    }

                    var pixelStat = new PixelApplyStat();
                    pixelStat.MappingIndex = mappingIndex;
                    pixelStat.X = x;
                    pixelStat.Y = y;
                    pixelStat.TargetRgb = targetRgb;
                    pixelStat.Changed = changed;
                    pixelStats.Add(pixelStat);
                }

                Marshal.Copy(outBuffer, 0, outData.Scan0, outBuffer.Length);
            }
            finally {
                outBmp.UnlockBits(outData);
                modBmp.UnlockBits(modData);
                oriBmp.UnlockBits(oriData);
            }

            outBmp.Save(outputPath, ImageFormat.Png);
        }

        return new object[] { regionStats, pixelStats };
    }
}
"@

function Read-TextUtf8 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $text = $encoding.GetString($bytes)
    if ($text.Length -gt 0 -and [int][char]$text[0] -eq 0xFEFF) {
        return $text.Substring(1)
    }
    return $text
}

function Write-TextUtf8 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Export-Utf8Csv {
    param(
        [Parameter(Mandatory = $true)]$Rows,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $csv = @($Rows | ConvertTo-Csv -NoTypeInformation)
    [System.IO.File]::WriteAllLines($Path, $csv, [System.Text.UTF8Encoding]::new($false))
}

function Get-RgbKey {
    param(
        [int]$R,
        [int]$G,
        [int]$B
    )

    return (($R -shl 16) -bor ($G -shl 8) -bor $B)
}

function Format-Rgb {
    param([int]$RgbKey)

    $r = ($RgbKey -shr 16) -band 255
    $g = ($RgbKey -shr 8) -band 255
    $b = $RgbKey -band 255
    return "$r,$g,$b"
}

function Parse-RgbString {
    param([Parameter(Mandatory = $true)][string]$Rgb)

    $parts = @($Rgb -split ',')
    if ($parts.Count -ne 3) {
        throw "Invalid RGB string: $Rgb"
    }

    return [pscustomobject]@{
        r = [int]$parts[0]
        g = [int]$parts[1]
        b = [int]$parts[2]
        key = (Get-RgbKey -R ([int]$parts[0]) -G ([int]$parts[1]) -B ([int]$parts[2]))
    }
}

function Load-DefinitionRows {
    param([Parameter(Mandatory = $true)][string]$Path)

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $parts = $line.Split(';')
        if ($parts.Count -lt 6) {
            continue
        }
        if ($parts[0] -notmatch '^\d+$') {
            continue
        }

        $rows.Add([pscustomobject]@{
            id = [int]$parts[0]
            r = [int]$parts[1]
            g = [int]$parts[2]
            b = [int]$parts[3]
            rgb = "$($parts[1]),$($parts[2]),$($parts[3])"
            name = [string]$parts[4]
            x = [string]$parts[5]
        }) | Out-Null
    }

    return $rows
}

function Write-DefinitionRows {
    param(
        [Parameter(Mandatory = $true)]$Rows,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $lines = foreach ($row in ($Rows | Sort-Object id)) {
        '{0};{1};{2};{3};{4};{5};' -f $row.id, $row.r, $row.g, $row.b, $row.name, $row.x
    }
    Write-TextUtf8 -Path $Path -Text (($lines -join "`r`n") + "`r`n")
}

function Get-TrackingLookup {
    param([Parameter(Mandatory = $true)][string]$Path)

    $lookup = @{}
    foreach ($row in (Import-Csv -Path $Path)) {
        $lookup[[string]$row.old_id] = $row
    }
    return $lookup
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$stagingDir = Join-Path $root 'Works\analysis\generated\source_semantic_staging_fix'
if (-not (Test-Path -LiteralPath $stagingDir)) {
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
}

$assignmentsPath = Join-Path $root 'Works\analysis\generated\source_semantic_overlap_audit\source_rgb_overlap_auto_rgb_assignments.csv'
$placeholderInventoryPath = Join-Path $root 'Works\analysis\generated\final_placeholder_inventory_preserve_old_ids.csv'
$placeholderPixelMapPath = Join-Path $root 'Works\analysis\generated\placeholder_pixel_map_preserve_old.csv'
$modTrackingPath = Join-Path $root 'Works\analysis\generated\final_modlu_tracking_preserve_old_ids.csv'
$oriTrackingPath = Join-Path $root 'Works\analysis\generated\final_orijinal_tracking_preserve_old_ids.csv'
$baseImagePath = Join-Path $root 'map_data\provinces.png'
$modMaskPath = Join-Path $root 'Works\map_data_sources\provinces_modlu_kalan.png'
$oriMaskPath = Join-Path $root 'Works\map_data_sources\provinces_orijinal_dogu.png'
$baseDefinitionPath = Join-Path $root 'map_data\definition.csv'

$outputImagePath = Join-Path $stagingDir 'provinces_source_semantic_staging.png'
$outputDefinitionPath = Join-Path $stagingDir 'definition_source_semantic_staging.csv'
$imageReportPath = Join-Path $stagingDir 'source_semantic_staging_image_apply_report.csv'
$splitIdAssignmentsPath = Join-Path $stagingDir 'source_semantic_same_id_split_id_assignments.csv'
$definitionReportPath = Join-Path $stagingDir 'source_semantic_staging_definition_changes.csv'
$summaryPath = Join-Path $stagingDir 'source_semantic_staging_fix_summary.md'

$assignments = @(
    Import-Csv -Path $assignmentsPath |
        Sort-Object @{ Expression = { if ($_.modlu_id -eq $_.orijinal_id) { 0 } else { 1 } } }, @{ Expression = { $_.rgb } }
)
Write-Output 'DEBUG: assignments_loaded'

$modTracking = Get-TrackingLookup -Path $modTrackingPath
$oriTracking = Get-TrackingLookup -Path $oriTrackingPath
$placeholderInventory = @(Import-Csv -Path $placeholderInventoryPath | Sort-Object { [int]$_.final_new_id })
$placeholderPixels = @{}
foreach ($row in (Import-Csv -Path $placeholderPixelMapPath)) {
    $placeholderPixels[[string]$row.final_new_id] = $row
}
Write-Output 'DEBUG: lookups_loaded'

$sameIdAssignments = @($assignments | Where-Object { $_.modlu_id -eq $_.orijinal_id })
if (@($placeholderInventory).Count -lt @($sameIdAssignments).Count) {
    throw "Not enough placeholder IDs to split same-ID semantic conflicts."
}

$placeholderCursor = 0
$splitIdAssignments = New-Object System.Collections.Generic.List[object]
$resolvedAssignments = New-Object System.Collections.Generic.List[object]

for ($i = 0; $i -lt $assignments.Count; $i++) {
    $row = $assignments[$i]
    $sameId = ([string]$row.modlu_id -eq [string]$row.orijinal_id)

    $keepSource = [string]$row.keep_rgb_source
    $recolorSource = [string]$row.recolor_source
    $sharedRgb = [string]$row.old_shared_rgb
    $newRgb = [string]$row.new_rgb

    $keepTracking = if ($keepSource -eq 'modlu') { $modTracking[[string]$row.modlu_id] } else { $oriTracking[[string]$row.orijinal_id] }
    $recolorTracking = if ($recolorSource -eq 'modlu') { $modTracking[[string]$row.modlu_id] } else { $oriTracking[[string]$row.orijinal_id] }

    if ($null -eq $keepTracking) {
        throw "Missing keep-source tracking row for RGB $sharedRgb"
    }
    if ($null -eq $recolorTracking) {
        throw "Missing recolor-source tracking row for RGB $sharedRgb"
    }

    $keepFinalId = [int]$keepTracking.final_new_id
    $recolorFinalId = [int]$recolorTracking.final_new_id
    $splitPlaceholderRow = $null
    $splitPixelRow = $null

    if ($sameId) {
        $splitPlaceholderRow = $placeholderInventory[$placeholderCursor]
        $placeholderCursor++
        $recolorFinalId = [int]$splitPlaceholderRow.final_new_id
        $splitPixelRow = $placeholderPixels[[string]$recolorFinalId]

        $splitIdAssignments.Add([pscustomobject]@{
            rgb = $sharedRgb
            keep_rgb_source = $keepSource
            recolor_source = $recolorSource
            keep_final_id = $keepFinalId
            recolor_final_id = $recolorFinalId
            consumed_placeholder_id = $recolorFinalId
            consumed_placeholder_rgb = [string]$splitPlaceholderRow.placeholder_rgb
            placeholder_x = if ($null -ne $splitPixelRow) { [string]$splitPixelRow.x } else { '' }
            placeholder_y = if ($null -ne $splitPixelRow) { [string]$splitPixelRow.y } else { '' }
            recolor_source_id = if ($recolorSource -eq 'modlu') { [string]$row.modlu_id } else { [string]$row.orijinal_id }
            recolor_source_name = if ($recolorSource -eq 'modlu') { [string]$row.modlu_name } else { [string]$row.orijinal_name }
        }) | Out-Null
    }

    $resolvedAssignments.Add([pscustomobject]@{
        mapping_index = $i
        rgb = $sharedRgb
        keep_rgb_source = $keepSource
        recolor_source = $recolorSource
        keep_final_id = $keepFinalId
        recolor_final_id = $recolorFinalId
        keep_source_name = if ($keepSource -eq 'modlu') { [string]$row.modlu_name } else { [string]$row.orijinal_name }
        recolor_source_name = if ($recolorSource -eq 'modlu') { [string]$row.modlu_name } else { [string]$row.orijinal_name }
        keep_source_subset = if ($keepSource -eq 'modlu') { 'modlu_kalan' } else { 'orijinal_dogu' }
        recolor_source_subset = if ($recolorSource -eq 'modlu') { 'modlu_kalan' } else { 'orijinal_dogu' }
        same_id = $sameId
        new_rgb = $newRgb
        placeholder_pixel_x = if ($null -ne $splitPixelRow) { [int]$splitPixelRow.x } else { $null }
        placeholder_pixel_y = if ($null -ne $splitPixelRow) { [int]$splitPixelRow.y } else { $null }
        assignment_notes = [string]$row.assignment_notes
    }) | Out-Null
}
Write-Output 'DEBUG: resolved_assignments_ready'

$regionSpecs = New-Object System.Collections.Generic.List[string]
$pixelSpecs = New-Object System.Collections.Generic.List[string]
foreach ($row in $resolvedAssignments) {
    $sharedRgbKey = (Parse-RgbString -Rgb $row.rgb).key
    $newRgbKey = (Parse-RgbString -Rgb $row.new_rgb).key

    $regionSpecs.Add(('{0}|keep|{1}|{2}|{2}' -f $row.mapping_index, $row.keep_source_subset, $sharedRgbKey)) | Out-Null
    $regionSpecs.Add(('{0}|recolor|{1}|{2}|{3}' -f $row.mapping_index, $row.recolor_source_subset, $sharedRgbKey, $newRgbKey)) | Out-Null

    if ($row.same_id -and $null -ne $row.placeholder_pixel_x -and $null -ne $row.placeholder_pixel_y) {
        $pixelSpecs.Add(('{0}|{1}|{2}|{3}' -f $row.mapping_index, $row.placeholder_pixel_x, $row.placeholder_pixel_y, $newRgbKey)) | Out-Null
    }
}
Write-Output 'DEBUG: specs_ready'

$applyResult = [SourceSemanticStagingMapper]::Apply(
    $baseImagePath,
    $modMaskPath,
    $oriMaskPath,
    $outputImagePath,
    $regionSpecs.ToArray(),
    $pixelSpecs.ToArray()
)
Write-Output 'DEBUG: image_applied'

$regionStats = @($applyResult[0])
$pixelStats = @($applyResult[1])

$definitionRows = Load-DefinitionRows -Path $baseDefinitionPath
$definitionById = @{}
foreach ($row in $definitionRows) {
    $definitionById[[int]$row.id] = $row
}
Write-Output 'DEBUG: definition_loaded'

$definitionChangeRows = New-Object System.Collections.Generic.List[object]
foreach ($row in $resolvedAssignments) {
    $keepRow = $definitionById[[int]$row.keep_final_id]
    $recolorRow = $definitionById[[int]$row.recolor_final_id]

    if ($null -eq $keepRow) {
        throw "Missing definition row for keep_final_id $($row.keep_final_id)"
    }
    if ($null -eq $recolorRow) {
        throw "Missing definition row for recolor_final_id $($row.recolor_final_id)"
    }

    $keepRgb = Parse-RgbString -Rgb $row.rgb
    $newRgb = Parse-RgbString -Rgb $row.new_rgb

    $definitionChangeRows.Add([pscustomobject]@{
        mapping_index = $row.mapping_index
        row_role = 'keep'
        final_id = $row.keep_final_id
        old_rgb = $keepRow.rgb
        new_rgb = $row.rgb
        old_name = $keepRow.name
        new_name = $row.keep_source_name
        notes = 'Keep-side row normalized to shared RGB and keep-source name.'
    }) | Out-Null

    $keepRow.r = $keepRgb.r
    $keepRow.g = $keepRgb.g
    $keepRow.b = $keepRgb.b
    $keepRow.rgb = $row.rgb
    $keepRow.name = $row.keep_source_name
    $keepRow.x = 'x'

    $definitionChangeRows.Add([pscustomobject]@{
        mapping_index = $row.mapping_index
        row_role = 'recolor'
        final_id = $row.recolor_final_id
        old_rgb = $recolorRow.rgb
        new_rgb = $row.new_rgb
        old_name = $recolorRow.name
        new_name = $row.recolor_source_name
        notes = if ($row.same_id) { 'Same-ID split consumed a placeholder row.' } else { 'Existing distinct final row recolored.' }
    }) | Out-Null

    $recolorRow.r = $newRgb.r
    $recolorRow.g = $newRgb.g
    $recolorRow.b = $newRgb.b
    $recolorRow.rgb = $row.new_rgb
    $recolorRow.name = $row.recolor_source_name
    $recolorRow.x = 'x'
}
Write-Output 'DEBUG: definition_updated'

Write-DefinitionRows -Rows $definitionRows -Path $outputDefinitionPath

$stagingDefinitionRows = Load-DefinitionRows -Path $outputDefinitionPath
$rgbGroups = @($stagingDefinitionRows | Group-Object rgb | Where-Object { $_.Count -gt 1 -and $_.Name -ne '0,0,0' })

$regionReportRows = @(
foreach ($stat in $regionStats) {
    [pscustomobject]@{
        mapping_index = $stat.MappingIndex
        role = $stat.Role
        source_subset = $stat.SourceSubset
        mask_rgb = (Format-Rgb -RgbKey $stat.MaskRgb)
        target_rgb = (Format-Rgb -RgbKey $stat.TargetRgb)
        target_subset_pixels = $stat.TargetSubsetPixels
        changed_pixels = $stat.ChangedPixels
    }
}
)

$pixelReportRows = @(
foreach ($stat in $pixelStats) {
    [pscustomobject]@{
        mapping_index = $stat.MappingIndex
        x = $stat.X
        y = $stat.Y
        target_rgb = (Format-Rgb -RgbKey $stat.TargetRgb)
        changed = $stat.Changed
    }
}
)

$resolvedAssignmentCount = if ($null -eq $resolvedAssignments) { 0 } else { [int]$resolvedAssignments.Count }
$sameIdCount = 0
$differentIdCount = 0
foreach ($assignment in $resolvedAssignments) {
    if ($assignment.same_id) {
        $sameIdCount++
    } else {
        $differentIdCount++
    }
}
$placeholderCount = if ($null -eq $splitIdAssignments) { 0 } else { [int]$splitIdAssignments.Count }
$regionReportCount = if ($null -eq $regionReportRows) { 0 } else { [int]$regionReportRows.Count }
$pixelReportCount = if ($null -eq $pixelReportRows) { 0 } else { [int]$pixelReportRows.Count }
$duplicateRgbCount = if ($null -eq $rgbGroups) { 0 } else { [int]$rgbGroups.Count }

$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add('# Source Semantic Staging Fix') | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add(('Toplam assignment satiri: {0}' -f $resolvedAssignmentCount)) | Out-Null
$summaryLines.Add(('- same_id split: {0}' -f $sameIdCount)) | Out-Null
$summaryLines.Add(('- different_id split: {0}' -f $differentIdCount)) | Out-Null
$summaryLines.Add(('- kullanilan placeholder id: {0}' -f $placeholderCount)) | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add(('Region apply satiri: {0}' -f $regionReportCount)) | Out-Null
$summaryLines.Add(('Placeholder pixel repurpose satiri: {0}' -f $pixelReportCount)) | Out-Null
$summaryLines.Add(('Definition duplicate RGB (0,0,0 disi): {0}' -f $duplicateRgbCount)) | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add('Ciktilar:') | Out-Null
$summaryLines.Add("- $outputImagePath") | Out-Null
$summaryLines.Add("- $outputDefinitionPath") | Out-Null
$summaryLines.Add("- $imageReportPath") | Out-Null
$summaryLines.Add("- $splitIdAssignmentsPath") | Out-Null
$summaryLines.Add("- $definitionReportPath") | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add('Notlar:') | Out-Null
$summaryLines.Add('- Bu tur sadece staging uretir; canli map_data dosyalarina dokunmaz.') | Out-Null
$summaryLines.Add('- same_id semantic splitlerde placeholder row ve onun gizli teknik pikseli repurpose edildi.') | Out-Null
$summaryLines.Add('- keep-source mask pikselleri de hedef eski/shared RGBye zorlandi; bu, onceki heuristic recolorlarin tersine cevrilmesini saglar.') | Out-Null

$splitIdAssignmentRows = if ($null -eq $splitIdAssignments) { @() } else { $splitIdAssignments.ToArray() }
$definitionChangeExportRows = if ($null -eq $definitionChangeRows) { @() } else { $definitionChangeRows.ToArray() }

Export-Utf8Csv -Rows $regionReportRows -Path $imageReportPath
Export-Utf8Csv -Rows $splitIdAssignmentRows -Path $splitIdAssignmentsPath
Export-Utf8Csv -Rows $definitionChangeExportRows -Path $definitionReportPath
Write-TextUtf8 -Path $summaryPath -Text (($summaryLines -join "`r`n") + "`r`n")
