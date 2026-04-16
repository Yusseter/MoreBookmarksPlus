param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$CandidatesCsv = '',
    [string]$PreserveAssignmentsCsv = '',
    [string]$PreservePlaceholdersCsv = '',
    [string]$PreserveModMapCsv = '',
    [string]$PreserveOrijinalMapCsv = '',
    [string]$FullAssignmentsCsv = '',
    [string]$FullModMapCsv = '',
    [string]$FullOrijinalMapCsv = '',
    [string]$SourceBurdenCsv = '',
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

function Parse-RgbKey {
    param([string]$Rgb)

    $parts = $Rgb.Split(',')
    if ($parts.Count -ne 3) {
        throw "Invalid RGB string: $Rgb"
    }
    return (Get-RgbKey -R ([int]$parts[0]) -G ([int]$parts[1]) -B ([int]$parts[2]))
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

function Get-CandidateRows {
    param([string]$Path)

    $rows = @(Import-Csv -Path $Path)
    $list = New-Object System.Collections.Generic.List[object]

    foreach ($row in $rows) {
        $currentId = if (-not [string]::IsNullOrWhiteSpace([string]$row.modlu_source_id)) {
            [int]$row.modlu_source_id
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$row.orijinal_source_id)) {
            [int]$row.orijinal_source_id
        }
        else {
            throw "Candidate row missing both modlu_source_id and orijinal_source_id."
        }

        $subsetPriority = if ([string]$row.preferred_source_subset -eq 'modlu_kalan') { 0 } elseif ([string]$row.preferred_source_subset -eq 'orijinal_dogu') { 1 } else { 9 }
        $candidatePriority = if ([string]$row.candidate_type -eq 'merged_benign_shared') { 0 } else { 1 }

        $list.Add([pscustomobject]@{
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
            preserve_priority_subset = $subsetPriority
            preserve_priority_candidate = $candidatePriority
        }) | Out-Null
    }

    return $list.ToArray()
}

function New-AssignmentRow {
    param(
        $Candidate,
        [int]$FinalNewId,
        [string]$PolicyName,
        [string]$AssignmentType,
        [bool]$KeepsCurrentId,
        [string]$IdChangeReason
    )

    return [pscustomobject]@{
        policy_name = $PolicyName
        row_type = 'candidate'
        assignment_type = $AssignmentType
        final_new_id = $FinalNewId
        current_id = $Candidate.current_id
        keeps_current_id = $KeepsCurrentId
        id_change_reason = $IdChangeReason
        placeholder_reason = ''
        effective_rgb = $Candidate.effective_rgb
        effective_name = $Candidate.effective_name
        candidate_type = $Candidate.candidate_type
        source_origin = $Candidate.source_origin
        preferred_source_subset = $Candidate.preferred_source_subset
        modlu_source_id = $Candidate.modlu_source_id
        modlu_source_rgb = $Candidate.modlu_source_rgb
        modlu_source_name = $Candidate.modlu_source_name
        orijinal_source_id = $Candidate.orijinal_source_id
        orijinal_source_rgb = $Candidate.orijinal_source_rgb
        orijinal_source_name = $Candidate.orijinal_source_name
        primary_status = $Candidate.primary_status
        rgb_resolution_status = $Candidate.rgb_resolution_status
        source_id_conflict_status = $Candidate.source_id_conflict_status
        final_id_status = if ($KeepsCurrentId) { 'draft_keep_id' } else { 'draft_new_id' }
        notes = $Candidate.notes
    }
}

function New-PlaceholderRow {
    param(
        [string]$PolicyName,
        [int]$FinalNewId,
        [string]$PlaceholderRgb,
        [string]$PlaceholderReason
    )

    return [pscustomobject]@{
        policy_name = $PolicyName
        row_type = 'placeholder'
        assignment_type = 'placeholder_fill'
        final_new_id = $FinalNewId
        current_id = ''
        keeps_current_id = $false
        id_change_reason = ''
        placeholder_reason = $PlaceholderReason
        effective_rgb = $PlaceholderRgb
        effective_name = ('zz_placeholder_{0}' -f $FinalNewId)
        candidate_type = ''
        source_origin = 'placeholder'
        preferred_source_subset = 'placeholder'
        modlu_source_id = ''
        modlu_source_rgb = ''
        modlu_source_name = ''
        orijinal_source_id = ''
        orijinal_source_rgb = ''
        orijinal_source_name = ''
        primary_status = 'placeholder'
        rgb_resolution_status = 'placeholder'
        source_id_conflict_status = 'placeholder'
        final_id_status = 'draft_placeholder'
        notes = 'Draft placeholder row to preserve contiguous IDs in old-id-heavy policy.'
    }
}

function Build-IdMapRows {
    param(
        [object[]]$AssignmentRows,
        [string]$SourceLabel
    )

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($row in $AssignmentRows) {
        if ([string]$row.row_type -ne 'candidate') {
            continue
        }

        if ($SourceLabel -eq 'modlu') {
            if ([string]::IsNullOrWhiteSpace([string]$row.modlu_source_id)) {
                continue
            }
            $rows.Add([pscustomobject]@{
                source_label = 'modlu'
                old_id = $row.modlu_source_id
                final_new_id = $row.final_new_id
                old_rgb = $row.modlu_source_rgb
                effective_rgb = $row.effective_rgb
                old_name = $row.modlu_source_name
                effective_name = $row.effective_name
                policy_name = $row.policy_name
                keeps_current_id = $row.keeps_current_id
                assignment_type = $row.assignment_type
                id_change_reason = $row.id_change_reason
                notes = $row.notes
            }) | Out-Null
        }
        else {
            if ([string]::IsNullOrWhiteSpace([string]$row.orijinal_source_id)) {
                continue
            }
            $rows.Add([pscustomobject]@{
                source_label = 'orijinal'
                old_id = $row.orijinal_source_id
                final_new_id = $row.final_new_id
                old_rgb = $row.orijinal_source_rgb
                effective_rgb = $row.effective_rgb
                old_name = $row.orijinal_source_name
                effective_name = $row.effective_name
                policy_name = $row.policy_name
                keeps_current_id = $row.keeps_current_id
                assignment_type = $row.assignment_type
                id_change_reason = $row.id_change_reason
                notes = $row.notes
            }) | Out-Null
        }
    }

    return $rows.ToArray()
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$generatedDir = Join-Path (Join-Path $root 'analysis') 'generated'

if ([string]::IsNullOrWhiteSpace($CandidatesCsv)) {
    $CandidatesCsv = Join-Path $generatedDir 'definition_rgb_resolved_candidates_pre_id.csv'
}
if ([string]::IsNullOrWhiteSpace($PreserveAssignmentsCsv)) {
    $PreserveAssignmentsCsv = Join-Path $generatedDir 'id_policy_preserve_old_assignments.csv'
}
if ([string]::IsNullOrWhiteSpace($PreservePlaceholdersCsv)) {
    $PreservePlaceholdersCsv = Join-Path $generatedDir 'id_policy_preserve_old_placeholders.csv'
}
if ([string]::IsNullOrWhiteSpace($PreserveModMapCsv)) {
    $PreserveModMapCsv = Join-Path $generatedDir 'id_map_modlu_preserve_old.csv'
}
if ([string]::IsNullOrWhiteSpace($PreserveOrijinalMapCsv)) {
    $PreserveOrijinalMapCsv = Join-Path $generatedDir 'id_map_orijinal_preserve_old.csv'
}
if ([string]::IsNullOrWhiteSpace($FullAssignmentsCsv)) {
    $FullAssignmentsCsv = Join-Path $generatedDir 'id_policy_full_renumber_assignments.csv'
}
if ([string]::IsNullOrWhiteSpace($FullModMapCsv)) {
    $FullModMapCsv = Join-Path $generatedDir 'id_map_modlu_full_renumber.csv'
}
if ([string]::IsNullOrWhiteSpace($FullOrijinalMapCsv)) {
    $FullOrijinalMapCsv = Join-Path $generatedDir 'id_map_orijinal_full_renumber.csv'
}
if ([string]::IsNullOrWhiteSpace($SourceBurdenCsv)) {
    $SourceBurdenCsv = Join-Path $generatedDir 'id_policy_source_burden.csv'
}
if ([string]::IsNullOrWhiteSpace($SummaryPath)) {
    $SummaryPath = Join-Path $generatedDir 'id_policy_drafts_summary.md'
}

Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($PreserveAssignmentsCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($PreservePlaceholdersCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($PreserveModMapCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($PreserveOrijinalMapCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($FullAssignmentsCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($FullModMapCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($FullOrijinalMapCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($SourceBurdenCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($SummaryPath))

$candidateRows = @(Get-CandidateRows -Path $CandidatesCsv)
if ($candidateRows.Count -eq 0) {
    throw "Candidate rows are empty."
}

$currentIdGroups = @($candidateRows | Group-Object current_id | Sort-Object {[int]$_.Name})
$maxCurrentId = ($candidateRows | Measure-Object -Property current_id -Maximum).Maximum

# Policy A: preserve as many current IDs as possible, prefer modlu rows in duplicate groups,
# assign displaced rows into existing gaps first, then use placeholders for remaining gaps.
$preserveAssignments = New-Object System.Collections.Generic.List[object]
$preserveKeptIds = New-Object 'System.Collections.Generic.HashSet[int]'
$preserveDisplaced = New-Object System.Collections.Generic.List[object]

foreach ($group in $currentIdGroups) {
    $sortedGroup = @(
        $group.Group |
            Sort-Object preserve_priority_subset, preserve_priority_candidate, preferred_source_subset, source_origin, effective_rgb, effective_name
    )

    $keeper = $sortedGroup[0]
    $preserveAssignments.Add((New-AssignmentRow -Candidate $keeper -FinalNewId $keeper.current_id -PolicyName 'preserve_old_ids' -AssignmentType 'keep_current_id' -KeepsCurrentId $true -IdChangeReason '')) | Out-Null
    [void]$preserveKeptIds.Add([int]$keeper.current_id)

    if ($sortedGroup.Count -gt 1) {
        for ($i = 1; $i -lt $sortedGroup.Count; $i++) {
            $preserveDisplaced.Add($sortedGroup[$i]) | Out-Null
        }
    }
}

$availableGapIds = New-Object System.Collections.Generic.List[int]
for ($id = 1; $id -le $maxCurrentId; $id++) {
    if (-not $preserveKeptIds.Contains($id)) {
        $availableGapIds.Add($id) | Out-Null
    }
}

$gapIndex = 0
$nextAppendedId = $maxCurrentId + 1
foreach ($candidate in $preserveDisplaced) {
    if ($gapIndex -lt $availableGapIds.Count) {
        $assignedId = $availableGapIds[$gapIndex]
        $gapIndex += 1
        $reason = 'duplicate_current_id_reassigned_into_existing_gap'
    }
    else {
        $assignedId = $nextAppendedId
        $nextAppendedId += 1
        $reason = 'duplicate_current_id_reassigned_after_max_id'
    }

    $preserveAssignments.Add((New-AssignmentRow -Candidate $candidate -FinalNewId $assignedId -PolicyName 'preserve_old_ids' -AssignmentType 'reassigned_duplicate' -KeepsCurrentId $false -IdChangeReason $reason)) | Out-Null
}

$usedPreserveFinalIds = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($row in $preserveAssignments) {
    [void]$usedPreserveFinalIds.Add([int]$row.final_new_id)
}

$remainingPlaceholderIds = New-Object System.Collections.Generic.List[int]
$preserveFinalMaxId = [Math]::Max($maxCurrentId, $nextAppendedId - 1)
for ($id = 1; $id -le $preserveFinalMaxId; $id++) {
    if (-not $usedPreserveFinalIds.Contains($id)) {
        $remainingPlaceholderIds.Add($id) | Out-Null
    }
}

$usedRgbKeys = New-Object System.Collections.Generic.List[int]
foreach ($candidate in $candidateRows) {
    $usedRgbKeys.Add((Parse-RgbKey -Rgb $candidate.effective_rgb)) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($candidate.modlu_source_rgb)) {
        $usedRgbKeys.Add((Parse-RgbKey -Rgb $candidate.modlu_source_rgb)) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($candidate.orijinal_source_rgb)) {
        $usedRgbKeys.Add((Parse-RgbKey -Rgb $candidate.orijinal_source_rgb)) | Out-Null
    }
}
$placeholderRgbKeys = Get-SuggestedRgbKeys -UsedRgbKeys $usedRgbKeys -Count $remainingPlaceholderIds.Count

$preservePlaceholderRows = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $remainingPlaceholderIds.Count; $i++) {
    $preservePlaceholderRows.Add((New-PlaceholderRow -PolicyName 'preserve_old_ids' -FinalNewId $remainingPlaceholderIds[$i] -PlaceholderRgb (Format-Rgb -RgbKey $placeholderRgbKeys[$i]) -PlaceholderReason 'fill_remaining_gap_to_keep_ids_contiguous')) | Out-Null
}

$preserveAssignmentExportRows = @($preserveAssignments | Sort-Object final_new_id, effective_rgb, effective_name)
$preservePlaceholderExportRows = @($preservePlaceholderRows | Sort-Object final_new_id)
Export-Utf8Csv -Rows $preserveAssignmentExportRows -Path $PreserveAssignmentsCsv
Export-Utf8Csv -Rows $preservePlaceholderExportRows -Path $PreservePlaceholdersCsv

$preserveModMapRows = @(Build-IdMapRows -AssignmentRows $preserveAssignmentExportRows -SourceLabel 'modlu' | Sort-Object {[int]$_.old_id}, {[int]$_.final_new_id})
$preserveOrijinalMapRows = @(Build-IdMapRows -AssignmentRows $preserveAssignmentExportRows -SourceLabel 'orijinal' | Sort-Object {[int]$_.old_id}, {[int]$_.final_new_id})
Export-Utf8Csv -Rows $preserveModMapRows -Path $PreserveModMapCsv
Export-Utf8Csv -Rows $preserveOrijinalMapRows -Path $PreserveOrijinalMapCsv

# Policy B: full renumber, contiguous final_new_id without placeholders.
$fullAssignments = New-Object System.Collections.Generic.List[object]
$fullSortedCandidates = @(
    $candidateRows |
        Sort-Object current_id, preserve_priority_subset, preserve_priority_candidate, preferred_source_subset, source_origin, effective_rgb, effective_name
)

for ($i = 0; $i -lt $fullSortedCandidates.Count; $i++) {
    $candidate = $fullSortedCandidates[$i]
    $newId = $i + 1
    $keepsCurrentId = ($candidate.current_id -eq $newId)
    $reason = if ($keepsCurrentId) { '' } else { 'full_renumber_policy_reassigned' }
    $assignmentType = if ($keepsCurrentId) { 'kept_by_position' } else { 'renumbered' }
    $fullAssignments.Add((New-AssignmentRow -Candidate $candidate -FinalNewId $newId -PolicyName 'full_renumber' -AssignmentType $assignmentType -KeepsCurrentId $keepsCurrentId -IdChangeReason $reason)) | Out-Null
}

$fullAssignmentExportRows = @($fullAssignments | Sort-Object final_new_id)
Export-Utf8Csv -Rows $fullAssignmentExportRows -Path $FullAssignmentsCsv

$fullModMapRows = @(Build-IdMapRows -AssignmentRows $fullAssignmentExportRows -SourceLabel 'modlu' | Sort-Object {[int]$_.old_id}, {[int]$_.final_new_id})
$fullOrijinalMapRows = @(Build-IdMapRows -AssignmentRows $fullAssignmentExportRows -SourceLabel 'orijinal' | Sort-Object {[int]$_.old_id}, {[int]$_.final_new_id})
Export-Utf8Csv -Rows $fullModMapRows -Path $FullModMapCsv
Export-Utf8Csv -Rows $fullOrijinalMapRows -Path $FullOrijinalMapCsv

$preserveKeepCount = @($preserveAssignmentExportRows | Where-Object { $_.keeps_current_id -eq $true }).Count
$preserveChangedCount = @($preserveAssignmentExportRows | Where-Object { $_.keeps_current_id -ne $true }).Count
$fullKeepCount = @($fullAssignmentExportRows | Where-Object { $_.keeps_current_id -eq $true }).Count
$fullChangedCount = @($fullAssignmentExportRows | Where-Object { $_.keeps_current_id -ne $true }).Count
$preservePlaceholderCount = $preservePlaceholderExportRows.Count
$preserveAppendedCount = @($preserveAssignmentExportRows | Where-Object { $_.id_change_reason -eq 'duplicate_current_id_reassigned_after_max_id' }).Count
$preserveGapReuseCount = @($preserveAssignmentExportRows | Where-Object { $_.id_change_reason -eq 'duplicate_current_id_reassigned_into_existing_gap' }).Count

$sourceBurdenRows = New-Object System.Collections.Generic.List[object]
foreach ($policyName in @('preserve_old_ids', 'full_renumber')) {
    $rows = if ($policyName -eq 'preserve_old_ids') { $preserveAssignmentExportRows } else { $fullAssignmentExportRows }
    foreach ($group in @($rows | Group-Object source_origin, keeps_current_id | Sort-Object Name)) {
        $parts = $group.Name.Split(',').Trim()
        $sourceOrigin = $parts[0]
        $keepsCurrentId = $parts[1]
        $sourceBurdenRows.Add([pscustomobject]@{
            policy_name = $policyName
            source_origin = $sourceOrigin
            keeps_current_id = $keepsCurrentId
            row_count = $group.Count
        }) | Out-Null
    }
}
$sourceBurdenExportRows = @($sourceBurdenRows | Sort-Object policy_name, source_origin, keeps_current_id)
Export-Utf8Csv -Rows $sourceBurdenExportRows -Path $SourceBurdenCsv

$preserveModChanged = @($preserveAssignmentExportRows | Where-Object { $_.preferred_source_subset -eq 'modlu_kalan' -and $_.keeps_current_id -ne $true }).Count
$preserveOrijinalChanged = @($preserveAssignmentExportRows | Where-Object { $_.preferred_source_subset -eq 'orijinal_dogu' -and $_.keeps_current_id -ne $true }).Count
$fullModChanged = @($fullAssignmentExportRows | Where-Object { $_.preferred_source_subset -eq 'modlu_kalan' -and $_.keeps_current_id -ne $true }).Count
$fullOrijinalChanged = @($fullAssignmentExportRows | Where-Object { $_.preferred_source_subset -eq 'orijinal_dogu' -and $_.keeps_current_id -ne $true }).Count

$summaryLines = @(
    '# ID Policy Draft Summary',
    '',
    '## Generated Files',
    '',
    ('- preserve assignments: `{0}`' -f $PreserveAssignmentsCsv),
    ('- preserve placeholders: `{0}`' -f $PreservePlaceholdersCsv),
    ('- preserve mod map: `{0}`' -f $PreserveModMapCsv),
    ('- preserve orijinal map: `{0}`' -f $PreserveOrijinalMapCsv),
    ('- full renumber assignments: `{0}`' -f $FullAssignmentsCsv),
    ('- full renumber mod map: `{0}`' -f $FullModMapCsv),
    ('- full renumber orijinal map: `{0}`' -f $FullOrijinalMapCsv),
    ('- source burden csv: `{0}`' -f $SourceBurdenCsv),
    '',
    '## Policy A: Preserve Old IDs (Draft)',
    '',
    '- intent: keep as many existing IDs as possible',
    '- tie-break for duplicate ID groups: prefer `modlu_kalan`, then deterministic lexical order',
    ('- candidate rows keeping current ID: `{0}`' -f $preserveKeepCount),
    ('- candidate rows getting new ID: `{0}`' -f $preserveChangedCount),
    ('- displaced duplicate rows reassigned into existing gaps: `{0}`' -f $preserveGapReuseCount),
    ('- displaced duplicate rows appended after max old ID: `{0}`' -f $preserveAppendedCount),
    ('- placeholder rows still required for contiguity: `{0}`' -f $preservePlaceholderCount),
    ('- final max ID under policy A: `{0}`' -f $preserveFinalMaxId),
    ('- changed modlu_kalan rows: `{0}`' -f $preserveModChanged),
    ('- changed orijinal_dogu rows: `{0}`' -f $preserveOrijinalChanged),
    '',
    '## Policy B: Full Renumber (Draft)',
    '',
    '- intent: assign dense contiguous IDs to real rows only',
    '- ordering: current_id asc, then preferred source subset priority, then deterministic lexical order',
    ('- candidate rows keeping current ID by coincidence: `{0}`' -f $fullKeepCount),
    ('- candidate rows changing ID: `{0}`' -f $fullChangedCount),
    ('- placeholder rows required: `0`' ),
    ('- final max ID under policy B: `{0}`' -f $fullAssignmentExportRows.Count),
    ('- changed modlu_kalan rows: `{0}`' -f $fullModChanged),
    ('- changed orijinal_dogu rows: `{0}`' -f $fullOrijinalChanged),
    '',
    '## Notes',
    '',
    '- Neither draft writes into actual game definition files yet.',
    '- Both drafts keep provenance fields through the source-specific ID maps.',
    '- Policy A minimizes changed IDs but still leaves a substantial placeholder burden.',
    '- Policy B maximizes renumbering but removes the placeholder burden completely.',
    '',
    '## Sample Preserve-Policy Rows',
    ''
)

foreach ($row in @($preserveAssignmentExportRows | Select-Object -First 12)) {
    $summaryLines += ('- final `{0}` <= current `{1}` `{2}`' -f $row.final_new_id, $row.current_id, $row.effective_name)
}

$summaryLines += ''
$summaryLines += '## Sample Full-Renumber Rows'
$summaryLines += ''

foreach ($row in @($fullAssignmentExportRows | Select-Object -First 12)) {
    $summaryLines += ('- final `{0}` <= current `{1}` `{2}`' -f $row.final_new_id, $row.current_id, $row.effective_name)
}

[System.IO.File]::WriteAllLines($SummaryPath, $summaryLines, [System.Text.UTF8Encoding]::new($false))

Write-Output "Built ID policy drafts under '$generatedDir'."
