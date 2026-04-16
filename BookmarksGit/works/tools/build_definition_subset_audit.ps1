param(
    [string]$RepoRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -ReferencedAssemblies 'System.Drawing.dll' -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class ProvinceImageTools {
    public static HashSet<int> GetColors(string path) {
        using (var bmp = new Bitmap(path)) {
            var rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
            var data = bmp.LockBits(rect, ImageLockMode.ReadOnly, bmp.PixelFormat);
            try {
                int bpp = Image.GetPixelFormatSize(data.PixelFormat) / 8;
                byte[] buffer = new byte[data.Stride * bmp.Height];
                Marshal.Copy(data.Scan0, buffer, 0, buffer.Length);
                var colors = new HashSet<int>();
                for (int y = 0; y < bmp.Height; y++) {
                    int row = y * data.Stride;
                    for (int x = 0; x < bmp.Width; x++) {
                        int idx = row + x * bpp;
                        int key = (buffer[idx + 2] << 16) | (buffer[idx + 1] << 8) | buffer[idx];
                        colors.Add(key);
                    }
                }
                return colors;
            }
            finally {
                bmp.UnlockBits(data);
            }
        }
    }

    public sealed class ColorStat {
        public int Count;
        public int MinX;
        public int MinY;
        public int MaxX;
        public int MaxY;
    }

    public static Dictionary<int, ColorStat> GetColorStats(string path) {
        using (var bmp = new Bitmap(path)) {
            var rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
            var data = bmp.LockBits(rect, ImageLockMode.ReadOnly, bmp.PixelFormat);
            try {
                int bpp = Image.GetPixelFormatSize(data.PixelFormat) / 8;
                byte[] buffer = new byte[data.Stride * bmp.Height];
                Marshal.Copy(data.Scan0, buffer, 0, buffer.Length);
                var stats = new Dictionary<int, ColorStat>();
                for (int y = 0; y < bmp.Height; y++) {
                    int row = y * data.Stride;
                    for (int x = 0; x < bmp.Width; x++) {
                        int idx = row + x * bpp;
                        int key = (buffer[idx + 2] << 16) | (buffer[idx + 1] << 8) | buffer[idx];
                        ColorStat stat;
                        if (!stats.TryGetValue(key, out stat)) {
                            stat = new ColorStat();
                            stat.Count = 1;
                            stat.MinX = x;
                            stat.MaxX = x;
                            stat.MinY = y;
                            stat.MaxY = y;
                            stats[key] = stat;
                        }
                        else {
                            stat.Count += 1;
                            if (x < stat.MinX) { stat.MinX = x; }
                            if (x > stat.MaxX) { stat.MaxX = x; }
                            if (y < stat.MinY) { stat.MinY = y; }
                            if (y > stat.MaxY) { stat.MaxY = y; }
                        }
                    }
                }
                return stats;
            }
            finally {
                bmp.UnlockBits(data);
            }
        }
    }

    public static void SaveColorPreview(string sourcePath, string outputPath, int rgbKey, int padding, int minX, int minY, int maxX, int maxY) {
        using (var bmp = new Bitmap(sourcePath)) {
            if (rgbKey == 0) {
                return;
            }

            int left = Math.Max(0, minX - padding);
            int top = Math.Max(0, minY - padding);
            int right = Math.Min(bmp.Width - 1, maxX + padding);
            int bottom = Math.Min(bmp.Height - 1, maxY + padding);
            int width = right - left + 1;
            int height = bottom - top + 1;

            using (var preview = new Bitmap(width, height, PixelFormat.Format32bppArgb)) {
                int r = (rgbKey >> 16) & 255;
                int g = (rgbKey >> 8) & 255;
                int b = rgbKey & 255;
                var target = Color.FromArgb(255, r, g, b);
                var background = Color.FromArgb(0, 0, 0, 0);

                for (int y = 0; y < height; y++) {
                    for (int x = 0; x < width; x++) {
                        var px = bmp.GetPixel(left + x, top + y);
                        if (px.R == r && px.G == g && px.B == b) {
                            preview.SetPixel(x, y, target);
                        }
                        else {
                            preview.SetPixel(x, y, background);
                        }
                    }
                }

                preview.Save(outputPath, ImageFormat.Png);
            }
        }
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

function Format-Rgb {
    param([int]$RgbKey)
    $r = ($RgbKey -shr 16) -band 255
    $g = ($RgbKey -shr 8) -band 255
    $b = $RgbKey -band 255
    return "$r,$g,$b"
}

function Load-DefinitionFile {
    param(
        [string]$Path,
        [string]$SourceLabel
    )

    $lines = Get-Content -Path $Path
    $entries = New-Object System.Collections.Generic.List[object]
    $byRgb = @{}
    $byId = @{}
    $rowZeroLine = $null

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
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

        $id = [int]$parts[0]
        $r = [int]$parts[1]
        $g = [int]$parts[2]
        $b = [int]$parts[3]
        $rgbKey = Get-RgbKey -R $r -G $g -B $b
        $name = $parts[4]
        $xValue = $parts[5]

        $entry = [pscustomobject]@{
            source_label = $SourceLabel
            source_path = $Path
            order = $i
            id = $id
            r = $r
            g = $g
            b = $b
            rgb = (Format-Rgb -RgbKey $rgbKey)
            rgb_key = $rgbKey
            name = $name
            x_value = $xValue
            original_line = $line
        }

        $entries.Add($entry) | Out-Null

        if ($id -eq 0 -and $rgbKey -eq 0 -and $null -eq $rowZeroLine) {
            $rowZeroLine = $line
        }

        if (-not $byRgb.ContainsKey($rgbKey)) {
            $byRgb[$rgbKey] = $entry
        }

        if (-not $byId.ContainsKey($id)) {
            $byId[$id] = New-Object System.Collections.Generic.List[object]
        }
        $byId[$id].Add($entry) | Out-Null
    }

    $entryArray = $entries.ToArray()

    return [pscustomobject]@{
        path = $Path
        source_label = $SourceLabel
        entries = $entryArray
        by_rgb = $byRgb
        by_id = $byId
        row_zero_line = $rowZeroLine
        non_black_entries = @($entryArray | Where-Object { $_.rgb_key -ne 0 })
    }
}

function Test-PlaceholderName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $true
    }

    return ($Name -match 'PLACEHOLDER')
}

function New-SubsetDefinition {
    param(
        [pscustomobject]$DefinitionData,
        [string]$ImagePath,
        [string]$SubsetName,
        [string]$OutputPath
    )

    $imageColors = [ProvinceImageTools]::GetColors($ImagePath)
    $selectedRgbKeys = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($rgbKey in $imageColors) {
        if ($rgbKey -ne 0) {
            [void]$selectedRgbKeys.Add($rgbKey)
        }
    }

    $selectedEntries = @(
        $DefinitionData.non_black_entries |
            Where-Object { $selectedRgbKeys.Contains($_.rgb_key) } |
            Sort-Object order
    )

    $missingColors = @()
    foreach ($rgbKey in $selectedRgbKeys) {
        if (-not $DefinitionData.by_rgb.ContainsKey($rgbKey)) {
            $missingColors += $rgbKey
        }
    }

    $rgbInventoryRows = New-Object System.Collections.Generic.List[object]
    foreach ($rgbKey in @($selectedRgbKeys | Sort-Object)) {
        $r = ($rgbKey -shr 16) -band 255
        $g = ($rgbKey -shr 8) -band 255
        $b = $rgbKey -band 255
        $hasDefinition = $DefinitionData.by_rgb.ContainsKey($rgbKey)
        $entry = if ($hasDefinition) { $DefinitionData.by_rgb[$rgbKey] } else { $null }
        $rgbInventoryRows.Add([pscustomobject]@{
            subset_name = $SubsetName
            source_label = $DefinitionData.source_label
            rgb = (Format-Rgb -RgbKey $rgbKey)
            r = $r
            g = $g
            b = $b
            present_in_png = $true
            present_in_definition = $hasDefinition
            source_id = if ($entry) { $entry.id } else { $null }
            source_name = if ($entry) { $entry.name } else { '' }
            definition_path = $DefinitionData.path
            image_path = $ImagePath
        }) | Out-Null
    }

    $outputLines = New-Object System.Collections.Generic.List[string]
    if ($null -ne $DefinitionData.row_zero_line) {
        $outputLines.Add($DefinitionData.row_zero_line) | Out-Null
    }
    foreach ($entry in $selectedEntries) {
        $outputLines.Add($entry.original_line) | Out-Null
    }

    [System.IO.File]::WriteAllLines($OutputPath, $outputLines, [System.Text.UTF8Encoding]::new($false))

    return [pscustomobject]@{
        subset_name = $SubsetName
        image_path = $ImagePath
        output_path = $OutputPath
        definition_path = $DefinitionData.path
        source_label = $DefinitionData.source_label
        image_non_black_unique = $selectedRgbKeys.Count
        extracted_entries_count = $selectedEntries.Count
        missing_colors_in_definition = $missingColors.Count
        unused_definition_colors = ($DefinitionData.non_black_entries.Count - $selectedEntries.Count)
        missing_color_samples = @($missingColors | Select-Object -First 15 | ForEach-Object {
            [pscustomobject]@{ rgb = (Format-Rgb -RgbKey $_) }
        })
        selected_rgb_keys = @($selectedRgbKeys | Sort-Object)
        rgb_inventory_rows = $rgbInventoryRows.ToArray()
        entries = $selectedEntries
    }
}

function Build-Lookups {
    param([object[]]$Entries)

    $byRgb = @{}
    $byId = @{}

    foreach ($entry in $Entries) {
        $byRgb[$entry.rgb_key] = $entry
        if (-not $byId.ContainsKey($entry.id)) {
            $byId[$entry.id] = New-Object System.Collections.Generic.List[object]
        }
        $byId[$entry.id].Add($entry) | Out-Null
    }

    return [pscustomobject]@{
        by_rgb = $byRgb
        by_id = $byId
    }
}

function Export-Utf8Csv {
    param(
        $Rows,
        [string]$Path
    )

    if ($null -eq $Rows) {
        @() | Export-Csv -Path $Path -NoTypeInformation -Encoding utf8
        return
    }

    if ($Rows -is [System.Collections.Generic.List[object]]) {
        $exportRows = $Rows.ToArray()
    }
    else {
        $exportRows = @($Rows)
    }

    $exportRows | Export-Csv -Path $Path -NoTypeInformation -Encoding utf8
}

function Format-Bbox {
    param($Stat)

    if ($null -eq $Stat) {
        return ''
    }

    return ('{0},{1} -> {2},{3}' -f $Stat.MinX, $Stat.MinY, $Stat.MaxX, $Stat.MaxY)
}

function Get-RgbFileStem {
    param([string]$Rgb)

    return ($Rgb -replace ',', '_')
}

function Get-SuggestedRgbKeys {
    param(
        [System.Collections.IEnumerable]$UsedRgbKeys,
        [int]$Count
    )

    $used = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($key in $UsedRgbKeys) {
        [void]$used.Add([int]$key)
    }
    [void]$used.Add(0)

    $suggested = New-Object System.Collections.Generic.List[int]
    $palette = @(16, 48, 80, 112, 144, 176, 208, 240)

    :paletteLoop foreach ($r in $palette) {
        foreach ($g in $palette) {
            foreach ($b in $palette) {
                $rgbKey = Get-RgbKey -R $r -G $g -B $b
                if (-not $used.Contains($rgbKey)) {
                    [void]$suggested.Add($rgbKey)
                    [void]$used.Add($rgbKey)
                    if ($suggested.Count -ge $Count) {
                        break paletteLoop
                    }
                }
            }
        }
    }

    if ($suggested.Count -lt $Count) {
        :fallbackLoop for ($r = 1; $r -le 255; $r++) {
            for ($g = 1; $g -le 255; $g++) {
                for ($b = 1; $b -le 255; $b++) {
                    $rgbKey = Get-RgbKey -R $r -G $g -B $b
                    if (-not $used.Contains($rgbKey)) {
                        [void]$suggested.Add($rgbKey)
                        [void]$used.Add($rgbKey)
                        if ($suggested.Count -ge $Count) {
                            break fallbackLoop
                        }
                    }
                }
            }
        }
    }

    return $suggested.ToArray()
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$mapDataDir = Join-Path $root 'map_data'
$analysisDir = Join-Path $root 'analysis'
$generatedDir = Join-Path $analysisDir 'generated'
$toolsDir = Join-Path $root 'tools'
$rgbConflictPreviewDir = Join-Path $generatedDir 'rgb_conflict_previews'
Ensure-Directory -Path $generatedDir
Ensure-Directory -Path $toolsDir
Ensure-Directory -Path $rgbConflictPreviewDir

$definitionModlu = Load-DefinitionFile -Path (Join-Path $mapDataDir 'definition_modlu.csv') -SourceLabel 'modlu'
$definitionOrijinal = Load-DefinitionFile -Path (Join-Path $mapDataDir 'definition_orijinal.csv') -SourceLabel 'orijinal'

$subsetResults = [ordered]@{}
$subsetResults['modlu_dogu'] = New-SubsetDefinition `
    -DefinitionData $definitionModlu `
    -ImagePath (Join-Path $mapDataDir 'provinces_modlu_dogu.png') `
    -SubsetName 'modlu_dogu' `
    -OutputPath (Join-Path $mapDataDir 'definition_modlu_dogu.csv')

$subsetResults['modlu_kalan'] = New-SubsetDefinition `
    -DefinitionData $definitionModlu `
    -ImagePath (Join-Path $mapDataDir 'provinces_modlu_kalan.png') `
    -SubsetName 'modlu_kalan' `
    -OutputPath (Join-Path $mapDataDir 'definition_modlu_kalan.csv')

$subsetResults['orijinal_dogu'] = New-SubsetDefinition `
    -DefinitionData $definitionOrijinal `
    -ImagePath (Join-Path $mapDataDir 'provinces_orijinal_dogu.png') `
    -SubsetName 'orijinal_dogu' `
    -OutputPath (Join-Path $mapDataDir 'definition_orijinal_dogu.csv')

$subsetResults['orijinal_kalan'] = New-SubsetDefinition `
    -DefinitionData $definitionOrijinal `
    -ImagePath (Join-Path $mapDataDir 'provinces_orijinal_kalan.png') `
    -SubsetName 'orijinal_kalan' `
    -OutputPath (Join-Path $mapDataDir 'definition_orijinal_kalan.csv')

$subsetValidationRows = New-Object System.Collections.Generic.List[object]
foreach ($subsetName in $subsetResults.Keys) {
    $subset = $subsetResults[$subsetName]
    $rgbInventoryPath = Join-Path $generatedDir ("definition_{0}_rgb_inventory.csv" -f $subsetName)
    Export-Utf8Csv -Rows $subset.rgb_inventory_rows -Path $rgbInventoryPath

    $subsetValidationRows.Add([pscustomobject]@{
        subset_name = $subsetName
        source_label = $subset.source_label
        image_path = $subset.image_path
        definition_path = $subset.definition_path
        output_path = $subset.output_path
        rgb_inventory_path = $rgbInventoryPath
        image_non_black_unique = $subset.image_non_black_unique
        extracted_entries_count = $subset.extracted_entries_count
        missing_colors_in_definition = $subset.missing_colors_in_definition
        rgb_inventory_rows = $subset.rgb_inventory_rows.Count
        extraction_matches_png_color_count = ($subset.image_non_black_unique -eq $subset.extracted_entries_count)
        inventory_matches_png_color_count = ($subset.image_non_black_unique -eq $subset.rgb_inventory_rows.Count)
        validation_pass = (
            $subset.missing_colors_in_definition -eq 0 -and
            $subset.image_non_black_unique -eq $subset.extracted_entries_count -and
            $subset.image_non_black_unique -eq $subset.rgb_inventory_rows.Count
        )
    }) | Out-Null
}

$modluKalanLookups = Build-Lookups -Entries $subsetResults['modlu_kalan'].entries
$orijinalDoguLookups = Build-Lookups -Entries $subsetResults['orijinal_dogu'].entries
$modluKalanColorStats = [ProvinceImageTools]::GetColorStats((Join-Path $mapDataDir 'provinces_modlu_kalan.png'))
$orijinalDoguColorStats = [ProvinceImageTools]::GetColorStats((Join-Path $mapDataDir 'provinces_orijinal_dogu.png'))

$sharedSameIdRows = New-Object System.Collections.Generic.List[object]
$rgbConflictRows = New-Object System.Collections.Generic.List[object]
$rgbDecisionRows = New-Object System.Collections.Generic.List[object]
$idConflictRows = New-Object System.Collections.Generic.List[object]
$nameDivergenceRows = New-Object System.Collections.Generic.List[object]
$qualityRows = New-Object System.Collections.Generic.List[object]
$mergeInventoryRows = New-Object System.Collections.Generic.List[object]
$idTrackingRows = New-Object System.Collections.Generic.List[object]

foreach ($rgbKey in $modluKalanLookups.by_rgb.Keys) {
    if (-not $orijinalDoguLookups.by_rgb.ContainsKey($rgbKey)) {
        continue
    }

    $modEntry = $modluKalanLookups.by_rgb[$rgbKey]
    $oriEntry = $orijinalDoguLookups.by_rgb[$rgbKey]

    if ($modEntry.id -eq $oriEntry.id) {
        $sharedSameIdRows.Add([pscustomobject]@{
            rgb = $modEntry.rgb
            shared_id = $modEntry.id
            modlu_name = $modEntry.name
            orijinal_name = $oriEntry.name
            names_equal = ($modEntry.name -eq $oriEntry.name)
        }) | Out-Null

        if ($modEntry.name -ne $oriEntry.name) {
            $nameDivergenceRows.Add([pscustomobject]@{
                relation = 'same_rgb_same_id_name_diff'
                rgb = $modEntry.rgb
                shared_id = $modEntry.id
                modlu_name = $modEntry.name
                orijinal_name = $oriEntry.name
            }) | Out-Null
        }
    }
    else {
        $modStat = if ($modluKalanColorStats.ContainsKey($rgbKey)) { $modluKalanColorStats[$rgbKey] } else { $null }
        $oriStat = if ($orijinalDoguColorStats.ContainsKey($rgbKey)) { $orijinalDoguColorStats[$rgbKey] } else { $null }
        $rgbStem = Get-RgbFileStem -Rgb $modEntry.rgb
        $modPreviewPath = Join-Path $rgbConflictPreviewDir ("rgb_{0}_modlu.png" -f $rgbStem)
        $oriPreviewPath = Join-Path $rgbConflictPreviewDir ("rgb_{0}_orijinal.png" -f $rgbStem)
        $modPixelCount = if ($modStat) { $modStat.Count } else { 0 }
        $oriPixelCount = if ($oriStat) { $oriStat.Count } else { 0 }
        $suggestRecolorSource = ''
        $suggestKeepSource = ''
        $suggestionReason = ''

        if ($modPixelCount -gt 0 -and $oriPixelCount -gt 0) {
            if ($modPixelCount -lt $oriPixelCount) {
                $suggestRecolorSource = 'modlu'
                $suggestKeepSource = 'orijinal'
                $suggestionReason = 'Smaller pixel footprint may be cheaper to recolor.'
            }
            elseif ($oriPixelCount -lt $modPixelCount) {
                $suggestRecolorSource = 'orijinal'
                $suggestKeepSource = 'modlu'
                $suggestionReason = 'Smaller pixel footprint may be cheaper to recolor.'
            }
            else {
                $suggestionReason = 'Pixel counts are equal; no automatic recolor-side suggestion.'
            }
        }

        $rgbConflictRows.Add([pscustomobject]@{
            rgb = $modEntry.rgb
            modlu_id = $modEntry.id
            modlu_name = $modEntry.name
            orijinal_id = $oriEntry.id
            orijinal_name = $oriEntry.name
        }) | Out-Null

        if ($null -ne $modStat) {
            [ProvinceImageTools]::SaveColorPreview(
                (Join-Path $mapDataDir 'provinces_modlu_kalan.png'),
                $modPreviewPath,
                $rgbKey,
                8,
                $modStat.MinX,
                $modStat.MinY,
                $modStat.MaxX,
                $modStat.MaxY
            )
        }
        if ($null -ne $oriStat) {
            [ProvinceImageTools]::SaveColorPreview(
                (Join-Path $mapDataDir 'provinces_orijinal_dogu.png'),
                $oriPreviewPath,
                $rgbKey,
                8,
                $oriStat.MinX,
                $oriStat.MinY,
                $oriStat.MaxX,
                $oriStat.MaxY
            )
        }

        $rgbDecisionRows.Add([pscustomobject]@{
            rgb = $modEntry.rgb
            modlu_id = $modEntry.id
            modlu_name = $modEntry.name
            modlu_pixel_count = $modPixelCount
            modlu_bbox = (Format-Bbox -Stat $modStat)
            modlu_preview_path = $modPreviewPath
            orijinal_id = $oriEntry.id
            orijinal_name = $oriEntry.name
            orijinal_pixel_count = $oriPixelCount
            orijinal_bbox = (Format-Bbox -Stat $oriStat)
            orijinal_preview_path = $oriPreviewPath
            suggest_keep_original_rgb_source = $suggestKeepSource
            suggest_recolor_source = $suggestRecolorSource
            suggestion_reason = $suggestionReason
            conflict_status = 'pending_manual_rgb_resolution'
            keep_original_rgb_source = ''
            recolor_source = ''
            recolor_required = 'yes'
            new_rgb = ''
            final_modlu_id = ''
            final_orijinal_id = ''
            tracking_note = 'If both provinces remain separate, one side must receive a new RGB in provinces_birlesim.png.'
            decision_notes = ''
        }) | Out-Null
    }
}

foreach ($id in $modluKalanLookups.by_id.Keys) {
    if (-not $orijinalDoguLookups.by_id.ContainsKey($id)) {
        continue
    }

    foreach ($modEntry in $modluKalanLookups.by_id[$id]) {
        foreach ($oriEntry in $orijinalDoguLookups.by_id[$id]) {
            if ($modEntry.rgb_key -ne $oriEntry.rgb_key) {
                $idConflictRows.Add([pscustomobject]@{
                    shared_id = $id
                    modlu_rgb = $modEntry.rgb
                    modlu_name = $modEntry.name
                    orijinal_rgb = $oriEntry.rgb
                    orijinal_name = $oriEntry.name
                }) | Out-Null
            }
            elseif ($modEntry.name -ne $oriEntry.name) {
                $nameDivergenceRows.Add([pscustomobject]@{
                    relation = 'same_id_same_rgb_name_diff'
                    rgb = $modEntry.rgb
                    shared_id = $id
                    modlu_name = $modEntry.name
                    orijinal_name = $oriEntry.name
                }) | Out-Null
            }
        }
    }
}

$allSubsetEntries = @()
foreach ($entry in $subsetResults['modlu_kalan'].entries) {
    $allSubsetEntries += [pscustomobject]@{
        source_subset = 'modlu_kalan'
        source_definition = 'definition_modlu.csv'
        entry = $entry
    }
}
foreach ($entry in $subsetResults['orijinal_dogu'].entries) {
    $allSubsetEntries += [pscustomobject]@{
        source_subset = 'orijinal_dogu'
        source_definition = 'definition_orijinal.csv'
        entry = $entry
    }
}

foreach ($wrapper in $allSubsetEntries) {
    $entry = $wrapper.entry

    if ($wrapper.source_subset -eq 'modlu_kalan') {
        $rgbPartner = if ($orijinalDoguLookups.by_rgb.ContainsKey($entry.rgb_key)) { $orijinalDoguLookups.by_rgb[$entry.rgb_key] } else { $null }
        $idPartners = if ($orijinalDoguLookups.by_id.ContainsKey($entry.id)) { $orijinalDoguLookups.by_id[$entry.id].ToArray() } else { @() }
    }
    else {
        $rgbPartner = if ($modluKalanLookups.by_rgb.ContainsKey($entry.rgb_key)) { $modluKalanLookups.by_rgb[$entry.rgb_key] } else { $null }
        $idPartners = if ($modluKalanLookups.by_id.ContainsKey($entry.id)) { $modluKalanLookups.by_id[$entry.id].ToArray() } else { @() }
    }

    $sameRgbSameId = $false
    $sameRgbDiffId = $false
    $sameIdDiffRgb = $false
    $nameDivergence = $false

    if ($null -ne $rgbPartner) {
        if ($rgbPartner.id -eq $entry.id) {
            $sameRgbSameId = $true
            if ($rgbPartner.name -ne $entry.name) {
                $nameDivergence = $true
            }
        }
        else {
            $sameRgbDiffId = $true
        }
    }

    foreach ($idPartner in $idPartners) {
        if ($idPartner.rgb_key -ne $entry.rgb_key) {
            $sameIdDiffRgb = $true
        }
    }

    $emptyName = [string]::IsNullOrWhiteSpace($entry.name)
    $placeholderName = Test-PlaceholderName -Name $entry.name

    if ($sameRgbDiffId) {
        $primaryStatus = 'rgb_conflict'
        $finalIdStatus = 'pending_manual_assignment'
    }
    elseif ($sameIdDiffRgb) {
        $primaryStatus = 'id_conflict'
        $finalIdStatus = 'pending_manual_assignment'
    }
    elseif ($sameRgbSameId) {
        $primaryStatus = 'benign_shared'
        $finalIdStatus = 'pending_keep_candidate'
    }
    elseif ($wrapper.source_subset -eq 'modlu_kalan') {
        $primaryStatus = 'mod_only'
        $finalIdStatus = 'pending_keep_candidate'
    }
    else {
        $primaryStatus = 'orijinal_only'
        $finalIdStatus = 'pending_keep_candidate'
    }

    $notes = @()
    if ($sameRgbDiffId) {
        $notes += 'Same RGB maps to different IDs across subsets.'
    }
    if ($sameIdDiffRgb) {
        $notes += 'Same ID maps to different RGB values across subsets.'
    }
    if ($nameDivergence) {
        $notes += 'Name/comment differs across sources for the same identity.'
    }
    if ($emptyName) {
        $notes += 'Name is empty.'
    }
    elseif ($placeholderName -and $entry.name -match 'PLACEHOLDER') {
        $notes += 'Name looks like a placeholder.'
    }

    $rgbPartnerSubset = if ($wrapper.source_subset -eq 'modlu_kalan') { 'orijinal_dogu' } else { 'modlu_kalan' }
    $rgbPartnerId = if ($null -ne $rgbPartner) { $rgbPartner.id } else { $null }
    $rgbPartnerRgb = if ($null -ne $rgbPartner) { $rgbPartner.rgb } else { '' }
    $rgbPartnerName = if ($null -ne $rgbPartner) { $rgbPartner.name } else { '' }

    $idPartnerDifferentRgb = @($idPartners | Where-Object { $_.rgb_key -ne $entry.rgb_key })
    $idPartnerRgb = if ($idPartnerDifferentRgb.Count -gt 0) { ($idPartnerDifferentRgb | Select-Object -First 1).rgb } else { '' }
    $idPartnerName = if ($idPartnerDifferentRgb.Count -gt 0) { ($idPartnerDifferentRgb | Select-Object -First 1).name } else { '' }
    $idPartnerSubset = if ($idPartnerDifferentRgb.Count -gt 0) { if ($wrapper.source_subset -eq 'modlu_kalan') { 'orijinal_dogu' } else { 'modlu_kalan' } } else { '' }

    $mergeInventoryRow = [pscustomobject]@{
        source_subset = $wrapper.source_subset
        source_definition = $wrapper.source_definition
        source_id = $entry.id
        source_rgb = $entry.rgb
        source_name = $entry.name
        primary_status = $primaryStatus
        same_rgb_same_id = $sameRgbSameId
        same_rgb_diff_id = $sameRgbDiffId
        same_id_diff_rgb = $sameIdDiffRgb
        name_divergence = $nameDivergence
        empty_name = $emptyName
        placeholder_name = $placeholderName
        rgb_partner_subset = $rgbPartnerSubset
        rgb_partner_id = $rgbPartnerId
        rgb_partner_rgb = $rgbPartnerRgb
        rgb_partner_name = $rgbPartnerName
        id_partner_subset = $idPartnerSubset
        id_partner_rgb = $idPartnerRgb
        id_partner_name = $idPartnerName
        final_new_id = ''
        final_id_status = $finalIdStatus
        notes = ($notes -join ' ')
    }
    $mergeInventoryRows.Add($mergeInventoryRow) | Out-Null

    $idTrackingRows.Add([pscustomobject]@{
        source_subset = $wrapper.source_subset
        source_definition = $wrapper.source_definition
        source_id = $entry.id
        source_rgb = $entry.rgb
        source_name = $entry.name
        primary_status = $primaryStatus
        final_new_id = ''
        final_id_status = $finalIdStatus
        requires_reference_update_if_changed = 'yes'
        future_reference_note = 'If final_new_id differs from source_id, province-referencing game files must be updated later.'
        rgb_partner_id = $rgbPartnerId
        id_partner_rgb = $idPartnerRgb
        notes = ($notes -join ' ')
    }) | Out-Null

    if ($emptyName -or $placeholderName -or $nameDivergence) {
        $qualityRows.Add([pscustomobject]@{
            source_subset = $wrapper.source_subset
            source_definition = $wrapper.source_definition
            source_id = $entry.id
            source_rgb = $entry.rgb
            source_name = $entry.name
            empty_name = $emptyName
            placeholder_name = $placeholderName
            name_divergence = $nameDivergence
            primary_status = $primaryStatus
            notes = ($notes -join ' ')
        }) | Out-Null
    }
}

$rgbConflictPath = Join-Path $generatedDir 'definition_rgb_conflicts.csv'
$rgbDecisionPath = Join-Path $generatedDir 'definition_rgb_conflict_decisions.csv'
$rgbMappingDraftPath = Join-Path $generatedDir 'rgb_mapping_draft.csv'
$idConflictPath = Join-Path $generatedDir 'definition_id_conflicts.csv'
$sharedSameIdPath = Join-Path $generatedDir 'definition_shared_same_id.csv'
$qualityPath = Join-Path $generatedDir 'definition_quality_flags.csv'
$mergeInventoryPath = Join-Path $generatedDir 'definition_merge_inventory.csv'
$idTrackingPath = Join-Path $generatedDir 'definition_id_tracking.csv'
$subsetValidationPath = Join-Path $generatedDir 'definition_subset_validation.csv'
$summaryPath = Join-Path $generatedDir 'definition_subset_audit.md'

$rgbConflictExportRows = @($rgbConflictRows | Sort-Object modlu_id, orijinal_id, rgb)
$rgbDecisionExportRows = @($rgbDecisionRows | Sort-Object modlu_id, orijinal_id, rgb)
$idConflictExportRows = @($idConflictRows | Sort-Object shared_id, modlu_rgb, orijinal_rgb)
$sharedSameIdExportRows = @($sharedSameIdRows | Sort-Object shared_id, rgb)
$qualityExportRows = @($qualityRows | Sort-Object source_subset, source_id, source_rgb)
$mergeInventoryExportRows = @($mergeInventoryRows | Sort-Object source_subset, source_id, source_rgb)
$idTrackingExportRows = @($idTrackingRows | Sort-Object source_subset, source_id, source_rgb)
$subsetValidationExportRows = @($subsetValidationRows | Sort-Object subset_name)

$allUsedRgbKeys = New-Object System.Collections.Generic.List[int]
foreach ($rgbKey in $definitionModlu.by_rgb.Keys) {
    $allUsedRgbKeys.Add([int]$rgbKey) | Out-Null
}
foreach ($rgbKey in $definitionOrijinal.by_rgb.Keys) {
    $allUsedRgbKeys.Add([int]$rgbKey) | Out-Null
}
$suggestedNewRgbKeys = Get-SuggestedRgbKeys -UsedRgbKeys $allUsedRgbKeys -Count $rgbDecisionExportRows.Count
$rgbDecisionSuggestedRows = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $rgbDecisionExportRows.Count; $i++) {
    $row = $rgbDecisionExportRows[$i]
    $suggestedRgb = if ($i -lt $suggestedNewRgbKeys.Count) { Format-Rgb -RgbKey $suggestedNewRgbKeys[$i] } else { '' }
    $rgbDecisionSuggestedRows.Add([pscustomobject]@{
        rgb = $row.rgb
        modlu_id = $row.modlu_id
        modlu_name = $row.modlu_name
        modlu_pixel_count = $row.modlu_pixel_count
        modlu_bbox = $row.modlu_bbox
        modlu_preview_path = $row.modlu_preview_path
        orijinal_id = $row.orijinal_id
        orijinal_name = $row.orijinal_name
        orijinal_pixel_count = $row.orijinal_pixel_count
        orijinal_bbox = $row.orijinal_bbox
        orijinal_preview_path = $row.orijinal_preview_path
        suggest_keep_original_rgb_source = $row.suggest_keep_original_rgb_source
        suggest_recolor_source = $row.suggest_recolor_source
        suggestion_reason = $row.suggestion_reason
        suggest_new_rgb = $suggestedRgb
        suggest_new_rgb_reason = 'Unused RGB proposal generated against the combined modlu+orijinal definition color space.'
        conflict_status = $row.conflict_status
        keep_original_rgb_source = $row.keep_original_rgb_source
        recolor_source = $row.recolor_source
        recolor_required = $row.recolor_required
        new_rgb = $row.new_rgb
        final_modlu_id = $row.final_modlu_id
        final_orijinal_id = $row.final_orijinal_id
        tracking_note = $row.tracking_note
        decision_notes = $row.decision_notes
    }) | Out-Null
}

$rgbMappingDraftRows = New-Object System.Collections.Generic.List[object]
foreach ($row in $rgbDecisionSuggestedRows) {
    if ([string]::IsNullOrWhiteSpace($row.suggest_recolor_source) -or [string]::IsNullOrWhiteSpace($row.suggest_new_rgb)) {
        continue
    }

    $affectedSubset = if ($row.suggest_recolor_source -eq 'modlu') { 'modlu_kalan' } else { 'orijinal_dogu' }
    $affectedId = if ($row.suggest_recolor_source -eq 'modlu') { $row.modlu_id } else { $row.orijinal_id }
    $affectedName = if ($row.suggest_recolor_source -eq 'modlu') { $row.modlu_name } else { $row.orijinal_name }
    $affectedPreviewPath = if ($row.suggest_recolor_source -eq 'modlu') { $row.modlu_preview_path } else { $row.orijinal_preview_path }

    $rgbMappingDraftRows.Add([pscustomobject]@{
        shared_old_rgb = $row.rgb
        keep_original_rgb_source = $row.suggest_keep_original_rgb_source
        recolor_source = $row.suggest_recolor_source
        affected_subset = $affectedSubset
        affected_source_id = $affectedId
        affected_source_name = $affectedName
        affected_preview_path = $affectedPreviewPath
        suggested_new_rgb = $row.suggest_new_rgb
        basis = 'heuristic_draft'
        basis_reason = $row.suggestion_reason
        notes = 'Draft only. Review before applying to provinces_birlesim.png or final definition outputs.'
    }) | Out-Null
}

Export-Utf8Csv -Rows $rgbConflictExportRows -Path $rgbConflictPath
Export-Utf8Csv -Rows $rgbDecisionSuggestedRows -Path $rgbDecisionPath
Export-Utf8Csv -Rows $rgbMappingDraftRows -Path $rgbMappingDraftPath
Export-Utf8Csv -Rows $idConflictExportRows -Path $idConflictPath
Export-Utf8Csv -Rows $sharedSameIdExportRows -Path $sharedSameIdPath
Export-Utf8Csv -Rows $qualityExportRows -Path $qualityPath
Export-Utf8Csv -Rows $mergeInventoryExportRows -Path $mergeInventoryPath
Export-Utf8Csv -Rows $idTrackingExportRows -Path $idTrackingPath
Export-Utf8Csv -Rows $subsetValidationExportRows -Path $subsetValidationPath

$sameNameSharedCount = @($sharedSameIdExportRows | Where-Object { $_.names_equal }).Count
$differentNameSharedCount = @($sharedSameIdExportRows | Where-Object { -not $_.names_equal }).Count
$emptyNameCount = @($mergeInventoryExportRows | Where-Object { $_.empty_name }).Count
$placeholderNameCount = @($mergeInventoryExportRows | Where-Object { $_.placeholder_name }).Count
$pendingManualAssignmentCount = @($idTrackingExportRows | Where-Object { $_.final_id_status -eq 'pending_manual_assignment' }).Count

$summaryLines = @(
    '# Definition Subset Audit',
    '',
    '## Generated Files',
    '',
    '- `map_data/definition_modlu_dogu.csv`',
    '- `map_data/definition_modlu_kalan.csv`',
    '- `map_data/definition_orijinal_dogu.csv`',
    '- `map_data/definition_orijinal_kalan.csv`',
    '- `analysis/generated/definition_rgb_conflicts.csv`',
    '- `analysis/generated/definition_rgb_conflict_decisions.csv`',
    '- `analysis/generated/rgb_mapping_draft.csv`',
    '- `analysis/generated/rgb_conflict_previews/`',
    '- `analysis/generated/definition_id_conflicts.csv`',
    '- `analysis/generated/definition_shared_same_id.csv`',
    '- `analysis/generated/definition_quality_flags.csv`',
    '- `analysis/generated/definition_merge_inventory.csv`',
    '- `analysis/generated/definition_id_tracking.csv`',
    '- `analysis/generated/definition_subset_validation.csv`',
    '- `analysis/generated/definition_modlu_dogu_rgb_inventory.csv`',
    '- `analysis/generated/definition_modlu_kalan_rgb_inventory.csv`',
    '- `analysis/generated/definition_orijinal_dogu_rgb_inventory.csv`',
    '- `analysis/generated/definition_orijinal_kalan_rgb_inventory.csv`',
    '',
    '## Subset Extraction Summary',
    '',
    ('- `modlu_dogu`: image colors `{0}`, extracted rows `{1}`, missing in definition `{2}`' -f $subsetResults['modlu_dogu'].image_non_black_unique, $subsetResults['modlu_dogu'].extracted_entries_count, $subsetResults['modlu_dogu'].missing_colors_in_definition),
    ('- `modlu_kalan`: image colors `{0}`, extracted rows `{1}`, missing in definition `{2}`' -f $subsetResults['modlu_kalan'].image_non_black_unique, $subsetResults['modlu_kalan'].extracted_entries_count, $subsetResults['modlu_kalan'].missing_colors_in_definition),
    ('- `orijinal_dogu`: image colors `{0}`, extracted rows `{1}`, missing in definition `{2}`' -f $subsetResults['orijinal_dogu'].image_non_black_unique, $subsetResults['orijinal_dogu'].extracted_entries_count, $subsetResults['orijinal_dogu'].missing_colors_in_definition),
    ('- `orijinal_kalan`: image colors `{0}`, extracted rows `{1}`, missing in definition `{2}`' -f $subsetResults['orijinal_kalan'].image_non_black_unique, $subsetResults['orijinal_kalan'].extracted_entries_count, $subsetResults['orijinal_kalan'].missing_colors_in_definition),
    '',
    '## Subset Validation Rerun',
    '',
    ('- `modlu_dogu` validation pass: `{0}`' -f (($subsetValidationRows | Where-Object { $_.subset_name -eq 'modlu_dogu' }).validation_pass)),
    ('- `modlu_kalan` validation pass: `{0}`' -f (($subsetValidationRows | Where-Object { $_.subset_name -eq 'modlu_kalan' }).validation_pass)),
    ('- `orijinal_dogu` validation pass: `{0}`' -f (($subsetValidationRows | Where-Object { $_.subset_name -eq 'orijinal_dogu' }).validation_pass)),
    ('- `orijinal_kalan` validation pass: `{0}`' -f (($subsetValidationRows | Where-Object { $_.subset_name -eq 'orijinal_kalan' }).validation_pass)),
    '',
    '## Merge Audit Summary',
    '',
    ('- benign shared rows (`same RGB + same ID`): `{0}`' -f $sharedSameIdRows.Count),
    ('- benign shared rows with same name: `{0}`' -f $sameNameSharedCount),
    ('- benign shared rows with different name/comment: `{0}`' -f $differentNameSharedCount),
    ('- RGB conflicts (`same RGB + different ID`): `{0}`' -f $rgbConflictRows.Count),
    ('- RGB decision rows (`pending_manual_rgb_resolution`): `{0}`' -f $rgbDecisionRows.Count),
    ('- ID conflicts (`different RGB + same ID`): `{0}`' -f $idConflictRows.Count),
    ('- quality-flagged rows: `{0}`' -f $qualityRows.Count),
    ('- rows with empty name: `{0}`' -f $emptyNameCount),
    ('- rows with placeholder-like name: `{0}`' -f $placeholderNameCount),
    ('- rows needing manual ID assignment review: `{0}`' -f $pendingManualAssignmentCount),
    '',
    '## Notes',
    '',
    '- `definition_id_tracking.csv` is the forward-looking sheet for future ID reassignment work.',
    '- `final_new_id` is intentionally blank for now because no final merge policy has been applied yet.',
    '- When a row later receives a new ID, that sheet should be the source of truth for updating province-referencing game files.',
    '- `definition_rgb_conflict_decisions.csv` is the manual decision scaffold for the 119 `same RGB + different ID` conflicts.',
    '- `rgb_mapping_draft.csv` is a non-final draft mapping generated from the current recolor-side heuristic.',
    '- `rgb_conflict_previews/` contains per-conflict crop previews for the modlu and orijinal sides.',
    '- ID conflicts should be solved with new final IDs plus provenance tracking; placeholder provinces do not solve those identity collisions by themselves.',
    '',
    '## Sample RGB Conflicts',
    ''
)

foreach ($row in @($rgbConflictExportRows | Select-Object -First 12)) {
    $summaryLines += ('- RGB `{0}` -> modlu ID `{1}` / orijinal ID `{2}`' -f $row.rgb, $row.modlu_id, $row.orijinal_id)
}

$summaryLines += ''
$summaryLines += '## Sample ID Conflicts'
$summaryLines += ''

foreach ($row in @($idConflictExportRows | Select-Object -First 12)) {
    $summaryLines += ('- ID `{0}` -> modlu RGB `{1}` / orijinal RGB `{2}`' -f $row.shared_id, $row.modlu_rgb, $row.orijinal_rgb)
}

$summaryLines += ''
$summaryLines += '## Sample Quality Flags'
$summaryLines += ''

foreach ($row in @($qualityExportRows | Select-Object -First 12)) {
    $summaryLines += ('- `{0}` ID `{1}` RGB `{2}` -> {3}' -f $row.source_subset, $row.source_id, $row.source_rgb, $row.notes)
}

[System.IO.File]::WriteAllLines($summaryPath, $summaryLines, [System.Text.UTF8Encoding]::new($false))

Write-Output "Generated subset CSVs and reports under '$generatedDir'."
