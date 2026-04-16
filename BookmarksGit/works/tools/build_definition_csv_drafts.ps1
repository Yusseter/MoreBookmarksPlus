param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$PreserveAssignmentsCsv = '',
    [string]$PreservePlaceholdersCsv = '',
    [string]$FullAssignmentsCsv = '',
    [string]$PreserveDefinitionCsv = '',
    [string]$FullDefinitionCsv = '',
    [string]$ValidationCsv = '',
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

function Parse-Rgb {
    param([string]$Rgb)

    $parts = $Rgb.Split(',')
    if ($parts.Count -ne 3) {
        throw "Invalid RGB string: $Rgb"
    }

    return [pscustomobject]@{
        r = [int]$parts[0]
        g = [int]$parts[1]
        b = [int]$parts[2]
    }
}

function Build-DefinitionDraft {
    param(
        [object[]]$AssignmentRows,
        [object[]]$PlaceholderRows,
        [string]$OutputPath,
        [string]$PolicyName
    )

    $allRows = @($AssignmentRows) + @($PlaceholderRows)
    $sortedRows = @($allRows | Sort-Object {[int]$_.final_new_id})

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('0;0;0;0;x;x') | Out-Null

    $rgbGroups = @($sortedRows | Group-Object effective_rgb | Where-Object { $_.Count -gt 1 })
    $idValues = @($sortedRows | ForEach-Object { [int]$_.final_new_id })
    $maxId = if ($idValues.Count -gt 0) { ($idValues | Measure-Object -Maximum).Maximum } else { 0 }

    $missingIds = New-Object System.Collections.Generic.List[int]
    for ($id = 1; $id -le $maxId; $id++) {
        if ($idValues -notcontains $id) {
            $missingIds.Add($id) | Out-Null
        }
    }

    foreach ($row in $sortedRows) {
        $rgb = Parse-Rgb -Rgb $row.effective_rgb
        $name = if ([string]::IsNullOrWhiteSpace([string]$row.effective_name)) { '' } else { [string]$row.effective_name }
        $lines.Add(('{0};{1};{2};{3};{4};x' -f [int]$row.final_new_id, $rgb.r, $rgb.g, $rgb.b, $name)) | Out-Null
    }

    [System.IO.File]::WriteAllLines($OutputPath, $lines, [System.Text.UTF8Encoding]::new($false))

    return [pscustomobject]@{
        policy_name = $PolicyName
        output_path = $OutputPath
        data_row_count = $sortedRows.Count
        max_final_id = $maxId
        placeholder_row_count = @($sortedRows | Where-Object { $_.row_type -eq 'placeholder' }).Count
        candidate_row_count = @($sortedRows | Where-Object { $_.row_type -eq 'candidate' }).Count
        duplicate_rgb_count = $rgbGroups.Count
        missing_id_count = $missingIds.Count
        contiguous_ids = ($missingIds.Count -eq 0)
    }
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$generatedDir = Join-Path (Join-Path $root 'analysis') 'generated'

if ([string]::IsNullOrWhiteSpace($PreserveAssignmentsCsv)) {
    $PreserveAssignmentsCsv = Join-Path $generatedDir 'id_policy_preserve_old_assignments.csv'
}
if ([string]::IsNullOrWhiteSpace($PreservePlaceholdersCsv)) {
    $PreservePlaceholdersCsv = Join-Path $generatedDir 'id_policy_preserve_old_placeholders.csv'
}
if ([string]::IsNullOrWhiteSpace($FullAssignmentsCsv)) {
    $FullAssignmentsCsv = Join-Path $generatedDir 'id_policy_full_renumber_assignments.csv'
}
if ([string]::IsNullOrWhiteSpace($PreserveDefinitionCsv)) {
    $PreserveDefinitionCsv = Join-Path $generatedDir 'definition_policy_preserve_old_draft.csv'
}
if ([string]::IsNullOrWhiteSpace($FullDefinitionCsv)) {
    $FullDefinitionCsv = Join-Path $generatedDir 'definition_policy_full_renumber_draft.csv'
}
if ([string]::IsNullOrWhiteSpace($ValidationCsv)) {
    $ValidationCsv = Join-Path $generatedDir 'definition_policy_draft_validation.csv'
}
if ([string]::IsNullOrWhiteSpace($SummaryPath)) {
    $SummaryPath = Join-Path $generatedDir 'definition_policy_drafts_summary.md'
}

Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($PreserveDefinitionCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($FullDefinitionCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($ValidationCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($SummaryPath))

$preserveAssignments = @(Import-Csv -Path $PreserveAssignmentsCsv)
$preservePlaceholders = @(Import-Csv -Path $PreservePlaceholdersCsv)
$fullAssignments = @(Import-Csv -Path $FullAssignmentsCsv)

$preserveValidation = Build-DefinitionDraft -AssignmentRows $preserveAssignments -PlaceholderRows $preservePlaceholders -OutputPath $PreserveDefinitionCsv -PolicyName 'preserve_old_ids'
$fullValidation = Build-DefinitionDraft -AssignmentRows $fullAssignments -PlaceholderRows @() -OutputPath $FullDefinitionCsv -PolicyName 'full_renumber'

$validationRows = @($preserveValidation, $fullValidation)
Export-Utf8Csv -Rows $validationRows -Path $ValidationCsv

$summaryLines = @(
    '# Definition Policy Draft Summary',
    '',
    ('- preserve draft: `{0}`' -f $PreserveDefinitionCsv),
    ('- full renumber draft: `{0}`' -f $FullDefinitionCsv),
    ('- validation csv: `{0}`' -f $ValidationCsv),
    '',
    '## Validation',
    '',
    ('- preserve_old_ids -> data rows `{0}`, max id `{1}`, placeholders `{2}`, duplicate RGB `{3}`, missing IDs `{4}`, contiguous `{5}`' -f $preserveValidation.data_row_count, $preserveValidation.max_final_id, $preserveValidation.placeholder_row_count, $preserveValidation.duplicate_rgb_count, $preserveValidation.missing_id_count, $preserveValidation.contiguous_ids),
    ('- full_renumber -> data rows `{0}`, max id `{1}`, placeholders `{2}`, duplicate RGB `{3}`, missing IDs `{4}`, contiguous `{5}`' -f $fullValidation.data_row_count, $fullValidation.max_final_id, $fullValidation.placeholder_row_count, $fullValidation.duplicate_rgb_count, $fullValidation.missing_id_count, $fullValidation.contiguous_ids),
    '',
    '## Notes',
    '',
    '- Both drafts emit `0;0;0;0;x;x` as the reserved first line.',
    '- Drafts are generated under `analysis/generated/` only and do not overwrite live map_data definitions.',
    '- RGB uniqueness here is checked against the draft rows themselves after the earlier RGB-resolution stage.'
)

[System.IO.File]::WriteAllLines($SummaryPath, $summaryLines, [System.Text.UTF8Encoding]::new($false))

Write-Output "Built definition CSV drafts under '$generatedDir'."
