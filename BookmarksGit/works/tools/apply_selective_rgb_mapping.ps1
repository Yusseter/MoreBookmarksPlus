param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$MappingCsv = '',
    [string]$OutputImagePath = '',
    [string]$ReportCsvPath = '',
    [string]$SummaryPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -ReferencedAssemblies 'System.Drawing.dll' -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public sealed class MappingStat {
    public int MappingIndex;
    public string AffectedSubset;
    public int OldRgb;
    public int NewRgb;
    public int TargetSubsetPixels;
    public int ChangedPixels;
    public int BaseMismatchPixels;
}

public static class SelectiveRgbMapper {
    public static List<MappingStat> Apply(
        string basePath,
        string modPath,
        string oriPath,
        string outputPath,
        string[] mappingSpecs
    ) {
        var modMap = new Dictionary<int, MappingStat>();
        var oriMap = new Dictionary<int, MappingStat>();
        var stats = new List<MappingStat>();

        foreach (var spec in mappingSpecs) {
            var parts = spec.Split('|');
            if (parts.Length < 4) {
                continue;
            }

            var stat = new MappingStat();
            stat.MappingIndex = int.Parse(parts[0]);
            stat.AffectedSubset = parts[1];
            stat.OldRgb = int.Parse(parts[2]);
            stat.NewRgb = int.Parse(parts[3]);
            stats.Add(stat);

            if (string.Equals(stat.AffectedSubset, "modlu_kalan", StringComparison.OrdinalIgnoreCase)) {
                modMap[stat.OldRgb] = stat;
            }
            else if (string.Equals(stat.AffectedSubset, "orijinal_dogu", StringComparison.OrdinalIgnoreCase)) {
                oriMap[stat.OldRgb] = stat;
            }
        }

        using (var baseBmp = new Bitmap(basePath))
        using (var modBmp = new Bitmap(modPath))
        using (var oriBmp = new Bitmap(oriPath))
        using (var outBmp = new Bitmap(baseBmp)) {
            if (baseBmp.Width != modBmp.Width || baseBmp.Height != modBmp.Height ||
                baseBmp.Width != oriBmp.Width || baseBmp.Height != oriBmp.Height) {
                throw new InvalidOperationException("Input images must have identical dimensions.");
            }

            var baseRect = new Rectangle(0, 0, outBmp.Width, outBmp.Height);
            var outData = outBmp.LockBits(baseRect, ImageLockMode.ReadWrite, outBmp.PixelFormat);
            var modData = modBmp.LockBits(baseRect, ImageLockMode.ReadOnly, modBmp.PixelFormat);
            var oriData = oriBmp.LockBits(baseRect, ImageLockMode.ReadOnly, oriBmp.PixelFormat);

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

                        int baseKey = (outBuffer[outIdx + 2] << 16) | (outBuffer[outIdx + 1] << 8) | outBuffer[outIdx];
                        int modKey = (modBuffer[modIdx + 2] << 16) | (modBuffer[modIdx + 1] << 8) | modBuffer[modIdx];
                        int oriKey = (oriBuffer[oriIdx + 2] << 16) | (oriBuffer[oriIdx + 1] << 8) | oriBuffer[oriIdx];

                        MappingStat stat;
                        if (modKey != 0 && modMap.TryGetValue(modKey, out stat)) {
                            stat.TargetSubsetPixels += 1;
                            if (baseKey == stat.OldRgb) {
                                outBuffer[outIdx] = (byte)(stat.NewRgb & 255);
                                outBuffer[outIdx + 1] = (byte)((stat.NewRgb >> 8) & 255);
                                outBuffer[outIdx + 2] = (byte)((stat.NewRgb >> 16) & 255);
                                stat.ChangedPixels += 1;
                            }
                            else {
                                stat.BaseMismatchPixels += 1;
                            }
                        }
                        else if (oriKey != 0 && oriMap.TryGetValue(oriKey, out stat)) {
                            stat.TargetSubsetPixels += 1;
                            if (baseKey == stat.OldRgb) {
                                outBuffer[outIdx] = (byte)(stat.NewRgb & 255);
                                outBuffer[outIdx + 1] = (byte)((stat.NewRgb >> 8) & 255);
                                outBuffer[outIdx + 2] = (byte)((stat.NewRgb >> 16) & 255);
                                stat.ChangedPixels += 1;
                            }
                            else {
                                stat.BaseMismatchPixels += 1;
                            }
                        }
                    }
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

        return stats;
    }
}
"@

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Get-RgbKey {
    param(
        [int]$R,
        [int]$G,
        [int]$B
    )

    return (($R -shl 16) -bor ($G -shl 8) -bor $B)
}

function Parse-RgbString {
    param([string]$Rgb)

    $parts = $Rgb.Split(',')
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

function Export-Utf8Csv {
    param(
        $Rows,
        [string]$Path
    )

    @($Rows) | Export-Csv -Path $Path -NoTypeInformation -Encoding utf8
}

function Resolve-ChosenRgb {
    param($Row)

    if ($null -ne $Row.PSObject.Properties['new_rgb'] -and -not [string]::IsNullOrWhiteSpace($Row.new_rgb)) {
        return [string]$Row.new_rgb
    }

    if ($null -ne $Row.PSObject.Properties['suggested_new_rgb'] -and -not [string]::IsNullOrWhiteSpace($Row.suggested_new_rgb)) {
        return [string]$Row.suggested_new_rgb
    }

    throw "Row for shared_old_rgb '$($Row.shared_old_rgb)' does not contain a usable new RGB."
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$analysisGeneratedDir = Join-Path (Join-Path $root 'analysis') 'generated'
$mapDataDir = Join-Path $root 'map_data'

if ([string]::IsNullOrWhiteSpace($MappingCsv)) {
    $MappingCsv = Join-Path $analysisGeneratedDir 'rgb_mapping_draft.csv'
}
if ([string]::IsNullOrWhiteSpace($OutputImagePath)) {
    $OutputImagePath = Join-Path $analysisGeneratedDir 'provinces_birlesim_rgb_draft.png'
}
if ([string]::IsNullOrWhiteSpace($ReportCsvPath)) {
    $ReportCsvPath = Join-Path $analysisGeneratedDir 'rgb_mapping_apply_report.csv'
}
if ([string]::IsNullOrWhiteSpace($SummaryPath)) {
    $SummaryPath = Join-Path $analysisGeneratedDir 'rgb_mapping_apply_summary.md'
}

Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($OutputImagePath))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($ReportCsvPath))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($SummaryPath))

$rows = @(Import-Csv -Path $MappingCsv)
if ($rows.Count -eq 0) {
    throw "Mapping CSV is empty: $MappingCsv"
}

$duplicateOld = @($rows | Group-Object shared_old_rgb | Where-Object { $_.Count -gt 1 })
if ($duplicateOld.Count -gt 0) {
    throw "Mapping CSV contains duplicate shared_old_rgb values."
}

$preparedRows = New-Object System.Collections.Generic.List[object]
$newRgbValues = New-Object System.Collections.Generic.List[string]

for ($i = 0; $i -lt $rows.Count; $i++) {
    $row = $rows[$i]
    $chosenNewRgb = Resolve-ChosenRgb -Row $row
    $newRgbValues.Add($chosenNewRgb) | Out-Null

    $affectedSubset = [string]$row.affected_subset
    if ($affectedSubset -notin @('modlu_kalan', 'orijinal_dogu')) {
        throw "Unsupported affected_subset '$affectedSubset' in mapping row $i."
    }

    $preparedRows.Add([pscustomobject]@{
        mapping_index = $i
        shared_old_rgb = [string]$row.shared_old_rgb
        keep_original_rgb_source = [string]$row.keep_original_rgb_source
        recolor_source = [string]$row.recolor_source
        affected_subset = $affectedSubset
        affected_source_id = [string]$row.affected_source_id
        affected_source_name = [string]$row.affected_source_name
        affected_preview_path = [string]$row.affected_preview_path
        chosen_new_rgb = $chosenNewRgb
        basis = [string]$row.basis
        basis_reason = [string]$row.basis_reason
        notes = [string]$row.notes
    }) | Out-Null
}

$duplicateNew = @($newRgbValues | Group-Object | Where-Object { $_.Count -gt 1 })
if ($duplicateNew.Count -gt 0) {
    throw "Mapping CSV contains duplicate chosen new RGB values."
}

$mappingSpecs = New-Object System.Collections.Generic.List[string]
foreach ($row in $preparedRows) {
    $oldRgb = Parse-RgbString -Rgb $row.shared_old_rgb
    $newRgb = Parse-RgbString -Rgb $row.chosen_new_rgb

    if ($oldRgb.key -eq $newRgb.key) {
        throw "Old RGB and new RGB are identical for shared_old_rgb '$($row.shared_old_rgb)'."
    }

    $mappingSpecs.Add(("{0}|{1}|{2}|{3}" -f $row.mapping_index, $row.affected_subset, $oldRgb.key, $newRgb.key)) | Out-Null
}

$applyStats = [SelectiveRgbMapper]::Apply(
    (Join-Path $mapDataDir 'provinces_birlesim.png'),
    (Join-Path $mapDataDir 'provinces_modlu_kalan.png'),
    (Join-Path $mapDataDir 'provinces_orijinal_dogu.png'),
    $OutputImagePath,
    $mappingSpecs.ToArray()
)

$statsByIndex = @{}
foreach ($stat in $applyStats) {
    $statsByIndex[$stat.MappingIndex] = $stat
}

$reportRows = New-Object System.Collections.Generic.List[object]
foreach ($row in $preparedRows) {
    $stat = $statsByIndex[[int]$row.mapping_index]
    $reportRows.Add([pscustomobject]@{
        mapping_index = $row.mapping_index
        shared_old_rgb = $row.shared_old_rgb
        keep_original_rgb_source = $row.keep_original_rgb_source
        recolor_source = $row.recolor_source
        affected_subset = $row.affected_subset
        affected_source_id = $row.affected_source_id
        affected_source_name = $row.affected_source_name
        affected_preview_path = $row.affected_preview_path
        chosen_new_rgb = $row.chosen_new_rgb
        target_subset_pixels = $stat.TargetSubsetPixels
        changed_pixels = $stat.ChangedPixels
        base_mismatch_pixels = $stat.BaseMismatchPixels
        fully_applied = ($stat.TargetSubsetPixels -gt 0 -and $stat.ChangedPixels -eq $stat.TargetSubsetPixels -and $stat.BaseMismatchPixels -eq 0)
        basis = $row.basis
        basis_reason = $row.basis_reason
        notes = $row.notes
    }) | Out-Null
}

$reportExportRows = @($reportRows | Sort-Object mapping_index)
Export-Utf8Csv -Rows $reportExportRows -Path $ReportCsvPath

$fullyAppliedCount = @($reportExportRows | Where-Object { $_.fully_applied }).Count
$totalChangedPixels = ($reportExportRows | Measure-Object -Property changed_pixels -Sum).Sum
$totalMismatchPixels = ($reportExportRows | Measure-Object -Property base_mismatch_pixels -Sum).Sum

$summaryLines = @(
    '# RGB Mapping Apply Summary',
    '',
    ('- mapping csv: `{0}`' -f $MappingCsv),
    ('- output image: `{0}`' -f $OutputImagePath),
    ('- report csv: `{0}`' -f $ReportCsvPath),
    ('- total mapping rows: `{0}`' -f $reportExportRows.Count),
    ('- fully applied rows: `{0}`' -f $fullyAppliedCount),
    ('- total changed pixels: `{0}`' -f $totalChangedPixels),
    ('- total base mismatch pixels: `{0}`' -f $totalMismatchPixels),
    '',
    '## Sample Rows',
    ''
)

foreach ($row in @($reportExportRows | Select-Object -First 12)) {
    $summaryLines += ('- row `{0}` -> recolor `{1}` ID `{2}` from `{3}` to `{4}`, changed `{5}` px' -f $row.mapping_index, $row.recolor_source, $row.affected_source_id, $row.shared_old_rgb, $row.chosen_new_rgb, $row.changed_pixels)
}

[System.IO.File]::WriteAllLines($SummaryPath, $summaryLines, [System.Text.UTF8Encoding]::new($false))

Write-Output "Applied selective RGB mapping draft to '$OutputImagePath'."
