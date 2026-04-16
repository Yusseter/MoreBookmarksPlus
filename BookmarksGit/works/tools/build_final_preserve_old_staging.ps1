param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$SourceImagePath = '',
    [string]$ModSubsetImagePath = '',
    [string]$OrijinalSubsetImagePath = '',
    [string]$MappingDraftCsv = '',
    [string]$ConflictDecisionCsv = '',
    [string]$MasterCsv = '',
    [string]$ModluTrackingCsv = '',
    [string]$OrijinalTrackingCsv = '',
    [string]$PlaceholderInventoryCsv = '',
    [string]$FinalRgbMappingCsv = '',
    [string]$RgbOnlyImagePath = '',
    [string]$FinalImagePath = '',
    [string]$RgbApplyReportCsv = '',
    [string]$RgbApplySummaryPath = '',
    [string]$PlaceholderPixelMapCsv = '',
    [string]$PlaceholderOverpaintReportCsv = '',
    [string]$LegacyUnusedCsv = '',
    [string]$DefinitionOutputCsv = '',
    [string]$DefaultMapPlaceholderBlockPath = '',
    [string]$ValidationSummaryPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -ReferencedAssemblies 'System.Drawing.dll' -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public sealed class PlaceholderPlacement {
    public int FinalNewId;
    public int PlaceholderRgb;
    public int X;
    public int Y;
    public int OverwrittenRgb;
}

public sealed class ColorCount {
    public int Rgb;
    public int Count;
}

public sealed class ImageOverlayResult {
    public int Width;
    public int Height;
    public int AnchorBaseRgb;
    public int PlaceholderColumns;
    public int PlaceholderRows;
    public List<PlaceholderPlacement> PlaceholderPlacements = new List<PlaceholderPlacement>();
    public List<ColorCount> FinalColorCounts = new List<ColorCount>();
}

public static class PlaceholderGridPainter {
    public static ImageOverlayResult Apply(
        string inputPath,
        string outputPath,
        string[] placeholderSpecs,
        int columns
    ) {
        if (columns <= 0) {
            throw new ArgumentOutOfRangeException("columns");
        }

        var result = new ImageOverlayResult();

        using (var bmp = new Bitmap(inputPath))
        using (var outBmp = new Bitmap(bmp)) {
            var rect = new Rectangle(0, 0, outBmp.Width, outBmp.Height);
            var data = outBmp.LockBits(rect, ImageLockMode.ReadWrite, outBmp.PixelFormat);

            try {
                int bpp = Image.GetPixelFormatSize(data.PixelFormat) / 8;
                if (bpp < 3) {
                    throw new InvalidOperationException("Expected image formats with at least 24 bits per pixel.");
                }

                byte[] buffer = new byte[data.Stride * outBmp.Height];
                Marshal.Copy(data.Scan0, buffer, 0, buffer.Length);

                result.Width = outBmp.Width;
                result.Height = outBmp.Height;
                result.PlaceholderColumns = columns;
                result.PlaceholderRows = (placeholderSpecs.Length + columns - 1) / columns;

                if (result.PlaceholderRows > outBmp.Height) {
                    throw new InvalidOperationException("Placeholder grid does not fit within the image height.");
                }

                int anchorIndex = (outBmp.Height - 1) * data.Stride + (outBmp.Width - 1) * bpp;
                result.AnchorBaseRgb = (buffer[anchorIndex + 2] << 16) | (buffer[anchorIndex + 1] << 8) | buffer[anchorIndex];

                for (int i = 0; i < placeholderSpecs.Length; i++) {
                    var specParts = placeholderSpecs[i].Split('|');
                    if (specParts.Length < 2) {
                        throw new InvalidOperationException("Invalid placeholder spec.");
                    }

                    int finalNewId = int.Parse(specParts[0]);
                    int placeholderRgb = int.Parse(specParts[1]);

                    int x = outBmp.Width - 1 - (i % columns);
                    int y = outBmp.Height - 1 - (i / columns);
                    if (x < 0 || y < 0) {
                        throw new InvalidOperationException("Placeholder grid placement exceeded image bounds.");
                    }

                    int idx = y * data.Stride + x * bpp;
                    int overwrittenRgb = (buffer[idx + 2] << 16) | (buffer[idx + 1] << 8) | buffer[idx];

                    buffer[idx] = (byte)(placeholderRgb & 255);
                    buffer[idx + 1] = (byte)((placeholderRgb >> 8) & 255);
                    buffer[idx + 2] = (byte)((placeholderRgb >> 16) & 255);

                    result.PlaceholderPlacements.Add(new PlaceholderPlacement {
                        FinalNewId = finalNewId,
                        PlaceholderRgb = placeholderRgb,
                        X = x,
                        Y = y,
                        OverwrittenRgb = overwrittenRgb
                    });
                }

                var colorCounts = new Dictionary<int, int>();
                for (int y = 0; y < outBmp.Height; y++) {
                    int row = y * data.Stride;
                    for (int x = 0; x < outBmp.Width; x++) {
                        int idx = row + x * bpp;
                        int rgb = (buffer[idx + 2] << 16) | (buffer[idx + 1] << 8) | buffer[idx];
                        if (colorCounts.ContainsKey(rgb)) {
                            colorCounts[rgb] += 1;
                        } else {
                            colorCounts[rgb] = 1;
                        }
                    }
                }

                foreach (var pair in colorCounts) {
                    result.FinalColorCounts.Add(new ColorCount {
                        Rgb = pair.Key,
                        Count = pair.Value
                    });
                }

                Marshal.Copy(buffer, 0, data.Scan0, buffer.Length);
            }
            finally {
                outBmp.UnlockBits(data);
            }

            outBmp.Save(outputPath, ImageFormat.Png);
        }

        return result;
    }
}
"@

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Export-Utf8Csv {
    param(
        $Rows,
        [string]$Path
    )

    @($Rows) | Export-Csv -Path $Path -NoTypeInformation -Encoding utf8
}

function Get-RgbKey {
    param(
        [int]$R,
        [int]$G,
        [int]$B
    )

    return (($R -shl 16) -bor ($G -shl 8) -bor $B)
}

function Convert-RgbStringToKey {
    param([string]$Rgb)

    $parts = $Rgb.Split(',')
    if ($parts.Count -ne 3) {
        throw "Invalid RGB string: $Rgb"
    }

    return (Get-RgbKey -R ([int]$parts[0]) -G ([int]$parts[1]) -B ([int]$parts[2]))
}

function Convert-RgbKeyToString {
    param([int]$RgbKey)

    $r = ($RgbKey -shr 16) -band 255
    $g = ($RgbKey -shr 8) -band 255
    $b = $RgbKey -band 255
    return ('{0},{1},{2}' -f $r, $g, $b)
}

function Resolve-ChosenRgb {
    param($Row)

    if ($null -ne $Row.PSObject.Properties['new_rgb'] -and -not [string]::IsNullOrWhiteSpace([string]$Row.new_rgb)) {
        return [string]$Row.new_rgb
    }

    if ($null -ne $Row.PSObject.Properties['chosen_new_rgb'] -and -not [string]::IsNullOrWhiteSpace([string]$Row.chosen_new_rgb)) {
        return [string]$Row.chosen_new_rgb
    }

    if ($null -ne $Row.PSObject.Properties['suggested_new_rgb'] -and -not [string]::IsNullOrWhiteSpace([string]$Row.suggested_new_rgb)) {
        return [string]$Row.suggested_new_rgb
    }

    throw "Could not resolve chosen RGB for row."
}

function Build-DefinitionLines {
    param([object[]]$Rows)

    $sortedRows = @($Rows | Sort-Object {[int]$_.final_new_id})
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('0;0;0;0;x;x') | Out-Null

    foreach ($row in $sortedRows) {
        $parts = ([string]$row.effective_rgb).Split(',')
        if ($parts.Count -ne 3) {
            throw "Invalid effective_rgb '$($row.effective_rgb)' for final_new_id '$($row.final_new_id)'."
        }

        $name = if ([string]::IsNullOrWhiteSpace([string]$row.effective_name)) { '' } else { [string]$row.effective_name }
        $lines.Add(('{0};{1};{2};{3};{4};x' -f [int]$row.final_new_id, [int]$parts[0], [int]$parts[1], [int]$parts[2], $name)) | Out-Null
    }

    return $lines
}

function Get-ConsecutiveRuns {
    param([int[]]$Ids)

    $sorted = @($Ids | Sort-Object)
    $runs = New-Object System.Collections.Generic.List[object]
    if ($sorted.Count -eq 0) {
        return @()
    }

    $start = $sorted[0]
    $prev = $sorted[0]
    for ($i = 1; $i -lt $sorted.Count; $i++) {
        $current = $sorted[$i]
        if ($current -eq ($prev + 1)) {
            $prev = $current
            continue
        }

        $runs.Add([pscustomobject]@{
            start = $start
            end = $prev
            count = ($prev - $start + 1)
        }) | Out-Null

        $start = $current
        $prev = $current
    }

    $runs.Add([pscustomobject]@{
        start = $start
        end = $prev
        count = ($prev - $start + 1)
    }) | Out-Null

    return $runs.ToArray()
}

function Flush-ListLine {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [System.Collections.Generic.List[int]]$Buffer
    )

    if ($Buffer.Count -eq 0) {
        return
    }

    $Lines.Add(('impassable_mountains = LIST {{ {0} }}' -f (($Buffer | ForEach-Object { [string]$_ }) -join ' '))) | Out-Null
    $Buffer.Clear()
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$generatedDir = Join-Path (Join-Path $root 'analysis') 'generated'
$mapDataDir = Join-Path $root 'map_data'

if ([string]::IsNullOrWhiteSpace($SourceImagePath)) {
    $SourceImagePath = Join-Path $mapDataDir 'provinces_birlesim.png'
}
if ([string]::IsNullOrWhiteSpace($ModSubsetImagePath)) {
    $ModSubsetImagePath = Join-Path $mapDataDir 'provinces_modlu_kalan.png'
}
if ([string]::IsNullOrWhiteSpace($OrijinalSubsetImagePath)) {
    $OrijinalSubsetImagePath = Join-Path $mapDataDir 'provinces_orijinal_dogu.png'
}
if ([string]::IsNullOrWhiteSpace($MappingDraftCsv)) {
    $MappingDraftCsv = Join-Path $generatedDir 'rgb_mapping_draft.csv'
}
if ([string]::IsNullOrWhiteSpace($ConflictDecisionCsv)) {
    $ConflictDecisionCsv = Join-Path $generatedDir 'definition_rgb_conflict_decisions.csv'
}
if ([string]::IsNullOrWhiteSpace($MasterCsv)) {
    $MasterCsv = Join-Path $generatedDir 'final_master_preserve_old_ids.csv'
}
if ([string]::IsNullOrWhiteSpace($ModluTrackingCsv)) {
    $ModluTrackingCsv = Join-Path $generatedDir 'final_modlu_tracking_preserve_old_ids.csv'
}
if ([string]::IsNullOrWhiteSpace($OrijinalTrackingCsv)) {
    $OrijinalTrackingCsv = Join-Path $generatedDir 'final_orijinal_tracking_preserve_old_ids.csv'
}
if ([string]::IsNullOrWhiteSpace($PlaceholderInventoryCsv)) {
    $PlaceholderInventoryCsv = Join-Path $generatedDir 'final_placeholder_inventory_preserve_old_ids.csv'
}
if ([string]::IsNullOrWhiteSpace($FinalRgbMappingCsv)) {
    $FinalRgbMappingCsv = Join-Path $generatedDir 'rgb_mapping_final_preserve_old.csv'
}
if ([string]::IsNullOrWhiteSpace($RgbOnlyImagePath)) {
    $RgbOnlyImagePath = Join-Path $generatedDir 'provinces_birlesim_rgb_only_preserve_old.png'
}
if ([string]::IsNullOrWhiteSpace($FinalImagePath)) {
    $FinalImagePath = Join-Path $generatedDir 'provinces_birlesim_final_preserve_old.png'
}
if ([string]::IsNullOrWhiteSpace($RgbApplyReportCsv)) {
    $RgbApplyReportCsv = Join-Path $generatedDir 'rgb_mapping_final_apply_report_preserve_old.csv'
}
if ([string]::IsNullOrWhiteSpace($RgbApplySummaryPath)) {
    $RgbApplySummaryPath = Join-Path $generatedDir 'rgb_mapping_final_apply_summary_preserve_old.md'
}
if ([string]::IsNullOrWhiteSpace($PlaceholderPixelMapCsv)) {
    $PlaceholderPixelMapCsv = Join-Path $generatedDir 'placeholder_pixel_map_preserve_old.csv'
}
if ([string]::IsNullOrWhiteSpace($PlaceholderOverpaintReportCsv)) {
    $PlaceholderOverpaintReportCsv = Join-Path $generatedDir 'placeholder_overpaint_report_preserve_old.csv'
}
if ([string]::IsNullOrWhiteSpace($LegacyUnusedCsv)) {
    $LegacyUnusedCsv = Join-Path $generatedDir 'legacy_unused_after_placeholder_overpaint_preserve_old.csv'
}
if ([string]::IsNullOrWhiteSpace($DefinitionOutputCsv)) {
    $DefinitionOutputCsv = Join-Path $generatedDir 'definition_birlesim_final_preserve_old.csv'
}
if ([string]::IsNullOrWhiteSpace($DefaultMapPlaceholderBlockPath)) {
    $DefaultMapPlaceholderBlockPath = Join-Path $generatedDir 'default_map_placeholder_block_preserve_old.txt'
}
if ([string]::IsNullOrWhiteSpace($ValidationSummaryPath)) {
    $ValidationSummaryPath = Join-Path $generatedDir 'final_staging_validation_preserve_old.md'
}

foreach ($path in @(
    $FinalRgbMappingCsv,
    $RgbOnlyImagePath,
    $FinalImagePath,
    $RgbApplyReportCsv,
    $RgbApplySummaryPath,
    $PlaceholderPixelMapCsv,
    $PlaceholderOverpaintReportCsv,
    $LegacyUnusedCsv,
    $DefinitionOutputCsv,
    $DefaultMapPlaceholderBlockPath,
    $ValidationSummaryPath
)) {
    Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($path))
}

$mappingDraftRows = @(Import-Csv -Path $MappingDraftCsv)
$conflictRows = @(Import-Csv -Path $ConflictDecisionCsv)
$masterRows = @(Import-Csv -Path $MasterCsv)
$modluTrackingRows = @(Import-Csv -Path $ModluTrackingCsv)
$orijinalTrackingRows = @(Import-Csv -Path $OrijinalTrackingCsv)
$placeholderInventoryRows = @(Import-Csv -Path $PlaceholderInventoryCsv)

if ($mappingDraftRows.Count -eq 0) {
    throw "RGB mapping draft CSV is empty: $MappingDraftCsv"
}
if ($masterRows.Count -eq 0) {
    throw "Master CSV is empty: $MasterCsv"
}

$conflictByRgb = @{}
foreach ($row in $conflictRows) {
    $conflictByRgb[[string]$row.rgb] = $row
}

$finalRgbMappingRows = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $mappingDraftRows.Count; $i++) {
    $row = $mappingDraftRows[$i]
    $sharedOldRgb = [string]$row.shared_old_rgb
    if (-not $conflictByRgb.ContainsKey($sharedOldRgb)) {
        throw "Conflict decision row not found for RGB '$sharedOldRgb'."
    }

    $decision = $conflictByRgb[$sharedOldRgb]
    $chosenNewRgb = Resolve-ChosenRgb -Row $row

    $finalRgbMappingRows.Add([pscustomobject]@{
        mapping_index = $i
        shared_old_rgb = $sharedOldRgb
        old_rgb = $sharedOldRgb
        new_rgb = $chosenNewRgb
        keep_original_rgb_source = [string]$row.keep_original_rgb_source
        recolor_source = [string]$row.recolor_source
        affected_subset = [string]$row.affected_subset
        affected_source_id = [string]$row.affected_source_id
        affected_source_name = [string]$row.affected_source_name
        affected_preview_path = [string]$row.affected_preview_path
        modlu_old_id = [string]$decision.modlu_id
        modlu_old_name = [string]$decision.modlu_name
        orijinal_old_id = [string]$decision.orijinal_id
        orijinal_old_name = [string]$decision.orijinal_name
        decision_origin = 'locked_from_existing_draft'
        basis = 'locked_from_existing_draft'
        basis_reason = 'Promoted from rgb_mapping_draft.csv as the final preserve_old_ids staging mapping.'
        notes = if ([string]::IsNullOrWhiteSpace([string]$row.notes)) {
            'Locked from rgb_mapping_draft.csv for final preserve_old_ids staging.'
        }
        else {
            'Locked from rgb_mapping_draft.csv for final preserve_old_ids staging. Original draft note: {0}' -f [string]$row.notes
        }
    }) | Out-Null
}

$finalRgbMappingExportRows = @($finalRgbMappingRows | Sort-Object mapping_index)
Export-Utf8Csv -Rows $finalRgbMappingExportRows -Path $FinalRgbMappingCsv

$applyScriptPath = Join-Path $root 'tools\apply_selective_rgb_mapping.ps1'
& $applyScriptPath `
    -RepoRoot $root `
    -MappingCsv $FinalRgbMappingCsv `
    -OutputImagePath $RgbOnlyImagePath `
    -ReportCsvPath $RgbApplyReportCsv `
    -SummaryPath $RgbApplySummaryPath | Out-Null

$sortedPlaceholderRows = @($placeholderInventoryRows | Sort-Object {[int]$_.final_new_id})
$placeholderCount = $sortedPlaceholderRows.Count
$placeholderColumns = [int][Math]::Ceiling([Math]::Sqrt([double]$placeholderCount))
if ($placeholderColumns -lt 1) {
    $placeholderColumns = 1
}

$placeholderSpecs = New-Object System.Collections.Generic.List[string]
foreach ($row in $sortedPlaceholderRows) {
    $placeholderSpecs.Add(('{0}|{1}' -f [int]$row.final_new_id, (Convert-RgbStringToKey -Rgb ([string]$row.placeholder_rgb))) ) | Out-Null
}

$overlayResult = [PlaceholderGridPainter]::Apply(
    $RgbOnlyImagePath,
    $FinalImagePath,
    $placeholderSpecs.ToArray(),
    $placeholderColumns
)

$masterByRgb = @{}
foreach ($row in $masterRows) {
    $masterByRgb[[string]$row.effective_rgb] = $row
}

$placeholderPixelRows = New-Object System.Collections.Generic.List[object]
foreach ($placement in $overlayResult.PlaceholderPlacements) {
    $overwrittenRgbString = Convert-RgbKeyToString -RgbKey $placement.OverwrittenRgb
    $matchedRow = if ($masterByRgb.ContainsKey($overwrittenRgbString)) { $masterByRgb[$overwrittenRgbString] } else { $null }

    $placeholderPixelRows.Add([pscustomobject]@{
        final_new_id = $placement.FinalNewId
        placeholder_rgb = (Convert-RgbKeyToString -RgbKey $placement.PlaceholderRgb)
        x = $placement.X
        y = $placement.Y
        overwritten_rgb = $overwrittenRgbString
        overwritten_final_new_id = if ($null -ne $matchedRow) { [string]$matchedRow.final_new_id } else { '' }
        overwritten_name = if ($null -ne $matchedRow) { [string]$matchedRow.effective_name } else { '' }
        overwritten_row_type = if ($null -ne $matchedRow) { [string]$matchedRow.row_type } else { '' }
        overwritten_source_origin = if ($null -ne $matchedRow) { [string]$matchedRow.source_origin } else { '' }
    }) | Out-Null
}

$placeholderPixelExportRows = @($placeholderPixelRows | Sort-Object final_new_id)
Export-Utf8Csv -Rows $placeholderPixelExportRows -Path $PlaceholderPixelMapCsv

$overpaintSummaryRows = New-Object System.Collections.Generic.List[object]
foreach ($group in @($placeholderPixelExportRows | Group-Object overwritten_rgb | Sort-Object Count -Descending)) {
    $sample = $group.Group[0]
    $overpaintSummaryRows.Add([pscustomobject]@{
        overwritten_rgb = [string]$group.Name
        overwritten_count = $group.Count
        overwritten_final_new_id = [string]$sample.overwritten_final_new_id
        overwritten_name = [string]$sample.overwritten_name
        overwritten_row_type = [string]$sample.overwritten_row_type
        overwritten_source_origin = [string]$sample.overwritten_source_origin
    }) | Out-Null
}

$overpaintExportRows = @(
    $overpaintSummaryRows | Sort-Object -Property @(
        @{ Expression = 'overwritten_count'; Descending = $true }
        @{ Expression = 'overwritten_rgb'; Descending = $false }
    )
)
Export-Utf8Csv -Rows $overpaintExportRows -Path $PlaceholderOverpaintReportCsv

$definitionLines = Build-DefinitionLines -Rows $masterRows
[System.IO.File]::WriteAllLines($DefinitionOutputCsv, $definitionLines, [System.Text.UTF8Encoding]::new($false))

$placeholderIds = @($sortedPlaceholderRows | ForEach-Object { [int]$_.final_new_id })
$runs = Get-ConsecutiveRuns -Ids $placeholderIds
$blockLines = New-Object System.Collections.Generic.List[string]
$blockLines.Add('# TECH PLACEHOLDER PROVINCES BEGIN') | Out-Null
$blockLines.Add('# Generated staging block for preserve_old_ids placeholder provinces.') | Out-Null

$listBuffer = New-Object System.Collections.Generic.List[int]
foreach ($run in $runs) {
    if ([int]$run.count -ge 3) {
        Flush-ListLine -Lines $blockLines -Buffer $listBuffer
        $blockLines.Add(('impassable_mountains = RANGE {{ {0} {1} }}' -f [int]$run.start, [int]$run.end)) | Out-Null
    }
    else {
        for ($id = [int]$run.start; $id -le [int]$run.end; $id++) {
            $listBuffer.Add($id) | Out-Null
            if ($listBuffer.Count -ge 24) {
                Flush-ListLine -Lines $blockLines -Buffer $listBuffer
            }
        }
    }
}
Flush-ListLine -Lines $blockLines -Buffer $listBuffer
$blockLines.Add('# TECH PLACEHOLDER PROVINCES END') | Out-Null
[System.IO.File]::WriteAllLines($DefaultMapPlaceholderBlockPath, $blockLines, [System.Text.UTF8Encoding]::new($false))

$imageColorCountRows = @($overlayResult.FinalColorCounts)
$imageNonBlackColors = @($imageColorCountRows | Where-Object { $_.Rgb -ne 0 })
$imageColorSet = @{}
foreach ($colorRow in $imageNonBlackColors) {
    $imageColorSet[[int]$colorRow.Rgb] = $true
}

$legacyUnusedRows = New-Object System.Collections.Generic.List[object]
foreach ($row in $masterRows) {
    $rgbKey = Convert-RgbStringToKey -Rgb ([string]$row.effective_rgb)
    if (-not $imageColorSet.ContainsKey($rgbKey)) {
        $legacyUnusedRows.Add([pscustomobject]@{
            final_new_id = [int]$row.final_new_id
            effective_rgb = [string]$row.effective_rgb
            effective_name = [string]$row.effective_name
            row_type = [string]$row.row_type
            source_origin = [string]$row.source_origin
            preferred_source_subset = [string]$row.preferred_source_subset
            reason = 'legacy_unused_after_placeholder_overpaint'
        }) | Out-Null
    }
}

$legacyUnusedExportRows = @($legacyUnusedRows | Sort-Object final_new_id)
Export-Utf8Csv -Rows $legacyUnusedExportRows -Path $LegacyUnusedCsv

$duplicateRgbGroups = @($masterRows | Group-Object effective_rgb | Where-Object { $_.Count -gt 1 })
$idValues = @($masterRows | ForEach-Object { [int]$_.final_new_id })
$maxId = ($idValues | Measure-Object -Maximum).Maximum
$missingIds = New-Object System.Collections.Generic.List[int]
for ($id = 1; $id -le $maxId; $id++) {
    if ($idValues -notcontains $id) {
        $missingIds.Add($id) | Out-Null
    }
}

$coordDistinctCount = @($placeholderPixelExportRows | Group-Object { '{0},{1}' -f $_.x, $_.y }).Count
$placeholderIdSetMatches = (
    (@($placeholderPixelExportRows | ForEach-Object { [int]$_.final_new_id } | Sort-Object) -join ',') -eq
    (($placeholderIds | Sort-Object) -join ',')
)
$placeholderBlockIdMatches = $true
$blockIdsParsed = New-Object System.Collections.Generic.List[int]
foreach ($line in $blockLines) {
    if ($line -match 'RANGE\s*\{\s*(\d+)\s+(\d+)\s*\}') {
        for ($id = [int]$matches[1]; $id -le [int]$matches[2]; $id++) {
            $blockIdsParsed.Add($id) | Out-Null
        }
    }
    elseif ($line -match 'LIST\s*\{\s*([^}]*)\}') {
        foreach ($match in [regex]::Matches($matches[1], '\b\d+\b')) {
            $blockIdsParsed.Add([int]$match.Value) | Out-Null
        }
    }
}
if ((($blockIdsParsed | Sort-Object) -join ',') -ne (($placeholderIds | Sort-Object) -join ',')) {
    $placeholderBlockIdMatches = $false
}

$modluChangedIdCount = @($modluTrackingRows | Where-Object { ([string]$_.id_changed).ToLowerInvariant() -eq 'true' }).Count
$orijinalChangedIdCount = @($orijinalTrackingRows | Where-Object { ([string]$_.id_changed).ToLowerInvariant() -eq 'true' }).Count
$modluChangedRgbCount = @($modluTrackingRows | Where-Object { ([string]$_.rgb_changed).ToLowerInvariant() -eq 'true' }).Count
$orijinalChangedRgbCount = @($orijinalTrackingRows | Where-Object { ([string]$_.rgb_changed).ToLowerInvariant() -eq 'true' }).Count

$validationLines = @(
    '# Final Staging Validation - preserve_old_ids',
    '',
    ('- source image: `{0}`' -f $SourceImagePath),
    ('- rgb-only image: `{0}`' -f $RgbOnlyImagePath),
    ('- final image: `{0}`' -f $FinalImagePath),
    ('- final rgb mapping csv: `{0}`' -f $FinalRgbMappingCsv),
    ('- placeholder pixel map csv: `{0}`' -f $PlaceholderPixelMapCsv),
    ('- placeholder overpaint report csv: `{0}`' -f $PlaceholderOverpaintReportCsv),
    ('- legacy unused csv: `{0}`' -f $LegacyUnusedCsv),
    ('- final definition csv: `{0}`' -f $DefinitionOutputCsv),
    ('- default.map placeholder block: `{0}`' -f $DefaultMapPlaceholderBlockPath),
    '',
    '## Core Checks',
    '',
    ('- contiguous final definition IDs: `{0}`' -f ($missingIds.Count -eq 0)),
    ('- duplicate RGB count in final definition rows: `{0}`' -f $duplicateRgbGroups.Count),
    ('- placeholder pixel count matches inventory: `{0}` (`{1}` vs `{2}`)' -f ($placeholderPixelExportRows.Count -eq $placeholderIds.Count), $placeholderPixelExportRows.Count, $placeholderIds.Count),
    ('- placeholder coordinates unique: `{0}` (`{1}`)' -f ($coordDistinctCount -eq $placeholderPixelExportRows.Count), $coordDistinctCount),
    ('- placeholder ID set matches inventory: `{0}`' -f $placeholderIdSetMatches),
    ('- default.map block ID set matches inventory: `{0}`' -f $placeholderBlockIdMatches),
    ('- modlu changed ID count: `{0}`' -f $modluChangedIdCount),
    ('- orijinal changed ID count: `{0}`' -f $orijinalChangedIdCount),
    ('- modlu changed RGB count: `{0}`' -f $modluChangedRgbCount),
    ('- orijinal changed RGB count: `{0}`' -f $orijinalChangedRgbCount),
    '',
    '## Image / Placeholder Stats',
    '',
    ('- image size: `{0}x{1}`' -f $overlayResult.Width, $overlayResult.Height),
    ('- anchor base RGB before placeholder overlay: `{0}`' -f (Convert-RgbKeyToString -RgbKey $overlayResult.AnchorBaseRgb)),
    ('- placeholder columns: `{0}`' -f $overlayResult.PlaceholderColumns),
    ('- placeholder rows: `{0}`' -f $overlayResult.PlaceholderRows),
    ('- final non-black image color count: `{0}`' -f $imageNonBlackColors.Count),
    ('- final definition color count: `{0}`' -f $masterRows.Count),
    ('- legacy unused definition rows after placeholder overpaint: `{0}`' -f $legacyUnusedExportRows.Count),
    '',
    '## Expected Counts',
    '',
    '- expected modlu changed ID count: `0`',
    '- expected orijinal changed ID count: `634`',
    '- expected modlu changed RGB count: `105`',
    '- expected orijinal changed RGB count: `14`'
)

[System.IO.File]::WriteAllLines($ValidationSummaryPath, $validationLines, [System.Text.UTF8Encoding]::new($false))

Write-Output "Built final preserve_old_ids staging outputs under '$generatedDir'."
