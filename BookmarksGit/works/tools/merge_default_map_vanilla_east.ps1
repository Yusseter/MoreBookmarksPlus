[CmdletBinding()]
param(
    [string]$RepoRoot = '.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Export-Utf8Csv {
    param(
        [Parameter(Mandatory = $true)]$Rows,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $csv = @($Rows | ConvertTo-Csv -NoTypeInformation)
    [System.IO.File]::WriteAllLines($Path, $csv, [System.Text.UTF8Encoding]::new($false))
}

function Get-ConsecutiveRuns {
    param([int[]]$Ids)

    $sorted = @($Ids | Sort-Object -Unique)
    if ($sorted.Count -eq 0) {
        return @()
    }

    $runs = New-Object System.Collections.Generic.List[object]
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
        [string]$Key,
        [System.Collections.Generic.List[int]]$Buffer
    )

    if ($Buffer.Count -eq 0) {
        return
    }

    $Lines.Add(('{0} = LIST {{ {1} }}' -f $Key, (($Buffer | ForEach-Object { [string]$_ }) -join ' '))) | Out-Null
    $Buffer.Clear()
}

function Convert-IdsToCategoryLines {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][int[]]$Ids
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $runs = Get-ConsecutiveRuns -Ids $Ids
    $buffer = New-Object System.Collections.Generic.List[int]

    foreach ($run in $runs) {
        if ([int]$run.count -ge 3) {
            Flush-ListLine -Lines $lines -Key $Key -Buffer $buffer
            $lines.Add(('{0} = RANGE {{ {1} {2} }}' -f $Key, [int]$run.start, [int]$run.end)) | Out-Null
        }
        else {
            for ($value = [int]$run.start; $value -le [int]$run.end; $value++) {
                $buffer.Add($value) | Out-Null
                if ($buffer.Count -ge 24) {
                    Flush-ListLine -Lines $lines -Key $Key -Buffer $buffer
                }
            }
        }
    }

    Flush-ListLine -Lines $lines -Key $Key -Buffer $buffer
    return $lines.ToArray()
}

function Try-ParseCategoryLine {
    param(
        [AllowEmptyString()][string]$Line,
        [ref]$Key,
        [ref]$Ids
    )

    $trimmed = $Line.Trim()
    if ($trimmed -notmatch '^([a-z_]+)\s*=\s*(LIST|RANGE)\s*\{([^}]*)\}') {
        return $false
    }

    $Key.Value = [string]$matches[1]
    $kind = [string]$matches[2]
    $body = [string]$matches[3]

    $numbers = @([regex]::Matches($body, '\d+') | ForEach-Object { [int]$_.Value })
    if ($numbers.Count -eq 0) {
        $Ids.Value = @()
        return $true
    }

    if ($kind -eq 'RANGE') {
        if ($numbers.Count -lt 2) {
            throw "Malformed RANGE line: $Line"
        }

        $start = [int]$numbers[0]
        $end = [int]$numbers[1]
        if ($end -lt $start) {
            throw "Descending RANGE line: $Line"
        }

        $expanded = New-Object System.Collections.Generic.List[int]
        for ($value = $start; $value -le $end; $value++) {
            $expanded.Add($value) | Out-Null
        }
        $Ids.Value = $expanded.ToArray()
        return $true
    }

    $Ids.Value = @($numbers)
    return $true
}

function New-IntSet {
    return ,(New-Object 'System.Collections.Generic.HashSet[int]')
}

function Parse-DefaultMapMembership {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$TargetKeys
    )

    $membership = @{}
    foreach ($key in $TargetKeys) {
        $membership[$key] = New-IntSet
    }

    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $keyRef = $null
        $idsRef = $null
        if (-not (Try-ParseCategoryLine -Line $line -Key ([ref]$keyRef) -Ids ([ref]$idsRef))) {
            continue
        }

        if ($TargetKeys -notcontains $keyRef) {
            continue
        }

        foreach ($id in $idsRef) {
            $membership[$keyRef].Add([int]$id) | Out-Null
        }
    }

    return $membership
}

function Get-DefinitionNameMap {
    param([string]$Path)

    $map = @{}
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($line.StartsWith('#')) {
            continue
        }

        $parts = $line.Split(';')
        if ($parts.Count -lt 5) {
            continue
        }
        if ($parts[0] -notmatch '^\d+$') {
            continue
        }

        $map[[int]$parts[0]] = [string]$parts[4]
    }

    return $map
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$worksGeneratedDir = Join-Path (Join-Path $root 'Works') 'analysis\generated\default_map_vanilla_east'
if (-not (Test-Path -LiteralPath $worksGeneratedDir)) {
    New-Item -ItemType Directory -Path $worksGeneratedDir -Force | Out-Null
}

$currentDefaultMapPath = Join-Path $root 'map_data\default.map'
$vanillaDefaultMapPath = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\map_data\default.map'
$trackingPath = Join-Path $root 'Works\analysis\generated\final_orijinal_tracking_preserve_old_ids.csv'
$definitionPath = Join-Path $root 'map_data\definition.csv'
$testCopyPath = Join-Path $root 'test_files\map_data\default.map'

$summaryPath = Join-Path $worksGeneratedDir 'default_map_vanilla_east_merge_summary.md'
$categoryReportPath = Join-Path $worksGeneratedDir 'default_map_vanilla_east_merge_category_report.csv'
$nameSampleReportPath = Join-Path $worksGeneratedDir 'default_map_vanilla_east_name_sample_report.csv'

$targetKeys = @(
    'sea_zones',
    'river_provinces',
    'lakes',
    'impassable_mountains',
    'impassable_seas'
)

$trackingRows = Import-Csv -Path $trackingPath
$oldToFinalMap = @{}
$importedFinalIds = New-IntSet
foreach ($row in $trackingRows) {
    if (($row.old_id -notmatch '^\d+$') -or ($row.final_new_id -notmatch '^\d+$')) {
        continue
    }

    $oldId = [int]$row.old_id
    $finalId = [int]$row.final_new_id
    $oldToFinalMap[$oldId] = $finalId
    $importedFinalIds.Add($finalId) | Out-Null
}

$vanillaMembership = Parse-DefaultMapMembership -Path $vanillaDefaultMapPath -TargetKeys $targetKeys
$existingMembership = Parse-DefaultMapMembership -Path $currentDefaultMapPath -TargetKeys $targetKeys

$managedCategorySets = @{}
$reportRows = New-Object System.Collections.Generic.List[object]
foreach ($key in $targetKeys) {
    $managedCategorySets[$key] = New-IntSet
    $oldIdsInVanilla = @($vanillaMembership[$key])
    $mappedOldCount = 0
    $mappedFinalCount = 0
    foreach ($oldId in $oldIdsInVanilla) {
        if ($oldToFinalMap.ContainsKey([int]$oldId)) {
            $mappedOldCount++
            $finalId = [int]$oldToFinalMap[[int]$oldId]
            if ($managedCategorySets[$key].Add($finalId)) {
                $mappedFinalCount++
            }
        }
    }

    $existingImportedCount = 0
    foreach ($value in $existingMembership[$key]) {
        if ($importedFinalIds.Contains([int]$value)) {
            $existingImportedCount++
        }
    }

    $reportRows.Add([pscustomobject]@{
        category = $key
        vanilla_old_id_hits = $mappedOldCount
        managed_final_id_count = $mappedFinalCount
        existing_imported_final_ids_removed = $existingImportedCount
    }) | Out-Null
}

$currentLines = [System.IO.File]::ReadAllLines($currentDefaultMapPath)
$strippedLines = New-Object System.Collections.Generic.List[string]
$inManagedBlock = $false
foreach ($line in $currentLines) {
    if ($line -eq '# VANILLA EAST DEFAULT MAP BEGIN') {
        $inManagedBlock = $true
        continue
    }
    if ($line -eq '# VANILLA EAST DEFAULT MAP END') {
        $inManagedBlock = $false
        continue
    }
    if ($inManagedBlock) {
        continue
    }

    $strippedLines.Add($line) | Out-Null
}

$rewrittenLines = New-Object System.Collections.Generic.List[string]
foreach ($line in $strippedLines) {
    $keyRef = $null
    $idsRef = $null
    if (-not (Try-ParseCategoryLine -Line $line -Key ([ref]$keyRef) -Ids ([ref]$idsRef))) {
        $rewrittenLines.Add($line) | Out-Null
        continue
    }

    if ($targetKeys -notcontains $keyRef) {
        $rewrittenLines.Add($line) | Out-Null
        continue
    }

    $remaining = @($idsRef | Where-Object { -not $importedFinalIds.Contains([int]$_) } | Sort-Object -Unique)
    if ($remaining.Count -eq 0) {
        continue
    }

    foreach ($outLine in (Convert-IdsToCategoryLines -Key $keyRef -Ids $remaining)) {
        $rewrittenLines.Add($outLine) | Out-Null
    }
}

$managedBlock = New-Object System.Collections.Generic.List[string]
$managedBlock.Add('') | Out-Null
$managedBlock.Add('# VANILLA EAST DEFAULT MAP BEGIN') | Out-Null
$managedBlock.Add('# Imported east classifications rewritten from vanilla default.map with final_new_id mapping.') | Out-Null
foreach ($key in $targetKeys) {
    $ids = @($managedCategorySets[$key] | Sort-Object -Unique)
    if ($ids.Count -eq 0) {
        continue
    }

    $managedBlock.Add(('') ) | Out-Null
    $managedBlock.Add(('# {0}' -f $key)) | Out-Null
    foreach ($outLine in (Convert-IdsToCategoryLines -Key $key -Ids $ids)) {
        $managedBlock.Add($outLine) | Out-Null
    }
}
$managedBlock.Add('# VANILLA EAST DEFAULT MAP END') | Out-Null

foreach ($line in $managedBlock) {
    $rewrittenLines.Add($line) | Out-Null
}

[System.IO.File]::WriteAllLines($currentDefaultMapPath, $rewrittenLines, [System.Text.UTF8Encoding]::new($false))

if (Test-Path -LiteralPath (Split-Path -Parent $testCopyPath)) {
    Copy-Item -LiteralPath $currentDefaultMapPath -Destination $testCopyPath -Force
}

$definitionNames = Get-DefinitionNameMap -Path $definitionPath
$sampleNames = @(
    'Tonchai Range',
    'Dawna Range',
    'Annamite Range',
    'Yunnan Range',
    'east_hokkaido_mountains',
    'shinano_mountains',
    'korea_mountains',
    'Binglingsi',
    'XYZ',
    'Hezhou',
    'Viet_Mountains_6',
    'Viet_Mountains_7',
    'Viet_Mountains_8'
)

$postMembership = Parse-DefaultMapMembership -Path $currentDefaultMapPath -TargetKeys $targetKeys
$sampleRows = New-Object System.Collections.Generic.List[object]
foreach ($sampleName in $sampleNames) {
    $matches = @($definitionNames.GetEnumerator() | Where-Object { $_.Value -eq $sampleName } | Sort-Object Key)
    if ($matches.Count -eq 0) {
        $sampleRows.Add([pscustomobject]@{
            province_name = $sampleName
            province_id = ''
            categories = ''
            found_in_definition = $false
        }) | Out-Null
        continue
    }

    foreach ($match in $matches) {
        $categories = @()
        foreach ($key in $targetKeys) {
            if ($postMembership[$key].Contains([int]$match.Key)) {
                $categories += $key
            }
        }

        $sampleRows.Add([pscustomobject]@{
            province_name = $sampleName
            province_id = [int]$match.Key
            categories = ($categories -join ',')
            found_in_definition = $true
        }) | Out-Null
    }
}

Export-Utf8Csv -Rows $reportRows.ToArray() -Path $categoryReportPath
Export-Utf8Csv -Rows $sampleRows.ToArray() -Path $nameSampleReportPath

$summaryLines = @(
    '# default.map vanilla east merge summary',
    '',
    ('- tracking rows used: `{0}`' -f @($trackingRows).Count),
    ('- imported east final province ids: `{0}`' -f $importedFinalIds.Count),
    ('- target categories: `{0}`' -f ($targetKeys -join ', ')),
    ('- live default.map updated: `{0}`' -f $currentDefaultMapPath),
    ('- test_files default.map synced: `{0}`' -f (Test-Path -LiteralPath $testCopyPath)),
    '',
    '## Per-category counts',
    ''
)

foreach ($row in $reportRows) {
    $summaryLines += ('- {0}: managed_final_id_count=`{1}`, removed_from_existing=`{2}`' -f $row.category, $row.managed_final_id_count, $row.existing_imported_final_ids_removed)
}

$summaryLines += @(
    '',
    '## Sample post-merge membership',
    ''
)
foreach ($row in $sampleRows) {
    $summaryLines += ('- {0} ({1}): `{2}`' -f $row.province_name, $row.province_id, $row.categories)
}

[System.IO.File]::WriteAllLines($summaryPath, $summaryLines, [System.Text.UTF8Encoding]::new($false))

Write-Output ('Merged vanilla east default.map classifications into {0}' -f $currentDefaultMapPath)
