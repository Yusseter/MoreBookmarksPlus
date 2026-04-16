$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-Utf8NoBomEncoding {
    return New-Object System.Text.UTF8Encoding($false)
}

function Read-TextUtf8 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $memory = New-Object System.IO.MemoryStream
        $stream.CopyTo($memory)
        $bytes = $memory.ToArray()
    }
    finally {
        $stream.Dispose()
    }
    $encoding = Get-Utf8NoBomEncoding
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

    [System.IO.File]::WriteAllText($Path, $Text, (Get-Utf8NoBomEncoding))
}

function Read-CsvUtf8 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $text = Read-TextUtf8 -Path $Path
    if ([string]::IsNullOrWhiteSpace($text)) {
        return @()
    }
    return $text | ConvertFrom-Csv
}

function Export-CsvUtf8 {
    param(
        [Parameter(Mandatory = $true)]$Rows,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $Rows | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
}

function Split-Lines {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    return [System.Text.RegularExpressions.Regex]::Split($Text, "`r?`n")
}

function Strip-LineComment {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Line)

    $index = $Line.IndexOf('#')
    if ($index -lt 0) {
        return $Line
    }
    return $Line.Substring(0, $index)
}

function Get-BraceDelta {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Line)

    $visible = Strip-LineComment -Line $Line
    $opens = ([regex]::Matches($visible, '\{')).Count
    $closes = ([regex]::Matches($visible, '\}')).Count
    return $opens - $closes
}

function Add-UniqueString {
    param(
        [Parameter(Mandatory = $true)]$TargetList,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }
    if (-not $TargetList.Contains($Value)) {
        [void]$TargetList.Add($Value)
    }
}

function Join-UniqueValues {
    param([Parameter(Mandatory = $true)]$Values)

    $unique = New-Object System.Collections.Generic.List[string]
    foreach ($value in $Values) {
        Add-UniqueString -TargetList $unique -Value ([string]$value)
    }

    if ($unique.Count -eq 0) {
        return ''
    }

    return (($unique | Sort-Object -Unique) -join '|')
}

function Parse-IntOrNull {
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $parsed = 0
    if ([int]::TryParse($Value, [ref]$parsed)) {
        return $parsed
    }

    return $null
}

function Get-DefinitionIndex {
    param([Parameter(Mandatory = $true)][string]$Path)

    $index = @{}
    foreach ($line in (Split-Lines -Text (Read-TextUtf8 -Path $Path))) {
        if ($line -match '^\s*(\d+);(\d+);(\d+);(\d+);([^;]+)') {
            $id = [int]$matches[1]
            $index[[string]$id] = [pscustomobject]@{
                id = $id
                rgb = ('{0},{1},{2}' -f $matches[2], $matches[3], $matches[4])
                name = [string]$matches[5]
            }
        }
    }
    return $index
}

function Get-DefinedTitleIndex {
    param([Parameter(Mandatory = $true)][string]$Text)

    $index = @{}
    foreach ($rawLine in (Split-Lines -Text $Text)) {
        $visible = Strip-LineComment -Line $rawLine
        if ($visible -match '^\s*([ehkdcb]_[A-Za-z0-9_\/\.\-]+)\s*=\s*\{') {
            $index[[string]$matches[1]] = $true
        }
    }
    return $index
}

function Parse-LandedTitleProvinceBindings {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$FileLabel
    )

    $bindingsByProvinceId = @{}
    $stack = New-Object System.Collections.Generic.List[object]
    $braceDepth = 0
    $lineNumber = 0

    foreach ($rawLine in (Split-Lines -Text $Text)) {
        $lineNumber++
        $visible = Strip-LineComment -Line $rawLine

        if ($visible -match '^\s*([ehkdcb]_[A-Za-z0-9_\/\.\-]+)\s*=\s*\{') {
            $stack.Add([pscustomobject]@{
                title = [string]$matches[1]
                depth = $braceDepth
            }) | Out-Null
        }

        if ($visible -match '^\s*province\s*=\s*(\d+)\s*$') {
            $provinceId = [int]$matches[1]
            $provinceKey = [string]$provinceId
            $barony = ''
            $county = ''
            $duchy = ''
            $kingdom = ''
            $rootTitle = ''

            for ($stackIndex = $stack.Count - 1; $stackIndex -ge 0; $stackIndex--) {
                $title = [string]$stack[$stackIndex].title
                if ([string]::IsNullOrWhiteSpace($barony) -and $title.StartsWith('b_')) {
                    $barony = $title
                    continue
                }
                if ([string]::IsNullOrWhiteSpace($county) -and $title.StartsWith('c_')) {
                    $county = $title
                    continue
                }
                if ([string]::IsNullOrWhiteSpace($duchy) -and $title.StartsWith('d_')) {
                    $duchy = $title
                    continue
                }
                if ([string]::IsNullOrWhiteSpace($kingdom) -and $title.StartsWith('k_')) {
                    $kingdom = $title
                    continue
                }
                if ([string]::IsNullOrWhiteSpace($rootTitle) -and ($title.StartsWith('e_') -or $title.StartsWith('h_'))) {
                    $rootTitle = $title
                    continue
                }
            }

            if ([string]::IsNullOrWhiteSpace($rootTitle)) {
                if (-not [string]::IsNullOrWhiteSpace($kingdom)) {
                    $rootTitle = $kingdom
                }
                elseif (-not [string]::IsNullOrWhiteSpace($duchy)) {
                    $rootTitle = $duchy
                }
                elseif (-not [string]::IsNullOrWhiteSpace($county)) {
                    $rootTitle = $county
                }
                elseif (-not [string]::IsNullOrWhiteSpace($barony)) {
                    $rootTitle = $barony
                }
            }

            $pathTitles = New-Object System.Collections.Generic.List[string]
            foreach ($frame in $stack) {
                Add-UniqueString -TargetList $pathTitles -Value ([string]$frame.title)
            }

            if (-not $bindingsByProvinceId.ContainsKey($provinceKey)) {
                $bindingsByProvinceId[$provinceKey] = New-Object System.Collections.ArrayList
            }

            [void]$bindingsByProvinceId[$provinceKey].Add([pscustomobject]@{
                province_id = $provinceId
                file_label = $FileLabel
                line_number = $lineNumber
                barony = $barony
                county = $county
                duchy = $duchy
                kingdom = $kingdom
                root_title = $rootTitle
                title_path = ($pathTitles -join ' > ')
            })
        }

        $braceDepth += Get-BraceDelta -Line $rawLine
        while ($stack.Count -gt 0 -and [int]$stack[$stack.Count - 1].depth -ge $braceDepth) {
            $stack.RemoveAt($stack.Count - 1)
        }
    }

    return $bindingsByProvinceId
}

function Build-LandedBindingIndexFromDirectory {
    param([Parameter(Mandatory = $true)][string]$DirectoryPath)

    $index = @{}
    $files = Get-ChildItem -Path $DirectoryPath -Filter '*.txt' | Sort-Object Name
    foreach ($file in $files) {
        $fileBindings = Parse-LandedTitleProvinceBindings -Text (Read-TextUtf8 -Path $file.FullName) -FileLabel $file.Name
        foreach ($entry in $fileBindings.GetEnumerator()) {
            $key = [string]$entry.Key
            if (-not $index.ContainsKey($key)) {
                $index[$key] = New-Object System.Collections.ArrayList
            }
            foreach ($binding in @($entry.Value)) {
                [void]$index[$key].Add($binding)
            }
        }
    }
    return $index
}

function Get-BindingSummary {
    param(
        [Parameter(Mandatory = $true)]$BindingsByProvinceId,
        [Parameter(Mandatory = $true)][int]$ProvinceId
    )

    $key = [string]$ProvinceId
    if (-not $BindingsByProvinceId.ContainsKey($key)) {
        return [pscustomobject]@{
            defined = $false
            binding_count = 0
            file_labels = ''
            line_numbers = ''
            barony = ''
            county = ''
            duchy = ''
            kingdom = ''
            root_title = ''
            title_path = ''
        }
    }

    $bindings = @($BindingsByProvinceId[$key])
    return [pscustomobject]@{
        defined = $true
        binding_count = $bindings.Count
        file_labels = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.file_label })
        line_numbers = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.line_number })
        barony = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.barony })
        county = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.county })
        duchy = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.duchy })
        kingdom = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.kingdom })
        root_title = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.root_title })
        title_path = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.title_path })
    }
}

function Get-MissingProvinceIdsFromLog {
    param([Parameter(Mandatory = $true)][string]$Path)

    $ids = New-Object 'System.Collections.Generic.SortedSet[int]'
    foreach ($line in (Split-Lines -Text (Read-TextUtf8 -Path $Path))) {
        if ($line -match "Province '(\d+)' has no associated title in common/landed_titles") {
            [void]$ids.Add([int]$matches[1])
        }
    }
    return @($ids)
}

function Get-IdRangesText {
    param([Parameter(Mandatory = $true)][int[]]$Ids)

    if ($Ids.Count -eq 0) {
        return ''
    }

    $ordered = @($Ids | Sort-Object -Unique)
    $parts = New-Object System.Collections.Generic.List[string]
    $start = $ordered[0]
    $previous = $ordered[0]

    for ($index = 1; $index -lt $ordered.Count; $index++) {
        $current = $ordered[$index]
        if ($current -eq ($previous + 1)) {
            $previous = $current
            continue
        }

        if ($start -eq $previous) {
            $parts.Add([string]$start)
        }
        else {
            $parts.Add(('{0}-{1}' -f $start, $previous))
        }

        $start = $current
        $previous = $current
    }

    if ($start -eq $previous) {
        $parts.Add([string]$start)
    }
    else {
        $parts.Add(('{0}-{1}' -f $start, $previous))
    }

    return ($parts -join ', ')
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$generatedRoot = Join-Path $repoRoot 'Works\analysis\generated\missing_landed_title_source_cluster'
New-Item -ItemType Directory -Path $generatedRoot -Force | Out-Null

$paths = @{
    Log = 'C:\Users\bsgho\Documents\Paradox Interactive\Crusader Kings III\logs\error.log'
    FinalMaster = Join-Path $repoRoot 'Works\analysis\generated\final_master_preserve_old_ids.csv'
    Definition = Join-Path $repoRoot 'map_data\definition.csv'
    LiveLanded = Join-Path $repoRoot 'common\landed_titles\00_landed_titles.txt'
    ModSourceDir = 'C:\Program Files (x86)\Steam\steamapps\workshop\content\1158310\2216670956\0backup\common\landed_titles'
    VanillaSourceDir = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles'
}

$missingIds = @(Get-MissingProvinceIdsFromLog -Path $paths.Log)
$definitionIndex = Get-DefinitionIndex -Path $paths.Definition
$finalMasterRows = @(Read-CsvUtf8 -Path $paths.FinalMaster)
$finalMasterById = @{}
foreach ($row in $finalMasterRows) {
    if ([string]::IsNullOrWhiteSpace([string]$row.final_new_id)) {
        continue
    }
    $finalId = [int]$row.final_new_id
    $key = [string]$finalId
    if (-not $finalMasterById.ContainsKey($key) -or [string]$row.row_type -eq 'candidate') {
        $finalMasterById[$key] = $row
    }
}

$liveLandedText = Read-TextUtf8 -Path $paths.LiveLanded
$liveBindings = Parse-LandedTitleProvinceBindings -Text $liveLandedText -FileLabel '00_landed_titles.txt'
$liveTitleIndex = Get-DefinedTitleIndex -Text $liveLandedText
$modSourceBindings = Build-LandedBindingIndexFromDirectory -DirectoryPath $paths.ModSourceDir
$vanillaSourceBindings = Build-LandedBindingIndexFromDirectory -DirectoryPath $paths.VanillaSourceDir

$detailRows = New-Object System.Collections.Generic.List[object]

foreach ($finalId in ($missingIds | Sort-Object)) {
    $finalKey = [string]$finalId
    $finalRow = if ($finalMasterById.ContainsKey($finalKey)) { $finalMasterById[$finalKey] } else { $null }
    $definitionRow = if ($definitionIndex.ContainsKey($finalKey)) { $definitionIndex[$finalKey] } else { $null }
    $liveSummary = Get-BindingSummary -BindingsByProvinceId $liveBindings -ProvinceId $finalId

    $preferredSubset = ''
    $sourceOrigin = ''
    $sourceOldId = $null
    $sourceOldName = ''
    $sourceBindings = $null
    $status = 'missing_final_master'

    if ($null -ne $finalRow) {
        $preferredSubset = [string]$finalRow.preferred_source_subset
        $sourceOrigin = [string]$finalRow.source_origin

        switch ($preferredSubset) {
            'modlu_kalan' {
                $sourceOldId = Parse-IntOrNull -Value ([string]$finalRow.modlu_old_id)
                $sourceOldName = [string]$finalRow.modlu_old_name
                $sourceBindings = $modSourceBindings
            }
            'orijinal_dogu' {
                $sourceOldId = Parse-IntOrNull -Value ([string]$finalRow.orijinal_old_id)
                $sourceOldName = [string]$finalRow.orijinal_old_name
                $sourceBindings = $vanillaSourceBindings
            }
            default {
                if (-not [string]::IsNullOrWhiteSpace([string]$finalRow.modlu_old_id)) {
                    $sourceOldId = Parse-IntOrNull -Value ([string]$finalRow.modlu_old_id)
                    $sourceOldName = [string]$finalRow.modlu_old_name
                    $sourceBindings = $modSourceBindings
                    $preferredSubset = 'modlu_kalan'
                }
                elseif (-not [string]::IsNullOrWhiteSpace([string]$finalRow.orijinal_old_id)) {
                    $sourceOldId = Parse-IntOrNull -Value ([string]$finalRow.orijinal_old_id)
                    $sourceOldName = [string]$finalRow.orijinal_old_name
                    $sourceBindings = $vanillaSourceBindings
                    $preferredSubset = 'orijinal_dogu'
                }
            }
        }

        if ($null -ne $sourceOldId -and $null -ne $sourceBindings) {
            $status = 'source_binding_lookup_pending'
        }
        else {
            $status = 'missing_source_old_id'
        }
    }

    $sourceSummary = if ($null -ne $sourceOldId -and $null -ne $sourceBindings) {
        Get-BindingSummary -BindingsByProvinceId $sourceBindings -ProvinceId ([int]$sourceOldId)
    }
    else {
        Get-BindingSummary -BindingsByProvinceId @{} -ProvinceId 0
    }

    if ($status -eq 'source_binding_lookup_pending') {
        if ($sourceSummary.defined) {
            $status = 'ok'
        }
        else {
            $status = 'missing_source_binding'
        }
    }

    $rootTitle = [string]$sourceSummary.root_title
    $subtreeTitle = if (-not [string]::IsNullOrWhiteSpace([string]$sourceSummary.duchy)) {
        [string]$sourceSummary.duchy
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$sourceSummary.kingdom)) {
        [string]$sourceSummary.kingdom
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$sourceSummary.county)) {
        [string]$sourceSummary.county
    }
    else {
        [string]$sourceSummary.barony
    }

    $detailRows.Add([pscustomobject]@{
        final_new_id = $finalId
        final_name = if ($null -ne $definitionRow) { [string]$definitionRow.name } elseif ($null -ne $finalRow) { [string]$finalRow.effective_name } else { '' }
        final_rgb = if ($null -ne $definitionRow) { [string]$definitionRow.rgb } else { '' }
        preferred_source_subset = $preferredSubset
        source_origin = $sourceOrigin
        source_old_id = if ($null -ne $sourceOldId) { [int]$sourceOldId } else { '' }
        source_old_name = $sourceOldName
        source_file_labels = [string]$sourceSummary.file_labels
        source_binding_count = [int]$sourceSummary.binding_count
        source_root_title = $rootTitle
        source_kingdom = [string]$sourceSummary.kingdom
        source_duchy = [string]$sourceSummary.duchy
        source_county = [string]$sourceSummary.county
        source_barony = [string]$sourceSummary.barony
        source_title_path = [string]$sourceSummary.title_path
        cluster_root = $rootTitle
        cluster_subtree = $subtreeTitle
        live_binding_defined = [bool]$liveSummary.defined
        live_binding_count = [int]$liveSummary.binding_count
        live_root_title_present = if ([string]::IsNullOrWhiteSpace($rootTitle)) { $false } else { $liveTitleIndex.ContainsKey($rootTitle) }
        live_kingdom_present = if ([string]::IsNullOrWhiteSpace([string]$sourceSummary.kingdom)) { $false } else { $liveTitleIndex.ContainsKey([string]$sourceSummary.kingdom) }
        live_duchy_present = if ([string]::IsNullOrWhiteSpace([string]$sourceSummary.duchy)) { $false } else { $liveTitleIndex.ContainsKey([string]$sourceSummary.duchy) }
        live_county_present = if ([string]::IsNullOrWhiteSpace([string]$sourceSummary.county)) { $false } else { $liveTitleIndex.ContainsKey([string]$sourceSummary.county) }
        status = $status
    }) | Out-Null
}

$detailRows = @($detailRows | Sort-Object final_new_id)

$byRootRows = foreach ($group in ($detailRows | Group-Object preferred_source_subset, cluster_root | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Descending = $false })) {
    $rows = @($group.Group)
    $rootIds = @($rows | ForEach-Object { [int]$_.final_new_id })
    $rootNames = @($rows | Select-Object -First 5 | ForEach-Object { [string]$_.final_name })
    $rootFiles = @($rows | ForEach-Object { [string]$_.source_file_labels })
    $rootMissingBindings = @($rows | Where-Object { $_.status -eq 'missing_source_binding' })
    $rootMissingLive = @($rows | Where-Object { -not $_.live_root_title_present })
    [pscustomobject]@{
        preferred_source_subset = [string]$rows[0].preferred_source_subset
        cluster_root = [string]$rows[0].cluster_root
        province_count = $rows.Count
        final_id_ranges = Get-IdRangesText -Ids $rootIds
        sample_final_names = ($rootNames -join ' | ')
        source_files = Join-UniqueValues -Values $rootFiles
        all_live_root_present = ($rootMissingLive.Count -eq 0)
        missing_source_binding_count = $rootMissingBindings.Count
    }
}

$bySubtreeRows = foreach ($group in ($detailRows | Group-Object preferred_source_subset, cluster_root, cluster_subtree | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Descending = $false })) {
    $rows = @($group.Group)
    $subtreeIds = @($rows | ForEach-Object { [int]$_.final_new_id })
    $subtreeNames = @($rows | Select-Object -First 5 | ForEach-Object { [string]$_.final_name })
    $subtreeFiles = @($rows | ForEach-Object { [string]$_.source_file_labels })
    $subtreeKingdoms = @($rows | ForEach-Object { [string]$_.source_kingdom })
    $subtreeDuchies = @($rows | ForEach-Object { [string]$_.source_duchy })
    $subtreeMissingBindings = @($rows | Where-Object { $_.status -eq 'missing_source_binding' })
    $subtreeMissingDuchy = @($rows | Where-Object { -not $_.live_duchy_present })
    $subtreeMissingCounty = @($rows | Where-Object { -not $_.live_county_present })
    [pscustomobject]@{
        preferred_source_subset = [string]$rows[0].preferred_source_subset
        cluster_root = [string]$rows[0].cluster_root
        cluster_subtree = [string]$rows[0].cluster_subtree
        source_kingdom = Join-UniqueValues -Values $subtreeKingdoms
        source_duchy = Join-UniqueValues -Values $subtreeDuchies
        province_count = $rows.Count
        final_id_ranges = Get-IdRangesText -Ids $subtreeIds
        sample_final_names = ($subtreeNames -join ' | ')
        source_files = Join-UniqueValues -Values $subtreeFiles
        live_duchy_present = ($subtreeMissingDuchy.Count -eq 0)
        live_county_present = ($subtreeMissingCounty.Count -eq 0)
        missing_source_binding_count = $subtreeMissingBindings.Count
    }
}

$summaryLines = New-Object System.Collections.Generic.List[string]
$okDetailRows = @($detailRows | Where-Object { $_.status -eq 'ok' })
$missingBindingRows = @($detailRows | Where-Object { $_.status -eq 'missing_source_binding' })
$missingMasterRows = @($detailRows | Where-Object { $_.status -in @('missing_final_master', 'missing_source_old_id') })
$summaryLines.Add('# Missing Landed Titles Source Cluster Report')
$summaryLines.Add('')
$summaryLines.Add(('- log path: `{0}`' -f $paths.Log))
$summaryLines.Add(('- missing live province ids: `{0}`' -f $missingIds.Count))
$summaryLines.Add(('- detail rows with source binding found: `{0}`' -f $okDetailRows.Count))
$summaryLines.Add(('- detail rows missing source binding: `{0}`' -f $missingBindingRows.Count))
$summaryLines.Add(('- detail rows missing final master/source old id: `{0}`' -f $missingMasterRows.Count))
$summaryLines.Add('')
$summaryLines.Add('## Largest Root Clusters')
$summaryLines.Add('')
foreach ($row in ($byRootRows | Select-Object -First 15)) {
    $summaryLines.Add(('- `{0}` / `{1}` -> `{2}` provinces, ids `{3}`' -f $row.preferred_source_subset, $row.cluster_root, $row.province_count, $row.final_id_ranges))
}
$summaryLines.Add('')
$summaryLines.Add('## Largest Subtree Clusters')
$summaryLines.Add('')
foreach ($row in ($bySubtreeRows | Select-Object -First 20)) {
    $summaryLines.Add(('- `{0}` / `{1}` / `{2}` -> `{3}` provinces, ids `{4}`' -f $row.preferred_source_subset, $row.cluster_root, $row.cluster_subtree, $row.province_count, $row.final_id_ranges))
}
$summaryLines.Add('')
$summaryLines.Add('## Files')
$summaryLines.Add('')
$summaryLines.Add('- `missing_landed_titles_source_detail.csv`: per-final-id provenance and source hierarchy')
$summaryLines.Add('- `missing_landed_titles_source_by_root.csv`: top root clusters')
$summaryLines.Add('- `missing_landed_titles_source_by_subtree.csv`: subtree clusters for targeted restore work')

Export-CsvUtf8 -Rows $detailRows -Path (Join-Path $generatedRoot 'missing_landed_titles_source_detail.csv')
Export-CsvUtf8 -Rows $byRootRows -Path (Join-Path $generatedRoot 'missing_landed_titles_source_by_root.csv')
Export-CsvUtf8 -Rows $bySubtreeRows -Path (Join-Path $generatedRoot 'missing_landed_titles_source_by_subtree.csv')
Write-TextUtf8 -Path (Join-Path $generatedRoot 'missing_landed_titles_source_summary.md') -Text (($summaryLines -join "`r`n") + "`r`n")
