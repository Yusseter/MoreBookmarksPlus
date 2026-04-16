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

function Parse-RgbString {
    param([Parameter(Mandatory = $true)][string]$Rgb)

    $parts = @($Rgb -split ',')
    if ($parts.Count -ne 3) {
        throw "Invalid RGB string: $Rgb"
    }

    return (Get-RgbKey -R ([int]$parts[0]) -G ([int]$parts[1]) -B ([int]$parts[2]))
}

function Collect-UsedRgbKeysFromDefinition {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$TargetSet
    )

    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($line.StartsWith('#')) {
            continue
        }

        $parts = $line.Split(';')
        if ($parts.Count -lt 4) {
            continue
        }
        if ($parts[0] -notmatch '^\d+$') {
            continue
        }
        if ($parts[1] -notmatch '^\d+$' -or $parts[2] -notmatch '^\d+$' -or $parts[3] -notmatch '^\d+$') {
            continue
        }

        [void]$TargetSet.Add((Get-RgbKey -R ([int]$parts[1]) -G ([int]$parts[2]) -B ([int]$parts[3])))
    }
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

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$generatedDir = Join-Path $root 'Works\analysis\generated\source_semantic_overlap_audit'
$decisionsPath = Join-Path $generatedDir 'source_rgb_overlap_semantic_decisions.csv'
$assignmentsPath = Join-Path $generatedDir 'source_rgb_overlap_auto_rgb_assignments.csv'
$summaryPath = Join-Path $generatedDir 'source_rgb_overlap_auto_rgb_assignments_summary.md'

$decisions = @(Import-Csv -Path $decisionsPath)
$targetRows = @(
    $decisions |
        Where-Object { $_.auto_final_action -eq 'new_rgb_needed' -and -not [string]::IsNullOrWhiteSpace($_.auto_keep_rgb_source) -and -not [string]::IsNullOrWhiteSpace($_.auto_recolor_source) } |
        Sort-Object @{ Expression = { $_.auto_recolor_source } }, @{ Expression = { [int]$_.modlu_id } }, @{ Expression = { [int]$_.orijinal_id } }, @{ Expression = { $_.rgb } }
)

$usedRgbKeys = New-Object 'System.Collections.Generic.HashSet[int]'
Collect-UsedRgbKeysFromDefinition -Path (Join-Path $root 'map_data\definition.csv') -TargetSet $usedRgbKeys
Collect-UsedRgbKeysFromDefinition -Path (Join-Path $root 'Works\map_data_sources\definition_modlu.csv') -TargetSet $usedRgbKeys
Collect-UsedRgbKeysFromDefinition -Path (Join-Path $root 'Works\map_data_sources\definition_orijinal.csv') -TargetSet $usedRgbKeys

foreach ($row in $decisions) {
    if (-not [string]::IsNullOrWhiteSpace([string]$row.rgb)) {
        [void]$usedRgbKeys.Add((Parse-RgbString -Rgb ([string]$row.rgb)))
    }
}

$newRgbKeys = Get-SuggestedRgbKeys -UsedRgbKeys $usedRgbKeys -Count $targetRows.Count

$assignmentRows = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $targetRows.Count; $i++) {
    $row = $targetRows[$i]
    $newRgb = Format-Rgb -RgbKey $newRgbKeys[$i]

    $affectedSubset = if ($row.auto_recolor_source -eq 'modlu') { 'modlu_kalan' } else { 'orijinal_dogu' }
    $affectedId = if ($row.auto_recolor_source -eq 'modlu') { [string]$row.modlu_id } else { [string]$row.orijinal_id }
    $affectedName = if ($row.auto_recolor_source -eq 'modlu') { [string]$row.modlu_name } else { [string]$row.orijinal_name }
    $keptId = if ($row.auto_keep_rgb_source -eq 'modlu') { [string]$row.modlu_id } elseif ($row.auto_keep_rgb_source -eq 'orijinal') { [string]$row.orijinal_id } else { '' }
    $keptName = if ($row.auto_keep_rgb_source -eq 'modlu') { [string]$row.modlu_name } elseif ($row.auto_keep_rgb_source -eq 'orijinal') { [string]$row.orijinal_name } else { '' }

    $assignmentRows.Add([pscustomobject]@{
        rgb = [string]$row.rgb
        semantic_classification = [string]$row.semantic_classification
        auto_decision_confidence = [string]$row.auto_decision_confidence
        keep_rgb_source = [string]$row.auto_keep_rgb_source
        keep_source_id = $keptId
        keep_source_name = $keptName
        recolor_source = [string]$row.auto_recolor_source
        recolor_subset = $affectedSubset
        recolor_source_id = $affectedId
        recolor_source_name = $affectedName
        modlu_id = [string]$row.modlu_id
        modlu_name = [string]$row.modlu_name
        orijinal_id = [string]$row.orijinal_id
        orijinal_name = [string]$row.orijinal_name
        old_shared_rgb = [string]$row.rgb
        new_rgb = $newRgb
        assignment_basis = 'source_semantic_auto_decision'
        assignment_notes = [string]$row.auto_decision_notes
    }) | Out-Null
}

$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add('# Source Semantic Auto RGB Assignments') | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add("Toplam new_rgb atanan satir: $($assignmentRows.Count)") | Out-Null
$summaryLines.Add("- recolor modlu: $(@($assignmentRows | Where-Object { $_.recolor_source -eq 'modlu' }).Count)") | Out-Null
$summaryLines.Add("- recolor orijinal: $(@($assignmentRows | Where-Object { $_.recolor_source -eq 'orijinal' }).Count)") | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add('Notlar:') | Out-Null
$summaryLines.Add('- Yeni RGBler canli definition.csv + source modlu/orijinal definition renk uzayina karsi bosluktan secildi.') | Out-Null
$summaryLines.Add('- Bu tur sadece assignment dosyasi uretir; canli provinces.png veya definition.csv uygulanmadi.') | Out-Null
$summaryLines.Add('- keep_single_identity satiri bu dosyaya dahil edilmedi; sadece recolor gereken satirlar vardir.') | Out-Null

Export-Utf8Csv -Rows $assignmentRows -Path $assignmentsPath
Write-TextUtf8 -Path $summaryPath -Text (($summaryLines -join "`r`n") + "`r`n")
