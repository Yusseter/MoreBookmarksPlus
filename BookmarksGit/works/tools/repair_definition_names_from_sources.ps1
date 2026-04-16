param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$MasterCsv = '',
    [string]$ModluDefinitionCsv = '',
    [string]$OrijinalDefinitionCsv = '',
    [string[]]$TargetDefinitionCsvs = @(),
    [string]$ReportCsv = '',
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

function Load-DefinitionNameMap {
    param([string]$Path)

    $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
    $map = @{}

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $trimmed = $line.TrimStart()
        if ($trimmed.StartsWith('#')) {
            continue
        }

        $parts = $line.Split(';')
        if ($parts.Count -lt 5) {
            continue
        }

        $idText = [string]$parts[0]
        if ($idText -notmatch '^\d+$') {
            continue
        }

        $map[$idText] = [string]$parts[4]
    }

    return $map
}

function Resolve-CorrectName {
    param(
        $Row,
        $ModluNames,
        $OrijinalNames
    )

    if ([string]$Row.row_type -eq 'placeholder') {
        return [string]$Row.effective_name
    }

    $modluOldId = [string]$Row.modlu_old_id
    $orijinalOldId = [string]$Row.orijinal_old_id
    $sourceOrigin = [string]$Row.source_origin

    if (($sourceOrigin -eq 'modlu' -or $sourceOrigin -eq 'both') -and -not [string]::IsNullOrWhiteSpace($modluOldId) -and $ModluNames.ContainsKey($modluOldId)) {
        return [string]$ModluNames[$modluOldId]
    }

    if (($sourceOrigin -eq 'orijinal' -or $sourceOrigin -eq 'both') -and -not [string]::IsNullOrWhiteSpace($orijinalOldId) -and $OrijinalNames.ContainsKey($orijinalOldId)) {
        return [string]$OrijinalNames[$orijinalOldId]
    }

    if (-not [string]::IsNullOrWhiteSpace($modluOldId) -and $ModluNames.ContainsKey($modluOldId)) {
        return [string]$ModluNames[$modluOldId]
    }

    if (-not [string]::IsNullOrWhiteSpace($orijinalOldId) -and $OrijinalNames.ContainsKey($orijinalOldId)) {
        return [string]$OrijinalNames[$orijinalOldId]
    }

    return [string]$Row.effective_name
}

function Repair-DefinitionFile {
    param(
        [string]$Path,
        $NameByFinalId
    )

    $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
    $outputLines = New-Object System.Collections.Generic.List[string]
    $changedRows = New-Object System.Collections.Generic.List[object]
    $seenNumericRows = 0

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) {
            $outputLines.Add($line) | Out-Null
            continue
        }

        $parts = $line.Split(';')
        if ($parts.Length -lt 6 -or $parts[0] -notmatch '^\d+$') {
            $outputLines.Add($line) | Out-Null
            continue
        }

        $seenNumericRows += 1
        $idText = [string]$parts[0]
        if ($idText -eq '0') {
            $outputLines.Add($line) | Out-Null
            continue
        }

        if ($NameByFinalId.ContainsKey($idText)) {
            $oldName = [string]$parts[4]
            $newName = [string]$NameByFinalId[$idText]
            if ($oldName -ne $newName) {
                $parts[4] = $newName
                $changedRows.Add([pscustomobject]@{
                    definition_path = $Path
                    final_new_id = [int]$idText
                    old_name = $oldName
                    new_name = $newName
                }) | Out-Null
            }
        }

        $outputLines.Add(($parts -join ';')) | Out-Null
    }

    [System.IO.File]::WriteAllLines($Path, $outputLines, [System.Text.UTF8Encoding]::new($false))

    return [pscustomobject]@{
        path = $Path
        numeric_row_count = $seenNumericRows
        changed_name_count = $changedRows.Count
        changed_rows = $changedRows.ToArray()
    }
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$generatedDir = Join-Path (Join-Path $root 'analysis') 'generated'
$mapDataDir = Join-Path $root 'map_data'

if ([string]::IsNullOrWhiteSpace($MasterCsv)) {
    $MasterCsv = Join-Path $generatedDir 'final_master_preserve_old_ids.csv'
}
if ([string]::IsNullOrWhiteSpace($ModluDefinitionCsv)) {
    $ModluDefinitionCsv = Join-Path $mapDataDir 'definition_modlu.csv'
}
if ([string]::IsNullOrWhiteSpace($OrijinalDefinitionCsv)) {
    $OrijinalDefinitionCsv = Join-Path $mapDataDir 'definition_orijinal.csv'
}
if ($TargetDefinitionCsvs.Count -eq 0) {
    $TargetDefinitionCsvs = @(
        (Join-Path $mapDataDir 'definition.csv'),
        (Join-Path $generatedDir 'definition_birlesim_final_preserve_old.csv')
    )
}
if ([string]::IsNullOrWhiteSpace($ReportCsv)) {
    $ReportCsv = Join-Path $generatedDir 'definition_name_repair_report.csv'
}
if ([string]::IsNullOrWhiteSpace($SummaryPath)) {
    $SummaryPath = Join-Path $generatedDir 'definition_name_repair_summary.md'
}

Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($ReportCsv))
Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($SummaryPath))

$masterRows = @(Import-Csv -Path $MasterCsv)
$modluNames = Load-DefinitionNameMap -Path $ModluDefinitionCsv
$orijinalNames = Load-DefinitionNameMap -Path $OrijinalDefinitionCsv

$nameByFinalId = @{}
foreach ($row in $masterRows) {
    $nameByFinalId[[string]$row.final_new_id] = Resolve-CorrectName -Row $row -ModluNames $modluNames -OrijinalNames $orijinalNames
}

$allChangedRows = New-Object System.Collections.Generic.List[object]
$fileResults = New-Object System.Collections.Generic.List[object]
foreach ($targetPath in $TargetDefinitionCsvs) {
    $result = Repair-DefinitionFile -Path $targetPath -NameByFinalId $nameByFinalId
    $fileResults.Add([pscustomobject]@{
        definition_path = $result.path
        numeric_row_count = $result.numeric_row_count
        changed_name_count = $result.changed_name_count
    }) | Out-Null

    foreach ($row in $result.changed_rows) {
        $allChangedRows.Add($row) | Out-Null
    }
}

$reportRows = @($allChangedRows | Sort-Object definition_path, final_new_id)
Export-Utf8Csv -Rows $reportRows -Path $ReportCsv

$summaryLines = @(
    '# Definition Name Repair Summary',
    '',
    ('- master csv: `{0}`' -f $MasterCsv),
    ('- modlu source definition: `{0}`' -f $ModluDefinitionCsv),
    ('- orijinal source definition: `{0}`' -f $OrijinalDefinitionCsv),
    ('- report csv: `{0}`' -f $ReportCsv),
    '',
    '## Target Files',
    ''
)

foreach ($row in $fileResults) {
    $summaryLines += ('- `{0}` -> numeric rows `{1}`, changed names `{2}`' -f $row.definition_path, $row.numeric_row_count, $row.changed_name_count)
}

$summaryLines += @(
    '',
    '## Notes',
    '',
    '- Only the name column was repaired; IDs, RGB values, placeholder rows, and row order were left unchanged.',
    '- Correct names were reloaded from UTF-8 source definitions using old source IDs from the final master tracking table.'
)

[System.IO.File]::WriteAllLines($SummaryPath, $summaryLines, [System.Text.UTF8Encoding]::new($false))

Write-Output "Repaired definition name columns from UTF-8 source definitions."
