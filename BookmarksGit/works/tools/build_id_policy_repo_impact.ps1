param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$PreserveModMapCsv = '',
    [string]$FullModMapCsv = '',
    [string]$ByContextCsv = '',
    [string]$ByFileCsv = '',
    [string]$SummaryPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Get-ActiveContent {
    param([string]$Line)

    $commentIndex = $Line.IndexOf('#')
    if ($commentIndex -ge 0) {
        return $Line.Substring(0, $commentIndex)
    }

    return $Line
}

function Add-ReferenceRow {
    param(
        [System.Collections.Generic.List[object]]$Rows,
        [string]$FilePath,
        [string]$Context,
        [int]$LineNumber,
        [int]$ReferenceCount,
        [int]$PreserveChangedCount,
        [int]$FullChangedCount
    )

    $Rows.Add([pscustomobject]@{
        file_path = $FilePath
        context = $Context
        line_number = $LineNumber
        reference_count = $ReferenceCount
        preserve_changed_count = $PreserveChangedCount
        full_changed_count = $FullChangedCount
        preserve_touches_line = ($PreserveChangedCount -gt 0)
        full_touches_line = ($FullChangedCount -gt 0)
    }) | Out-Null
}

function Count-ChangedIds {
    param(
        [int[]]$Ids,
        $MapTable
    )

    $changed = 0
    foreach ($id in $Ids) {
        $idString = [string]$id
        if ($MapTable.ContainsKey($idString) -and [int]$MapTable[$idString] -ne $id) {
            $changed += 1
        }
    }
    return $changed
}

function Parse-ProvincesBlocks {
    param(
        [string[]]$FilePaths,
        [string]$Context,
        [System.Collections.Generic.List[object]]$Rows,
        $PreserveMap,
        $FullMap
    )

    foreach ($filePath in $FilePaths) {
        $lines = @(Get-Content -Path $filePath)
        $inBlock = $false
        $blockLine = 0

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $active = Get-ActiveContent -Line $lines[$i]

            if (-not $inBlock) {
                if ($active -match 'provinces\s*=\s*\{') {
                    $inBlock = $true
                    $blockLine = $i + 1
                    $numbers = @([regex]::Matches($active, '\b\d+\b') | ForEach-Object { [int]$_.Value })
                    if ($numbers.Count -gt 0) {
                        Add-ReferenceRow -Rows $Rows -FilePath $filePath -Context $Context -LineNumber $blockLine -ReferenceCount $numbers.Count -PreserveChangedCount (Count-ChangedIds -Ids $numbers -MapTable $PreserveMap) -FullChangedCount (Count-ChangedIds -Ids $numbers -MapTable $FullMap)
                    }
                    if ($active -match '\}') {
                        $inBlock = $false
                    }
                }
            }
            else {
                $numbers = @([regex]::Matches($active, '\b\d+\b') | ForEach-Object { [int]$_.Value })
                if ($numbers.Count -gt 0) {
                    Add-ReferenceRow -Rows $Rows -FilePath $filePath -Context $Context -LineNumber ($i + 1) -ReferenceCount $numbers.Count -PreserveChangedCount (Count-ChangedIds -Ids $numbers -MapTable $PreserveMap) -FullChangedCount (Count-ChangedIds -Ids $numbers -MapTable $FullMap)
                }
                if ($active -match '\}') {
                    $inBlock = $false
                }
            }
        }
    }
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$generatedDir = Join-Path (Join-Path $root 'analysis') 'generated'

if ([string]::IsNullOrWhiteSpace($PreserveModMapCsv)) {
    $PreserveModMapCsv = Join-Path $generatedDir 'id_map_modlu_preserve_old.csv'
}
if ([string]::IsNullOrWhiteSpace($FullModMapCsv)) {
    $FullModMapCsv = Join-Path $generatedDir 'id_map_modlu_full_renumber.csv'
}
if ([string]::IsNullOrWhiteSpace($ByContextCsv)) {
    $ByContextCsv = Join-Path $generatedDir 'id_policy_repo_impact_by_context.csv'
}
if ([string]::IsNullOrWhiteSpace($ByFileCsv)) {
    $ByFileCsv = Join-Path $generatedDir 'id_policy_repo_impact_by_file.csv'
}
if ([string]::IsNullOrWhiteSpace($SummaryPath)) {
    $SummaryPath = Join-Path $generatedDir 'id_policy_repo_impact_summary.md'
}

Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($ByContextCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($ByFileCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($SummaryPath))

$preserveMapRows = @(Import-Csv -Path $PreserveModMapCsv)
$fullMapRows = @(Import-Csv -Path $FullModMapCsv)

$preserveMap = @{}
foreach ($row in $preserveMapRows) {
    $preserveMap[[string]$row.old_id] = [int]$row.final_new_id
}
$fullMap = @{}
foreach ($row in $fullMapRows) {
    $fullMap[[string]$row.old_id] = [int]$row.final_new_id
}

$referenceRows = New-Object System.Collections.Generic.List[object]

# history/provinces block headers
foreach ($file in @(Get-ChildItem (Join-Path $root 'history\\provinces') -File -Recurse)) {
    $lines = @(Get-Content -Path $file.FullName)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $active = Get-ActiveContent -Line $lines[$i]
        if ($active -match '^\s*(\d+)\s*=\s*\{') {
            $id = [int]$matches[1]
            Add-ReferenceRow -Rows $referenceRows -FilePath $file.FullName -Context 'history_provinces_block_header' -LineNumber ($i + 1) -ReferenceCount 1 -PreserveChangedCount (Count-ChangedIds -Ids @($id) -MapTable $preserveMap) -FullChangedCount (Count-ChangedIds -Ids @($id) -MapTable $fullMap)
        }
    }
}

# history/province_mapping left/right sides
foreach ($file in @(Get-ChildItem (Join-Path $root 'history\\province_mapping') -File -Recurse)) {
    $lines = @(Get-Content -Path $file.FullName)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $active = Get-ActiveContent -Line $lines[$i]
        if ($active -match '^\s*(\d+)\s*=\s*(\d+)\s*$') {
            $leftId = [int]$matches[1]
            $rightId = [int]$matches[2]
            Add-ReferenceRow -Rows $referenceRows -FilePath $file.FullName -Context 'history_province_mapping_left' -LineNumber ($i + 1) -ReferenceCount 1 -PreserveChangedCount (Count-ChangedIds -Ids @($leftId) -MapTable $preserveMap) -FullChangedCount (Count-ChangedIds -Ids @($leftId) -MapTable $fullMap)
            Add-ReferenceRow -Rows $referenceRows -FilePath $file.FullName -Context 'history_province_mapping_right' -LineNumber ($i + 1) -ReferenceCount 1 -PreserveChangedCount (Count-ChangedIds -Ids @($rightId) -MapTable $preserveMap) -FullChangedCount (Count-ChangedIds -Ids @($rightId) -MapTable $fullMap)
        }
    }
}

# common/landed_titles province = X
foreach ($file in @(Get-ChildItem (Join-Path $root 'common\\landed_titles') -File -Recurse)) {
    $lines = @(Get-Content -Path $file.FullName)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $active = Get-ActiveContent -Line $lines[$i]
        if ($active -match 'province\s*=\s*(\d+)') {
            $id = [int]$matches[1]
            Add-ReferenceRow -Rows $referenceRows -FilePath $file.FullName -Context 'common_landed_titles_province' -LineNumber ($i + 1) -ReferenceCount 1 -PreserveChangedCount (Count-ChangedIds -Ids @($id) -MapTable $preserveMap) -FullChangedCount (Count-ChangedIds -Ids @($id) -MapTable $fullMap)
        }
    }
}

# common/situation capital_province = X
foreach ($file in @(Get-ChildItem (Join-Path $root 'common\\situation') -File -Recurse -ErrorAction SilentlyContinue)) {
    $lines = @(Get-Content -Path $file.FullName)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $active = Get-ActiveContent -Line $lines[$i]
        if ($active -match 'capital_province\s*=\s*(\d+)') {
            $id = [int]$matches[1]
            Add-ReferenceRow -Rows $referenceRows -FilePath $file.FullName -Context 'common_situation_capital_province' -LineNumber ($i + 1) -ReferenceCount 1 -PreserveChangedCount (Count-ChangedIds -Ids @($id) -MapTable $preserveMap) -FullChangedCount (Count-ChangedIds -Ids @($id) -MapTable $fullMap)
        }
    }
}

# history/titles active capital = X
foreach ($file in @(Get-ChildItem (Join-Path $root 'history\\titles') -File -Recurse -ErrorAction SilentlyContinue)) {
    $lines = @(Get-Content -Path $file.FullName)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $active = Get-ActiveContent -Line $lines[$i]
        if ($active -match 'capital\s*=\s*(\d+)') {
            $id = [int]$matches[1]
            Add-ReferenceRow -Rows $referenceRows -FilePath $file.FullName -Context 'history_titles_capital' -LineNumber ($i + 1) -ReferenceCount 1 -PreserveChangedCount (Count-ChangedIds -Ids @($id) -MapTable $preserveMap) -FullChangedCount (Count-ChangedIds -Ids @($id) -MapTable $fullMap)
        }
    }
}

# map_data/adjacencies.csv
$adjPath = Join-Path $root 'map_data\\adjacencies.csv'
$adjLines = @(Get-Content -Path $adjPath)
for ($i = 1; $i -lt $adjLines.Count; $i++) {
    $line = $adjLines[$i]
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
        continue
    }
    $parts = $line.Split(';')
    if ($parts.Count -lt 4) {
        continue
    }
    foreach ($pair in @(@('adjacencies_from', 0), @('adjacencies_to', 1), @('adjacencies_through', 3))) {
        $context = $pair[0]
        $index = $pair[1]
        if ($parts[$index] -match '^\d+$') {
            $id = [int]$parts[$index]
            Add-ReferenceRow -Rows $referenceRows -FilePath $adjPath -Context $context -LineNumber ($i + 1) -ReferenceCount 1 -PreserveChangedCount (Count-ChangedIds -Ids @($id) -MapTable $preserveMap) -FullChangedCount (Count-ChangedIds -Ids @($id) -MapTable $fullMap)
        }
    }
}

# map_data/default.map LIST/RANGE lines
$defaultMapPath = Join-Path $root 'map_data\\default.map'
$defaultLines = @(Get-Content -Path $defaultMapPath)
for ($i = 0; $i -lt $defaultLines.Count; $i++) {
    $active = Get-ActiveContent -Line $defaultLines[$i]
    if ($active -match '^\s*(\w+)\s*=\s*LIST\s*\{([^}]*)\}') {
        $context = "default_map_$($matches[1])_list"
        $ids = @([regex]::Matches($matches[2], '\b\d+\b') | ForEach-Object { [int]$_.Value })
        if ($ids.Count -gt 0) {
            Add-ReferenceRow -Rows $referenceRows -FilePath $defaultMapPath -Context $context -LineNumber ($i + 1) -ReferenceCount $ids.Count -PreserveChangedCount (Count-ChangedIds -Ids $ids -MapTable $preserveMap) -FullChangedCount (Count-ChangedIds -Ids $ids -MapTable $fullMap)
        }
    }
    elseif ($active -match '^\s*(\w+)\s*=\s*RANGE\s*\{([^}]*)\}') {
        $context = "default_map_$($matches[1])_range"
        $nums = @([regex]::Matches($matches[2], '\b\d+\b') | ForEach-Object { [int]$_.Value })
        if ($nums.Count -ge 2) {
            $start = $nums[0]
            $end = $nums[1]
            $ids = @()
            for ($id = $start; $id -le $end; $id++) {
                $ids += $id
            }
            Add-ReferenceRow -Rows $referenceRows -FilePath $defaultMapPath -Context $context -LineNumber ($i + 1) -ReferenceCount $ids.Count -PreserveChangedCount (Count-ChangedIds -Ids $ids -MapTable $preserveMap) -FullChangedCount (Count-ChangedIds -Ids $ids -MapTable $fullMap)
        }
    }
}

# provinces = { } blocks
Parse-ProvincesBlocks -FilePaths @((Join-Path $root 'map_data\\island_region.txt')) -Context 'map_data_island_region_provinces_block' -Rows $referenceRows -PreserveMap $preserveMap -FullMap $fullMap
Parse-ProvincesBlocks -FilePaths @(Get-ChildItem (Join-Path $root 'map_data\\geographical_regions') -File -Recurse | Select-Object -ExpandProperty FullName) -Context 'map_data_geographical_regions_provinces_block' -Rows $referenceRows -PreserveMap $preserveMap -FullMap $fullMap
Parse-ProvincesBlocks -FilePaths @(Get-ChildItem (Join-Path $root 'common\\connection_arrows') -File -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName) -Context 'common_connection_arrows_provinces_block' -Rows $referenceRows -PreserveMap $preserveMap -FullMap $fullMap

$byContextRows = New-Object System.Collections.Generic.List[object]
foreach ($group in @($referenceRows | Group-Object context | Sort-Object Name)) {
    $totalRefs = ($group.Group | Measure-Object -Property reference_count -Sum).Sum
    $preserveChanged = ($group.Group | Measure-Object -Property preserve_changed_count -Sum).Sum
    $fullChanged = ($group.Group | Measure-Object -Property full_changed_count -Sum).Sum
    $preserveLines = @($group.Group | Where-Object { $_.preserve_touches_line }).Count
    $fullLines = @($group.Group | Where-Object { $_.full_touches_line }).Count

    $byContextRows.Add([pscustomobject]@{
        context = $group.Name
        reference_rows = $group.Count
        total_references = $totalRefs
        preserve_changed_references = $preserveChanged
        preserve_touched_lines = $preserveLines
        full_changed_references = $fullChanged
        full_touched_lines = $fullLines
    }) | Out-Null
}

$byFileRows = New-Object System.Collections.Generic.List[object]
foreach ($group in @($referenceRows | Group-Object file_path | Sort-Object Name)) {
    $totalRefs = ($group.Group | Measure-Object -Property reference_count -Sum).Sum
    $preserveChanged = ($group.Group | Measure-Object -Property preserve_changed_count -Sum).Sum
    $fullChanged = ($group.Group | Measure-Object -Property full_changed_count -Sum).Sum
    $preserveLines = @($group.Group | Where-Object { $_.preserve_touches_line }).Count
    $fullLines = @($group.Group | Where-Object { $_.full_touches_line }).Count

    $byFileRows.Add([pscustomobject]@{
        file_path = $group.Name
        context_count = @($group.Group | Select-Object -ExpandProperty context -Unique).Count
        reference_rows = $group.Count
        total_references = $totalRefs
        preserve_changed_references = $preserveChanged
        preserve_touched_lines = $preserveLines
        full_changed_references = $fullChanged
        full_touched_lines = $fullLines
    }) | Out-Null
}

$byContextExportRows = @($byContextRows | Sort-Object context)
$byFileExportRows = @(
    $byFileRows | Sort-Object -Property @(
        @{ Expression = 'full_touched_lines'; Descending = $true }
        @{ Expression = 'preserve_touched_lines'; Descending = $true }
        @{ Expression = 'file_path'; Descending = $false }
    )
)
Export-Utf8Csv -Rows $byContextExportRows -Path $ByContextCsv
Export-Utf8Csv -Rows $byFileExportRows -Path $ByFileCsv

$totalPreserveChanged = ($referenceRows | Measure-Object -Property preserve_changed_count -Sum).Sum
$totalFullChanged = ($referenceRows | Measure-Object -Property full_changed_count -Sum).Sum
$totalPreserveTouchedLines = @($referenceRows | Where-Object { $_.preserve_touches_line }).Count
$totalFullTouchedLines = @($referenceRows | Where-Object { $_.full_touches_line }).Count

$summaryLines = @(
    '# ID Policy Repo Impact Summary',
    '',
    ('- by context csv: `{0}`' -f $ByContextCsv),
    ('- by file csv: `{0}`' -f $ByFileCsv),
    ('- preserve_old_ids changed references: `{0}`' -f $totalPreserveChanged),
    ('- preserve_old_ids touched lines: `{0}`' -f $totalPreserveTouchedLines),
    ('- full_renumber changed references: `{0}`' -f $totalFullChanged),
    ('- full_renumber touched lines: `{0}`' -f $totalFullTouchedLines),
    '',
    '## Top Contexts By Full-Renumber Touched Lines',
    ''
)

foreach ($row in @($byContextExportRows | Sort-Object full_touched_lines -Descending | Select-Object -First 12)) {
    $summaryLines += ('- `{0}` -> preserve lines `{1}`, full lines `{2}`' -f $row.context, $row.preserve_touched_lines, $row.full_touched_lines)
}

$summaryLines += ''
$summaryLines += '## Top Files By Full-Renumber Touched Lines'
$summaryLines += ''

foreach ($row in @($byFileExportRows | Select-Object -First 12)) {
    $summaryLines += ('- `{0}` -> preserve lines `{1}`, full lines `{2}`' -f $row.file_path, $row.preserve_touched_lines, $row.full_touched_lines)
}

[System.IO.File]::WriteAllLines($SummaryPath, $summaryLines, [System.Text.UTF8Encoding]::new($false))

Write-Output "Built ID policy repo impact summary under '$generatedDir'."
