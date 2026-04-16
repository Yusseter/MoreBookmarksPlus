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

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $csv = @($Rows | ConvertTo-Csv -NoTypeInformation)
    [System.IO.File]::WriteAllLines($Path, $csv, [System.Text.UTF8Encoding]::new($false))
}

function Parse-DefinitionMap {
    param([Parameter(Mandatory = $true)][string]$Path)

    $map = @{}
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }
        $parts = $line.Split(';')
        if ($parts.Count -lt 5) {
            continue
        }
        if ($parts[0] -notmatch '^\d+$') {
            continue
        }

        $map[[string]$parts[0]] = [pscustomobject]@{
            id = [int]$parts[0]
            rgb = '{0},{1},{2}' -f $parts[1], $parts[2], $parts[3]
            name = [string]$parts[4]
        }
    }
    return $map
}

function Get-ClassList {
    param([AllowEmptyString()][string]$ClassSummary)

    if ([string]::IsNullOrWhiteSpace($ClassSummary) -or $ClassSummary -eq 'none') {
        return @()
    }
    return @($ClassSummary -split '\|')
}

function Get-IdsFromDefaultMapAssignmentLine {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Line
    )

    if ($Line -notmatch '^\s*([A-Za-z_]+)\s*=\s*(LIST|RANGE)\s*\{\s*([^}]*)\s*\}') {
        return $null
    }

    $className = [string]$matches[1]
    $assignmentType = [string]$matches[2]
    $body = [string]$matches[3]
    $tokens = @($body -split '\s+' | Where-Object { $_ -match '^\d+$' })
    if ($tokens.Count -eq 0) {
        return [pscustomobject]@{
            class_name = $className
            ids = @()
        }
    }

    if ($assignmentType -eq 'LIST') {
        return [pscustomobject]@{
            class_name = $className
            ids = @($tokens | ForEach-Object { [int]$_ })
        }
    }

    $ids = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt ($tokens.Count - 1); $i += 2) {
        $start = [int]$tokens[$i]
        $end = [int]$tokens[$i + 1]
        foreach ($value in ($start..$end)) {
            [void]$ids.Add($value)
        }
    }

    return [pscustomobject]@{
        class_name = $className
        ids = $ids.ToArray()
    }
}

function Convert-IdsToDefaultMapListLines {
    param(
        [Parameter(Mandatory = $true)][string]$ClassName,
        [Parameter(Mandatory = $true)][int[]]$Ids,
        [int]$ChunkSize = 32
    )

    $lines = New-Object System.Collections.Generic.List[string]
    if ($Ids.Length -eq 0) {
        return $lines.ToArray()
    }

    for ($offset = 0; $offset -lt $Ids.Length; $offset += $ChunkSize) {
        $count = [Math]::Min($ChunkSize, $Ids.Length - $offset)
        $chunk = $Ids[$offset..($offset + $count - 1)]
        [void]$lines.Add(('{0} = LIST {{ {1} }}' -f $ClassName, ($chunk -join ' ')))
    }

    return $lines.ToArray()
}

function Rewrite-VanillaEastDefaultMapBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][System.Collections.IEnumerable]$ReplacementRows
    )

    $semanticBlockPattern = '(?ms)\r?\n?# SOURCE SEMANTIC SAME-ID SPLITS BEGIN.*?# SOURCE SEMANTIC SAME-ID SPLITS END\r?\n?'
    $cleanText = [regex]::Replace($Text, $semanticBlockPattern, "`r`n")

    $beginMarker = '# VANILLA EAST DEFAULT MAP BEGIN'
    $endMarker = '# VANILLA EAST DEFAULT MAP END'
    $beginIndex = $cleanText.IndexOf($beginMarker)
    $endIndex = $cleanText.IndexOf($endMarker)
    if ($beginIndex -lt 0 -or $endIndex -lt 0 -or $endIndex -le $beginIndex) {
        throw 'Could not locate VANILLA EAST DEFAULT MAP block in test default.map'
    }

    $beforeBlock = $cleanText.Substring(0, $beginIndex)
    $afterBlock = $cleanText.Substring($endIndex + $endMarker.Length)
    $innerStart = $beginIndex + $beginMarker.Length
    $blockText = $cleanText.Substring($innerStart, $endIndex - $innerStart)

    $classSets = @{}
    foreach ($line in ($blockText -split "`r?`n")) {
        $parsed = Get-IdsFromDefaultMapAssignmentLine -Line $line
        if ($null -eq $parsed) {
            continue
        }
        if (-not $classSets.ContainsKey($parsed.class_name)) {
            $classSets[$parsed.class_name] = New-Object 'System.Collections.Generic.HashSet[int]'
        }
        foreach ($id in $parsed.ids) {
            [void]$classSets[$parsed.class_name].Add([int]$id)
        }
    }

    foreach ($row in $ReplacementRows) {
        foreach ($className in @($row.class_list)) {
            if (-not $classSets.ContainsKey($className)) {
                $classSets[$className] = New-Object 'System.Collections.Generic.HashSet[int]'
            }
            [void]$classSets[$className].Remove([int]$row.old_id)
            [void]$classSets[$className].Add([int]$row.new_id)
        }
    }

    $rebuiltBlockLines = New-Object System.Collections.Generic.List[string]
    [void]$rebuiltBlockLines.Add($beginMarker)
    foreach ($className in @('sea_zones', 'river_provinces', 'lakes', 'impassable_mountains', 'impassable_seas')) {
        if (-not $classSets.ContainsKey($className)) {
            continue
        }
        $ids = @($classSets[$className] | Sort-Object)
        foreach ($line in (Convert-IdsToDefaultMapListLines -ClassName $className -Ids $ids)) {
            [void]$rebuiltBlockLines.Add($line)
        }
    }
    [void]$rebuiltBlockLines.Add($endMarker)

    $rebuiltText = ($rebuiltBlockLines -join "`r`n")
    return (($beforeBlock.TrimEnd("`r", "`n")) + "`r`n" + $rebuiltText + $afterBlock)
}

function Update-BaronyProvinceLinks {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][System.Collections.IEnumerable]$ReplacementRows
    )

    $replacementIndex = @{}
    foreach ($row in $ReplacementRows) {
        $replacementIndex[[string]$row.barony] = $row
    }

    $lines = [System.IO.File]::ReadAllLines($Path)
    $currentBarony = $null
    $baronyDepth = -1
    $depth = 0
    $updatedRows = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        $trimmed = $line.Trim()

        if ($trimmed -match '^(b_[A-Za-z0-9_]+)\s*=\s*\{$') {
            $currentBarony = $matches[1]
            $baronyDepth = $depth
        }

        if ($null -ne $currentBarony -and $replacementIndex.ContainsKey($currentBarony) -and $line -match '^(\s*)province\s*=\s*(\d+)\s*$') {
            $row = $replacementIndex[$currentBarony]
            $oldId = [int]$matches[2]
            $newLine = '{0}province = {1}' -f $matches[1], $row.new_id
            $lines[$i] = $newLine

            $updatedRows.Add([pscustomobject]@{
                barony = $currentBarony
                old_id = $oldId
                new_id = [int]$row.new_id
                source = [string]$row.source
                rgb = [string]$row.rgb
            }) | Out-Null
        }

        $openCount = ([regex]::Matches($line, '\{')).Count
        $closeCount = ([regex]::Matches($line, '\}')).Count
        $depth += $openCount
        $depth -= $closeCount

        if ($null -ne $currentBarony -and $depth -le $baronyDepth) {
            $currentBarony = $null
            $baronyDepth = -1
        }
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $lines, $encoding)
    return $updatedRows.ToArray()
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$stagingDir = Join-Path $root 'Works\analysis\generated\source_semantic_staging_fix'
$semanticDecisionsPath = Join-Path $root 'Works\analysis\generated\source_semantic_overlap_audit\source_rgb_overlap_semantic_decisions.csv'
$splitAssignmentsPath = Join-Path $stagingDir 'source_semantic_same_id_split_id_assignments.csv'
$stagingDefinitionPath = Join-Path $stagingDir 'definition_source_semantic_staging.csv'
$stagingProvincesPath = Join-Path $stagingDir 'provinces_source_semantic_staging.png'

$testRoot = Join-Path $root 'test_files'
$testDefinitionPath = Join-Path $testRoot 'map_data\definition.csv'
$testProvincesPath = Join-Path $testRoot 'map_data\provinces.png'
$testDefaultMapPath = Join-Path $testRoot 'map_data\default.map'
$testLandedTitlesPath = Join-Path $testRoot 'common\landed_titles\00_landed_titles.txt'

$reportDir = Join-Path $root 'Works\analysis\generated\source_semantic_test_package'
if (-not (Test-Path -LiteralPath $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

$defaultMapReportPath = Join-Path $reportDir 'source_semantic_test_default_map_additions.csv'
$landedTitlesReportPath = Join-Path $reportDir 'source_semantic_test_landed_title_relinks.csv'
$summaryPath = Join-Path $reportDir 'source_semantic_test_package_summary.md'

Copy-Item -LiteralPath $stagingDefinitionPath -Destination $testDefinitionPath -Force
Copy-Item -LiteralPath $stagingProvincesPath -Destination $testProvincesPath -Force

$splitAssignments = @(Import-Csv -Path $splitAssignmentsPath)
$semanticRows = @(Import-Csv -Path $semanticDecisionsPath)
$semanticIndex = @{}
foreach ($row in $semanticRows) {
    $semanticIndex[[string]$row.rgb] = $row
}

$stagingDefinitionMap = Parse-DefinitionMap -Path $stagingDefinitionPath

$defaultMapShiftRows = New-Object System.Collections.Generic.List[object]
$landedTitleReplacementRows = New-Object System.Collections.Generic.List[object]

foreach ($assignment in $splitAssignments) {
    $rgb = [string]$assignment.rgb
    if (-not $semanticIndex.ContainsKey($rgb)) {
        continue
    }

    $semanticRow = $semanticIndex[$rgb]
    $recolorSource = [string]$assignment.recolor_source
    $newId = [int]$assignment.recolor_final_id
    $newDefinitionRow = $stagingDefinitionMap[[string]$newId]

    $classSummary = if ($recolorSource -eq 'modlu') {
        [string]$semanticRow.modlu_default_map_class
    } else {
        [string]$semanticRow.orijinal_default_map_class
    }

    $classList = @(Get-ClassList -ClassSummary $classSummary)
    if ($classList.Count -gt 0) {
        $defaultMapShiftRows.Add([pscustomobject]@{
            rgb = $rgb
            source = $recolorSource
            old_id = [int]$assignment.keep_final_id
            new_id = $newId
            class_list = $classList
            class_summary = $classSummary
            new_name = if ($null -ne $newDefinitionRow) { [string]$newDefinitionRow.name } else { '' }
            new_rgb = if ($null -ne $newDefinitionRow) { [string]$newDefinitionRow.rgb } else { '' }
        }) | Out-Null
    }

    $barony = if ($recolorSource -eq 'modlu') {
        [string]$semanticRow.modlu_barony
    } else {
        [string]$semanticRow.orijinal_barony
    }

    if (-not [string]::IsNullOrWhiteSpace($barony)) {
        $landedTitleReplacementRows.Add([pscustomobject]@{
            barony = $barony
            old_id = [int]$assignment.keep_final_id
            new_id = $newId
            source = $recolorSource
            rgb = $rgb
            new_rgb = if ($null -ne $newDefinitionRow) { [string]$newDefinitionRow.rgb } else { '' }
            new_name = if ($null -ne $newDefinitionRow) { [string]$newDefinitionRow.name } else { '' }
        }) | Out-Null
    }
}

$defaultMapText = Read-TextUtf8 -Path $testDefaultMapPath
$defaultMapUpdatedText = Rewrite-VanillaEastDefaultMapBlock -Text $defaultMapText -ReplacementRows $defaultMapShiftRows
Write-TextUtf8 -Path $testDefaultMapPath -Text $defaultMapUpdatedText

$landedTitleUpdates = Update-BaronyProvinceLinks -Path $testLandedTitlesPath -ReplacementRows $landedTitleReplacementRows

$defaultMapReportRows = foreach ($row in $defaultMapShiftRows) {
    foreach ($className in @($row.class_list)) {
        [pscustomobject]@{
            default_map_class = $className
            old_id = [int]$row.old_id
            final_new_id = [int]$row.new_id
            rgb = [string]$row.new_rgb
            name = [string]$row.new_name
            source = [string]$row.source
            original_rgb = [string]$row.rgb
        }
    }
}

Export-Utf8Csv -Rows @($defaultMapReportRows) -Path $defaultMapReportPath
Export-Utf8Csv -Rows @($landedTitleUpdates) -Path $landedTitlesReportPath

$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add('# Source Semantic Test Package Apply') | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add('Test package guncellendi:') | Out-Null
$summaryLines.Add("- $testProvincesPath") | Out-Null
$summaryLines.Add("- $testDefinitionPath") | Out-Null
$summaryLines.Add("- $testDefaultMapPath") | Out-Null
$summaryLines.Add("- $testLandedTitlesPath") | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add(('same_id split default.map rewrite satiri: {0}' -f @($defaultMapReportRows).Count)) | Out-Null
$summaryLines.Add(('same_id split landed_titles relink satiri: {0}' -f @($landedTitleUpdates).Count)) | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add('Raporlar:') | Out-Null
$summaryLines.Add("- $defaultMapReportPath") | Out-Null
$summaryLines.Add("- $landedTitlesReportPath") | Out-Null

Write-TextUtf8 -Path $summaryPath -Text (($summaryLines -join "`r`n") + "`r`n")
