param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$CandidatesCsv = '',
    [string]$CandidateInventoryCsv = '',
    [string]$DuplicateIdsCsv = '',
    [string]$GapRangesCsv = '',
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

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$generatedDir = Join-Path (Join-Path $root 'analysis') 'generated'

if ([string]::IsNullOrWhiteSpace($CandidatesCsv)) {
    $CandidatesCsv = Join-Path $generatedDir 'definition_rgb_resolved_candidates_pre_id.csv'
}
if ([string]::IsNullOrWhiteSpace($CandidateInventoryCsv)) {
    $CandidateInventoryCsv = Join-Path $generatedDir 'current_id_candidate_inventory.csv'
}
if ([string]::IsNullOrWhiteSpace($DuplicateIdsCsv)) {
    $DuplicateIdsCsv = Join-Path $generatedDir 'id_duplicates_pre_id.csv'
}
if ([string]::IsNullOrWhiteSpace($GapRangesCsv)) {
    $GapRangesCsv = Join-Path $generatedDir 'id_gap_ranges_pre_id.csv'
}
if ([string]::IsNullOrWhiteSpace($SummaryPath)) {
    $SummaryPath = Join-Path $generatedDir 'id_strategy_pre_id_summary.md'
}

Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($CandidateInventoryCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($DuplicateIdsCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($GapRangesCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($SummaryPath))

$candidateRows = @(Import-Csv -Path $CandidatesCsv)
if ($candidateRows.Count -eq 0) {
    throw "Candidate CSV is empty: $CandidatesCsv"
}

$inventoryRows = New-Object System.Collections.Generic.List[object]
foreach ($row in $candidateRows) {
    $currentId = if (-not [string]::IsNullOrWhiteSpace([string]$row.modlu_source_id)) {
        [int]$row.modlu_source_id
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$row.orijinal_source_id)) {
        [int]$row.orijinal_source_id
    }
    else {
        throw "Candidate row missing both modlu_source_id and orijinal_source_id."
    }

    $inventoryRows.Add([pscustomobject]@{
        candidate_type = [string]$row.candidate_type
        source_origin = [string]$row.source_origin
        preferred_source_subset = [string]$row.preferred_source_subset
        current_id = $currentId
        effective_rgb = [string]$row.effective_rgb
        effective_name = [string]$row.effective_name
        modlu_source_id = [string]$row.modlu_source_id
        modlu_source_rgb = [string]$row.modlu_source_rgb
        modlu_source_name = [string]$row.modlu_source_name
        orijinal_source_id = [string]$row.orijinal_source_id
        orijinal_source_rgb = [string]$row.orijinal_source_rgb
        orijinal_source_name = [string]$row.orijinal_source_name
        primary_status = [string]$row.primary_status
        rgb_resolution_status = [string]$row.rgb_resolution_status
        source_id_conflict_status = [string]$row.source_id_conflict_status
        final_new_id = [string]$row.final_new_id
        final_id_status = [string]$row.final_id_status
        notes = [string]$row.notes
    }) | Out-Null
}

$inventoryExportRows = @($inventoryRows | Sort-Object current_id, effective_rgb, effective_name)
Export-Utf8Csv -Rows $inventoryExportRows -Path $CandidateInventoryCsv

$duplicateGroups = @($inventoryExportRows | Group-Object current_id | Where-Object { $_.Count -gt 1 } | Sort-Object {[int]$_.Name})
$duplicateRows = New-Object System.Collections.Generic.List[object]
foreach ($group in $duplicateGroups) {
    foreach ($row in $group.Group) {
        $duplicateRows.Add([pscustomobject]@{
            current_id = [int]$group.Name
            duplicate_group_size = $group.Count
            candidate_type = $row.candidate_type
            source_origin = $row.source_origin
            preferred_source_subset = $row.preferred_source_subset
            effective_rgb = $row.effective_rgb
            effective_name = $row.effective_name
            modlu_source_id = $row.modlu_source_id
            orijinal_source_id = $row.orijinal_source_id
            primary_status = $row.primary_status
            rgb_resolution_status = $row.rgb_resolution_status
            source_id_conflict_status = $row.source_id_conflict_status
            notes = $row.notes
        }) | Out-Null
    }
}
$duplicateExportRows = @($duplicateRows | Sort-Object current_id, source_origin, effective_rgb)
Export-Utf8Csv -Rows $duplicateExportRows -Path $DuplicateIdsCsv

$uniqueIds = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($row in $inventoryExportRows) {
    [void]$uniqueIds.Add([int]$row.current_id)
}

$maxId = ($inventoryExportRows | Measure-Object -Property current_id -Maximum).Maximum
$gapRanges = New-Object System.Collections.Generic.List[object]
$gapStart = $null
$previousMissing = $null
$missingIdCount = 0

for ($id = 1; $id -le $maxId; $id++) {
    if (-not $uniqueIds.Contains($id)) {
        $missingIdCount += 1
        if ($null -eq $gapStart) {
            $gapStart = $id
            $previousMissing = $id
        }
        elseif ($id -eq ($previousMissing + 1)) {
            $previousMissing = $id
        }
        else {
            $gapRanges.Add([pscustomobject]@{
                gap_start = $gapStart
                gap_end = $previousMissing
                gap_length = ($previousMissing - $gapStart + 1)
            }) | Out-Null
            $gapStart = $id
            $previousMissing = $id
        }
    }
}

if ($null -ne $gapStart) {
    $gapRanges.Add([pscustomobject]@{
        gap_start = $gapStart
        gap_end = $previousMissing
        gap_length = ($previousMissing - $gapStart + 1)
    }) | Out-Null
}

$gapRangeExportRows = @($gapRanges | Sort-Object gap_start)
Export-Utf8Csv -Rows $gapRangeExportRows -Path $GapRangesCsv

$duplicateGroupCount = $duplicateGroups.Count
$duplicateRowCount = $duplicateExportRows.Count
$newIdsNeededIfKeepOnePerDuplicateGroup = $duplicateRowCount - $duplicateGroupCount

$summaryLines = @(
    '# Pre-ID Strategy Summary',
    '',
    ('- candidates csv: `{0}`' -f $CandidatesCsv),
    ('- candidate inventory csv: `{0}`' -f $CandidateInventoryCsv),
    ('- duplicate ids csv: `{0}`' -f $DuplicateIdsCsv),
    ('- gap ranges csv: `{0}`' -f $GapRangesCsv),
    ('- candidate row count: `{0}`' -f $inventoryExportRows.Count),
    ('- unique current ID count: `{0}`' -f $uniqueIds.Count),
    ('- max current ID: `{0}`' -f $maxId),
    ('- duplicate current ID groups: `{0}`' -f $duplicateGroupCount),
    ('- duplicate current ID rows: `{0}`' -f $duplicateRowCount),
    ('- new IDs needed if one row per duplicate group keeps its old ID: `{0}`' -f $newIdsNeededIfKeepOnePerDuplicateGroup),
    ('- missing ID count from 1..max current ID: `{0}`' -f $missingIdCount),
    ('- gap range count: `{0}`' -f $gapRangeExportRows.Count),
    ('- placeholder count needed to keep all unique old IDs contiguous up to max: `{0}`' -f $missingIdCount),
    '',
    '## Notes',
    '',
    '- This summary describes the candidate set after RGB resolution but before final ID assignment.',
    '- Duplicate IDs show how many rows cannot keep the same current ID simultaneously.',
    '- Missing IDs show the placeholder burden if continuity is enforced while preserving unique existing IDs.',
    '',
    '## Sample Duplicate ID Groups',
    ''
)

foreach ($group in @($duplicateGroups | Select-Object -First 12)) {
    $summaryLines += ('- current ID `{0}` appears `{1}` times' -f $group.Name, $group.Count)
}

$summaryLines += ''
$summaryLines += '## Sample Gap Ranges'
$summaryLines += ''

foreach ($gap in @($gapRangeExportRows | Select-Object -First 12)) {
    $summaryLines += ('- gap `{0}` -> `{1}` length `{2}`' -f $gap.gap_start, $gap.gap_end, $gap.gap_length)
}

[System.IO.File]::WriteAllLines($SummaryPath, $summaryLines, [System.Text.UTF8Encoding]::new($false))

Write-Output "Analyzed pre-ID strategy under '$generatedDir'."
