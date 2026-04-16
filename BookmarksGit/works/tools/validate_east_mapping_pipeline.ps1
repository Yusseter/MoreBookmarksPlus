param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-Utf8NoBomEncoding {
	return New-Object System.Text.UTF8Encoding($false)
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

function Read-CsvUtf8 {
	param([Parameter(Mandatory = $true)][string]$Path)

	if (-not (Test-Path -LiteralPath $Path)) {
		return @()
	}

	$text = Read-TextUtf8 -Path $Path
	if ([string]::IsNullOrWhiteSpace($text)) {
		return @()
	}
	return $text | ConvertFrom-Csv
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

function Normalize-YesNo {
	param([AllowEmptyString()][string]$Value)

	switch (([string]$Value).Trim().ToLowerInvariant()) {
		'yes' { return 'yes' }
		'no' { return 'no' }
		default { return ([string]$Value).Trim().ToLowerInvariant() }
	}
}

function Normalize-Status {
	param([AllowEmptyString()][string]$Value)

	switch (([string]$Value).Trim().ToLowerInvariant()) {
		'mapped' { return 'mapped' }
		'manual_review' { return 'manual_review' }
		'blocked' { return 'blocked' }
		default { return ([string]$Value).Trim().ToLowerInvariant() }
	}
}

function Get-BraceCount {
	param(
		[Parameter(Mandatory = $true)][AllowEmptyString()][string]$Line,
		[Parameter(Mandatory = $true)][char]$Brace
	)

	$count = 0
	foreach ($character in $Line.ToCharArray()) {
		if ($character -eq $Brace) {
			$count++
		}
	}
	return $count
}

function Add-IdsFromSpec {
	param(
		[Parameter(Mandatory = $true)]$Set,
		[Parameter(Mandatory = $true)][string]$Body
	)

	$rangeMatches = [regex]::Matches($Body, 'RANGE\s*\{\s*(\d+)\s+(\d+)\s*\}')
	foreach ($match in $rangeMatches) {
		$start = [int]$match.Groups[1].Value
		$end = [int]$match.Groups[2].Value
		for ($id = $start; $id -le $end; $id++) {
			$Set.Add($id) | Out-Null
		}
	}

	$listMatches = [regex]::Matches($Body, 'LIST\s*\{\s*([0-9\s]+)\}')
	foreach ($match in $listMatches) {
		$numbers = ([string]$match.Groups[1].Value).Trim() -split '\s+'
		foreach ($number in $numbers) {
			if ($number) {
				$Set.Add([int]$number) | Out-Null
			}
		}
	}
}

function Get-ProvinceSetsFromDefaultMap {
	param([Parameter(Mandatory = $true)][string]$Path)

	$sea = New-Object System.Collections.Generic.HashSet[int]
	$river = New-Object System.Collections.Generic.HashSet[int]
	$lakes = New-Object System.Collections.Generic.HashSet[int]
	$impassable = New-Object System.Collections.Generic.HashSet[int]

	foreach ($line in (Split-Lines -Text (Read-TextUtf8 -Path $Path))) {
		$visible = Strip-LineComment -Line $line
		if ($visible -match '^\s*sea_zones\s*=') {
			Add-IdsFromSpec -Set $sea -Body $visible
			continue
		}
		if ($visible -match '^\s*river_provinces\s*=') {
			Add-IdsFromSpec -Set $river -Body $visible
			continue
		}
		if ($visible -match '^\s*lakes\s*=') {
			Add-IdsFromSpec -Set $lakes -Body $visible
			continue
		}
		if ($visible -match '^\s*impassable_mountains\s*=') {
			Add-IdsFromSpec -Set $impassable -Body $visible
			continue
		}
		if ($visible -match '^\s*impassable_seas\s*=') {
			Add-IdsFromSpec -Set $impassable -Body $visible
			continue
		}
	}

	return [pscustomobject]@{
		SeaZones = $sea
		RiverProvinces = $river
		Lakes = $lakes
		Impassable = $impassable
	}
}

function Get-DefinitionProvinceMap {
	param([Parameter(Mandatory = $true)][string]$Path)

	$result = @{}
	foreach ($line in (Split-Lines -Text (Read-TextUtf8 -Path $Path))) {
		$visible = Strip-LineComment -Line $line
		if ([string]::IsNullOrWhiteSpace($visible)) {
			continue
		}
		$parts = $visible.Split(';')
		if ($parts.Length -lt 5) {
			continue
		}
		if (-not [int]::TryParse($parts[0], [ref]$null)) {
			continue
		}
		$id = [int]$parts[0]
		$result[$id] = [pscustomobject]@{
			Id = $id
			R = [string]$parts[1]
			G = [string]$parts[2]
			B = [string]$parts[3]
			Name = [string]$parts[4]
		}
	}
	return $result
}

function Parse-LandedTitlesFile {
	param([Parameter(Mandatory = $true)][string]$Path)

	$titleNodes = @{}
	$titleIds = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
	$stack = New-Object System.Collections.ArrayList
	$braceDepth = 0
	$lineNumber = 0

	foreach ($line in (Split-Lines -Text (Read-TextUtf8 -Path $Path))) {
		$lineNumber++
		$visible = Strip-LineComment -Line $line
		$trimmed = $visible.Trim()

		$titleMatch = [regex]::Match($visible, "^\s*([ehkdcb]_[A-Za-z0-9_\/\.\-']+)\s*=\s*\{\s*$")
		if ($titleMatch.Success) {
			$titleId = [string]$titleMatch.Groups[1].Value
			$tier = $titleId.Substring(0, 1)
			$parentTitleId = $null
			for ($index = $stack.Count - 1; $index -ge 0; $index--) {
				$frame = $stack[$index]
				if ($frame.Kind -eq 'title') {
					$parentTitleId = [string]$frame.TitleId
					break
				}
			}

			$node = [pscustomobject]@{
				TitleId = $titleId
				Tier = $tier
				ParentTitleId = $parentTitleId
				CapitalTitleId = ''
				ProvinceId = ''
				LineNumber = $lineNumber
			}
			$titleNodes[$titleId] = $node
			$titleIds.Add($titleId) | Out-Null
			[void]$stack.Add([pscustomobject]@{ Kind = 'title'; TitleId = $titleId })
		}

		$currentTitleId = $null
		for ($index = $stack.Count - 1; $index -ge 0; $index--) {
			$frame = $stack[$index]
			if ($frame.Kind -eq 'title') {
				$currentTitleId = [string]$frame.TitleId
				break
			}
		}

		if ($currentTitleId) {
			$capitalMatch = [regex]::Match($visible, '^\s*capital\s*=\s*(c_[A-Za-z0-9_\/\.\-]+)\b')
			if ($capitalMatch.Success) {
				$titleNodes[$currentTitleId].CapitalTitleId = [string]$capitalMatch.Groups[1].Value
			}
			$provinceMatch = [regex]::Match($visible, '^\s*province\s*=\s*(\d+)\b')
			if ($provinceMatch.Success) {
				$titleNodes[$currentTitleId].ProvinceId = [string]$provinceMatch.Groups[1].Value
			}
		}

		$openCount = Get-BraceCount -Line $visible -Brace '{'
		$closeCount = Get-BraceCount -Line $visible -Brace '}'
		if ($titleMatch.Success) {
			$openCount--
		}
		for ($i = 0; $i -lt $openCount; $i++) {
			[void]$stack.Add([pscustomobject]@{ Kind = 'generic'; TitleId = '' })
		}
		for ($i = 0; $i -lt $closeCount; $i++) {
			if ($stack.Count -gt 0) {
				$stack.RemoveAt($stack.Count - 1)
			}
		}

		$braceDepth += (Get-BraceCount -Line $visible -Brace '{')
		$braceDepth -= (Get-BraceCount -Line $visible -Brace '}')
	}

	return [pscustomobject]@{
		TitleNodes = $titleNodes
		TitleIds = $titleIds
		FinalBraceDepth = $braceDepth
	}
}

function Get-ExpectedChildTier {
	param([Parameter(Mandatory = $true)][string]$Tier)

	switch ($Tier) {
		'e' { return 'k' }
		'k' { return 'd' }
		'd' { return 'c' }
		'c' { return 'b' }
		default { return '' }
	}
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$generatedRoot = Join-Path $repoRoot 'works\analysis\generated\east_mapping_validation'
New-Item -ItemType Directory -Path $generatedRoot -Force | Out-Null

$provinceMasterPath = Join-Path $repoRoot 'works\map_data_sources\province_relation_master.csv'
$provinceApplyReportPath = Join-Path $repoRoot 'works\analysis\generated\province_relation_mapping\province_relation_history_apply_report.csv'
$titleMasterPath = Join-Path $repoRoot 'works\map_data_sources\title_relation_master.csv'
$titleInventoryPath = Join-Path $repoRoot 'works\analysis\generated\title_relation_mapping\title_relation_source_inventory.csv'
$titleRewriteCandidatesPath = Join-Path $repoRoot 'works\analysis\generated\title_relation_mapping\title_relation_rewrite_candidates.csv'
$landedTitlesPath = Join-Path $repoRoot 'common\landed_titles\00_landed_titles.txt'
$testLandedTitlesPath = Join-Path $repoRoot 'test_files\common\landed_titles\00_landed_titles.txt'
$definitionPath = Join-Path $repoRoot 'map_data\definition.csv'
$defaultMapPath = Join-Path $repoRoot 'map_data\default.map'

$provinceRows = @(Read-CsvUtf8 -Path $provinceMasterPath)
$provinceApplyRows = @(Read-CsvUtf8 -Path $provinceApplyReportPath)
$titleRows = @(Read-CsvUtf8 -Path $titleMasterPath)
$titleInventoryRows = @(Read-CsvUtf8 -Path $titleInventoryPath)
$rewriteCandidateRows = @(Read-CsvUtf8 -Path $titleRewriteCandidatesPath)

$findings = New-Object System.Collections.Generic.List[object]

foreach ($row in $provinceRows) {
	$classification = ([string]$row.classification).Trim().ToLowerInvariant()
	$status = Normalize-Status -Value ([string]$row.status)
	$applyToHistory = Normalize-YesNo -Value ([string]$row.apply_to_history)
	if ($applyToHistory -eq 'yes' -and -not ($classification -eq 'exact' -and $status -eq 'mapped')) {
		$findings.Add([pscustomobject]@{
			category = 'province_master'
			severity = 'error'
			key = [string]$row.source_province_id
			message = 'apply_to_history=yes only allowed for exact + mapped rows.'
		}) | Out-Null
	}
}

$provinceAllowedKeys = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
foreach ($row in $provinceRows) {
	if (([string]$row.classification).Trim().ToLowerInvariant() -eq 'exact' -and
		(Normalize-Status -Value ([string]$row.status)) -eq 'mapped' -and
		(Normalize-YesNo -Value ([string]$row.apply_to_history)) -eq 'yes') {
		$provinceAllowedKeys.Add(("{0}|{1}" -f [string]$row.source_province_id, [string]$row.target_province_id)) | Out-Null
	}
}

foreach ($row in $provinceApplyRows) {
	if (([string]$row.status).Trim().ToLowerInvariant() -ne 'applied') {
		continue
	}
	$key = '{0}|{1}' -f [string]$row.source_province_id, [string]$row.target_province_id
	if (-not $provinceAllowedKeys.Contains($key)) {
		$findings.Add([pscustomobject]@{
			category = 'province_history_apply'
			severity = 'error'
			key = $key
			message = 'Applied province history row is not backed by exact + mapped + apply_to_history=yes.'
		}) | Out-Null
	}
}

$titleBySource = @{}
foreach ($row in $titleRows) {
	$titleBySource[[string]$row.source_title_id] = $row
}

foreach ($inventoryRow in $titleInventoryRows) {
	if (-not $titleBySource.ContainsKey([string]$inventoryRow.source_title_id)) {
		$findings.Add([pscustomobject]@{
			category = 'title_master'
			severity = 'error'
			key = [string]$inventoryRow.source_title_id
			message = 'Source title exists in inventory but not in title_relation_master.csv.'
		}) | Out-Null
	}
}

foreach ($rewriteRow in $rewriteCandidateRows) {
	$sourceTitleId = [string]$rewriteRow.source_title_id
	if (-not $titleBySource.ContainsKey($sourceTitleId)) {
		$findings.Add([pscustomobject]@{
			category = 'title_rewrite'
			severity = 'error'
			key = $sourceTitleId
			message = 'Rewrite candidate does not exist in title master.'
		}) | Out-Null
		continue
	}

	$masterRow = $titleBySource[$sourceTitleId]
	$status = Normalize-Status -Value ([string]$masterRow.status)
	$rewriteAllowed = Normalize-YesNo -Value ([string]$masterRow.rewrite_allowed)
	$relationType = ([string]$masterRow.relation_type).Trim().ToLowerInvariant()
	if (-not ($status -eq 'mapped' -and $rewriteAllowed -eq 'yes' -and @('exact', 'contextual') -contains $relationType)) {
		$findings.Add([pscustomobject]@{
			category = 'title_rewrite'
			severity = 'error'
			key = $sourceTitleId
			message = 'Rewrite candidate violates mapped/allowed/exact-contextual safety gate.'
		}) | Out-Null
	}
}

$landed = Parse-LandedTitlesFile -Path $landedTitlesPath
$testLanded = Parse-LandedTitlesFile -Path $testLandedTitlesPath

if ($landed.FinalBraceDepth -ne 0) {
	$findings.Add([pscustomobject]@{
		category = 'landed_titles'
		severity = 'error'
		key = 'common/landed_titles/00_landed_titles.txt'
		message = ('Brace balance is not zero. final_depth={0}' -f $landed.FinalBraceDepth)
	}) | Out-Null
}

if ($testLanded.FinalBraceDepth -ne 0) {
	$findings.Add([pscustomobject]@{
		category = 'landed_titles'
		severity = 'error'
		key = 'test_files/common/landed_titles/00_landed_titles.txt'
		message = ('Brace balance is not zero. final_depth={0}' -f $testLanded.FinalBraceDepth)
	}) | Out-Null
}

$landedHash = (Get-FileHash -LiteralPath $landedTitlesPath).Hash
$testLandedHash = (Get-FileHash -LiteralPath $testLandedTitlesPath).Hash
if ($landedHash -ne $testLandedHash) {
	$findings.Add([pscustomobject]@{
		category = 'landed_titles_sync'
		severity = 'error'
		key = 'live_vs_test'
		message = 'common and test_files landed_titles hashes differ.'
	}) | Out-Null
}

$provinceToTitles = @{}
foreach ($node in $landed.TitleNodes.Values) {
	if ($node.Tier -ne 'b' -or [string]::IsNullOrWhiteSpace([string]$node.ProvinceId)) {
		continue
	}
	if (-not $provinceToTitles.ContainsKey([string]$node.ProvinceId)) {
		$provinceToTitles[[string]$node.ProvinceId] = New-Object System.Collections.Generic.List[string]
	}
	$provinceToTitles[[string]$node.ProvinceId].Add([string]$node.TitleId) | Out-Null
}

foreach ($provinceId in ($provinceToTitles.Keys | Sort-Object { [int]$_ })) {
	$titles = $provinceToTitles[$provinceId]
	if ($titles.Count -gt 1) {
		$findings.Add([pscustomobject]@{
			category = 'duplicate_province_assignment'
			severity = 'error'
			key = $provinceId
			message = ('Province ID is assigned to multiple baronies: {0}' -f ($titles -join ', '))
		}) | Out-Null
	}
}

foreach ($node in $landed.TitleNodes.Values) {
	if ($node.ParentTitleId) {
		$parentNode = $landed.TitleNodes[[string]$node.ParentTitleId]
		if ($null -ne $parentNode -and $parentNode.Tier -ne 'h') {
			$expectedTier = Get-ExpectedChildTier -Tier ([string]$parentNode.Tier)
			if ($expectedTier -and $node.Tier -ne $expectedTier) {
				$findings.Add([pscustomobject]@{
					category = 'invalid_hierarchy'
					severity = 'error'
					key = [string]$node.TitleId
					message = ('Invalid de jure parent/child tier: {0} -> {1}' -f $node.ParentTitleId, $node.TitleId)
				}) | Out-Null
			}
		}
	}

	if ($node.CapitalTitleId -and -not $landed.TitleIds.Contains([string]$node.CapitalTitleId)) {
		$findings.Add([pscustomobject]@{
			category = 'invalid_capital'
			severity = 'error'
			key = [string]$node.TitleId
			message = ('Capital title does not exist: {0}' -f $node.CapitalTitleId)
		}) | Out-Null
	}
}

$provinceSets = Get-ProvinceSetsFromDefaultMap -Path $defaultMapPath
$definitionMap = Get-DefinitionProvinceMap -Path $definitionPath

$nonLand = New-Object System.Collections.Generic.HashSet[int]
foreach ($id in $provinceSets.SeaZones) { $nonLand.Add($id) | Out-Null }
foreach ($id in $provinceSets.RiverProvinces) { $nonLand.Add($id) | Out-Null }
foreach ($id in $provinceSets.Lakes) { $nonLand.Add($id) | Out-Null }
foreach ($id in $provinceSets.Impassable) { $nonLand.Add($id) | Out-Null }

foreach ($node in $landed.TitleNodes.Values) {
	if ($node.Tier -ne 'b' -or [string]::IsNullOrWhiteSpace([string]$node.ProvinceId)) {
		continue
	}
	$provinceId = [int]$node.ProvinceId
	if ($nonLand.Contains($provinceId)) {
		$findings.Add([pscustomobject]@{
			category = 'non_land_province_assignment'
			severity = 'error'
			key = [string]$node.TitleId
			message = ('Barony uses non-land province ID {0}' -f $provinceId)
		}) | Out-Null
	}
}

$missingProvinceTitleRows = New-Object System.Collections.Generic.List[object]
foreach ($entry in $definitionMap.GetEnumerator()) {
	$id = [int]$entry.Key
	$name = [string]$entry.Value.Name
	if ($id -le 0) {
		continue
	}
	if ([string]::IsNullOrWhiteSpace($name)) {
		continue
	}
	if ($nonLand.Contains($id)) {
		continue
	}
	if (-not $provinceToTitles.ContainsKey([string]$id)) {
		$missingProvinceTitleRows.Add([pscustomobject]@{
			province_id = $id
			province_name = $name
		}) | Out-Null
	}
}

foreach ($row in $missingProvinceTitleRows) {
	$findings.Add([pscustomobject]@{
		category = 'missing_province_title'
		severity = 'error'
		key = [string]$row.province_id
		message = ('Playable province has no associated landed title: {0}' -f [string]$row.province_name)
	}) | Out-Null
}

$findingsPath = Join-Path $generatedRoot 'east_mapping_validation_findings.csv'
$missingProvinceTitlesPath = Join-Path $generatedRoot 'east_mapping_missing_province_titles.csv'
$summaryPath = Join-Path $generatedRoot 'east_mapping_validation_summary.md'

$findings | Export-Csv -Path $findingsPath -NoTypeInformation -Encoding UTF8
$missingProvinceTitleRows | Export-Csv -Path $missingProvinceTitlesPath -NoTypeInformation -Encoding UTF8

$errorCount = @($findings | Where-Object { $_.severity -eq 'error' }).Count
$warningCount = @($findings | Where-Object { $_.severity -eq 'warning' }).Count

$summaryLines = @(
	'# East Mapping Validation Summary',
	'',
	('- province master rows: {0}' -f $provinceRows.Count),
	('- title master rows: {0}' -f $titleRows.Count),
	('- title inventory rows: {0}' -f $titleInventoryRows.Count),
	('- rewrite candidate rows: {0}' -f $rewriteCandidateRows.Count),
	('- landed_titles live/test hash match: {0}' -f $(if ($landedHash -eq $testLandedHash) { 'yes' } else { 'no' })),
	('- missing playable province titles: {0}' -f $missingProvinceTitleRows.Count),
	('- validation errors: {0}' -f $errorCount),
	('- validation warnings: {0}' -f $warningCount)
)

Write-TextUtf8 -Path $summaryPath -Text (($summaryLines -join "`r`n") + "`r`n")
