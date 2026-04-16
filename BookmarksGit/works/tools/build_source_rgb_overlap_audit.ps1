param(
    [string]$RepoRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$reportDir = Join-Path $RepoRoot 'Works/analysis/generated/source_rgb_overlap_audit'
$null = New-Item -ItemType Directory -Path $reportDir -Force

$modPngPath = Join-Path $RepoRoot 'Works/map_data_sources/provinces_modlu_kalan.png'
$origPngPath = Join-Path $RepoRoot 'Works/map_data_sources/provinces_orijinal_dogu.png'
$modDefPath = Join-Path $RepoRoot 'Works/map_data_sources/definition_modlu_kalan.csv'
$origDefPath = Join-Path $RepoRoot 'Works/map_data_sources/definition_orijinal_dogu.csv'

$outModInventory = Join-Path $reportDir 'modlu_kalan_rgb_inventory_from_png.csv'
$outOrigInventory = Join-Path $reportDir 'orijinal_dogu_rgb_inventory_from_png.csv'
$outSharedSameId = Join-Path $reportDir 'source_rgb_overlap_same_id.csv'
$outSharedConflict = Join-Path $reportDir 'source_rgb_overlap_conflicts.csv'
$outMissing = Join-Path $reportDir 'source_rgb_overlap_missing_definition.csv'
$outDecisionTemplate = Join-Path $reportDir 'source_rgb_overlap_conflict_decisions.csv'
$outSummary = Join-Path $reportDir 'source_rgb_overlap_summary.md'

function Get-DefinitionRowsByRgb {
    param([string]$Path)

    $map = @{}
    $duplicates = New-Object 'System.Collections.Generic.List[object]'
    foreach ($line in Get-Content -Path $Path -Encoding UTF8) {
        if ($line -notmatch '^\s*(\d+);(\d+);(\d+);(\d+);([^;]*);') {
            continue
        }
        $id = [int]$matches[1]
        $rgb = '{0},{1},{2}' -f $matches[2], $matches[3], $matches[4]
        $name = $matches[5]
        $row = [pscustomobject]@{
            id = $id
            rgb = $rgb
            name = $name
        }
        if ($map.ContainsKey($rgb)) {
            $duplicates.Add([pscustomobject]@{
                definition_path = $Path
                rgb = $rgb
                first_id = $map[$rgb].id
                second_id = $id
                first_name = $map[$rgb].name
                second_name = $name
            }) | Out-Null
        }
        else {
            $map[$rgb] = $row
        }
    }
    return [pscustomobject]@{
        Map = $map
        Duplicates = $duplicates
    }
}

Add-Type -AssemblyName System.Drawing

$csharp = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class RgbInventoryRow {
    public int Key;
    public long PixelCount;
    public int MinX = int.MaxValue;
    public int MinY = int.MaxValue;
    public int MaxX = -1;
    public int MaxY = -1;
}

public static class RgbInventoryExtractor {
    private static Bitmap LoadAs32bpp(string path) {
        using (var original = new Bitmap(path)) {
            return original.Clone(new Rectangle(0, 0, original.Width, original.Height), PixelFormat.Format32bppArgb);
        }
    }

    public static List<RgbInventoryRow> Extract(string path) {
        var rows = new Dictionary<int, RgbInventoryRow>();

        using (var bmp = LoadAs32bpp(path)) {
            var rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
            var data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try {
                var bytes = new byte[Math.Abs(data.Stride) * bmp.Height];
                Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);

                int width = bmp.Width;
                int stride = data.Stride;
                for (int y = 0; y < bmp.Height; y++) {
                    int rowOffset = y * stride;
                    for (int x = 0; x < width; x++) {
                        int offset = rowOffset + (x * 4);
                        int key = (bytes[offset + 2] << 16) | (bytes[offset + 1] << 8) | bytes[offset];
                        if (key == 0) {
                            continue;
                        }

                        RgbInventoryRow row;
                        if (!rows.TryGetValue(key, out row)) {
                            row = new RgbInventoryRow { Key = key, PixelCount = 0 };
                            rows[key] = row;
                        }

                        row.PixelCount++;
                        if (x < row.MinX) row.MinX = x;
                        if (y < row.MinY) row.MinY = y;
                        if (x > row.MaxX) row.MaxX = x;
                        if (y > row.MaxY) row.MaxY = y;
                    }
                }
            }
            finally {
                bmp.UnlockBits(data);
            }
        }

        return new List<RgbInventoryRow>(rows.Values);
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

function Convert-NativeInventoryToObjects {
    param(
        [System.Collections.IEnumerable]$NativeRows,
        [string]$SubsetName,
        [hashtable]$DefinitionMap
    )

    $rows = foreach ($native in $NativeRows) {
        $rgb = Convert-KeyToRgb -Key $native.Key
        $def = $DefinitionMap[$rgb]
        [pscustomobject]@{
            subset_name          = $SubsetName
            rgb                  = $rgb
            pixel_count          = $native.PixelCount
            bbox                 = '{0},{1} -> {2},{3}' -f $native.MinX, $native.MinY, $native.MaxX, $native.MaxY
            min_x                = $native.MinX
            min_y                = $native.MinY
            max_x                = $native.MaxX
            max_y                = $native.MaxY
            definition_found     = [bool]($null -ne $def)
            source_id            = if ($def) { $def.id } else { $null }
            source_name          = if ($def) { $def.name } else { $null }
        }
    }
    return @($rows | Sort-Object rgb)
}

$modDefData = Get-DefinitionRowsByRgb -Path $modDefPath
$origDefData = Get-DefinitionRowsByRgb -Path $origDefPath

$modNativeInventory = [RgbInventoryExtractor]::Extract($modPngPath)
$origNativeInventory = [RgbInventoryExtractor]::Extract($origPngPath)

$modInventory = Convert-NativeInventoryToObjects -NativeRows $modNativeInventory -SubsetName 'modlu_kalan' -DefinitionMap $modDefData.Map
$origInventory = Convert-NativeInventoryToObjects -NativeRows $origNativeInventory -SubsetName 'orijinal_dogu' -DefinitionMap $origDefData.Map

$modInventory | Export-Csv -Path $outModInventory -NoTypeInformation -Encoding UTF8
$origInventory | Export-Csv -Path $outOrigInventory -NoTypeInformation -Encoding UTF8

$missingRows = New-Object 'System.Collections.Generic.List[object]'
foreach ($row in $modInventory + $origInventory) {
    if (-not $row.definition_found) {
        $missingRows.Add($row) | Out-Null
    }
}

$modByRgb = @{}
foreach ($row in $modInventory) { $modByRgb[$row.rgb] = $row }
$origByRgb = @{}
foreach ($row in $origInventory) { $origByRgb[$row.rgb] = $row }

$sharedRgbs = @($modByRgb.Keys | Where-Object { $origByRgb.ContainsKey($_) } | Sort-Object)
$sameIdRows = New-Object 'System.Collections.Generic.List[object]'
$conflictRows = New-Object 'System.Collections.Generic.List[object]'

foreach ($rgb in $sharedRgbs) {
    $modRow = $modByRgb[$rgb]
    $origRow = $origByRgb[$rgb]
    if (-not $modRow.definition_found -or -not $origRow.definition_found) {
        continue
    }

    $joined = [pscustomobject]@{
        rgb                   = $rgb
        modlu_id              = [int]$modRow.source_id
        modlu_name            = $modRow.source_name
        modlu_pixel_count     = [int64]$modRow.pixel_count
        modlu_bbox            = $modRow.bbox
        orijinal_id           = [int]$origRow.source_id
        orijinal_name         = $origRow.source_name
        orijinal_pixel_count  = [int64]$origRow.pixel_count
        orijinal_bbox         = $origRow.bbox
        same_id               = ([int]$modRow.source_id -eq [int]$origRow.source_id)
        same_name             = ($modRow.source_name -eq $origRow.source_name)
    }

    if ($joined.same_id) {
        $sameIdRows.Add($joined) | Out-Null
    }
    else {
        $conflictRows.Add($joined) | Out-Null
    }
}

$sameIdRows | Export-Csv -Path $outSharedSameId -NoTypeInformation -Encoding UTF8
$conflictRows | Export-Csv -Path $outSharedConflict -NoTypeInformation -Encoding UTF8
$missingRows | Export-Csv -Path $outMissing -NoTypeInformation -Encoding UTF8

$decisionTemplateRows = foreach ($row in $conflictRows) {
    [pscustomobject]@{
        rgb                   = $row.rgb
        modlu_id              = $row.modlu_id
        modlu_name            = $row.modlu_name
        modlu_pixel_count     = $row.modlu_pixel_count
        modlu_bbox            = $row.modlu_bbox
        orijinal_id           = $row.orijinal_id
        orijinal_name         = $row.orijinal_name
        orijinal_pixel_count  = $row.orijinal_pixel_count
        orijinal_bbox         = $row.orijinal_bbox
        keep_rgb_source       = ''
        recolor_source        = ''
        new_rgb               = ''
        decision_notes        = ''
    }
}
$decisionTemplateRows | Export-Csv -Path $outDecisionTemplate -NoTypeInformation -Encoding UTF8

$summaryLines = @(
    '# Source RGB Overlap Audit',
    '',
    'Method:',
    '- source west image: `Works/map_data_sources/provinces_modlu_kalan.png`',
    '- source east image: `Works/map_data_sources/provinces_orijinal_dogu.png`',
    '- west definition subset: `Works/map_data_sources/definition_modlu_kalan.csv`',
    '- east definition subset: `Works/map_data_sources/definition_orijinal_dogu.csv`',
    '- overlap decision rule:',
    '  - same RGB + same ID = benign',
    '  - same RGB + different ID = real conflict',
    '',
    ('- modlu_kalan unique non-black RGB: `{0}`' -f $modInventory.Count),
    ('- orijinal_dogu unique non-black RGB: `{0}`' -f $origInventory.Count),
    ('- shared RGB count: `{0}`' -f $sharedRgbs.Count),
    ('- benign shared (same RGB + same ID): `{0}`' -f $sameIdRows.Count),
    ('- real conflicts (same RGB + different ID): `{0}`' -f $conflictRows.Count),
    ('- missing definition rows across both subsets: `{0}`' -f $missingRows.Count),
    ''
)

if ($conflictRows.Count -gt 0) {
    $summaryLines += 'Conflict rows:'
    foreach ($row in $conflictRows) {
        $summaryLines += ('- `{0}` -> mod `{1}` `{2}` / orijinal `{3}` `{4}`' -f $row.rgb, $row.modlu_id, $row.modlu_name, $row.orijinal_id, $row.orijinal_name)
    }
}

Set-Content -Path $outSummary -Value ($summaryLines -join "`r`n") -Encoding UTF8

Write-Host "Wrote $outSummary"
Write-Host "Wrote $outSharedConflict"
