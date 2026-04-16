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

function Export-CsvUtf8 {
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

function Get-TopLevelBlocks {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )

    $lines = Split-Lines -Text $Text
    $blocks = New-Object System.Collections.Generic.List[object]
    $inBlock = $false
    $blockName = $null
    $blockStart = -1
    $depth = 0

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if (-not $inBlock) {
            if ($line -match '^\s*([A-Za-z0-9_@:\.\-\?]+)\s*=\s*\{') {
                $blockName = $matches[1]
                $blockStart = $i
                $depth = Get-BraceDelta -Line $line
                if ($depth -le 0) {
                    $blockText = ($lines[$blockStart..$i] -join "`r`n")
                    $blocks.Add([pscustomobject]@{
                        Name = $blockName
                        StartIndex = $blockStart
                        EndIndex = $i
                        Text = $blockText
                    }) | Out-Null
                    $blockName = $null
                    $blockStart = -1
                    $depth = 0
                }
                else {
                    $inBlock = $true
                }
            }
        }
        else {
            $depth += Get-BraceDelta -Line $line
            if ($depth -eq 0) {
                $blockText = ($lines[$blockStart..$i] -join "`r`n")
                $blocks.Add([pscustomobject]@{
                    Name = $blockName
                    StartIndex = $blockStart
                    EndIndex = $i
                    Text = $blockText
                }) | Out-Null
                $inBlock = $false
                $blockName = $null
                $blockStart = -1
            }
        }
    }

    return $blocks
}

function Remove-TopLevelBlocksAndAppend {
    param(
        [Parameter(Mandatory = $true)][string]$OriginalText,
        [Parameter(Mandatory = $true)][string[]]$RemoveNames,
        [Parameter(Mandatory = $true)][string[]]$AppendBlocks,
        [Parameter(Mandatory = $true)][string]$MarkerComment
    )

    $removeLookup = @{}
    foreach ($name in $RemoveNames) {
        $removeLookup[$name] = $true
    }

    $lines = Split-Lines -Text $OriginalText
    $blocks = Get-TopLevelBlocks -Text $OriginalText
    $skipLine = @{}

    foreach ($block in $blocks) {
        if ($removeLookup.ContainsKey($block.Name)) {
            for ($lineIndex = [int]$block.StartIndex; $lineIndex -le [int]$block.EndIndex; $lineIndex++) {
                $skipLine[$lineIndex] = $true
            }
        }
    }

    $outputLines = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if (-not $skipLine.ContainsKey($i)) {
            $line = [string]$lines[$i]
            if ($line -eq "# $MarkerComment") {
                continue
            }
            if ($line -eq '# -----------------------------------------------------------------------------') {
                # Keep existing separators. A duplicate marker line alone is harmless,
                # but skipping exact marker comments reduces clutter on refresh runs.
                $outputLines.Add($line) | Out-Null
                continue
            }
            $outputLines.Add($line) | Out-Null
        }
    }

    while ($outputLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($outputLines[$outputLines.Count - 1])) {
        $outputLines.RemoveAt($outputLines.Count - 1)
    }

    if ($AppendBlocks.Count -gt 0) {
        $outputLines.Add('') | Out-Null
        $outputLines.Add('# -----------------------------------------------------------------------------') | Out-Null
        $outputLines.Add("# $MarkerComment") | Out-Null
        $outputLines.Add('# -----------------------------------------------------------------------------') | Out-Null
        $outputLines.Add('') | Out-Null

        for ($i = 0; $i -lt $AppendBlocks.Count; $i++) {
            foreach ($appendLine in (Split-Lines -Text $AppendBlocks[$i])) {
                $outputLines.Add([string]$appendLine) | Out-Null
            }
            if ($i -lt ($AppendBlocks.Count - 1)) {
                $outputLines.Add('') | Out-Null
            }
        }
    }

    return (($outputLines -join "`r`n").TrimEnd() + "`r`n")
}

function Remove-NestedBlocksByName {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    if ($Names.Count -eq 0) {
        return $Text
    }

    $nameLookup = @{}
    foreach ($name in $Names) {
        $nameLookup[$name] = $true
    }

    $lines = Split-Lines -Text $Text
    $output = New-Object System.Collections.Generic.List[string]
    $skipping = $false
    $depth = 0

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if (-not $skipping) {
            if ($line -match '^\s*([A-Za-z0-9_@:\.\-\?]+)\s*=\s*\{') {
                $name = $matches[1]
                if ($nameLookup.ContainsKey($name)) {
                    $skipping = $true
                    $depth = Get-BraceDelta -Line $line
                    if ($depth -le 0) {
                        $skipping = $false
                        $depth = 0
                    }
                    continue
                }
            }
            $output.Add($line) | Out-Null
        }
        else {
            $depth += Get-BraceDelta -Line $line
            if ($depth -eq 0) {
                $skipping = $false
                $depth = 0
            }
        }
    }

    return ($output -join "`r`n")
}

function Rewrite-VanillaRootProvinceIds {
    param(
        [Parameter(Mandatory = $true)][string]$BlockText,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$VanillaOldToFinal,
        [Parameter(Mandatory = $true)]$DefinitionById,
        [Parameter(Mandatory = $true)]$ReportRows
    )

    $lines = Split-Lines -Text $BlockText
    $output = New-Object System.Collections.Generic.List[string]
    $inBarony = $false
    $baronyName = ''
    $depth = 0
    $missingBaronies = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if (-not $inBarony) {
            if ($line -match '^\s*(b_[A-Za-z0-9_\/\.-]+)\s*=\s*\{') {
                $inBarony = $true
                $baronyName = $matches[1]
                $depth = Get-BraceDelta -Line $line
            }

            $output.Add($line) | Out-Null
            if ($inBarony -and $depth -le 0) {
                $inBarony = $false
                $baronyName = ''
                $depth = 0
            }
            continue
        }

        if ($line -match '^(\s*province\s*=\s*)(\d+)(\s*(#.*)?)$') {
            $oldId = [int]$matches[2]
            if ($VanillaOldToFinal.ContainsKey($oldId)) {
                $newId = [int]$VanillaOldToFinal[$oldId]
                $newName = ''
                if ($DefinitionById.ContainsKey($newId)) {
                    $newName = [string]$DefinitionById[$newId]
                }

                $ReportRows.Add([pscustomobject]@{
                    root = $Root
                    barony = $baronyName
                    old_vanilla_id = $oldId
                    final_new_id = $newId
                    final_name = $newName
                    status = if ($newId -eq $oldId) { 'kept_same_id' } else { 'rewritten' }
                }) | Out-Null

                $line = $matches[1] + $newId + $matches[3]
            }
            else {
                $ReportRows.Add([pscustomobject]@{
                    root = $Root
                    barony = $baronyName
                    old_vanilla_id = $oldId
                    final_new_id = ''
                    final_name = ''
                    status = 'missing_tracking_removed'
                }) | Out-Null

                if (-not $missingBaronies.Contains($baronyName)) {
                    $missingBaronies.Add($baronyName) | Out-Null
                }
            }
        }

        $output.Add($line) | Out-Null
        $depth += Get-BraceDelta -Line $line
        if ($depth -eq 0) {
            $inBarony = $false
            $baronyName = ''
            $depth = 0
        }
    }

    $rewritten = ($output -join "`r`n")
    if ($missingBaronies.Count -gt 0) {
        return Remove-NestedBlocksByName -Text $rewritten -Names $missingBaronies.ToArray()
    }
    return $rewritten
}

function Get-BaronyProvinceMapFromRoots {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Roots
    )

    $topLevel = Get-TopLevelBlocks -Text $Text
    $rootLookup = @{}
    foreach ($root in $Roots) {
        $rootLookup[$root] = $true
    }

    $map = @{}
    foreach ($block in $topLevel) {
        if (-not $rootLookup.ContainsKey($block.Name)) {
            continue
        }

        $lines = Split-Lines -Text $block.Text
        $inBarony = $false
        $baronyName = ''
        $depth = 0

        foreach ($line in $lines) {
            if (-not $inBarony) {
                if ($line -match '^\s*(b_[A-Za-z0-9_\/\.-]+)\s*=\s*\{') {
                    $inBarony = $true
                    $baronyName = $matches[1]
                    $depth = Get-BraceDelta -Line $line
                }
            }
            else {
                if ($line -match '^\s*province\s*=\s*(\d+)') {
                    if (-not $map.ContainsKey($baronyName)) {
                        $map[$baronyName] = [int]$matches[1]
                    }
                }
                $depth += Get-BraceDelta -Line $line
                if ($depth -eq 0) {
                    $inBarony = $false
                    $baronyName = ''
                    $depth = 0
                }
            }
        }
    }

    return $map
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$repoLandedTitles = Join-Path $root 'common\landed_titles\00_landed_titles.txt'
$testLandedTitles = Join-Path $root 'test_files\common\landed_titles\00_landed_titles.txt'
$trackingPath = Join-Path $root 'Works\analysis\generated\final_orijinal_tracking_preserve_old_ids.csv'
$definitionPath = Join-Path $root 'map_data\definition.csv'
$generatedDir = Join-Path $root 'Works\analysis\generated\landed_titles_vanilla_refresh'
if (-not (Test-Path -LiteralPath $generatedDir)) {
    New-Item -ItemType Directory -Path $generatedDir -Force | Out-Null
}

$reportPath = Join-Path $generatedDir 'landed_titles_vanilla_refresh_report.csv'
$summaryPath = Join-Path $generatedDir 'landed_titles_vanilla_refresh_summary.md'
$validationPath = Join-Path $generatedDir 'landed_titles_vanilla_refresh_validation.csv'

$definitionById = @{}
foreach ($line in [System.IO.File]::ReadLines($definitionPath)) {
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
    $definitionById[[int]$parts[0]] = [string]$parts[4]
}

$vanillaOldToFinal = @{}
foreach ($row in (Import-Csv -Path $trackingPath)) {
    if ($row.old_id -match '^\d+$' -and $row.final_new_id -match '^\d+$') {
        $vanillaOldToFinal[[int]$row.old_id] = [int]$row.final_new_id
    }
}

$vanillaCommonBase = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles'
$rootSpecs = @(
    @{ Root = 'e_viet'; File = Join-Path $vanillaCommonBase '00_landed_titles.txt' },
    @{ Root = 'e_tibet'; File = Join-Path $vanillaCommonBase '00_landed_titles.txt' },
    @{ Root = 'h_china'; File = Join-Path $vanillaCommonBase '02_china.txt' },
    @{ Root = 'e_suvarnabhumi'; File = Join-Path $vanillaCommonBase '03_seasia.txt' },
    @{ Root = 'e_brunei'; File = Join-Path $vanillaCommonBase '03_seasia.txt' },
    @{ Root = 'e_kambuja'; File = Join-Path $vanillaCommonBase '03_seasia.txt' },
    @{ Root = 'e_nusantara'; File = Join-Path $vanillaCommonBase '06_philippines.txt' },
    @{ Root = 'e_japan'; File = Join-Path $vanillaCommonBase '01_japan.txt' },
    @{ Root = 'k_chrysanthemum_throne'; File = Join-Path $vanillaCommonBase '01_japan.txt' },
    @{ Root = 'e_goryeo'; File = Join-Path $vanillaCommonBase '05_goryeo.txt' },
    @{ Root = 'k_yongson_throne'; File = Join-Path $vanillaCommonBase '05_goryeo.txt' }
)

$legacyModEastRoots = @(
    'e_qixi',
    'e_tunguse',
    'e_jurchen_china',
    'e_java',
    'e_malayadvipa',
    'e_srivijaya',
    'e_kalimantan',
    'e_angkor',
    'e_ramanya',
    'e_panyupayana',
    'e_maluku'
)

$blocksByFile = @{}
foreach ($spec in $rootSpecs) {
    if (-not $blocksByFile.ContainsKey($spec.File)) {
        $blocksByFile[$spec.File] = Get-TopLevelBlocks -Text (Read-TextUtf8 -Path $spec.File)
    }
}

$reportRows = New-Object System.Collections.Generic.List[object]
$appendBlocks = New-Object System.Collections.Generic.List[string]
foreach ($spec in $rootSpecs) {
    $block = $blocksByFile[$spec.File] | Where-Object { $_.Name -eq $spec.Root } | Select-Object -First 1
    if ($null -eq $block) {
        throw "Failed to locate vanilla landed title root $($spec.Root) in $($spec.File)"
    }

    $rewrittenBlock = Rewrite-VanillaRootProvinceIds `
        -BlockText $block.Text `
        -Root $spec.Root `
        -VanillaOldToFinal $vanillaOldToFinal `
        -DefinitionById $definitionById `
        -ReportRows $reportRows
    $appendBlocks.Add($rewrittenBlock) | Out-Null
}

$liveOriginal = Read-TextUtf8 -Path $repoLandedTitles
$removeRoots = @($rootSpecs | ForEach-Object { $_.Root }) + $legacyModEastRoots
$liveRewritten = Remove-TopLevelBlocksAndAppend `
    -OriginalText $liveOriginal `
    -RemoveNames $removeRoots `
    -AppendBlocks $appendBlocks.ToArray() `
    -MarkerComment 'Refreshed imported vanilla east landed title roots'

Write-TextUtf8 -Path $repoLandedTitles -Text $liveRewritten
Write-TextUtf8 -Path $testLandedTitles -Text $liveRewritten

$refreshedBaronyMap = Get-BaronyProvinceMapFromRoots -Text $liveRewritten -Roots $removeRoots
$validationRows = New-Object System.Collections.Generic.List[object]
foreach ($entry in $refreshedBaronyMap.GetEnumerator() | Sort-Object Key) {
    $barony = [string]$entry.Key
    $provinceId = [int]$entry.Value
    $provinceName = ''
    $classification = 'missing_definition'
    if ($definitionById.ContainsKey($provinceId)) {
        $provinceName = [string]$definitionById[$provinceId]
        if ($provinceName -like 'zz_placeholder_*') {
            $classification = 'placeholder'
        }
        elseif ($provinceName -like 'sea_*' -or $provinceName -like 'river_*' -or $provinceName -like 'lake_*') {
            $classification = 'water'
        }
        else {
            $classification = 'land'
        }
    }

    $validationRows.Add([pscustomobject]@{
        barony = $barony
        province_id = $provinceId
        province_name = $provinceName
        classification = $classification
    }) | Out-Null
}

Export-CsvUtf8 -Rows $reportRows -Path $reportPath
Export-CsvUtf8 -Rows $validationRows -Path $validationPath

$rewrittenCount = @($reportRows | Where-Object { $_.status -eq 'rewritten' }).Count
$keptCount = @($reportRows | Where-Object { $_.status -eq 'kept_same_id' }).Count
$removedCount = @($reportRows | Where-Object { $_.status -eq 'missing_tracking_removed' }).Count
$landCount = @($validationRows | Where-Object { $_.classification -eq 'land' }).Count
$waterCount = @($validationRows | Where-Object { $_.classification -eq 'water' }).Count
$placeholderCount = @($validationRows | Where-Object { $_.classification -eq 'placeholder' }).Count
$missingDefCount = @($validationRows | Where-Object { $_.classification -eq 'missing_definition' }).Count

$summary = @"
# Landed Titles Vanilla Refresh Summary

- refreshed roots: $($removeRoots.Count)
- rewritten province rows: $rewrittenCount
- kept same-id province rows: $keptCount
- removed unmapped baronies: $removedCount
- validation land province links: $landCount
- validation water province links: $waterCount
- validation placeholder links: $placeholderCount
- validation missing-definition links: $missingDefCount

Roots refreshed:
$((@($removeRoots) | ForEach-Object { "- $_" }) -join "`r`n")
"@

Write-TextUtf8 -Path $summaryPath -Text ($summary.TrimEnd() + "`r`n")
