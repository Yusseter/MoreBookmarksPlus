$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-Utf8NoBomEncoding {
    return New-Object System.Text.UTF8Encoding($false)
}

function Read-TextUtf8 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $memory = New-Object System.IO.MemoryStream
        $stream.CopyTo($memory)
        $bytes = $memory.ToArray()
    }
    finally {
        $stream.Dispose()
    }

    $encoding = Get-Utf8NoBomEncoding
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

    [System.IO.File]::WriteAllText($Path, $Text, (Get-Utf8NoBomEncoding))
}

function Read-CsvUtf8 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $text = Read-TextUtf8 -Path $Path
    if ([string]::IsNullOrWhiteSpace($text)) {
        return @()
    }
    return $text | ConvertFrom-Csv
}

function Export-CsvUtf8 {
    param(
        [Parameter(Mandatory = $true)]$Rows,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $Rows | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
}

function Split-Lines {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    return [System.Text.RegularExpressions.Regex]::Split($Text, "`r?`n")
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
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $lines = Split-Lines -Text $Text
    $blocks = New-Object System.Collections.Generic.List[object]
    $inBlock = $false
    $blockName = ''
    $blockStart = -1
    $depth = 0

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if (-not $inBlock) {
            if ($line -match '^\s*([A-Za-z0-9_@:\.\-\?\/]+)\s*=\s*\{') {
                $blockName = [string]$matches[1]
                $blockStart = $i
                $depth = Get-BraceDelta -Line $line
                if ($depth -le 0) {
                    $blocks.Add([pscustomobject]@{
                        Name = $blockName
                        StartIndex = $blockStart
                        EndIndex = $i
                        Text = ($lines[$blockStart..$i] -join "`r`n")
                    }) | Out-Null
                    $blockName = ''
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
                $blocks.Add([pscustomobject]@{
                    Name = $blockName
                    StartIndex = $blockStart
                    EndIndex = $i
                    Text = ($lines[$blockStart..$i] -join "`r`n")
                }) | Out-Null
                $inBlock = $false
                $blockName = ''
                $blockStart = -1
            }
        }
    }

    return $blocks
}

function Get-NamedBlockText {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $lines = Split-Lines -Text $Text
    $capturing = $false
    $startIndex = -1
    $depth = 0

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if (-not $capturing) {
            if ($line -match ('^\s*' + [regex]::Escape($Name) + '\s*=\s*\{')) {
                $capturing = $true
                $startIndex = $i
                $depth = Get-BraceDelta -Line $line
                if ($depth -le 0) {
                    return ($lines[$startIndex..$i] -join "`r`n")
                }
            }
        }
        else {
            $depth += Get-BraceDelta -Line $line
            if ($depth -eq 0) {
                return ($lines[$startIndex..$i] -join "`r`n")
            }
        }
    }

    return $null
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
        if ($removeLookup.ContainsKey([string]$block.Name)) {
            for ($lineIndex = [int]$block.StartIndex; $lineIndex -le [int]$block.EndIndex; $lineIndex++) {
                $skipLine[$lineIndex] = $true
            }
        }
    }

    $outputLines = New-Object System.Collections.Generic.List[string]
    for ($lineIndex = 0; $lineIndex -lt $lines.Length; $lineIndex++) {
        if (-not $skipLine.ContainsKey($lineIndex)) {
            $outputLines.Add([string]$lines[$lineIndex]) | Out-Null
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

        for ($blockIndex = 0; $blockIndex -lt $AppendBlocks.Count; $blockIndex++) {
            foreach ($appendLine in (Split-Lines -Text $AppendBlocks[$blockIndex])) {
                $outputLines.Add([string]$appendLine) | Out-Null
            }
            if ($blockIndex -lt ($AppendBlocks.Count - 1)) {
                $outputLines.Add('') | Out-Null
            }
        }
    }

    return (($outputLines -join "`r`n").TrimEnd() + "`r`n")
}

function Get-BaronyProvinceMapFromText {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $lines = Split-Lines -Text $Text
    $map = @{}
    $inBarony = $false
    $baronyName = ''
    $depth = 0

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if (-not $inBarony) {
            if ($line -match '^\s*(b_[A-Za-z0-9_]+)\s*=\s*\{') {
                $inBarony = $true
                $baronyName = [string]$matches[1]
                $depth = Get-BraceDelta -Line $line
                if ($depth -le 0) {
                    $inBarony = $false
                    $baronyName = ''
                }
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
            }
        }
    }

    return $map
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
            if ($line -match '^\s*([A-Za-z0-9_@:\.\-\?\/]+)\s*=\s*\{') {
                $name = [string]$matches[1]
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

function Rewrite-LandedTitleBlockProvinceIds {
    param(
        [Parameter(Mandatory = $true)][string]$BlockText,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$OldToFinal,
        [Parameter(Mandatory = $true)]$FallbackBaronyProvinceMap,
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
            if ($line -match '^\s*(b_[A-Za-z0-9_]+)\s*=\s*\{') {
                $inBarony = $true
                $baronyName = [string]$matches[1]
                $depth = Get-BraceDelta -Line $line
            }
            $output.Add($line) | Out-Null
            if ($inBarony -and $depth -le 0) {
                $inBarony = $false
                $baronyName = ''
            }
        }
        else {
            if ($line -match '^(\s*province\s*=\s*)(\d+)(\s*(#.*)?)$') {
                $oldId = [int]$matches[2]
                if ($OldToFinal.ContainsKey($oldId)) {
                    $newId = [int]$OldToFinal[$oldId]
                    $ReportRows.Add([pscustomobject]@{
                        root = $Root
                        barony = $baronyName
                        old_source_id = $oldId
                        final_new_id = $newId
                        status = 'rewritten'
                    }) | Out-Null
                    $line = $matches[1] + $newId + $matches[3]
                }
                elseif ($FallbackBaronyProvinceMap.ContainsKey($baronyName)) {
                    $newId = [int]$FallbackBaronyProvinceMap[$baronyName]
                    $ReportRows.Add([pscustomobject]@{
                        root = $Root
                        barony = $baronyName
                        old_source_id = $oldId
                        final_new_id = $newId
                        status = 'fallback_live_barony'
                    }) | Out-Null
                    $line = $matches[1] + $newId + $matches[3]
                }
                else {
                    $ReportRows.Add([pscustomobject]@{
                        root = $Root
                        barony = $baronyName
                        old_source_id = $oldId
                        final_new_id = ''
                        status = 'missing_mapping_barony_blocked'
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
            }
        }
    }

    if ($missingBaronies.Count -gt 0) {
        $sample = (($missingBaronies | Select-Object -First 10) -join ', ')
        throw ("Missing province mapping for root {0}: {1} baronies blocked. Examples: {2}" -f $Root, $missingBaronies.Count, $sample)
    }
    return ($output -join "`r`n")
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$generatedRoot = Join-Path $repoRoot 'Works\analysis\generated\missing_landed_title_restore_roots'
New-Item -ItemType Directory -Path $generatedRoot -Force | Out-Null

$paths = @{
    LiveLanded = Join-Path $repoRoot 'common\landed_titles\00_landed_titles.txt'
    TestLanded = Join-Path $repoRoot 'test_files\common\landed_titles\00_landed_titles.txt'
    FinalModlu = Join-Path $repoRoot 'Works\analysis\generated\final_modlu_tracking_preserve_old_ids.csv'
    FinalOrijinal = Join-Path $repoRoot 'Works\analysis\generated\final_orijinal_tracking_preserve_old_ids.csv'
    ModSource = 'C:\Program Files (x86)\Steam\steamapps\workshop\content\1158310\2216670956\0backup\common\landed_titles\00_landed_titles.txt'
    VanillaSource = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles\00_landed_titles.txt'
}

$modOldToFinal = @{}
foreach ($row in (Read-CsvUtf8 -Path $paths.FinalModlu)) {
    $modOldToFinal[[int]$row.old_id] = [int]$row.final_new_id
}

$vanillaOldToFinal = @{}
foreach ($row in (Read-CsvUtf8 -Path $paths.FinalOrijinal)) {
    $vanillaOldToFinal[[int]$row.old_id] = [int]$row.final_new_id
}

$restoreSpecs = @(
    @{ Root = 'e_andong'; SourceFile = $paths.VanillaSource; Mapping = $vanillaOldToFinal; SourceSubset = 'orijinal_dogu' },
    @{ Root = 'e_srivijaya'; SourceFile = $paths.VanillaSource; Mapping = $vanillaOldToFinal; SourceSubset = 'orijinal_dogu' },
    @{ Root = 'e_amur'; SourceFile = $paths.VanillaSource; Mapping = $vanillaOldToFinal; SourceSubset = 'orijinal_dogu' },
    @{ Root = 'e_bengal'; SourceFile = $paths.VanillaSource; Mapping = $vanillaOldToFinal; SourceSubset = 'orijinal_dogu' },
    @{ Root = 'e_qixi'; SourceFile = $paths.ModSource; Mapping = $modOldToFinal; SourceSubset = 'modlu_kalan' },
    @{ Root = 'e_xi_xia'; SourceFile = $paths.ModSource; Mapping = $modOldToFinal; SourceSubset = 'modlu_kalan' },
    @{ Root = 'e_tibet'; SourceFile = $paths.ModSource; Mapping = $modOldToFinal; SourceSubset = 'modlu_kalan' },
    @{ Root = 'e_yongliang'; SourceFile = $paths.ModSource; Mapping = $modOldToFinal; SourceSubset = 'modlu_kalan' },
    @{ Root = 'e_wendish_empire'; SourceFile = $paths.ModSource; Mapping = $modOldToFinal; SourceSubset = 'modlu_kalan' }
)

$liveText = Read-TextUtf8 -Path $paths.LiveLanded
$liveBaronyProvinceMap = Get-BaronyProvinceMapFromText -Text $liveText
$sourceBlocksByFile = @{}
$rewrittenBlocks = New-Object System.Collections.Generic.List[string]
$rewriteRows = New-Object System.Collections.Generic.List[object]

foreach ($spec in $restoreSpecs) {
    $sourceFile = [string]$spec.SourceFile
    if (-not $sourceBlocksByFile.ContainsKey($sourceFile)) {
        $sourceBlocksByFile[$sourceFile] = Get-TopLevelBlocks -Text (Read-TextUtf8 -Path $sourceFile)
    }

    $sourceBlock = $sourceBlocksByFile[$sourceFile] | Where-Object { $_.Name -eq $spec.Root } | Select-Object -First 1
    $sourceBlockText = if ($null -ne $sourceBlock) { [string]$sourceBlock.Text } else { Get-NamedBlockText -Text (Read-TextUtf8 -Path $sourceFile) -Name ([string]$spec.Root) }
    if ([string]::IsNullOrWhiteSpace($sourceBlockText)) {
        throw "Failed to locate root $($spec.Root) in $sourceFile"
    }

    $rewrittenBlock = Rewrite-LandedTitleBlockProvinceIds `
        -BlockText $sourceBlockText `
        -Root ([string]$spec.Root) `
        -OldToFinal $spec.Mapping `
        -FallbackBaronyProvinceMap $liveBaronyProvinceMap `
        -ReportRows $rewriteRows

    $rewrittenBlocks.Add($rewrittenBlock) | Out-Null
}

$updatedText = Remove-TopLevelBlocksAndAppend `
    -OriginalText $liveText `
    -RemoveNames @($restoreSpecs | ForEach-Object { [string]$_.Root }) `
    -AppendBlocks $rewrittenBlocks.ToArray() `
    -MarkerComment 'Restored missing landed title roots from source provenance'

Write-TextUtf8 -Path $paths.LiveLanded -Text $updatedText
Write-TextUtf8 -Path $paths.TestLanded -Text $updatedText
Export-CsvUtf8 -Rows $rewriteRows -Path (Join-Path $generatedRoot 'restored_missing_landed_title_roots_rewrite_report.csv')

$summaryRows = foreach ($rootGroup in ($rewriteRows | Group-Object root | Sort-Object Name)) {
    $rows = @($rootGroup.Group)
    $rewritten = @($rows | Where-Object { $_.status -eq 'rewritten' })
    $fallback = @($rows | Where-Object { $_.status -eq 'fallback_live_barony' })
    $blocked = @($rows | Where-Object { $_.status -eq 'missing_mapping_barony_blocked' })
    [pscustomobject]@{
        root = [string]$rootGroup.Name
        rewritten_count = $rewritten.Count
        fallback_count = $fallback.Count
        blocked_barony_count = $blocked.Count
        blocked_barony_sample = (($blocked | Select-Object -First 10 | ForEach-Object { $_.barony }) -join '|')
    }
}

Export-CsvUtf8 -Rows $summaryRows -Path (Join-Path $generatedRoot 'restored_missing_landed_title_roots_summary.csv')

$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add('# Restored Missing Landed Title Roots')
$summaryLines.Add('')
foreach ($row in $summaryRows) {
    $summaryLines.Add(('- `{0}` -> rewritten `{1}`, fallback `{2}`, blocked `{3}`' -f $row.root, $row.rewritten_count, $row.fallback_count, $row.blocked_barony_count))
}
$summaryLines.Add('')
$summaryLines.Add('Files:')
$summaryLines.Add('- `restored_missing_landed_title_roots_rewrite_report.csv`')
$summaryLines.Add('- `restored_missing_landed_title_roots_summary.csv`')

Write-TextUtf8 -Path (Join-Path $generatedRoot 'restored_missing_landed_title_roots_summary.md') -Text (($summaryLines -join "`r`n") + "`r`n")
