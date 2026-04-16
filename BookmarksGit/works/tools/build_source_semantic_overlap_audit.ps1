[CmdletBinding()]
param(
    [string]$RepoRoot = '.',
    [string]$VanillaGameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game',
    [string]$ModSourceRoot = 'C:\Program Files (x86)\Steam\steamapps\workshop\content\1158310\2216670956\0backup'
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

function Add-UniqueString {
    param(
        [Parameter(Mandatory = $true)]$TargetList,
        [Parameter(Mandatory = $true)][string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    foreach ($existing in $TargetList) {
        if ([string]$existing -eq $Value) {
            return
        }
    }

    $TargetList.Add($Value) | Out-Null
}

function Get-GitHeadText {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $prefixLines = @(& git -C $RepoRoot rev-parse --show-prefix 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to resolve git prefix under $RepoRoot"
    }

    $prefix = ($prefixLines -join '').Trim()
    $normalizedRelative = ($RelativePath -replace '\\', '/').TrimStart('./')
    $pathSpec = if ([string]::IsNullOrWhiteSpace($prefix)) {
        $normalizedRelative
    }
    else {
        ($prefix.TrimEnd('/') + '/' + $normalizedRelative)
    }

    $contentLines = @(& git -C $RepoRoot show "HEAD:$pathSpec" 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to read git HEAD text for $RelativePath (pathspec $pathSpec)"
    }

    return (($contentLines -join "`n").TrimEnd("`r", "`n") + "`n")
}

function Parse-DefaultMapClasses {
    param([Parameter(Mandatory = $true)][string]$Text)

    $allowedCategories = @(
        'sea_zones',
        'river_provinces',
        'lakes',
        'impassable_mountains',
        'impassable_seas'
    )
    $allowedLookup = @{}
    foreach ($category in $allowedCategories) {
        $allowedLookup[$category] = $true
    }

    $result = @{}
    foreach ($line in (Split-Lines -Text $Text)) {
        $visible = Strip-LineComment -Line $line
        if ([string]::IsNullOrWhiteSpace($visible)) {
            continue
        }

        if ($visible -match '^\s*([A-Za-z_]+)\s*=\s*(RANGE|LIST)\s*\{\s*([0-9\s]+)\s*\}\s*$') {
            $category = [string]$matches[1]
            $mode = [string]$matches[2]
            $numbers = @(
                foreach ($token in (($matches[3] -split '\s+') | Where-Object { $_ -match '^\d+$' })) {
                    [int]$token
                }
            )

            if (-not $allowedLookup.ContainsKey($category)) {
                continue
            }

            $ids = New-Object System.Collections.Generic.List[int]
            if ($mode -eq 'LIST') {
                foreach ($number in $numbers) {
                    $ids.Add([int]$number) | Out-Null
                }
            }
            elseif ($mode -eq 'RANGE' -and $numbers.Count -ge 2) {
                for ($id = [int]$numbers[0]; $id -le [int]$numbers[1]; $id++) {
                    $ids.Add($id) | Out-Null
                }
            }

            foreach ($id in $ids) {
                $key = [string]$id
                if (-not $result.ContainsKey($key)) {
                    $result[$key] = New-Object System.Collections.Generic.List[string]
                }
                Add-UniqueString -TargetList $result[$key] -Value $category
            }
        }
    }

    return $result
}

function Parse-LandedTitleProvinceBindings {
    param([Parameter(Mandatory = $true)][string]$Text)

    $bindingsByProvinceId = @{}
    $stack = New-Object System.Collections.Generic.List[object]
    $braceDepth = 0
    $lineNumber = 0

    foreach ($rawLine in (Split-Lines -Text $Text)) {
        $lineNumber++
        $visible = Strip-LineComment -Line $rawLine

        if ($visible -match '^\s*([ekdcb]_[A-Za-z0-9_\/\.\-]+)\s*=\s*\{') {
            $stack.Add([pscustomobject]@{
                title = [string]$matches[1]
                depth = $braceDepth
            }) | Out-Null
        }

        if ($visible -match '^\s*province\s*=\s*(\d+)\s*$') {
            $provinceId = [int]$matches[1]
            $provinceKey = [string]$provinceId
            $barony = ''
            $county = ''
            $duchy = ''
            $kingdom = ''
            $empire = ''

            for ($stackIndex = $stack.Count - 1; $stackIndex -ge 0; $stackIndex--) {
                $title = [string]$stack[$stackIndex].title
                if ([string]::IsNullOrWhiteSpace($barony) -and $title.StartsWith('b_')) {
                    $barony = $title
                    continue
                }
                if ([string]::IsNullOrWhiteSpace($county) -and $title.StartsWith('c_')) {
                    $county = $title
                    continue
                }
                if ([string]::IsNullOrWhiteSpace($duchy) -and $title.StartsWith('d_')) {
                    $duchy = $title
                    continue
                }
                if ([string]::IsNullOrWhiteSpace($kingdom) -and $title.StartsWith('k_')) {
                    $kingdom = $title
                    continue
                }
                if ([string]::IsNullOrWhiteSpace($empire) -and $title.StartsWith('e_')) {
                    $empire = $title
                    continue
                }
            }

            if (-not $bindingsByProvinceId.ContainsKey($provinceKey)) {
                $bindingsByProvinceId[$provinceKey] = New-Object System.Collections.ArrayList
            }

            [void]$bindingsByProvinceId[$provinceKey].Add([pscustomobject]@{
                province_id = $provinceId
                line_number = $lineNumber
                barony = $barony
                county = $county
                duchy = $duchy
                kingdom = $kingdom
                empire = $empire
            })
        }

        $braceDepth += Get-BraceDelta -Line $rawLine
        while ($stack.Count -gt 0 -and [int]$stack[$stack.Count - 1].depth -ge $braceDepth) {
            $stack.RemoveAt($stack.Count - 1)
        }
    }

    return $bindingsByProvinceId
}

function Join-UniqueValues {
    param([Parameter(Mandatory = $true)]$Values)

    $unique = New-Object System.Collections.Generic.List[string]
    foreach ($value in $Values) {
        $stringValue = [string]$value
        if ([string]::IsNullOrWhiteSpace($stringValue)) {
            continue
        }
        Add-UniqueString -TargetList $unique -Value $stringValue
    }

    if ($unique.Count -eq 0) {
        return ''
    }

    return (($unique | Sort-Object -Unique) -join '|')
}

function Get-LandedBindingSummary {
    param(
        [Parameter(Mandatory = $true)]$BindingsByProvinceId,
        [Parameter(Mandatory = $true)][int]$ProvinceId
    )

    $resolvedKey = [string]$ProvinceId
    if (-not $BindingsByProvinceId.ContainsKey($resolvedKey)) {
        return [pscustomobject]@{
            defined = $false
            binding_count = 0
            line_numbers = ''
            barony = ''
            county = ''
            duchy = ''
            kingdom = ''
            empire = ''
        }
    }

    $bindings = @($BindingsByProvinceId[$resolvedKey])
    return [pscustomobject]@{
        defined = $true
        binding_count = $bindings.Count
        line_numbers = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.line_number })
        barony = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.barony })
        county = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.county })
        duchy = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.duchy })
        kingdom = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.kingdom })
        empire = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.empire })
    }
}

function Build-LandedBindingSummaryIndex {
    param([Parameter(Mandatory = $true)]$BindingsByProvinceId)

    $summaryIndex = @{}
    foreach ($entry in $BindingsByProvinceId.GetEnumerator()) {
        $key = [string]$entry.Key
        $bindings = @($entry.Value)
        $summaryIndex[$key] = [pscustomobject]@{
            defined = $true
            binding_count = $bindings.Count
            line_numbers = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.line_number })
            barony = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.barony })
            county = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.county })
            duchy = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.duchy })
            kingdom = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.kingdom })
            empire = Join-UniqueValues -Values ($bindings | ForEach-Object { $_.empire })
        }
    }

    return $summaryIndex
}

function Get-DefaultMapClassSummary {
    param(
        [Parameter(Mandatory = $true)]$ClassIndex,
        [Parameter(Mandatory = $true)][int]$ProvinceId
    )

    $key = [string]$ProvinceId
    if (-not $ClassIndex.ContainsKey($key)) {
        return 'none'
    }

    $values = @($ClassIndex[$key] | Sort-Object -Unique)
    if ($values.Count -eq 0) {
        return 'none'
    }

    return ($values -join '|')
}

function Resolve-SemanticSuggestion {
    param(
        [Parameter(Mandatory = $true)]$Row
    )

    $modHasBarony = -not [string]::IsNullOrWhiteSpace([string]$Row.modlu_barony)
    $oriHasBarony = -not [string]::IsNullOrWhiteSpace([string]$Row.orijinal_barony)
    $modClass = [string]$Row.modlu_default_map_class
    $oriClass = [string]$Row.orijinal_default_map_class
    $sameId = [bool]$Row.same_id
    $sameName = [bool]$Row.same_name
    $modClassGroup = Get-ClassPriorityGroup -ClassSummary $modClass
    $oriClassGroup = Get-ClassPriorityGroup -ClassSummary $oriClass

    if ($modHasBarony -and $oriHasBarony) {
        if ([string]$Row.modlu_barony -eq [string]$Row.orijinal_barony) {
            return [pscustomobject]@{
                semantic_same_province_suggest = 'True'
                semantic_classification = 'same_barony'
                final_action_suggest = if ($sameId) { 'keep_single_identity' } else { 'merge_to_single_final_identity' }
                rationale = 'Iki source da ayni baronyye bagli.'
            }
        }

        return [pscustomobject]@{
            semantic_same_province_suggest = 'False'
            semantic_classification = 'different_barony'
            final_action_suggest = 'new_rgb_needed'
            rationale = 'Iki source farkli baronylere bagli.'
        }
    }

    if ($modHasBarony -xor $oriHasBarony) {
        return [pscustomobject]@{
            semantic_same_province_suggest = 'False'
            semantic_classification = 'barony_vs_nonbarony'
            final_action_suggest = 'new_rgb_needed'
            rationale = 'Bir source barony province, digeri landed_titles icinde barony olarak tanimli degil.'
        }
    }

    if ($sameId -and $sameName -and -not $modHasBarony -and -not $oriHasBarony) {
        $bothHaveStructuredNonlandClass =
            ($modClassGroup -in @('navigable_water', 'impassable', 'other')) -and
            ($oriClassGroup -in @('navigable_water', 'impassable', 'other'))

        if ($bothHaveStructuredNonlandClass) {
            return [pscustomobject]@{
                semantic_same_province_suggest = 'True'
                semantic_classification = 'same_id_same_name_nonbarony_nonland'
                final_action_suggest = 'keep_single_identity'
                rationale = 'ID ve isim ayni; iki source da landed barony degil ve default.map uzerinde yapisal nonland/su kaniti var.'
            }
        }
    }

    if ($modClass -ne 'none' -and $oriClass -ne 'none' -and $modClass -ne $oriClass) {
        return [pscustomobject]@{
            semantic_same_province_suggest = 'False'
            semantic_classification = 'different_default_map_class'
            final_action_suggest = 'new_rgb_needed'
            rationale = 'Source default.map siniflari farkli.'
        }
    }

    if ($modClass -ne 'none' -and $oriClass -ne 'none' -and $modClass -eq $oriClass) {
        return [pscustomobject]@{
            semantic_same_province_suggest = 'Review'
            semantic_classification = 'same_noncounty_default_class_review'
            final_action_suggest = 'needs_manual_review'
            rationale = 'Iki source ayni non-county default.map sinifinda ama landed_titles barony kaniti yok.'
        }
    }

    if ($sameId -and $sameName) {
        return [pscustomobject]@{
            semantic_same_province_suggest = 'Review'
            semantic_classification = 'same_id_same_name_no_structural_match_review'
            final_action_suggest = 'needs_manual_review'
            rationale = 'ID ve isim ayni ama structural kanit bulunmadi.'
        }
    }

    return [pscustomobject]@{
        semantic_same_province_suggest = 'Review'
        semantic_classification = 'unclassified_review'
        final_action_suggest = 'needs_manual_review'
        rationale = 'Source default.map ve landed_titles tek basina net karar vermiyor.'
    }
}

function Get-ClassPriorityGroup {
    param([AllowEmptyString()][string]$ClassSummary)

    if ([string]::IsNullOrWhiteSpace($ClassSummary) -or $ClassSummary -eq 'none') {
        return 'none'
    }

    $classes = @($ClassSummary -split '\|')
    if ($classes -contains 'sea_zones') { return 'navigable_water' }
    if ($classes -contains 'river_provinces') { return 'navigable_water' }
    if ($classes -contains 'lakes') { return 'navigable_water' }
    if ($classes -contains 'impassable_mountains') { return 'impassable' }
    if ($classes -contains 'impassable_seas') { return 'impassable' }
    return 'other'
}

function Get-IntValueSafe {
    param($Value)

    $text = [string]$Value
    if ($text -match '^\d+$') {
        return [int]$text
    }
    return 0
}

function Resolve-AutoDecisionRecommendation {
    param(
        [Parameter(Mandatory = $true)]$Row
    )

    $modHasBarony = -not [string]::IsNullOrWhiteSpace([string]$Row.modlu_barony)
    $oriHasBarony = -not [string]::IsNullOrWhiteSpace([string]$Row.orijinal_barony)
    $modClassGroup = Get-ClassPriorityGroup -ClassSummary ([string]$Row.modlu_default_map_class)
    $oriClassGroup = Get-ClassPriorityGroup -ClassSummary ([string]$Row.orijinal_default_map_class)
    $modPixels = Get-IntValueSafe -Value $Row.modlu_pixel_count
    $oriPixels = Get-IntValueSafe -Value $Row.orijinal_pixel_count
    $classification = [string]$Row.semantic_classification
    $semanticSuggest = [string]$Row.semantic_same_province_suggest

    if ($classification -eq 'same_barony' -and $semanticSuggest -eq 'True') {
        return [pscustomobject]@{
            auto_keep_rgb_source = 'shared'
            auto_recolor_source = ''
            auto_requires_new_rgb = 'False'
            auto_final_action = 'keep_single_identity'
            auto_decision_confidence = 'high'
            auto_decision_notes = 'Iki source ayni baronyye bagli; recolor gerekmiyor.'
        }
    }

    if ($classification -eq 'same_id_same_name_nonbarony_nonland' -and $semanticSuggest -eq 'True') {
        return [pscustomobject]@{
            auto_keep_rgb_source = 'shared'
            auto_recolor_source = ''
            auto_requires_new_rgb = 'False'
            auto_final_action = 'keep_single_identity'
            auto_decision_confidence = 'high'
            auto_decision_notes = 'Ayni ID ve isimle yapisal nonland/su province; recolor gerekmiyor.'
        }
    }

    if ($classification -eq 'barony_vs_nonbarony' -and $semanticSuggest -eq 'False') {
        if ($modHasBarony -and -not $oriHasBarony) {
            return [pscustomobject]@{
                auto_keep_rgb_source = 'modlu'
                auto_recolor_source = 'orijinal'
                auto_requires_new_rgb = 'True'
                auto_final_action = 'new_rgb_needed'
                auto_decision_confidence = 'high'
                auto_decision_notes = 'Barony province tarafi modlu; nonbarony/orijinal taraf recolor olmali.'
            }
        }

        if ($oriHasBarony -and -not $modHasBarony) {
            return [pscustomobject]@{
                auto_keep_rgb_source = 'orijinal'
                auto_recolor_source = 'modlu'
                auto_requires_new_rgb = 'True'
                auto_final_action = 'new_rgb_needed'
                auto_decision_confidence = 'high'
                auto_decision_notes = 'Barony province tarafi orijinal; nonbarony/modlu taraf recolor olmali.'
            }
        }
    }

    if ($classification -eq 'different_default_map_class' -and $semanticSuggest -eq 'False') {
        if ($modClassGroup -eq 'navigable_water' -and $oriClassGroup -eq 'impassable') {
            return [pscustomobject]@{
                auto_keep_rgb_source = 'modlu'
                auto_recolor_source = 'orijinal'
                auto_requires_new_rgb = 'True'
                auto_final_action = 'new_rgb_needed'
                auto_decision_confidence = 'medium'
                auto_decision_notes = 'Navigable water tarafi korunur, impassable taraf recolor olur.'
            }
        }

        if ($oriClassGroup -eq 'navigable_water' -and $modClassGroup -eq 'impassable') {
            return [pscustomobject]@{
                auto_keep_rgb_source = 'orijinal'
                auto_recolor_source = 'modlu'
                auto_requires_new_rgb = 'True'
                auto_final_action = 'new_rgb_needed'
                auto_decision_confidence = 'medium'
                auto_decision_notes = 'Navigable water tarafi korunur, impassable taraf recolor olur.'
            }
        }
    }

    if ($classification -eq 'different_barony' -and $semanticSuggest -eq 'False') {
        if ($modPixels -gt 0 -or $oriPixels -gt 0) {
            if ($modPixels -ge $oriPixels) {
                return [pscustomobject]@{
                    auto_keep_rgb_source = 'modlu'
                    auto_recolor_source = 'orijinal'
                    auto_requires_new_rgb = 'True'
                    auto_final_action = 'new_rgb_needed'
                    auto_decision_confidence = 'medium'
                    auto_decision_notes = 'Iki taraf da farkli barony; daha buyuk piksel alani korundu.'
                }
            }

            return [pscustomobject]@{
                auto_keep_rgb_source = 'orijinal'
                auto_recolor_source = 'modlu'
                auto_requires_new_rgb = 'True'
                auto_final_action = 'new_rgb_needed'
                auto_decision_confidence = 'medium'
                auto_decision_notes = 'Iki taraf da farkli barony; daha buyuk piksel alani korundu.'
            }
        }
    }

    return [pscustomobject]@{
        auto_keep_rgb_source = ''
        auto_recolor_source = ''
        auto_requires_new_rgb = ''
        auto_final_action = 'needs_manual_review'
        auto_decision_confidence = ''
        auto_decision_notes = ''
    }
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$outputDir = Join-Path $root 'Works\analysis\generated\source_semantic_overlap_audit'
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$conflictsPath = Join-Path $root 'Works\analysis\generated\source_rgb_overlap_audit\source_rgb_overlap_conflicts.csv'
$sameIdPath = Join-Path $root 'Works\analysis\generated\source_rgb_overlap_audit\source_rgb_overlap_same_id.csv'
$auditPath = Join-Path $outputDir 'source_rgb_overlap_semantic_audit.csv'
$decisionsPath = Join-Path $outputDir 'source_rgb_overlap_semantic_decisions.csv'
$summaryPath = Join-Path $outputDir 'source_rgb_overlap_semantic_summary.md'
$classCountsPath = Join-Path $outputDir 'source_rgb_overlap_semantic_class_counts.csv'

$modDefaultMapPath = Join-Path $ModSourceRoot 'map_data\default.map'
$modLandedTitlesPath = Join-Path $ModSourceRoot 'common\landed_titles\00_landed_titles.txt'
$useBackupModSource = (Test-Path -LiteralPath $modDefaultMapPath) -and (Test-Path -LiteralPath $modLandedTitlesPath)

$modDefaultMapText = if ($useBackupModSource) {
    Read-TextUtf8 -Path $modDefaultMapPath
}
else {
    Get-GitHeadText -RepoRoot $root -RelativePath 'map_data/default.map'
}

$modLandedTitlesText = if ($useBackupModSource) {
    Read-TextUtf8 -Path $modLandedTitlesPath
}
else {
    Get-GitHeadText -RepoRoot $root -RelativePath 'common/landed_titles/00_landed_titles.txt'
}
$vanillaDefaultMapPath = Join-Path $VanillaGameRoot 'map_data\default.map'
$vanillaLandedTitlesPath = Join-Path $VanillaGameRoot 'common\landed_titles\00_landed_titles.txt'
$vanillaDefaultMapText = Read-TextUtf8 -Path $vanillaDefaultMapPath
$vanillaLandedTitlesText = Read-TextUtf8 -Path $vanillaLandedTitlesPath

$modDefaultMapIndex = Parse-DefaultMapClasses -Text $modDefaultMapText
$vanillaDefaultMapIndex = Parse-DefaultMapClasses -Text $vanillaDefaultMapText
$modLandedBindings = Parse-LandedTitleProvinceBindings -Text $modLandedTitlesText
$vanillaLandedBindings = Parse-LandedTitleProvinceBindings -Text $vanillaLandedTitlesText
$modLandedBindingSummaryIndex = Build-LandedBindingSummaryIndex -BindingsByProvinceId $modLandedBindings
$vanillaLandedBindingSummaryIndex = Build-LandedBindingSummaryIndex -BindingsByProvinceId $vanillaLandedBindings

$inputRows = @()
$inputRows += Import-Csv -Path $sameIdPath
$inputRows += Import-Csv -Path $conflictsPath

$auditRows = New-Object System.Collections.Generic.List[object]
foreach ($row in $inputRows) {
    $modId = [int]$row.modlu_id
    $oriId = [int]$row.orijinal_id
    $sameId = [System.Convert]::ToBoolean([string]$row.same_id)
    $sameName = [System.Convert]::ToBoolean([string]$row.same_name)

    $modClass = Get-DefaultMapClassSummary -ClassIndex $modDefaultMapIndex -ProvinceId $modId
    $oriClass = Get-DefaultMapClassSummary -ClassIndex $vanillaDefaultMapIndex -ProvinceId $oriId
    $modBinding = if ($modLandedBindingSummaryIndex.ContainsKey([string]$modId)) {
        $modLandedBindingSummaryIndex[[string]$modId]
    }
    else {
        [pscustomobject]@{
            defined = $false
            binding_count = 0
            line_numbers = ''
            barony = ''
            county = ''
            duchy = ''
            kingdom = ''
            empire = ''
        }
    }

    $oriBinding = if ($vanillaLandedBindingSummaryIndex.ContainsKey([string]$oriId)) {
        $vanillaLandedBindingSummaryIndex[[string]$oriId]
    }
    else {
        [pscustomobject]@{
            defined = $false
            binding_count = 0
            line_numbers = ''
            barony = ''
            county = ''
            duchy = ''
            kingdom = ''
            empire = ''
        }
    }

    $enriched = [pscustomobject]@{
        rgb = [string]$row.rgb
        modlu_id = $modId
        modlu_name = [string]$row.modlu_name
        modlu_pixel_count = [string]$row.modlu_pixel_count
        modlu_bbox = [string]$row.modlu_bbox
        modlu_default_map_class = $modClass
        modlu_landed_defined = [bool]$modBinding.defined
        modlu_landed_binding_count = [int]$modBinding.binding_count
        modlu_landed_line_numbers = [string]$modBinding.line_numbers
        modlu_barony = [string]$modBinding.barony
        modlu_county = [string]$modBinding.county
        modlu_duchy = [string]$modBinding.duchy
        modlu_kingdom = [string]$modBinding.kingdom
        modlu_empire = [string]$modBinding.empire
        orijinal_id = $oriId
        orijinal_name = [string]$row.orijinal_name
        orijinal_pixel_count = [string]$row.orijinal_pixel_count
        orijinal_bbox = [string]$row.orijinal_bbox
        orijinal_default_map_class = $oriClass
        orijinal_landed_defined = [bool]$oriBinding.defined
        orijinal_landed_binding_count = [int]$oriBinding.binding_count
        orijinal_landed_line_numbers = [string]$oriBinding.line_numbers
        orijinal_barony = [string]$oriBinding.barony
        orijinal_county = [string]$oriBinding.county
        orijinal_duchy = [string]$oriBinding.duchy
        orijinal_kingdom = [string]$oriBinding.kingdom
        orijinal_empire = [string]$oriBinding.empire
        same_id = $sameId
        same_name = $sameName
    }

    $suggestion = Resolve-SemanticSuggestion -Row $enriched
    $auditRows.Add([pscustomobject]@{
        rgb = $enriched.rgb
        modlu_id = $enriched.modlu_id
        modlu_name = $enriched.modlu_name
        modlu_pixel_count = $enriched.modlu_pixel_count
        modlu_bbox = $enriched.modlu_bbox
        modlu_default_map_class = $enriched.modlu_default_map_class
        modlu_landed_defined = $enriched.modlu_landed_defined
        modlu_landed_binding_count = $enriched.modlu_landed_binding_count
        modlu_landed_line_numbers = $enriched.modlu_landed_line_numbers
        modlu_barony = $enriched.modlu_barony
        modlu_county = $enriched.modlu_county
        modlu_duchy = $enriched.modlu_duchy
        modlu_kingdom = $enriched.modlu_kingdom
        modlu_empire = $enriched.modlu_empire
        orijinal_id = $enriched.orijinal_id
        orijinal_name = $enriched.orijinal_name
        orijinal_pixel_count = $enriched.orijinal_pixel_count
        orijinal_bbox = $enriched.orijinal_bbox
        orijinal_default_map_class = $enriched.orijinal_default_map_class
        orijinal_landed_defined = $enriched.orijinal_landed_defined
        orijinal_landed_binding_count = $enriched.orijinal_landed_binding_count
        orijinal_landed_line_numbers = $enriched.orijinal_landed_line_numbers
        orijinal_barony = $enriched.orijinal_barony
        orijinal_county = $enriched.orijinal_county
        orijinal_duchy = $enriched.orijinal_duchy
        orijinal_kingdom = $enriched.orijinal_kingdom
        orijinal_empire = $enriched.orijinal_empire
        same_id = $enriched.same_id
        same_name = $enriched.same_name
        semantic_same_province_suggest = [string]$suggestion.semantic_same_province_suggest
        semantic_classification = [string]$suggestion.semantic_classification
        final_action_suggest = [string]$suggestion.final_action_suggest
        rationale = [string]$suggestion.rationale
    }) | Out-Null
}

$orderedAuditRows = @(
    $auditRows |
        Sort-Object `
            @{ Expression = { if ([bool]$_.same_id) { 0 } else { 1 } } }, `
            @{ Expression = { $_.rgb } }
)

$decisionRows = foreach ($row in $orderedAuditRows) {
    $autoDecision = Resolve-AutoDecisionRecommendation -Row $row
    [pscustomobject]@{
        rgb = $row.rgb
        modlu_id = $row.modlu_id
        modlu_name = $row.modlu_name
        modlu_default_map_class = $row.modlu_default_map_class
        modlu_barony = $row.modlu_barony
        modlu_county = $row.modlu_county
        orijinal_id = $row.orijinal_id
        orijinal_name = $row.orijinal_name
        orijinal_default_map_class = $row.orijinal_default_map_class
        orijinal_barony = $row.orijinal_barony
        orijinal_county = $row.orijinal_county
        same_id = $row.same_id
        same_name = $row.same_name
        semantic_same_province_suggest = $row.semantic_same_province_suggest
        semantic_classification = $row.semantic_classification
        final_action_suggest = $row.final_action_suggest
        rationale = $row.rationale
        auto_keep_rgb_source = $autoDecision.auto_keep_rgb_source
        auto_recolor_source = $autoDecision.auto_recolor_source
        auto_requires_new_rgb = $autoDecision.auto_requires_new_rgb
        auto_final_action = $autoDecision.auto_final_action
        auto_decision_confidence = $autoDecision.auto_decision_confidence
        auto_decision_notes = $autoDecision.auto_decision_notes
        manual_semantic_same_province = ''
        manual_final_action = ''
        manual_notes = ''
    }
}

$classCountRows = @(
    $orderedAuditRows |
        Group-Object semantic_classification |
        Sort-Object -Property @{ Expression = { $_.Count }; Descending = $true }, @{ Expression = { $_.Name }; Descending = $false } |
        ForEach-Object {
            [pscustomobject]@{
                semantic_classification = $_.Name
                count = $_.Count
            }
        }
)

$suggestCountRows = @(
    $orderedAuditRows |
        Group-Object semantic_same_province_suggest |
        Sort-Object -Property @{ Expression = { $_.Count }; Descending = $true }, @{ Expression = { $_.Name }; Descending = $false }
)

$sameIdTotal = @($orderedAuditRows | Where-Object { $_.same_id }).Count
$sameIdDifferentName = @($orderedAuditRows | Where-Object { $_.same_id -and -not $_.same_name }).Count
$differentIdTotal = @($orderedAuditRows | Where-Object { -not $_.same_id }).Count
$autoDecisionRows = @($decisionRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.auto_keep_rgb_source) -or $_.auto_final_action -eq 'keep_single_identity' })
$manualReviewRows = @($decisionRows | Where-Object { $_.auto_final_action -eq 'needs_manual_review' })

$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add('# Source Semantic RGB Overlap Audit') | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add("Toplam ortak RGB satiri: $($orderedAuditRows.Count)") | Out-Null
$summaryLines.Add("- same RGB + same ID: $sameIdTotal") | Out-Null
$summaryLines.Add("- same RGB + different ID: $differentIdTotal") | Out-Null
$summaryLines.Add("- same RGB + same ID + different name: $sameIdDifferentName") | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add('Semantic suggestion sayilari:') | Out-Null
foreach ($group in $suggestCountRows) {
    $summaryLines.Add("- $([string]$group.Name): $([int]$group.Count)") | Out-Null
}
$summaryLines.Add('') | Out-Null
$summaryLines.Add('Semantic classification sayilari:') | Out-Null
foreach ($row in $classCountRows) {
    $summaryLines.Add("- $([string]$row.semantic_classification): $([int]$row.count)") | Out-Null
}
$summaryLines.Add('') | Out-Null
$summaryLines.Add("Otomatik karar verilebilen satir: $($autoDecisionRows.Count)") | Out-Null
$summaryLines.Add("Manual review kalan satir: $($manualReviewRows.Count)") | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add('Notlar:') | Out-Null
$summaryLines.Add("- Mod source semantic verisi $(if ($useBackupModSource) { '0backup klasorunden okundu.' } else { 'git HEAD icindeki source default.map ve source landed_titles uzerinden okundu.' })") | Out-Null
$summaryLines.Add('- Orijinal source semantic verisi vanilla game default.map ve landed_titles uzerinden okundu.') | Out-Null
$summaryLines.Add('- Bu tur sadece audit/karar destegi uretir; canli map_data veya landed_titles dosyalarina dokunmaz.') | Out-Null
$summaryLines.Add('- semantic_same_province_suggest = True sadece ayni barony kaniti varsa verilir; diger pek cok durum bilincli olarak Review kalir.') | Out-Null

Export-Utf8Csv -Rows $orderedAuditRows -Path $auditPath
Export-Utf8Csv -Rows $decisionRows -Path $decisionsPath
Export-Utf8Csv -Rows $classCountRows -Path $classCountsPath
Write-TextUtf8 -Path $summaryPath -Text (($summaryLines -join "`r`n") + "`r`n")
