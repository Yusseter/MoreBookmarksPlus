param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$MergeInventoryCsv = '',
    [string]$DecisionCsv = '',
    [string]$ApplyReportCsv = '',
    [string]$ResolvedInventoryCsv = '',
    [string]$CandidatesCsv = '',
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

if ([string]::IsNullOrWhiteSpace($MergeInventoryCsv)) {
    $MergeInventoryCsv = Join-Path $generatedDir 'definition_merge_inventory.csv'
}
if ([string]::IsNullOrWhiteSpace($DecisionCsv)) {
    $DecisionCsv = Join-Path $generatedDir 'definition_rgb_conflict_decisions.csv'
}
if ([string]::IsNullOrWhiteSpace($ApplyReportCsv)) {
    $ApplyReportCsv = Join-Path $generatedDir 'rgb_mapping_apply_report.csv'
}
if ([string]::IsNullOrWhiteSpace($ResolvedInventoryCsv)) {
    $ResolvedInventoryCsv = Join-Path $generatedDir 'definition_rgb_resolved_inventory.csv'
}
if ([string]::IsNullOrWhiteSpace($CandidatesCsv)) {
    $CandidatesCsv = Join-Path $generatedDir 'definition_rgb_resolved_candidates_pre_id.csv'
}
if ([string]::IsNullOrWhiteSpace($SummaryPath)) {
    $SummaryPath = Join-Path $generatedDir 'definition_rgb_resolved_summary.md'
}

Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($ResolvedInventoryCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($CandidatesCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($SummaryPath))

$mergeRows = @(Import-Csv -Path $MergeInventoryCsv)
$decisionRows = @(Import-Csv -Path $DecisionCsv)
$applyRows = @(Import-Csv -Path $ApplyReportCsv)

if ($mergeRows.Count -eq 0) {
    throw "Merge inventory is empty: $MergeInventoryCsv"
}

$decisionByRgb = @{}
foreach ($row in $decisionRows) {
    $decisionByRgb[[string]$row.rgb] = $row
}

$applyByOldRgb = @{}
foreach ($row in $applyRows) {
    $applyByOldRgb[[string]$row.shared_old_rgb] = $row
}

$recolorByRowKey = @{}
$keepByRowKey = @{}

foreach ($oldRgb in $decisionByRgb.Keys) {
    if (-not $applyByOldRgb.ContainsKey($oldRgb)) {
        continue
    }

    $decision = $decisionByRgb[$oldRgb]
    $apply = $applyByOldRgb[$oldRgb]
    $chosenNewRgb = [string]$apply.chosen_new_rgb

    if ([string]::IsNullOrWhiteSpace($chosenNewRgb)) {
        continue
    }

    if ([string]$apply.recolor_source -eq 'modlu') {
        $recolorKey = "modlu_kalan|$($decision.modlu_id)"
        $keepKey = "orijinal_dogu|$($decision.orijinal_id)"
    }
    elseif ([string]$apply.recolor_source -eq 'orijinal') {
        $recolorKey = "orijinal_dogu|$($decision.orijinal_id)"
        $keepKey = "modlu_kalan|$($decision.modlu_id)"
    }
    else {
        continue
    }

    $recolorByRowKey[$recolorKey] = [pscustomobject]@{
        shared_old_rgb = $oldRgb
        chosen_new_rgb = $chosenNewRgb
        keep_original_rgb_source = [string]$apply.keep_original_rgb_source
        recolor_source = [string]$apply.recolor_source
        basis = [string]$apply.basis
        basis_reason = [string]$apply.basis_reason
    }

    $keepByRowKey[$keepKey] = [pscustomobject]@{
        shared_old_rgb = $oldRgb
        chosen_new_rgb = $chosenNewRgb
        keep_original_rgb_source = [string]$apply.keep_original_rgb_source
        recolor_source = [string]$apply.recolor_source
        basis = [string]$apply.basis
        basis_reason = [string]$apply.basis_reason
    }
}

$resolvedRows = New-Object System.Collections.Generic.List[object]
$resolvedByKey = @{}

foreach ($row in $mergeRows) {
    $rowKey = "$($row.source_subset)|$($row.source_id)"

    $effectiveRgb = [string]$row.source_rgb
    $rgbResolutionStatus = 'unchanged'
    $sharedOldRgb = ''
    $chosenNewRgb = ''
    $keepOriginalRgbSource = ''
    $recolorSource = ''
    $rgbResolutionBasis = ''
    $rgbResolutionReason = ''

    if ($recolorByRowKey.ContainsKey($rowKey)) {
        $info = $recolorByRowKey[$rowKey]
        $effectiveRgb = [string]$info.chosen_new_rgb
        $rgbResolutionStatus = 'recolor_to_new_rgb'
        $sharedOldRgb = [string]$info.shared_old_rgb
        $chosenNewRgb = [string]$info.chosen_new_rgb
        $keepOriginalRgbSource = [string]$info.keep_original_rgb_source
        $recolorSource = [string]$info.recolor_source
        $rgbResolutionBasis = [string]$info.basis
        $rgbResolutionReason = [string]$info.basis_reason
    }
    elseif ($keepByRowKey.ContainsKey($rowKey)) {
        $info = $keepByRowKey[$rowKey]
        $rgbResolutionStatus = 'keep_original_shared_rgb'
        $sharedOldRgb = [string]$info.shared_old_rgb
        $chosenNewRgb = [string]$info.chosen_new_rgb
        $keepOriginalRgbSource = [string]$info.keep_original_rgb_source
        $recolorSource = [string]$info.recolor_source
        $rgbResolutionBasis = [string]$info.basis
        $rgbResolutionReason = [string]$info.basis_reason
    }
    elseif ([string]$row.primary_status -eq 'benign_shared') {
        $rgbResolutionStatus = 'benign_shared_keep_rgb'
    }

    $resolvedRow = [pscustomobject]@{
        source_subset = [string]$row.source_subset
        source_definition = [string]$row.source_definition
        source_id = [string]$row.source_id
        source_rgb = [string]$row.source_rgb
        effective_rgb = $effectiveRgb
        source_name = [string]$row.source_name
        primary_status = [string]$row.primary_status
        rgb_resolution_status = $rgbResolutionStatus
        shared_old_rgb = $sharedOldRgb
        chosen_new_rgb = $chosenNewRgb
        keep_original_rgb_source = $keepOriginalRgbSource
        recolor_source = $recolorSource
        rgb_resolution_basis = $rgbResolutionBasis
        rgb_resolution_reason = $rgbResolutionReason
        same_rgb_same_id = [string]$row.same_rgb_same_id
        same_rgb_diff_id = [string]$row.same_rgb_diff_id
        same_id_diff_rgb = [string]$row.same_id_diff_rgb
        name_divergence = [string]$row.name_divergence
        rgb_partner_subset = [string]$row.rgb_partner_subset
        rgb_partner_id = [string]$row.rgb_partner_id
        rgb_partner_rgb = [string]$row.rgb_partner_rgb
        rgb_partner_name = [string]$row.rgb_partner_name
        final_new_id = [string]$row.final_new_id
        final_id_status = [string]$row.final_id_status
        notes = [string]$row.notes
    }

    $resolvedRows.Add($resolvedRow) | Out-Null
    $resolvedByKey[$rowKey] = $resolvedRow
}

$resolvedExportRows = @($resolvedRows | Sort-Object source_subset, {[int]$_.source_id}, effective_rgb)
Export-Utf8Csv -Rows $resolvedExportRows -Path $ResolvedInventoryCsv

$candidateRows = New-Object System.Collections.Generic.List[object]
$processedBenignKeys = New-Object 'System.Collections.Generic.HashSet[string]'

foreach ($row in $resolvedExportRows) {
    $rowKey = "$($row.source_subset)|$($row.source_id)|$($row.source_rgb)"

    if ([string]$row.primary_status -eq 'benign_shared') {
        if ($processedBenignKeys.Contains($rowKey)) {
            continue
        }

        if ([string]$row.source_subset -ne 'modlu_kalan') {
            continue
        }

        $partnerKey = "orijinal_dogu|$($row.source_id)|$($row.source_rgb)"
        if (-not $processedBenignKeys.Contains($partnerKey)) {
            [void]$processedBenignKeys.Add($rowKey)
            [void]$processedBenignKeys.Add($partnerKey)
        }

        $partnerResolved = $null
        if ($resolvedByKey.ContainsKey("orijinal_dogu|$($row.source_id)")) {
            $candidatePartner = $resolvedByKey["orijinal_dogu|$($row.source_id)"]
            if ([string]$candidatePartner.source_rgb -eq [string]$row.source_rgb) {
                $partnerResolved = $candidatePartner
            }
        }

        $candidateRows.Add([pscustomobject]@{
            candidate_type = 'merged_benign_shared'
            source_origin = 'both'
            preferred_source_subset = 'modlu_kalan'
            effective_rgb = [string]$row.effective_rgb
            effective_name = [string]$row.source_name
            modlu_source_id = [string]$row.source_id
            modlu_source_rgb = [string]$row.source_rgb
            modlu_source_name = [string]$row.source_name
            orijinal_source_id = if ($partnerResolved) { [string]$partnerResolved.source_id } else { [string]$row.source_id }
            orijinal_source_rgb = if ($partnerResolved) { [string]$partnerResolved.source_rgb } else { [string]$row.source_rgb }
            orijinal_source_name = if ($partnerResolved) { [string]$partnerResolved.source_name } else { '' }
            primary_status = 'benign_shared'
            rgb_resolution_status = 'benign_shared_keep_rgb'
            source_id_conflict_status = [string]$row.primary_status
            final_new_id = ''
            final_id_status = [string]$row.final_id_status
            notes = 'Merged benign shared row before final ID assignment.'
        }) | Out-Null

        continue
    }

    $candidateRows.Add([pscustomobject]@{
        candidate_type = 'single_source'
        source_origin = if ([string]$row.source_subset -eq 'modlu_kalan') { 'modlu' } else { 'orijinal' }
        preferred_source_subset = [string]$row.source_subset
        effective_rgb = [string]$row.effective_rgb
        effective_name = [string]$row.source_name
        modlu_source_id = if ([string]$row.source_subset -eq 'modlu_kalan') { [string]$row.source_id } else { '' }
        modlu_source_rgb = if ([string]$row.source_subset -eq 'modlu_kalan') { [string]$row.source_rgb } else { '' }
        modlu_source_name = if ([string]$row.source_subset -eq 'modlu_kalan') { [string]$row.source_name } else { '' }
        orijinal_source_id = if ([string]$row.source_subset -eq 'orijinal_dogu') { [string]$row.source_id } else { '' }
        orijinal_source_rgb = if ([string]$row.source_subset -eq 'orijinal_dogu') { [string]$row.source_rgb } else { '' }
        orijinal_source_name = if ([string]$row.source_subset -eq 'orijinal_dogu') { [string]$row.source_name } else { '' }
        primary_status = [string]$row.primary_status
        rgb_resolution_status = [string]$row.rgb_resolution_status
        source_id_conflict_status = if ([string]$row.same_id_diff_rgb -eq 'True') { 'id_conflict' } else { 'no_id_conflict_flag' }
        final_new_id = ''
        final_id_status = [string]$row.final_id_status
        notes = [string]$row.notes
    }) | Out-Null
}

$candidateExportRows = @($candidateRows | Sort-Object preferred_source_subset, effective_rgb, effective_name)
Export-Utf8Csv -Rows $candidateExportRows -Path $CandidatesCsv

$recolorResolvedCount = @($resolvedExportRows | Where-Object { $_.rgb_resolution_status -eq 'recolor_to_new_rgb' }).Count
$keepResolvedCount = @($resolvedExportRows | Where-Object { $_.rgb_resolution_status -eq 'keep_original_shared_rgb' }).Count
$benignResolvedCount = @($resolvedExportRows | Where-Object { $_.rgb_resolution_status -eq 'benign_shared_keep_rgb' }).Count
$candidateMergedBenignCount = @($candidateExportRows | Where-Object { $_.candidate_type -eq 'merged_benign_shared' }).Count

$summaryLines = @(
    '# RGB Resolved Candidate Summary',
    '',
    ('- resolved inventory csv: `{0}`' -f $ResolvedInventoryCsv),
    ('- candidates csv: `{0}`' -f $CandidatesCsv),
    ('- resolved inventory rows: `{0}`' -f $resolvedExportRows.Count),
    ('- candidate rows pre-ID: `{0}`' -f $candidateExportRows.Count),
    ('- recolored rows: `{0}`' -f $recolorResolvedCount),
    ('- keep-original-shared-rgb rows: `{0}`' -f $keepResolvedCount),
    ('- benign-shared rows kept as-is in inventory: `{0}`' -f $benignResolvedCount),
    ('- benign-shared merged candidates: `{0}`' -f $candidateMergedBenignCount),
    '',
    '## Notes',
    '',
    '- `definition_rgb_resolved_inventory.csv` keeps all subset rows but applies the selected/effective RGB layer.',
    '- `definition_rgb_resolved_candidates_pre_id.csv` collapses benign shared duplicates before final ID assignment.',
    '- ID conflicts are still unresolved at this stage; `final_new_id` remains blank.',
    '',
    '## Sample Candidate Rows',
    ''
)

foreach ($row in @($candidateExportRows | Select-Object -First 12)) {
    $summaryLines += ('- `{0}` `{1}` RGB `{2}` name `{3}`' -f $row.candidate_type, $row.source_origin, $row.effective_rgb, $row.effective_name)
}

[System.IO.File]::WriteAllLines($SummaryPath, $summaryLines, [System.Text.UTF8Encoding]::new($false))

Write-Output "Built RGB-resolved inventory and pre-ID candidates under '$generatedDir'."
