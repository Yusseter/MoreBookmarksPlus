param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$VanillaGameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-IntSet {
    New-Object 'System.Collections.Generic.HashSet[int]'
}

function Get-CategorySetsFromText {
    param(
        [string]$Text,
        [string[]]$Categories
    )

    $result = @{}
    foreach ($category in $Categories) {
        $set = New-IntSet
        $pattern = '(?im)^\s*' + [regex]::Escape($category) + '\s*=\s*(list|range)\s*\{([^}]*)\}'
        foreach ($match in [regex]::Matches($Text, $pattern)) {
            $kind = $match.Groups[1].Value.ToLowerInvariant()
            $numbers = [regex]::Matches($match.Groups[2].Value, '\d+') | ForEach-Object { [int]$_.Value }
            if ($kind -eq 'range') {
                if ($numbers.Count -ne 2) {
                    throw "Unexpected RANGE payload for ${category}: $($match.Value)"
                }
                foreach ($n in ($numbers[0]..$numbers[1])) {
                    $null = $set.Add([int]$n)
                }
            }
            else {
                foreach ($n in $numbers) {
                    $null = $set.Add([int]$n)
                }
            }
        }
        $result[$category] = $set
    }
    return $result
}

function Convert-IdsToDefaultMapLines {
    param(
        [string]$Category,
        [int[]]$Ids
    )

    $sorted = $Ids | Sort-Object -Unique
    if (-not $sorted -or $sorted.Count -eq 0) {
        return @("# ${Category}: <empty>")
    }

    $lines = New-Object 'System.Collections.Generic.List[string]'
    $pendingSingles = New-Object 'System.Collections.Generic.List[int]'

    function Flush-Singles {
        param($Singles, $OutputLines, $CategoryName)
        if ($Singles.Count -gt 0) {
            $OutputLines.Add(("{0} = LIST {{ {1} }}" -f $CategoryName, (($Singles | ForEach-Object { $_.ToString() }) -join ' ')))
            $Singles.Clear()
        }
    }

    $start = $sorted[0]
    $prev = $sorted[0]

    for ($i = 1; $i -le $sorted.Count; $i++) {
        $current = if ($i -lt $sorted.Count) { $sorted[$i] } else { $null }
        $continues = $null -ne $current -and $current -eq ($prev + 1)
        if ($continues) {
            $prev = $current
            continue
        }

        $runLength = $prev - $start + 1
        if ($runLength -ge 3) {
            Flush-Singles -Singles $pendingSingles -OutputLines $lines -CategoryName $Category
            $lines.Add(("{0} = RANGE {{ {1} {2} }}" -f $Category, $start, $prev))
        }
        else {
            foreach ($n in ($start..$prev)) {
                $pendingSingles.Add([int]$n)
                if ($pendingSingles.Count -ge 24) {
                    Flush-Singles -Singles $pendingSingles -OutputLines $lines -CategoryName $Category
                }
            }
        }

        if ($null -ne $current) {
            $start = $current
            $prev = $current
        }
    }

    Flush-Singles -Singles $pendingSingles -OutputLines $lines -CategoryName $Category
    return $lines
}

function Get-HeaderLines {
    param([string]$Text)
    $lines = $Text -split "`r?`n"
    $firstBanner = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*#+\s*$') {
            $firstBanner = $i
            break
        }
    }
    if ($firstBanner -lt 0) {
        throw 'Could not find the category banner in mod default.map base.'
    }
    return $lines[0..($firstBanner - 1)]
}

function Get-DefinitionNameMap {
    param([string]$Path)
    $map = @{}
    foreach ($line in Get-Content -Path $Path -Encoding UTF8) {
        if ($line -match '^\s*(\d+);(\d+);(\d+);(\d+);([^;]*);') {
            $map[[int]$matches[1]] = $matches[5]
        }
    }
    return $map
}

$categories = @('sea_zones', 'river_provinces', 'lakes', 'impassable_mountains', 'impassable_seas')
$modDefaultText = git show HEAD:BookmarksGit/map_data/default.map | Out-String
if (-not $modDefaultText.Trim()) {
    throw 'Failed to read mod default.map from git HEAD.'
}

$vanillaDefaultPath = Join-Path $VanillaGameRoot 'map_data/default.map'
$vanillaDefaultText = Get-Content -Path $vanillaDefaultPath -Raw -Encoding UTF8
$currentDefaultPath = Join-Path $RepoRoot 'map_data/default.map'
$currentDefaultText = Get-Content -Path $currentDefaultPath -Raw -Encoding UTF8

$modSets = Get-CategorySetsFromText -Text $modDefaultText -Categories $categories
$vanillaSets = Get-CategorySetsFromText -Text $vanillaDefaultText -Categories $categories
$currentSets = Get-CategorySetsFromText -Text $currentDefaultText -Categories $categories

$masterPath = Join-Path $RepoRoot 'Works/analysis/generated/final_master_preserve_old_ids.csv'
$placeholderPath = Join-Path $RepoRoot 'Works/analysis/generated/final_placeholder_inventory_preserve_old_ids.csv'
$definitionPath = Join-Path $RepoRoot 'map_data/definition.csv'
$reportDir = Join-Path $RepoRoot 'Works/analysis/generated/default_map_source_split'
$null = New-Item -ItemType Directory -Path $reportDir -Force

$masterRows = Import-Csv -Path $masterPath
$placeholderRows = Import-Csv -Path $placeholderPath
$definitionNames = Get-DefinitionNameMap -Path $definitionPath

$rebuiltSets = @{}
foreach ($category in $categories) {
    $rebuiltSets[$category] = New-IntSet
}

$sourceDecisionRows = New-Object 'System.Collections.Generic.List[object]'

foreach ($row in $masterRows) {
    if ($row.row_type -ne 'candidate') {
        continue
    }

    $finalId = [int]$row.final_new_id
    $preferredSubset = $row.preferred_source_subset
    $sourceUsed = $null
    $oldId = $null
    $oldRgb = $null

    switch ($preferredSubset) {
        'modlu_kalan' {
            if ($row.modlu_old_id) {
                $sourceUsed = 'modlu'
                $oldId = [int]$row.modlu_old_id
                $oldRgb = $row.modlu_old_rgb
            }
        }
        'orijinal_dogu' {
            if ($row.orijinal_old_id) {
                $sourceUsed = 'orijinal'
                $oldId = [int]$row.orijinal_old_id
                $oldRgb = $row.orijinal_old_rgb
            }
        }
    }

    if (-not $sourceUsed) {
        if ($row.modlu_old_id) {
            $sourceUsed = 'modlu'
            $oldId = [int]$row.modlu_old_id
            $oldRgb = $row.modlu_old_rgb
        }
        elseif ($row.orijinal_old_id) {
            $sourceUsed = 'orijinal'
            $oldId = [int]$row.orijinal_old_id
            $oldRgb = $row.orijinal_old_rgb
        }
        else {
            continue
        }
    }

    foreach ($category in $categories) {
        $sourceSet = if ($sourceUsed -eq 'modlu') { $modSets[$category] } else { $vanillaSets[$category] }
        if ($sourceSet.Contains($oldId)) {
            $null = $rebuiltSets[$category].Add($finalId)
        }
    }

    $sourceDecisionRows.Add([pscustomobject]@{
        final_new_id          = $finalId
        final_name            = $row.effective_name
        source_origin         = $row.source_origin
        preferred_subset      = $preferredSubset
        source_used           = $sourceUsed
        source_old_id         = $oldId
        source_old_rgb        = $oldRgb
        modlu_old_id          = $row.modlu_old_id
        modlu_old_rgb         = $row.modlu_old_rgb
        orijinal_old_id       = $row.orijinal_old_id
        orijinal_old_rgb      = $row.orijinal_old_rgb
        keeps_current_id      = $row.keeps_current_id
        id_change_reason      = $row.id_change_reason
        rgb_resolution_status = $row.rgb_resolution_status
        primary_status        = $row.primary_status
    }) | Out-Null
}

foreach ($placeholder in $placeholderRows) {
    $placeholderId = [int]$placeholder.final_new_id
    $null = $rebuiltSets['impassable_mountains'].Add($placeholderId)
    foreach ($otherCategory in @('sea_zones', 'river_provinces', 'lakes', 'impassable_seas')) {
        $null = $rebuiltSets[$otherCategory].Remove($placeholderId)
    }
}

$headerLines = Get-HeaderLines -Text $modDefaultText
$newLines = New-Object 'System.Collections.Generic.List[string]'
foreach ($line in $headerLines) {
    $newLines.Add($line)
}

$newLines.Add('')
$newLines.Add('#############')
$newLines.Add('# SEA ZONES')
$newLines.Add('#############')
$newLines.Add('# GENERATED: modlu_kalan categories come from the mod base default.map (git HEAD).')
$newLines.Add('# GENERATED: orijinal_dogu categories come from vanilla default.map, rewritten to final_new_id.')
$newLines.Add('# GENERATED: final source choice is resolved through final_master_preserve_old_ids.csv,')
$newLines.Add('# which already encodes old_id + old_rgb + source provenance.')
foreach ($line in (Convert-IdsToDefaultMapLines -Category 'sea_zones' -Ids $rebuiltSets['sea_zones'].ToArray())) {
    $newLines.Add($line)
}

$newLines.Add('')
$newLines.Add('###############')
$newLines.Add('# MAJOR RIVERS')
$newLines.Add('###############')
foreach ($line in (Convert-IdsToDefaultMapLines -Category 'river_provinces' -Ids $rebuiltSets['river_provinces'].ToArray())) {
    $newLines.Add($line)
}

$newLines.Add('')
$newLines.Add('########')
$newLines.Add('# LAKES')
$newLines.Add('########')
foreach ($line in (Convert-IdsToDefaultMapLines -Category 'lakes' -Ids $rebuiltSets['lakes'].ToArray())) {
    $newLines.Add($line)
}

$newLines.Add('')
$newLines.Add('#####################')
$newLines.Add('# IMPASSABLE TERRAIN')
$newLines.Add('#####################')
$newLines.Add('# Placeholder provinces are also forced into impassable_mountains below.')
foreach ($line in (Convert-IdsToDefaultMapLines -Category 'impassable_mountains' -Ids $rebuiltSets['impassable_mountains'].ToArray())) {
    $newLines.Add($line)
}

$newLines.Add('')
$newLines.Add('####################')
$newLines.Add('# IMPASSABLE SEA ZONES')
$newLines.Add('####################')
foreach ($line in (Convert-IdsToDefaultMapLines -Category 'impassable_seas' -Ids $rebuiltSets['impassable_seas'].ToArray())) {
    $newLines.Add($line)
}

$newLines.Add('')
$newLines.Add('# TECH PLACEHOLDER PROVINCES')
$newLines.Add('# These are represented physically in provinces.png and must remain impassable.')
foreach ($line in (Convert-IdsToDefaultMapLines -Category 'impassable_mountains' -Ids ($placeholderRows | ForEach-Object { [int]$_.final_new_id }))) {
    $newLines.Add('# ' + $line)
}

$newDefaultText = ($newLines -join "`r`n") + "`r`n"

$testDefaultPath = Join-Path $RepoRoot 'test_files/map_data/default.map'
Set-Content -Path $currentDefaultPath -Value $newDefaultText -Encoding UTF8
Set-Content -Path $testDefaultPath -Value $newDefaultText -Encoding UTF8

$diffRows = New-Object 'System.Collections.Generic.List[object]'
$summaryRows = New-Object 'System.Collections.Generic.List[object]'

foreach ($category in $categories) {
    $currentIds = $currentSets[$category].ToArray()
    $rebuiltIds = $rebuiltSets[$category].ToArray()
    $currentLookup = @{}
    foreach ($id in $currentIds) { $currentLookup[[int]$id] = $true }
    $rebuiltLookup = @{}
    foreach ($id in $rebuiltIds) { $rebuiltLookup[[int]$id] = $true }

    $removed = $currentIds | Where-Object { -not $rebuiltLookup.ContainsKey([int]$_) } | Sort-Object
    $added = $rebuiltIds | Where-Object { -not $currentLookup.ContainsKey([int]$_) } | Sort-Object

    foreach ($id in $removed) {
        $decision = $sourceDecisionRows | Where-Object { $_.final_new_id -eq [int]$id } | Select-Object -First 1
        $diffRows.Add([pscustomobject]@{
            category            = $category
            action              = 'removed_from_live'
            final_new_id        = [int]$id
            final_name          = $definitionNames[[int]$id]
            preferred_subset    = $decision.preferred_subset
            source_origin       = $decision.source_origin
            source_used         = $decision.source_used
            source_old_id       = $decision.source_old_id
            source_old_rgb      = $decision.source_old_rgb
        }) | Out-Null
    }

    foreach ($id in $added) {
        $decision = $sourceDecisionRows | Where-Object { $_.final_new_id -eq [int]$id } | Select-Object -First 1
        $diffRows.Add([pscustomobject]@{
            category            = $category
            action              = 'added_to_live'
            final_new_id        = [int]$id
            final_name          = $definitionNames[[int]$id]
            preferred_subset    = $decision.preferred_subset
            source_origin       = $decision.source_origin
            source_used         = $decision.source_used
            source_old_id       = $decision.source_old_id
            source_old_rgb      = $decision.source_old_rgb
        }) | Out-Null
    }

    $summaryRows.Add([pscustomobject]@{
        category            = $category
        current_live_count  = $currentIds.Count
        rebuilt_count       = $rebuiltIds.Count
        removed_count       = $removed.Count
        added_count         = $added.Count
    }) | Out-Null
}

$summaryPath = Join-Path $reportDir 'default_map_source_split_summary.md'
$summaryLines = @(
    '# default.map Source Split Summary',
    '',
    'Rebuilt categories:',
    '- `sea_zones`',
    '- `river_provinces`',
    '- `lakes`',
    '- `impassable_mountains`',
    '- `impassable_seas`',
    '',
    'Policy used:',
    '- `modlu_kalan` / preferred mod source: category membership from mod `default.map` at git HEAD',
    '- `orijinal_dogu` / preferred original source: category membership from vanilla `default.map`, rewritten to `final_new_id`',
    '- placeholder rows: always `impassable_mountains`',
    '',
    'Count changes by category:'
)
foreach ($row in $summaryRows) {
    $summaryLines += ('- `{0}`: current `{1}`, rebuilt `{2}`, removed `{3}`, added `{4}`' -f $row.category, $row.current_live_count, $row.rebuilt_count, $row.removed_count, $row.added_count)
}
$summaryLines += ''
$summaryLines += 'Important note: benign shared / `source_origin=both` rows use `preferred_source_subset` from `final_master_preserve_old_ids.csv`, preventing west provinces such as `Crivitz` from inheriting east impassable flags just because vanilla reused the same old ID/RGB.'
Set-Content -Path $summaryPath -Value ($summaryLines -join "`r`n") -Encoding UTF8

$summaryCsvPath = Join-Path $reportDir 'default_map_source_split_category_summary.csv'
$diffCsvPath = Join-Path $reportDir 'default_map_source_split_diff.csv'
$decisionCsvPath = Join-Path $reportDir 'default_map_source_decisions.csv'

$summaryRows | Export-Csv -Path $summaryCsvPath -NoTypeInformation -Encoding UTF8
$diffRows | Export-Csv -Path $diffCsvPath -NoTypeInformation -Encoding UTF8
$sourceDecisionRows | Export-Csv -Path $decisionCsvPath -NoTypeInformation -Encoding UTF8

Write-Host "Rebuilt default.map using source split policy."
Write-Host "Summary: $summaryPath"
Write-Host "Diff CSV: $diffCsvPath"
