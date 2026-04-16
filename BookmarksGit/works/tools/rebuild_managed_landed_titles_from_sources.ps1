$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-Utf8NoBomEncoding {
    return New-Object System.Text.UTF8Encoding($false)
}

function Get-Utf8BomEncoding {
    return New-Object System.Text.UTF8Encoding($true)
}

function Read-TextUtf8 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
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

function Write-TextUtf8Bom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Text, (Get-Utf8BomEncoding))
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
            for ($i = [int]$block.StartIndex; $i -le [int]$block.EndIndex; $i++) {
                $skipLine[$i] = $true
            }
        }
    }

    $outputLines = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if (-not $skipLine.ContainsKey($i)) {
            $line = [string]$lines[$i]
            if ($line -eq '# Refreshed imported vanilla east landed title roots') { continue }
            if ($line -eq '# Restored missing landed title roots from source provenance') { continue }
            if ($line -eq '# Rebuilt managed landed title roots from source provenance') { continue }
            $outputLines.Add($line) | Out-Null
        }
    }

    while ($outputLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($outputLines[$outputLines.Count - 1])) {
        $outputLines.RemoveAt($outputLines.Count - 1)
    }

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
            if ($line -match '^\s*(b_[A-Za-z0-9_\/\.-]+)\s*=\s*\{') {
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
            $output.Add([string]$line) | Out-Null
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

function Rename-BlockRootName {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$NewName
    )

    $lines = Split-Lines -Text $Text
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match '^(\s*)([A-Za-z0-9_@:\.\-\?\/]+)(\s*=\s*\{.*)$') {
            $lines[$i] = $matches[1] + $NewName + $matches[3]
            break
        }
    }

    return ($lines -join "`r`n")
}

function Get-InvalidProvinceIdSetFromDefaultMap {
    param([Parameter(Mandatory = $true)][string]$Path)

    $set = @{}
    foreach ($line in (Split-Lines -Text (Read-TextUtf8 -Path $Path))) {
        $visible = (Strip-LineComment -Line $line).Trim()
        if ([string]::IsNullOrWhiteSpace($visible)) {
            continue
        }

        if ($visible -match '^(sea_zones|impassable_mountains|impassable_seas)\s*=\s*RANGE\s*\{\s*(\d+)\s+(\d+)\s*\}$') {
            $start = [int]$matches[2]
            $end = [int]$matches[3]
            foreach ($id in $start..$end) {
                $set[$id] = $true
            }
            continue
        }

        if ($visible -match '^(sea_zones|impassable_mountains|impassable_seas)\s*=\s*LIST\s*\{\s*([^\}]*)\}$') {
            foreach ($match in [regex]::Matches($matches[2], '\d+')) {
                $set[[int]$match.Value] = $true
            }
        }
    }

    return $set
}

function Resolve-ProvinceId {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('modlu', 'orijinal')][string]$SourceType,
        [Parameter(Mandatory = $true)][int]$OldId,
        [Parameter(Mandatory = $true)]$TrackingMap,
        [Parameter(Mandatory = $true)]$SplitIndex
    )

    $splitKey = '{0}|{1}' -f $SourceType, $OldId
    if ($SplitIndex.ContainsKey($splitKey)) {
        return [pscustomobject]@{
            FinalId = [int]$SplitIndex[$splitKey]
            Reason = 'split_recolor'
        }
    }

    if ($TrackingMap.ContainsKey($OldId)) {
        return [pscustomobject]@{
            FinalId = [int]$TrackingMap[$OldId]
            Reason = 'tracking'
        }
    }

    return [pscustomobject]@{
        FinalId = $OldId
        Reason = 'source_old_id_kept'
    }
}

function Rewrite-LandedTitleBlockProvinceIds {
    param(
        [Parameter(Mandatory = $true)][string]$BlockText,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][ValidateSet('modlu', 'orijinal')][string]$SourceType,
        [Parameter(Mandatory = $true)]$TrackingMap,
        [Parameter(Mandatory = $true)]$SplitIndex,
        [Parameter(Mandatory = $true)]$FallbackBaronyProvinceMap,
        [Parameter(Mandatory = $true)]$InvalidProvinceIds,
        [Parameter(Mandatory = $true)]$ManualBaronyOverrides,
        [Parameter(Mandatory = $true)]$ReportRows
    )

    $lines = Split-Lines -Text $BlockText
    $output = New-Object System.Collections.Generic.List[string]
    $inBarony = $false
    $baronyName = ''
    $depth = 0

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if (-not $inBarony) {
            if ($line -match '^\s*(b_[A-Za-z0-9_\/\.-]+)\s*=\s*\{') {
                $inBarony = $true
                $baronyName = [string]$matches[1]
                $depth = Get-BraceDelta -Line $line
            }
            $output.Add([string]$line) | Out-Null
            if ($inBarony -and $depth -le 0) {
                $inBarony = $false
                $baronyName = ''
                $depth = 0
            }
            continue
        }

        if ($line -match '^(\s*province\s*=\s*)(\d+)(\s*(#.*)?)$') {
            $oldId = [int]$matches[2]
            $resolved = Resolve-ProvinceId -SourceType $SourceType -OldId $oldId -TrackingMap $TrackingMap -SplitIndex $SplitIndex
            $finalId = [int]$resolved.FinalId
            $reason = [string]$resolved.Reason
            $overrideKey = '{0}|{1}' -f $Root, $baronyName

            if ($ManualBaronyOverrides.ContainsKey($overrideKey)) {
                $finalId = [int]$ManualBaronyOverrides[$overrideKey]
                $reason = 'manual_barony_override'
            }

            if ($reason -eq 'source_old_id_kept' -and $FallbackBaronyProvinceMap.ContainsKey($baronyName)) {
                $finalId = [int]$FallbackBaronyProvinceMap[$baronyName]
                $reason = 'fallback_live_barony'
            }

            if ($InvalidProvinceIds.ContainsKey($finalId)) {
                if ($FallbackBaronyProvinceMap.ContainsKey($baronyName)) {
                    $fallbackId = [int]$FallbackBaronyProvinceMap[$baronyName]
                    if (-not $InvalidProvinceIds.ContainsKey($fallbackId)) {
                        $finalId = $fallbackId
                        $reason = 'fallback_live_barony_invalid_tracking'
                    }
                }

                if ($InvalidProvinceIds.ContainsKey($finalId) -and -not $InvalidProvinceIds.ContainsKey($oldId)) {
                    $finalId = $oldId
                    $reason = 'source_old_id_preserved_invalid_tracking'
                }

                if ($InvalidProvinceIds.ContainsKey($finalId)) {
                    $reason = $reason + '_invalid_province'
                }
            }

            $line = $matches[1] + [string]$finalId + $matches[3]

            $ReportRows.Add([pscustomobject]@{
                root = $Root
                barony = $baronyName
                source_type = $SourceType
                old_source_id = $oldId
                final_new_id = $finalId
                reason = $reason
            }) | Out-Null
        }

        $output.Add([string]$line) | Out-Null
        $depth += Get-BraceDelta -Line $line
        if ($depth -eq 0) {
            $inBarony = $false
            $baronyName = ''
            $depth = 0
        }
    }

    return ($output -join "`r`n")
}

function Get-BaronyAssignments {
    param([Parameter(Mandatory = $true)][string]$Text)

    $topBlocks = Get-TopLevelBlocks -Text $Text
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($block in $topBlocks) {
        $lines = Split-Lines -Text ([string]$block.Text)
        $inBarony = $false
        $baronyName = ''
        $depth = 0

        foreach ($line in $lines) {
            if (-not $inBarony) {
                if ($line -match '^\s*(b_[A-Za-z0-9_\/\.-]+)\s*=\s*\{') {
                    $inBarony = $true
                    $baronyName = [string]$matches[1]
                    $depth = Get-BraceDelta -Line $line
                }
            }
            else {
                if ($line -match '^\s*province\s*=\s*(\d+)') {
                    $rows.Add([pscustomobject]@{
                        root = [string]$block.Name
                        barony = $baronyName
                        province_id = [int]$matches[1]
                    }) | Out-Null
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

    return $rows.ToArray()
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$generatedRoot = Join-Path $repoRoot 'Works\analysis\generated\landed_titles_full_source_repair'
New-Item -ItemType Directory -Path $generatedRoot -Force | Out-Null

$paths = @{
    LiveLanded = Join-Path $repoRoot 'common\landed_titles\00_landed_titles.txt'
    TestLanded = Join-Path $repoRoot 'test_files\common\landed_titles\00_landed_titles.txt'
    FinalModlu = Join-Path $repoRoot 'Works\analysis\generated\final_modlu_tracking_preserve_old_ids.csv'
    FinalOrijinal = Join-Path $repoRoot 'Works\analysis\generated\final_orijinal_tracking_preserve_old_ids.csv'
    SplitAssignments = Join-Path $repoRoot 'Works\analysis\generated\source_semantic_staging_fix\source_semantic_same_id_split_id_assignments.csv'
    DefaultMap = Join-Path $repoRoot 'map_data\default.map'
    ModSource = 'C:\Program Files (x86)\Steam\steamapps\workshop\content\1158310\2216670956\0backup\common\landed_titles\00_landed_titles.txt'
    Vanilla00 = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles\00_landed_titles.txt'
    Vanilla01 = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles\01_japan.txt'
    Vanilla02 = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles\02_china.txt'
    Vanilla03 = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles\03_seasia.txt'
    Vanilla05 = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles\05_goryeo.txt'
    Vanilla06 = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles\06_philippines.txt'
}

$invalidProvinceIds = Get-InvalidProvinceIdSetFromDefaultMap -Path $paths.DefaultMap

$modTracking = @{}
foreach ($row in (Read-CsvUtf8 -Path $paths.FinalModlu)) {
    if ($row.old_id -match '^\d+$' -and $row.final_new_id -match '^\d+$') {
        $modTracking[[int]$row.old_id] = [int]$row.final_new_id
    }
}

$orijinalTracking = @{}
foreach ($row in (Read-CsvUtf8 -Path $paths.FinalOrijinal)) {
    if ($row.old_id -match '^\d+$' -and $row.final_new_id -match '^\d+$') {
        $orijinalTracking[[int]$row.old_id] = [int]$row.final_new_id
    }
}

$splitIndex = @{}
foreach ($row in (Read-CsvUtf8 -Path $paths.SplitAssignments)) {
    if ($row.recolor_source_id -notmatch '^\d+$' -or $row.recolor_final_id -notmatch '^\d+$') {
        continue
    }
    $key = '{0}|{1}' -f [string]$row.recolor_source, [int]$row.recolor_source_id
    $splitIndex[$key] = [int]$row.recolor_final_id
}

$manualBaronyOverrides = @{
    'e_tibet|b_maowun' = 7115
    'e_tibet|b_muli' = 11454
    'e_tibet|b_sumshul' = 12535
    'e_tibet|b_wunchoin' = 10322
}

$managedRootSpecs = @(
    @{ Root = 'e_viet'; SourceFile = $paths.Vanilla00; SourceType = 'orijinal' },
    @{ Root = 'h_india'; SourceFile = $paths.ModSource; SourceType = 'modlu'; RemoveNestedNames = @('b_kaptai') },
    @{ Root = 'e_tibet'; SourceFile = $paths.ModSource; SourceType = 'modlu'; RemoveNestedNames = @('b_jagsam') },
    @{ Root = 'e_qixi'; SourceFile = $paths.ModSource; SourceType = 'modlu' },
    @{ Root = 'h_china'; SourceFile = $paths.Vanilla02; SourceType = 'orijinal'; RemoveNestedNames = @('k_xia', 'c_maozhou', 'b_shanglin') },
    @{ Root = 'e_suvarnabhumi'; SourceFile = $paths.Vanilla03; SourceType = 'orijinal' },
    @{ Root = 'e_brunei'; SourceFile = $paths.Vanilla03; SourceType = 'orijinal' },
    @{ Root = 'e_kambuja'; SourceFile = $paths.Vanilla03; SourceType = 'orijinal' },
    @{ Root = 'e_nusantara'; SourceFile = $paths.Vanilla06; SourceType = 'orijinal' },
    @{ Root = 'e_japan'; SourceFile = $paths.Vanilla01; SourceType = 'orijinal' },
    @{ Root = 'k_chrysanthemum_throne'; SourceFile = $paths.Vanilla01; SourceType = 'orijinal' },
    @{ Root = 'e_goryeo'; SourceFile = $paths.Vanilla05; SourceType = 'orijinal' },
    @{ Root = 'k_yongson_throne'; SourceFile = $paths.Vanilla05; SourceType = 'orijinal' },
    @{ Root = 'e_andong'; SourceFile = $paths.Vanilla00; SourceType = 'orijinal' },
    @{ Root = 'e_srivijaya'; SourceFile = $paths.Vanilla00; SourceType = 'orijinal' },
    @{ Root = 'e_amur'; SourceFile = $paths.Vanilla00; SourceType = 'orijinal' },
    @{ Root = 'e_yongliang'; SourceFile = $paths.ModSource; SourceType = 'modlu' },
    @{ Root = 'e_xi_xia'; SourceFile = $paths.ModSource; SourceType = 'modlu' }
)

$sourceTextByFile = @{}
$rewrittenBlocks = New-Object System.Collections.Generic.List[string]
$rewriteRows = New-Object System.Collections.Generic.List[object]
$liveOriginal = Read-TextUtf8 -Path $paths.LiveLanded
$liveBaronyProvinceMap = Get-BaronyProvinceMapFromText -Text $liveOriginal
foreach ($spec in $managedRootSpecs) {
    $sourceFile = [string]$spec.SourceFile
    if (-not $sourceTextByFile.ContainsKey($sourceFile)) {
        $sourceTextByFile[$sourceFile] = Read-TextUtf8 -Path $sourceFile
    }

    $sourceBlockName = if ($spec.ContainsKey('SourceBlockName')) { [string]$spec.SourceBlockName } else { [string]$spec.Root }
    $blockText = Get-NamedBlockText -Text $sourceTextByFile[$sourceFile] -Name $sourceBlockName
    if ([string]::IsNullOrWhiteSpace($blockText)) {
        throw "Failed to locate root $sourceBlockName in $sourceFile"
    }

    if ($spec.ContainsKey('RemoveNestedNames')) {
        $blockText = Remove-NestedBlocksByName -Text $blockText -Names @([string[]]$spec.RemoveNestedNames)
    }

    if ($sourceBlockName -ne [string]$spec.Root) {
        $blockText = Rename-BlockRootName -Text $blockText -NewName ([string]$spec.Root)
    }

    $trackingMap = if ($spec.SourceType -eq 'modlu') { $modTracking } else { $orijinalTracking }
    $rewrittenBlocks.Add(
        (Rewrite-LandedTitleBlockProvinceIds `
            -BlockText $blockText `
            -Root ([string]$spec.Root) `
            -SourceType ([string]$spec.SourceType) `
            -TrackingMap $trackingMap `
            -SplitIndex $splitIndex `
            -FallbackBaronyProvinceMap $liveBaronyProvinceMap `
            -InvalidProvinceIds $invalidProvinceIds `
            -ManualBaronyOverrides $manualBaronyOverrides `
            -ReportRows $rewriteRows)
    ) | Out-Null
}

$managedRoots = @($managedRootSpecs | ForEach-Object { [string]$_.Root })
$retiredTopLevelRoots = @()
$removeRoots = @($managedRoots + $retiredTopLevelRoots)
$rebuiltText = Remove-TopLevelBlocksAndAppend `
    -OriginalText $liveOriginal `
    -RemoveNames $removeRoots `
    -AppendBlocks $rewrittenBlocks.ToArray() `
    -MarkerComment 'Rebuilt managed landed title roots from source provenance'

$rebuiltText = Remove-NestedBlocksByName -Text $rebuiltText -Names @(
    'd_hantuman',
    'b_yongan_jiangsheng_china',
    'b_Goryeo_Bukgye_Maengju',
    'b_Goryeo_Donggye_Myeongju',
    'b_Goryeo_Donggye_Deungju',
    'b_Goryeo_Donggye_Uiju',
    'b_Goryeo_Donggye_Hwaju',
    'b_muot',
    'b_siantan'
)
$rebuiltText = (($rebuiltText -replace "(?m)^[ \t]*#Remove[ \t]*\r?\n", '') -replace "(?m)^[ \t]*# -----------------------------------------------------------------------------[ \t]*\r?\n(?=[ \t]*# -----------------------------------------------------------------------------[ \t]*\r?\n)", '')
$rebuiltText = ($rebuiltText.TrimEnd() + "`r`n")

$assignments = @(Get-BaronyAssignments -Text $rebuiltText)
$duplicateRows = foreach ($group in ($assignments | Group-Object province_id | Where-Object { $_.Count -gt 1 } | Sort-Object Name)) {
    foreach ($row in $group.Group) {
        [pscustomobject]@{
            province_id = [int]$group.Name
            root = [string]$row.root
            barony = [string]$row.barony
        }
    }
}

$rewriteReportPath = Join-Path $generatedRoot 'managed_root_rewrite_report.csv'
$duplicateReportPath = Join-Path $generatedRoot 'duplicate_province_assignments_after_rebuild.csv'
$summaryPath = Join-Path $generatedRoot 'managed_root_rebuild_summary.md'

Export-CsvUtf8 -Rows $rewriteRows -Path $rewriteReportPath
Export-CsvUtf8 -Rows @($duplicateRows) -Path $duplicateReportPath

if (@($duplicateRows).Count -gt 0) {
    $examples = (($duplicateRows | Select-Object -First 12 | ForEach-Object { '{0}:{1}' -f $_.province_id, $_.barony }) -join ', ')
    throw "Duplicate province assignments remain after rebuild: $examples"
}

Write-TextUtf8Bom -Path $paths.LiveLanded -Text $rebuiltText
Write-TextUtf8Bom -Path $paths.TestLanded -Text $rebuiltText

$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add('# Managed Landed Titles Rebuild') | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add(('managed roots rebuilt: {0}' -f $managedRoots.Count)) | Out-Null
$summaryLines.Add(('province rows rewritten/re-evaluated: {0}' -f ([int]$rewriteRows.Count))) | Out-Null
$summaryLines.Add(('duplicate province rows after rebuild: {0}' -f ([int](@($duplicateRows).Count)))) | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add('Reports:') | Out-Null
$summaryLines.Add("- $rewriteReportPath") | Out-Null
$summaryLines.Add("- $duplicateReportPath") | Out-Null

Write-TextUtf8 -Path $summaryPath -Text (($summaryLines -join "`r`n") + "`r`n")
