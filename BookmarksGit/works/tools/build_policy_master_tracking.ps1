param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$AssignmentCsv = '',
    [string]$AssignmentPlaceholderCsv = '',
    [string]$MasterCsv = '',
    [string]$ModluTrackingCsv = '',
    [string]$OrijinalTrackingCsv = '',
    [string]$PlaceholderCsv = '',
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

function As-Bool {
    param($Value)

    if ($null -eq $Value) {
        return $false
    }

    return ([string]$Value).Trim().ToLowerInvariant() -eq 'true'
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$generatedDir = Join-Path (Join-Path $root 'analysis') 'generated'

if ([string]::IsNullOrWhiteSpace($AssignmentCsv)) {
    $AssignmentCsv = Join-Path $generatedDir 'id_policy_preserve_old_assignments.csv'
}

$assignmentRows = @(Import-Csv -Path $AssignmentCsv)
if ($assignmentRows.Count -eq 0) {
    throw "No assignment rows found in '$AssignmentCsv'."
}

$policyName = [string]$assignmentRows[0].policy_name
if ([string]::IsNullOrWhiteSpace($policyName)) {
    $policyName = 'unknown_policy'
}

if ([string]::IsNullOrWhiteSpace($MasterCsv)) {
    $MasterCsv = Join-Path $generatedDir ("final_master_{0}.csv" -f $policyName)
}
if ([string]::IsNullOrWhiteSpace($AssignmentPlaceholderCsv)) {
    $defaultPlaceholderInput = Join-Path $generatedDir ("id_policy_{0}_placeholders.csv" -f ($policyName -replace '_ids$', ''))
    if (Test-Path -LiteralPath $defaultPlaceholderInput) {
        $AssignmentPlaceholderCsv = $defaultPlaceholderInput
    }
}
if ([string]::IsNullOrWhiteSpace($ModluTrackingCsv)) {
    $ModluTrackingCsv = Join-Path $generatedDir ("final_modlu_tracking_{0}.csv" -f $policyName)
}
if ([string]::IsNullOrWhiteSpace($OrijinalTrackingCsv)) {
    $OrijinalTrackingCsv = Join-Path $generatedDir ("final_orijinal_tracking_{0}.csv" -f $policyName)
}
if ([string]::IsNullOrWhiteSpace($PlaceholderCsv)) {
    $PlaceholderCsv = Join-Path $generatedDir ("final_placeholder_inventory_{0}.csv" -f $policyName)
}
if ([string]::IsNullOrWhiteSpace($SummaryPath)) {
    $SummaryPath = Join-Path $generatedDir ("final_tracking_summary_{0}.md" -f $policyName)
}

Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($MasterCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($ModluTrackingCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($OrijinalTrackingCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($PlaceholderCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($SummaryPath))

$supplementalPlaceholderRows = @()
if (-not [string]::IsNullOrWhiteSpace($AssignmentPlaceholderCsv) -and (Test-Path -LiteralPath $AssignmentPlaceholderCsv)) {
    $supplementalPlaceholderRows = @(Import-Csv -Path $AssignmentPlaceholderCsv)
}

$allInputRows = @($assignmentRows + $supplementalPlaceholderRows)

$masterRows = New-Object System.Collections.Generic.List[object]
$modluTrackingRows = New-Object System.Collections.Generic.List[object]
$orijinalTrackingRows = New-Object System.Collections.Generic.List[object]
$placeholderRows = New-Object System.Collections.Generic.List[object]

foreach ($row in $allInputRows) {
    $finalId = if ([string]::IsNullOrWhiteSpace([string]$row.final_new_id)) { '' } else { [int]$row.final_new_id }
    $currentId = if ([string]::IsNullOrWhiteSpace([string]$row.current_id)) { '' } else { [int]$row.current_id }
    $modluOldId = if ([string]::IsNullOrWhiteSpace([string]$row.modlu_source_id)) { '' } else { [int]$row.modlu_source_id }
    $orijinalOldId = if ([string]::IsNullOrWhiteSpace([string]$row.orijinal_source_id)) { '' } else { [int]$row.orijinal_source_id }
    $keepsCurrentId = As-Bool -Value $row.keeps_current_id

    $masterRows.Add([pscustomobject]@{
        policy_name = $policyName
        final_new_id = $finalId
        row_type = [string]$row.row_type
        assignment_type = [string]$row.assignment_type
        effective_rgb = [string]$row.effective_rgb
        effective_name = [string]$row.effective_name
        source_origin = [string]$row.source_origin
        preferred_source_subset = [string]$row.preferred_source_subset
        candidate_type = [string]$row.candidate_type
        current_id = $currentId
        keeps_current_id = $keepsCurrentId
        id_change_reason = [string]$row.id_change_reason
        placeholder_reason = [string]$row.placeholder_reason
        modlu_old_id = $modluOldId
        modlu_old_rgb = [string]$row.modlu_source_rgb
        modlu_old_name = [string]$row.modlu_source_name
        orijinal_old_id = $orijinalOldId
        orijinal_old_rgb = [string]$row.orijinal_source_rgb
        orijinal_old_name = [string]$row.orijinal_source_name
        primary_status = [string]$row.primary_status
        rgb_resolution_status = [string]$row.rgb_resolution_status
        source_id_conflict_status = [string]$row.source_id_conflict_status
        final_id_status = [string]$row.final_id_status
        notes = [string]$row.notes
    }) | Out-Null

    if ($modluOldId -ne '') {
        $modluTrackingRows.Add([pscustomobject]@{
            policy_name = $policyName
            old_id = $modluOldId
            old_rgb = [string]$row.modlu_source_rgb
            old_name = [string]$row.modlu_source_name
            old_source = 'modlu'
            old_subset = 'modlu_kalan'
            final_new_id = $finalId
            final_rgb = [string]$row.effective_rgb
            final_name = [string]$row.effective_name
            row_type = [string]$row.row_type
            source_origin = [string]$row.source_origin
            candidate_type = [string]$row.candidate_type
            primary_status = [string]$row.primary_status
            rgb_resolution_status = [string]$row.rgb_resolution_status
            source_id_conflict_status = [string]$row.source_id_conflict_status
            final_id_status = [string]$row.final_id_status
            keeps_current_id = $keepsCurrentId
            id_changed = ($finalId -ne '' -and [int]$finalId -ne [int]$modluOldId)
            rgb_changed = ([string]$row.effective_rgb -ne [string]$row.modlu_source_rgb)
            partner_orijinal_old_id = $orijinalOldId
            partner_orijinal_old_rgb = [string]$row.orijinal_source_rgb
            partner_orijinal_old_name = [string]$row.orijinal_source_name
            notes = [string]$row.notes
        }) | Out-Null
    }

    if ($orijinalOldId -ne '') {
        $orijinalTrackingRows.Add([pscustomobject]@{
            policy_name = $policyName
            old_id = $orijinalOldId
            old_rgb = [string]$row.orijinal_source_rgb
            old_name = [string]$row.orijinal_source_name
            old_source = 'orijinal'
            old_subset = 'orijinal_dogu'
            final_new_id = $finalId
            final_rgb = [string]$row.effective_rgb
            final_name = [string]$row.effective_name
            row_type = [string]$row.row_type
            source_origin = [string]$row.source_origin
            candidate_type = [string]$row.candidate_type
            primary_status = [string]$row.primary_status
            rgb_resolution_status = [string]$row.rgb_resolution_status
            source_id_conflict_status = [string]$row.source_id_conflict_status
            final_id_status = [string]$row.final_id_status
            keeps_current_id = $keepsCurrentId
            id_changed = ($finalId -ne '' -and [int]$finalId -ne [int]$orijinalOldId)
            rgb_changed = ([string]$row.effective_rgb -ne [string]$row.orijinal_source_rgb)
            partner_modlu_old_id = $modluOldId
            partner_modlu_old_rgb = [string]$row.modlu_source_rgb
            partner_modlu_old_name = [string]$row.modlu_source_name
            notes = [string]$row.notes
        }) | Out-Null
    }

    if ([string]$row.row_type -eq 'placeholder') {
        $placeholderRows.Add([pscustomobject]@{
            policy_name = $policyName
            final_new_id = $finalId
            placeholder_rgb = [string]$row.effective_rgb
            placeholder_name = [string]$row.effective_name
            placeholder_reason = [string]$row.placeholder_reason
            final_id_status = [string]$row.final_id_status
            notes = [string]$row.notes
        }) | Out-Null
    }
}

$masterExportRows = @($masterRows | Sort-Object final_new_id)
$modluExportRows = @($modluTrackingRows | Sort-Object old_id)
$orijinalExportRows = @($orijinalTrackingRows | Sort-Object old_id)
$placeholderExportRows = @($placeholderRows | Sort-Object final_new_id)

Export-Utf8Csv -Rows $masterExportRows -Path $MasterCsv
Export-Utf8Csv -Rows $modluExportRows -Path $ModluTrackingCsv
Export-Utf8Csv -Rows $orijinalExportRows -Path $OrijinalTrackingCsv
Export-Utf8Csv -Rows $placeholderExportRows -Path $PlaceholderCsv

$realRows = @($masterExportRows | Where-Object { $_.row_type -eq 'candidate' })
$placeholderCount = @($masterExportRows | Where-Object { $_.row_type -eq 'placeholder' }).Count
$modluChangedIdCount = @($modluExportRows | Where-Object { $_.id_changed }).Count
$orijinalChangedIdCount = @($orijinalExportRows | Where-Object { $_.id_changed }).Count
$modluChangedRgbCount = @($modluExportRows | Where-Object { $_.rgb_changed }).Count
$orijinalChangedRgbCount = @($orijinalExportRows | Where-Object { $_.rgb_changed }).Count

$summaryLines = @(
    ('# Final Tracking Summary - {0}' -f $policyName),
    '',
    ('- assignment csv: `{0}`' -f $AssignmentCsv),
    ('- assignment placeholder csv: `{0}`' -f $(if ([string]::IsNullOrWhiteSpace($AssignmentPlaceholderCsv)) { '<none>' } else { $AssignmentPlaceholderCsv })),
    ('- master csv: `{0}`' -f $MasterCsv),
    ('- modlu tracking csv: `{0}`' -f $ModluTrackingCsv),
    ('- orijinal tracking csv: `{0}`' -f $OrijinalTrackingCsv),
    ('- placeholder csv: `{0}`' -f $PlaceholderCsv),
    '',
    '## Counts',
    '',
    ('- master rows: `{0}`' -f $masterExportRows.Count),
    ('- real candidate rows: `{0}`' -f $realRows.Count),
    ('- placeholder rows: `{0}`' -f $placeholderCount),
    ('- modlu tracking rows: `{0}`' -f $modluExportRows.Count),
    ('- orijinal tracking rows: `{0}`' -f $orijinalExportRows.Count),
    ('- modlu rows with changed final ID: `{0}`' -f $modluChangedIdCount),
    ('- orijinal rows with changed final ID: `{0}`' -f $orijinalChangedIdCount),
    ('- modlu rows with changed final RGB: `{0}`' -f $modluChangedRgbCount),
    ('- orijinal rows with changed final RGB: `{0}`' -f $orijinalChangedRgbCount),
    '',
    '## Real Row Source Split',
    ''
)

foreach ($group in @($realRows | Group-Object source_origin | Sort-Object Name)) {
    $summaryLines += ('- `{0}`: `{1}`' -f $group.Name, $group.Count)
}

$summaryLines += @(
    '',
    '## Real Row Primary Status Split',
    ''
)

foreach ($group in @($realRows | Group-Object primary_status | Sort-Object Name)) {
    $summaryLines += ('- `{0}`: `{1}`' -f $group.Name, $group.Count)
}

Set-Content -Path $SummaryPath -Value $summaryLines -Encoding utf8

Write-Host ("Built final tracking outputs for policy '{0}' under '{1}'." -f $policyName, $generatedDir)
