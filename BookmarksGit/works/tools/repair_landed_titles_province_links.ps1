[CmdletBinding()]
param(
    [string]$RepoRoot = '.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-TextUtf8 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $encoding = New-Object System.Text.UTF8Encoding($false)
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

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Export-Utf8Csv {
    param(
        [Parameter(Mandatory = $true)]$Rows,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $csv = @($Rows | ConvertTo-Csv -NoTypeInformation)
    [System.IO.File]::WriteAllLines($Path, $csv, [System.Text.UTF8Encoding]::new($false))
}

function Split-Lines {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    return [regex]::Split($Text, "`r?`n")
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

function Normalize-ProvinceName {
    param([AllowEmptyString()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ''
    }

    $lower = $Name.ToLowerInvariant()
    return (($lower -replace '[^a-z0-9]', ''))
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$landedTitlesPath = Join-Path $root 'common\landed_titles\00_landed_titles.txt'
$definitionPath = Join-Path $root 'map_data\definition.csv'
$placeholderInventoryPath = Join-Path $root 'Works\analysis\generated\final_placeholder_inventory_preserve_old_ids.csv'
$orijinalTrackingPath = Join-Path $root 'Works\analysis\generated\final_orijinal_tracking_preserve_old_ids.csv'
$generatedDir = Join-Path $root 'Works\analysis\generated\landed_titles_link_repair'
if (-not (Test-Path -LiteralPath $generatedDir)) {
    New-Item -ItemType Directory -Path $generatedDir -Force | Out-Null
}

$reportPath = Join-Path $generatedDir 'landed_titles_province_link_repair_report.csv'
$summaryPath = Join-Path $generatedDir 'landed_titles_province_link_repair_summary.md'

$definitionById = @{}
$definitionIdsByNormalizedName = @{}
foreach ($line in [System.IO.File]::ReadLines($definitionPath)) {
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

    $id = [int]$parts[0]
    $name = [string]$parts[4]
    $normalized = Normalize-ProvinceName -Name $name
    $row = [pscustomobject]@{
        id = $id
        name = $name
        normalized = $normalized
        is_placeholder = ($name -like 'zz_placeholder_*')
    }
    $definitionById[$id] = $row

    if (-not [string]::IsNullOrWhiteSpace($normalized)) {
        if (-not $definitionIdsByNormalizedName.ContainsKey($normalized)) {
            $definitionIdsByNormalizedName[$normalized] = New-Object System.Collections.Generic.List[int]
        }
        $definitionIdsByNormalizedName[$normalized].Add($id) | Out-Null
    }
}

$placeholderIds = @{}
if (Test-Path -LiteralPath $placeholderInventoryPath) {
    foreach ($row in (Import-Csv -Path $placeholderInventoryPath)) {
        if ($row.final_new_id -match '^\d+$') {
            $placeholderIds[[int]$row.final_new_id] = $true
        }
    }
}

$importedEastFinalIds = @{}
if (Test-Path -LiteralPath $orijinalTrackingPath) {
    foreach ($row in (Import-Csv -Path $orijinalTrackingPath)) {
        if ($row.final_new_id -match '^\d+$') {
            $importedEastFinalIds[[int]$row.final_new_id] = $true
        }
    }
}

$text = Read-TextUtf8 -Path $landedTitlesPath
$lines = Split-Lines -Text $text
$output = New-Object System.Collections.Generic.List[string]
$reportRows = New-Object System.Collections.Generic.List[object]

$inBarony = $false
$baronyName = ''
$baronyDepth = 0
$baronyStartLine = 0

for ($i = 0; $i -lt $lines.Length; $i++) {
    $line = $lines[$i]

    if (-not $inBarony) {
        if ($line -match '^\s*(b_[A-Za-z0-9_\/\.-]+)\s*=\s*\{') {
            $inBarony = $true
            $baronyName = [string]$matches[1]
            $baronyDepth = Get-BraceDelta -Line $line
            $baronyStartLine = $i + 1
        }

        $output.Add($line) | Out-Null
        if ($inBarony -and $baronyDepth -le 0) {
            $inBarony = $false
            $baronyName = ''
            $baronyDepth = 0
            $baronyStartLine = 0
        }
        continue
    }

    if ($line -match '^(\s*province\s*=\s*)(\d+)(\s*(#.*)?)$') {
        $currentId = [int]$matches[2]
        $currentDefinition = $null
        if ($definitionById.ContainsKey($currentId)) {
            $currentDefinition = $definitionById[$currentId]
        }

        $expectedNameRaw = $baronyName.Substring(2)
        $expectedNormalized = Normalize-ProvinceName -Name $expectedNameRaw
        $candidateIds = @()
        if ($definitionIdsByNormalizedName.ContainsKey($expectedNormalized)) {
            $candidateIds = @($definitionIdsByNormalizedName[$expectedNormalized] | Sort-Object -Unique)
        }

        $currentName = if ($null -ne $currentDefinition) { [string]$currentDefinition.name } else { '' }
        $currentNormalized = if ($null -ne $currentDefinition) { [string]$currentDefinition.normalized } else { '' }
        $isPlaceholder = ($placeholderIds.ContainsKey($currentId) -or (($null -ne $currentDefinition) -and [bool]$currentDefinition.is_placeholder))
        $needsRewrite = $false
        if ($candidateIds.Count -eq 1) {
            $candidateId = [int]$candidateIds[0]
            $isImportedEastRelevant = ($importedEastFinalIds.ContainsKey($currentId) -or $importedEastFinalIds.ContainsKey($candidateId))
            if ($candidateId -ne $currentId) {
                if (($isPlaceholder -or $isImportedEastRelevant) -and ($isPlaceholder -or $currentNormalized -ne $expectedNormalized)) {
                    $needsRewrite = $true
                }
            }

            if ($needsRewrite) {
                $line = $matches[1] + $candidateId + $matches[3]
                $candidateDefinition = $definitionById[$candidateId]
                $reportRows.Add([pscustomobject]@{
                    line_number = $i + 1
                    barony = $baronyName
                    expected_name = $expectedNameRaw
                    current_id = $currentId
                    current_name = $currentName
                    new_id = $candidateId
                    new_name = [string]$candidateDefinition.name
                    reason = if ($isPlaceholder) { 'placeholder_or_placeholder_alias' } else { 'normalized_name_mismatch' }
                    status = 'rewritten'
                }) | Out-Null
            }
            else {
                $reportRows.Add([pscustomobject]@{
                    line_number = $i + 1
                    barony = $baronyName
                    expected_name = $expectedNameRaw
                    current_id = $currentId
                    current_name = $currentName
                    new_id = ''
                    new_name = ''
                    reason = if ($candidateId -eq $currentId) { 'already_matches_expected_name' } else { 'candidate_not_needed' }
                    status = 'kept'
                }) | Out-Null
            }
        }
        else {
            $reportRows.Add([pscustomobject]@{
                line_number = $i + 1
                barony = $baronyName
                expected_name = $expectedNameRaw
                current_id = $currentId
                current_name = $currentName
                new_id = ''
                new_name = ''
                reason = if ($candidateIds.Count -eq 0) { 'no_unique_definition_match' } else { 'multiple_definition_matches' }
                status = 'unresolved'
            }) | Out-Null
        }
    }

    $output.Add($line) | Out-Null
    $baronyDepth += Get-BraceDelta -Line $line
    if ($baronyDepth -eq 0) {
        $inBarony = $false
        $baronyName = ''
        $baronyDepth = 0
        $baronyStartLine = 0
    }
}

$outText = (($output -join "`r`n").TrimEnd() + "`r`n")
Write-TextUtf8 -Path $landedTitlesPath -Text $outText

$testCopyPath = Join-Path $root 'test_files\common\landed_titles\00_landed_titles.txt'
if (Test-Path -LiteralPath (Split-Path -Parent $testCopyPath)) {
    Copy-Item -LiteralPath $landedTitlesPath -Destination $testCopyPath -Force
}

$reportArray = $reportRows.ToArray()
Export-Utf8Csv -Rows $reportArray -Path $reportPath

$rewrittenCount = @($reportArray | Where-Object { $_.status -eq 'rewritten' }).Count
$unresolvedCount = @($reportArray | Where-Object { $_.status -eq 'unresolved' }).Count
$keptCount = @($reportArray | Where-Object { $_.status -eq 'kept' }).Count
$placeholderRewriteCount = @($reportArray | Where-Object { $_.reason -eq 'placeholder_or_placeholder_alias' -and $_.status -eq 'rewritten' }).Count
$mismatchRewriteCount = @($reportArray | Where-Object { $_.reason -eq 'normalized_name_mismatch' -and $_.status -eq 'rewritten' }).Count

$summaryLines = @(
    '# landed_titles province link repair summary',
    '',
    ('- live file updated: `{0}`' -f $landedTitlesPath),
    ('- test_files copy synced: `{0}`' -f (Test-Path -LiteralPath $testCopyPath)),
    ('- province assignments scanned: `{0}`' -f @($reportArray).Count),
    ('- rewritten: `{0}`' -f $rewrittenCount),
    ('- kept: `{0}`' -f $keptCount),
    ('- unresolved: `{0}`' -f $unresolvedCount),
    ('- rewritten from placeholder/stale placeholder ids: `{0}`' -f $placeholderRewriteCount),
    ('- rewritten from normalized name mismatch: `{0}`' -f $mismatchRewriteCount)
)

[System.IO.File]::WriteAllLines($summaryPath, $summaryLines, [System.Text.UTF8Encoding]::new($false))
Write-Output ('Repaired landed title province links in {0}' -f $landedTitlesPath)
