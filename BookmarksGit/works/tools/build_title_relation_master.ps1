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
		$nameLookup[[string]$name] = $true
	}

	$lines = Split-Lines -Text $Text
	$output = New-Object System.Collections.Generic.List[string]
	$skipping = $false
	$depth = 0

	for ($i = 0; $i -lt $lines.Length; $i++) {
		$line = $lines[$i]
		if (-not $skipping) {
			if ($line -match '^\s*([A-Za-z0-9_@:\.\-\?\/'']+)\s*=\s*\{') {
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

function Get-TitleTier {
	param([Parameter(Mandatory = $true)][string]$TitleId)

	if ($TitleId -match '^[ehkdcb]_') {
		return $TitleId.Substring(0, 1)
	}
	return ''
}

function Get-TierRank {
	param([Parameter(Mandatory = $true)][string]$Tier)

	switch ($Tier) {
		'e' { return 1 }
		'h' { return 1 }
		'k' { return 2 }
		'd' { return 3 }
		'c' { return 4 }
		'b' { return 5 }
		default { return 9 }
	}
}

function New-IntSet {
	return New-Object 'System.Collections.Generic.HashSet[int]'
}

function New-StringSet {
	return New-Object 'System.Collections.Generic.HashSet[string]'
}

function Test-IntSetEqual {
	param(
		[Parameter(Mandatory = $true)]$Left,
		[Parameter(Mandatory = $true)]$Right
	)

	if ($Left.Count -ne $Right.Count) {
		return $false
	}

	foreach ($value in $Left) {
		if (-not $Right.Contains([int]$value)) {
			return $false
		}
	}
	return $true
}

function Get-IntSetIntersectionCount {
	param(
		[Parameter(Mandatory = $true)]$Left,
		[Parameter(Mandatory = $true)]$Right
	)

	$count = 0
	foreach ($value in $Left) {
		if ($Right.Contains([int]$value)) {
			$count++
		}
	}
	return $count
}

function Format-Ratio {
	param([double]$Value)
	return ('{0:N6}' -f $Value)
}

function Parse-TitleTree {
	param(
		[Parameter(Mandatory = $true)][string]$Text,
		[AllowEmptyString()][string]$SourceRootTitle,
		[Parameter(Mandatory = $true)][string]$SourceFileLabel,
		$ProvinceIdMap = $null
	)

	$nodes = @{}
	$stack = New-Object System.Collections.Generic.List[object]
	$braceDepth = 0
	$lineNumber = 0

	foreach ($rawLine in (Split-Lines -Text $Text)) {
		$lineNumber++
		$visible = Strip-LineComment -Line $rawLine

		if ($visible -match '^\s*([ehkdcb]_[A-Za-z0-9_\/\.\-'']+)\s*=\s*\{') {
			$titleId = [string]$matches[1]
			$tier = Get-TitleTier -TitleId $titleId
			$parentTitle = ''
			$path = $titleId
			$rootTitle = if (-not [string]::IsNullOrWhiteSpace($SourceRootTitle)) { $SourceRootTitle } else { $titleId }
			if ($stack.Count -gt 0) {
				$parentTitle = [string]$stack[$stack.Count - 1].title_id
				$path = [string]$stack[$stack.Count - 1].path + ' > ' + $titleId
				$rootTitle = [string]$stack[0].root_title
			}

			$node = [pscustomobject]@{
				title_id = $titleId
				tier = $tier
				parent_title = $parentTitle
				root_title = $rootTitle
				path = $path
				depth = $stack.Count
				line_number = $lineNumber
				source_file = $SourceFileLabel
				direct_province_ids = (New-IntSet)
				descendant_province_ids = (New-IntSet)
			}

			$nodes[$titleId] = $node
			$stack.Add($node) | Out-Null
		}

		if ($visible -match '^\s*province\s*=\s*(\d+)\s*$') {
			$provinceId = [int]$matches[1]
			if ($null -ne $ProvinceIdMap) {
				if (-not $ProvinceIdMap.ContainsKey($provinceId)) {
					continue
				}
				$provinceId = [int]$ProvinceIdMap[$provinceId]
			}
			for ($stackIndex = $stack.Count - 1; $stackIndex -ge 0; $stackIndex--) {
				if ([string]$stack[$stackIndex].tier -eq 'b') {
					[void]$stack[$stackIndex].direct_province_ids.Add($provinceId)
					break
				}
			}
		}

		$braceDepth += Get-BraceDelta -Line $rawLine
		while ($stack.Count -gt 0 -and [int]$stack[$stack.Count - 1].depth -ge $braceDepth) {
			$stack.RemoveAt($stack.Count - 1)
		}
	}

	$orderedNodes = @($nodes.Values | Sort-Object @{ Expression = { $_.depth }; Descending = $true }, @{ Expression = { $_.line_number }; Descending = $true })
	foreach ($node in $orderedNodes) {
		foreach ($provinceId in $node.direct_province_ids) {
			[void]$node.descendant_province_ids.Add([int]$provinceId)
		}
		if (-not [string]::IsNullOrWhiteSpace($node.parent_title) -and $nodes.ContainsKey([string]$node.parent_title)) {
			foreach ($provinceId in $node.descendant_province_ids) {
				[void]$nodes[[string]$node.parent_title].descendant_province_ids.Add([int]$provinceId)
			}
		}
	}

	return $nodes
}

function Add-TitleIndexEntries {
	param(
		[Parameter(Mandatory = $true)]$NodesById,
		[Parameter(Mandatory = $true)]$ProvinceTierIndex
	)

	foreach ($node in $NodesById.Values) {
		foreach ($provinceId in $node.descendant_province_ids) {
			$key = '{0}|{1}' -f [string]$node.tier, [int]$provinceId
			if (-not $ProvinceTierIndex.ContainsKey($key)) {
				$ProvinceTierIndex[$key] = New-Object System.Collections.Generic.List[string]
			}
			$ProvinceTierIndex[$key].Add([string]$node.title_id) | Out-Null
		}
	}
}

function Get-ScoreSignature {
	param([Parameter(Mandatory = $true)]$Score)
	return ('{0}|{1}|{2}|{3}' -f [int][bool]$Score.set_equal, [int]$Score.overlap_count, (Format-Ratio -Value ([double]$Score.source_coverage)), (Format-Ratio -Value ([double]$Score.candidate_coverage)))
}

function Resolve-CanonicalMapping {
	param(
		[Parameter(Mandatory = $true)]$SourceNode,
		[Parameter(Mandatory = $true)]$ModNodesById,
		[Parameter(Mandatory = $true)]$ProvinceTierIndex
	)

	$sourceProvinceCount = [int]$SourceNode.descendant_province_ids.Count

	if ($ModNodesById.ContainsKey([string]$SourceNode.title_id)) {
		$liveNode = $ModNodesById[[string]$SourceNode.title_id]
		return [pscustomobject]@{
			mod_title_id = [string]$liveNode.title_id
			mod_tier = [string]$liveNode.tier
			relation_type = 'exact'
			rewrite_allowed = 'yes'
			status = 'mapped'
			notes = 'auto: same_title_id'
			auto_candidate_title_id = [string]$liveNode.title_id
			auto_candidate_tier = [string]$liveNode.tier
			auto_match_method = 'same_title_id'
			auto_source_province_count = $sourceProvinceCount
			auto_candidate_province_count = [int]$liveNode.descendant_province_ids.Count
			auto_overlap_count = $sourceProvinceCount
			auto_source_coverage = if ($sourceProvinceCount -gt 0) { '1.000000' } else { '' }
			auto_candidate_coverage = if ($sourceProvinceCount -gt 0) { '1.000000' } else { '' }
		}
	}

	$candidateIds = New-StringSet
	foreach ($provinceId in $SourceNode.descendant_province_ids) {
		$key = '{0}|{1}' -f [string]$SourceNode.tier, [int]$provinceId
		if ($ProvinceTierIndex.ContainsKey($key)) {
			foreach ($candidateId in $ProvinceTierIndex[$key]) {
				$liveNode = $ModNodesById[[string]$candidateId]
				if ([string]$liveNode.root_title -eq [string]$SourceNode.root_title) {
					[void]$candidateIds.Add([string]$candidateId)
				}
			}
		}
	}

	$scoredCandidates = New-Object System.Collections.Generic.List[object]
	foreach ($candidateId in $candidateIds) {
		$liveNode = $ModNodesById[[string]$candidateId]
		$overlapCount = Get-IntSetIntersectionCount -Left $SourceNode.descendant_province_ids -Right $liveNode.descendant_province_ids
		if ($overlapCount -le 0) {
			continue
		}

		$candidateProvinceCount = [int]$liveNode.descendant_province_ids.Count
		$sourceCoverage = if ($sourceProvinceCount -gt 0) { [double]$overlapCount / [double]$sourceProvinceCount } else { 0.0 }
		$candidateCoverage = if ($candidateProvinceCount -gt 0) { [double]$overlapCount / [double]$candidateProvinceCount } else { 0.0 }

		$scoredCandidates.Add([pscustomobject]@{
			title_id = [string]$liveNode.title_id
			tier = [string]$liveNode.tier
			overlap_count = $overlapCount
			source_coverage = $sourceCoverage
			candidate_coverage = $candidateCoverage
			candidate_province_count = $candidateProvinceCount
			set_equal = if ($sourceProvinceCount -gt 0) { (Test-IntSetEqual -Left $SourceNode.descendant_province_ids -Right $liveNode.descendant_province_ids) } else { $false }
		}) | Out-Null
	}

	if ($scoredCandidates.Count -eq 0) {
		return [pscustomobject]@{
			mod_title_id = ''
			mod_tier = ''
			relation_type = ''
			rewrite_allowed = 'no'
			status = 'manual_review'
			notes = 'auto: no_live_candidate'
			auto_candidate_title_id = ''
			auto_candidate_tier = ''
			auto_match_method = ''
			auto_source_province_count = $sourceProvinceCount
			auto_candidate_province_count = ''
			auto_overlap_count = ''
			auto_source_coverage = ''
			auto_candidate_coverage = ''
		}
	}

	$orderedCandidates = @(
		$scoredCandidates | Sort-Object `
			@{ Expression = { [int][bool]$_.set_equal }; Descending = $true }, `
			@{ Expression = { [double]$_.source_coverage }; Descending = $true }, `
			@{ Expression = { [double]$_.candidate_coverage }; Descending = $true }, `
			@{ Expression = { [int]$_.overlap_count }; Descending = $true }, `
			@{ Expression = { [string]$_.title_id }; Descending = $false }
	)

	$bestCandidate = $orderedCandidates[0]
	$hasUniqueBest = $orderedCandidates.Count -eq 1 -or (Get-ScoreSignature -Score $orderedCandidates[0]) -ne (Get-ScoreSignature -Score $orderedCandidates[1])
	$canMapContextual = $false
	$matchMethod = ''

	if ($hasUniqueBest) {
		if ([string]$SourceNode.tier -eq 'b' -and $sourceProvinceCount -eq 1 -and [int]$bestCandidate.overlap_count -eq 1) {
			$canMapContextual = $true
			$matchMethod = 'unique_barony_province'
		}
		elseif ($bestCandidate.set_equal) {
			$canMapContextual = $true
			$matchMethod = 'exact_descendant_province_set'
		}
	}

	if ($canMapContextual) {
		return [pscustomobject]@{
			mod_title_id = [string]$bestCandidate.title_id
			mod_tier = [string]$bestCandidate.tier
			relation_type = 'contextual'
			rewrite_allowed = 'yes'
			status = 'mapped'
			notes = ('auto: {0}' -f $matchMethod)
			auto_candidate_title_id = [string]$bestCandidate.title_id
			auto_candidate_tier = [string]$bestCandidate.tier
			auto_match_method = $matchMethod
			auto_source_province_count = $sourceProvinceCount
			auto_candidate_province_count = [int]$bestCandidate.candidate_province_count
			auto_overlap_count = [int]$bestCandidate.overlap_count
			auto_source_coverage = (Format-Ratio -Value ([double]$bestCandidate.source_coverage))
			auto_candidate_coverage = (Format-Ratio -Value ([double]$bestCandidate.candidate_coverage))
		}
	}

	return [pscustomobject]@{
		mod_title_id = ''
		mod_tier = ''
		relation_type = ''
		rewrite_allowed = 'no'
		status = 'manual_review'
		notes = 'auto: review_best_candidate'
		auto_candidate_title_id = [string]$bestCandidate.title_id
		auto_candidate_tier = [string]$bestCandidate.tier
		auto_match_method = if ($hasUniqueBest) { 'review_unique_candidate' } else { 'review_tied_candidates' }
		auto_source_province_count = $sourceProvinceCount
		auto_candidate_province_count = [int]$bestCandidate.candidate_province_count
		auto_overlap_count = [int]$bestCandidate.overlap_count
		auto_source_coverage = (Format-Ratio -Value ([double]$bestCandidate.source_coverage))
		auto_candidate_coverage = (Format-Ratio -Value ([double]$bestCandidate.candidate_coverage))
	}
}

function Merge-EditableValue {
	param(
		[AllowEmptyString()][string]$ExistingValue,
		[AllowEmptyString()][string]$AutoValue
	)

	if (-not [string]::IsNullOrWhiteSpace($ExistingValue)) {
		return [string]$ExistingValue
	}
	return [string]$AutoValue
}

function Normalize-YesNo {
	param([AllowEmptyString()][string]$Value)

	$normalized = ([string]$Value).Trim().ToLowerInvariant()
	switch ($normalized) {
		'yes' { return 'yes' }
		'no' { return 'no' }
		default { return $normalized }
	}
}

function Normalize-Status {
	param([AllowEmptyString()][string]$Value)

	$normalized = ([string]$Value).Trim().ToLowerInvariant()
	switch ($normalized) {
		'mapped' { return 'mapped' }
		'manual_review' { return 'manual_review' }
		default { return $normalized }
	}
}

function Get-PathTitleByPrefix {
	param(
		[Parameter(Mandatory = $true)]$Node,
		[Parameter(Mandatory = $true)][string]$Prefix
	)

	foreach ($part in ([string]$Node.path -split ' > ')) {
		if (([string]$part).StartsWith($Prefix)) {
			return [string]$part
		}
	}
	return ''
}

function Get-NormalizedTitleStem {
	param([AllowEmptyString()][string]$TitleId)

	$value = ([string]$TitleId).ToLowerInvariant()
	$value = $value -replace '^[ehkdcb]_', ''
	$value = $value -replace '''', ''
	$value = $value -replace '^(goryeo_|liao_|fic_|eman_|cirqf_|cirlzj_|sw_)', ''
	$value = $value -replace '_(qin|song|yuan|ming|tang|han|jin|sui)_china$', ''
	$value = $value -replace '_china$', ''
	$value = $value -replace '_\d+$', ''
	return $value
}

function Get-ClusterKeyForNode {
	param([Parameter(Mandatory = $true)]$Node)

	$parts = New-Object System.Collections.Generic.List[string]
	$parts.Add([string]$Node.root_title) | Out-Null

	$kingdom = Get-PathTitleByPrefix -Node $Node -Prefix 'k_'
	if (-not [string]::IsNullOrWhiteSpace($kingdom)) {
		$parts.Add($kingdom) | Out-Null
	}

	$duchy = Get-PathTitleByPrefix -Node $Node -Prefix 'd_'
	if (-not [string]::IsNullOrWhiteSpace($duchy)) {
		$parts.Add($duchy) | Out-Null
	}

	return ($parts -join ' > ')
}

function Get-TitleCandidateSignature {
	param([Parameter(Mandatory = $true)]$Candidate)

	return ('{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}' -f `
		[int][bool]$Candidate.same_title_id, `
		[int][bool]$Candidate.set_equal, `
		[int][bool]$Candidate.same_stem, `
		(Format-Ratio -Value ([double]$Candidate.source_coverage)), `
		(Format-Ratio -Value ([double]$Candidate.candidate_coverage)), `
		[int][bool]$Candidate.same_county, `
		[int][bool]$Candidate.same_duchy, `
		[int][bool]$Candidate.same_kingdom)
}

function Add-NormalizedCandidateIndexEntries {
	param(
		[Parameter(Mandatory = $true)]$NodesById,
		[Parameter(Mandatory = $true)]$Index
	)

	foreach ($node in $NodesById.Values) {
		$key = '{0}|{1}' -f [string]$node.tier, (Get-NormalizedTitleStem -TitleId ([string]$node.title_id))
		if (-not $Index.ContainsKey($key)) {
			$Index[$key] = New-Object System.Collections.Generic.List[string]
		}
		$Index[$key].Add([string]$node.title_id) | Out-Null
	}
}

function Get-ExpectedSourceProvinceIds {
	param(
		[Parameter(Mandatory = $true)]$SourceNode,
		[Parameter(Mandatory = $true)]$FinalToSourceExactMap
	)

	$result = New-IntSet
	foreach ($finalProvinceId in $SourceNode.descendant_province_ids) {
		$key = [string]$finalProvinceId
		if ($FinalToSourceExactMap.ContainsKey($key)) {
			[void]$result.Add([int]$FinalToSourceExactMap[$key])
		}
	}
	return ,$result
}

function Get-ExpectedOverlapCount {
	param(
		[Parameter(Mandatory = $true)]$Left,
		[Parameter(Mandatory = $true)]$Right
	)

	$count = 0
	foreach ($value in $Left) {
		if ($Right.Contains([int]$value)) {
			$count++
		}
	}
	return $count
}

function Test-ExpectedSetEqual {
	param(
		[Parameter(Mandatory = $true)]$Left,
		[Parameter(Mandatory = $true)]$Right
	)

	$leftCount = 0
	foreach ($value in $Left) {
		$leftCount++
		if (-not $Right.Contains([int]$value)) {
			return $false
		}
	}

	return ($leftCount -eq [int]$Right.Count)
}

function Resolve-CanonicalMappingV2 {
	param(
		[Parameter(Mandatory = $true)]$SourceNode,
		[Parameter(Mandatory = $true)]$ModNodesById,
		[Parameter(Mandatory = $true)]$LiveNodesById,
		[Parameter(Mandatory = $true)]$NormalizedCandidateIndex,
		[Parameter(Mandatory = $true)]$FinalToSourceExactMap
	)

	try {
		$sourceProvinceCount = [int]$SourceNode.descendant_province_ids.Count
		$expectedSourceProvinceIds = Get-ExpectedSourceProvinceIds -SourceNode $SourceNode -FinalToSourceExactMap $FinalToSourceExactMap
		$expectedSourceCount = [int]$expectedSourceProvinceIds.Count
		$sourceStem = Get-NormalizedTitleStem -TitleId ([string]$SourceNode.title_id)
		$sourceKingdomStem = Get-NormalizedTitleStem -TitleId (Get-PathTitleByPrefix -Node $SourceNode -Prefix 'k_')
		$sourceDuchyStem = Get-NormalizedTitleStem -TitleId (Get-PathTitleByPrefix -Node $SourceNode -Prefix 'd_')
		$sourceCountyStem = Get-NormalizedTitleStem -TitleId (Get-PathTitleByPrefix -Node $SourceNode -Prefix 'c_')

		$candidateIds = New-StringSet
		if ($ModNodesById.ContainsKey([string]$SourceNode.title_id)) {
			[void]$candidateIds.Add([string]$SourceNode.title_id)
		}

		$normalizedKey = '{0}|{1}' -f [string]$SourceNode.tier, $sourceStem
		if ($NormalizedCandidateIndex.ContainsKey($normalizedKey)) {
			foreach ($candidateId in $NormalizedCandidateIndex[$normalizedKey]) {
				[void]$candidateIds.Add([string]$candidateId)
			}
		}

		$scoredCandidates = New-Object System.Collections.Generic.List[object]
		foreach ($candidateId in $candidateIds) {
			try {
				$candidateNode = $ModNodesById[[string]$candidateId]
				$candidateProvinceCount = [int]$candidateNode.descendant_province_ids.Count
				$overlapCount = if ($expectedSourceCount -gt 0) {
					Get-ExpectedOverlapCount -Left $expectedSourceProvinceIds -Right $candidateNode.descendant_province_ids
				}
				else {
					0
				}

				$scoredCandidates.Add([pscustomobject]@{
					title_id = [string]$candidateNode.title_id
					tier = [string]$candidateNode.tier
					same_title_id = ([string]$candidateNode.title_id -eq [string]$SourceNode.title_id)
					same_stem = ((Get-NormalizedTitleStem -TitleId ([string]$candidateNode.title_id)) -eq $sourceStem)
					same_kingdom = ((Get-NormalizedTitleStem -TitleId (Get-PathTitleByPrefix -Node $candidateNode -Prefix 'k_')) -eq $sourceKingdomStem)
					same_duchy = ((Get-NormalizedTitleStem -TitleId (Get-PathTitleByPrefix -Node $candidateNode -Prefix 'd_')) -eq $sourceDuchyStem)
					same_county = ((Get-NormalizedTitleStem -TitleId (Get-PathTitleByPrefix -Node $candidateNode -Prefix 'c_')) -eq $sourceCountyStem)
					overlap_count = $overlapCount
					source_coverage = if ($expectedSourceCount -gt 0) { [double]$overlapCount / [double]$expectedSourceCount } else { 0.0 }
					candidate_coverage = if ($candidateProvinceCount -gt 0) { [double]$overlapCount / [double]$candidateProvinceCount } else { 0.0 }
					set_equal = if ($expectedSourceCount -gt 0) { (Test-ExpectedSetEqual -Left $expectedSourceProvinceIds -Right $candidateNode.descendant_province_ids) } else { $false }
					candidate_province_count = $candidateProvinceCount
				}) | Out-Null
			}
			catch {
				throw ("Resolve-CanonicalMappingV2 failed for source {0} candidate {1}: {2}" -f [string]$SourceNode.title_id, [string]$candidateId, $_.Exception.Message)
			}
		}

		$orderedCandidates = @(
			$scoredCandidates.ToArray() | Sort-Object `
				@{ Expression = { [int][bool]$_.same_title_id }; Descending = $true }, `
				@{ Expression = { [int][bool]$_.set_equal }; Descending = $true }, `
				@{ Expression = { [int][bool]$_.same_stem }; Descending = $true }, `
				@{ Expression = { [double]$_.source_coverage }; Descending = $true }, `
				@{ Expression = { [double]$_.candidate_coverage }; Descending = $true }, `
				@{ Expression = { [int][bool]$_.same_county }; Descending = $true }, `
				@{ Expression = { [int][bool]$_.same_duchy }; Descending = $true }, `
				@{ Expression = { [int][bool]$_.same_kingdom }; Descending = $true }, `
				@{ Expression = { [string]$_.title_id }; Descending = $false }
		)

		$liveSameTitleExists = $LiveNodesById.ContainsKey([string]$SourceNode.title_id)

		if ($orderedCandidates.Count -gt 0) {
			$bestCandidate = $orderedCandidates[0]
			$hasUniqueBest = $orderedCandidates.Count -eq 1 -or (Get-TitleCandidateSignature -Candidate $orderedCandidates[0]) -ne (Get-TitleCandidateSignature -Candidate $orderedCandidates[1])

			if ([bool]$bestCandidate.same_title_id -and [bool]$bestCandidate.set_equal) {
				return [pscustomobject]@{
					canonical_title_id = [string]$bestCandidate.title_id
					canonical_tier = [string]$bestCandidate.tier
					canonical_namespace = 'mod'
					relation_type = 'exact'
					rewrite_allowed = 'yes'
					status = 'mapped'
					notes = 'auto: mod_exact_same_title_id_province_set'
					auto_candidate_title_id = [string]$bestCandidate.title_id
					auto_candidate_tier = [string]$bestCandidate.tier
					auto_match_method = 'mod_exact_same_title_id_province_set'
					auto_source_province_count = $sourceProvinceCount
					auto_expected_source_province_count = $expectedSourceCount
					auto_candidate_province_count = [int]$bestCandidate.candidate_province_count
					auto_overlap_count = [int]$bestCandidate.overlap_count
					auto_source_coverage = (Format-Ratio -Value ([double]$bestCandidate.source_coverage))
					auto_candidate_coverage = (Format-Ratio -Value ([double]$bestCandidate.candidate_coverage))
				}
			}

			if (
				$hasUniqueBest -and
				[bool]$bestCandidate.same_stem -and
				(
					[bool]$bestCandidate.same_county -or
					[bool]$bestCandidate.same_duchy -or
					[bool]$bestCandidate.same_kingdom -or
					(
						[string]$SourceNode.tier -eq 'b' -and
						[int]$bestCandidate.candidate_province_count -eq 1
					)
				) -and
				($expectedSourceCount -eq 0 -or [double]$bestCandidate.source_coverage -ge 0.50 -or [double]$bestCandidate.candidate_coverage -ge 0.50)
			) {
				return [pscustomobject]@{
					canonical_title_id = [string]$bestCandidate.title_id
					canonical_tier = [string]$bestCandidate.tier
					canonical_namespace = 'mod'
					relation_type = 'contextual'
					rewrite_allowed = 'yes'
					status = 'mapped'
					notes = 'auto: mod_context_name_family_context'
					auto_candidate_title_id = [string]$bestCandidate.title_id
					auto_candidate_tier = [string]$bestCandidate.tier
					auto_match_method = 'mod_context_name_family_context'
					auto_source_province_count = $sourceProvinceCount
					auto_expected_source_province_count = $expectedSourceCount
					auto_candidate_province_count = [int]$bestCandidate.candidate_province_count
					auto_overlap_count = [int]$bestCandidate.overlap_count
					auto_source_coverage = (Format-Ratio -Value ([double]$bestCandidate.source_coverage))
					auto_candidate_coverage = (Format-Ratio -Value ([double]$bestCandidate.candidate_coverage))
				}
			}

			if ($liveSameTitleExists) {
				return [pscustomobject]@{
					canonical_title_id = [string]$SourceNode.title_id
					canonical_tier = [string]$SourceNode.tier
					canonical_namespace = 'vanilla'
					relation_type = 'exact'
					rewrite_allowed = 'yes'
					status = 'mapped'
					notes = 'auto: vanilla_same_title_id'
					auto_candidate_title_id = [string]$bestCandidate.title_id
					auto_candidate_tier = [string]$bestCandidate.tier
					auto_match_method = 'vanilla_same_title_id'
					auto_source_province_count = $sourceProvinceCount
					auto_expected_source_province_count = $expectedSourceCount
					auto_candidate_province_count = [int]$bestCandidate.candidate_province_count
					auto_overlap_count = [int]$bestCandidate.overlap_count
					auto_source_coverage = (Format-Ratio -Value ([double]$bestCandidate.source_coverage))
					auto_candidate_coverage = (Format-Ratio -Value ([double]$bestCandidate.candidate_coverage))
				}
			}

			return [pscustomobject]@{
				canonical_title_id = [string]$bestCandidate.title_id
				canonical_tier = [string]$bestCandidate.tier
				canonical_namespace = ''
				relation_type = 'manual_review'
				rewrite_allowed = 'no'
				status = 'manual_review'
				notes = 'auto: review_best_candidate'
				auto_candidate_title_id = [string]$bestCandidate.title_id
				auto_candidate_tier = [string]$bestCandidate.tier
				auto_match_method = if ($hasUniqueBest) { 'review_unique_candidate' } else { 'review_tied_candidates' }
				auto_source_province_count = $sourceProvinceCount
				auto_expected_source_province_count = $expectedSourceCount
				auto_candidate_province_count = [int]$bestCandidate.candidate_province_count
				auto_overlap_count = [int]$bestCandidate.overlap_count
				auto_source_coverage = (Format-Ratio -Value ([double]$bestCandidate.source_coverage))
				auto_candidate_coverage = (Format-Ratio -Value ([double]$bestCandidate.candidate_coverage))
			}
		}

		if ($liveSameTitleExists) {
			return [pscustomobject]@{
				canonical_title_id = [string]$SourceNode.title_id
				canonical_tier = [string]$SourceNode.tier
				canonical_namespace = 'vanilla'
				relation_type = 'exact'
				rewrite_allowed = 'yes'
				status = 'mapped'
				notes = 'auto: vanilla_same_title_id'
				auto_candidate_title_id = ''
				auto_candidate_tier = ''
				auto_match_method = 'vanilla_same_title_id'
				auto_source_province_count = $sourceProvinceCount
				auto_expected_source_province_count = $expectedSourceCount
				auto_candidate_province_count = ''
				auto_overlap_count = ''
				auto_source_coverage = ''
				auto_candidate_coverage = ''
			}
		}

		return [pscustomobject]@{
			canonical_title_id = ''
			canonical_tier = ''
			canonical_namespace = ''
			relation_type = 'manual_review'
			rewrite_allowed = 'no'
			status = 'manual_review'
			notes = 'auto: no_candidate_after_filters'
			auto_candidate_title_id = ''
			auto_candidate_tier = ''
			auto_match_method = ''
			auto_source_province_count = $sourceProvinceCount
			auto_expected_source_province_count = $expectedSourceCount
			auto_candidate_province_count = ''
			auto_overlap_count = ''
			auto_source_coverage = ''
			auto_candidate_coverage = ''
		}
	}
	catch {
		throw ("Resolve-CanonicalMappingV2 failed for source {0}: {1}" -f [string]$SourceNode.title_id, $_.Exception.Message)
	}
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$generatedRoot = Join-Path $repoRoot 'Works\analysis\generated\title_relation_mapping'
$masterPath = Join-Path $repoRoot 'Works\map_data_sources\title_relation_master.csv'
$inventoryPath = Join-Path $generatedRoot 'title_relation_source_inventory.csv'
$summaryPath = Join-Path $generatedRoot 'title_relation_master_seed_summary.md'
New-Item -ItemType Directory -Path $generatedRoot -Force | Out-Null

$paths = @{
	ModSource = 'C:\Program Files (x86)\Steam\steamapps\workshop\content\1158310\2216670956\0backup\common\landed_titles\00_landed_titles.txt'
	CurrentLive = Join-Path $repoRoot 'common\landed_titles\00_landed_titles.txt'
	FinalModlu = Join-Path $repoRoot 'Works\analysis\generated\final_modlu_tracking_preserve_old_ids.csv'
	FinalOrijinal = Join-Path $repoRoot 'Works\analysis\generated\final_orijinal_tracking_preserve_old_ids.csv'
	ProvinceRelationMaster = Join-Path $repoRoot 'works\map_data_sources\province_relation_master.csv'
	Vanilla00 = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles\00_landed_titles.txt'
	Vanilla01 = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles\01_japan.txt'
	Vanilla02 = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles\02_china.txt'
	Vanilla03 = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles\03_seasia.txt'
	Vanilla05 = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles\05_goryeo.txt'
	Vanilla06 = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles\06_philippines.txt'
}

$managedVanillaSpecs = @(
	@{ Root = 'e_viet'; SourceFile = $paths.Vanilla00 },
	@{ Root = 'h_china'; SourceFile = $paths.Vanilla02; RemoveNestedNames = @('k_xia', 'c_maozhou', 'b_shanglin') },
	@{ Root = 'e_suvarnabhumi'; SourceFile = $paths.Vanilla03 },
	@{ Root = 'e_brunei'; SourceFile = $paths.Vanilla03 },
	@{ Root = 'e_kambuja'; SourceFile = $paths.Vanilla03 },
	@{ Root = 'e_nusantara'; SourceFile = $paths.Vanilla06 },
	@{ Root = 'e_japan'; SourceFile = $paths.Vanilla01 },
	@{ Root = 'k_chrysanthemum_throne'; SourceFile = $paths.Vanilla01 },
	@{ Root = 'e_goryeo'; SourceFile = $paths.Vanilla05 },
	@{ Root = 'k_yongson_throne'; SourceFile = $paths.Vanilla05 },
	@{ Root = 'e_andong'; SourceFile = $paths.Vanilla00 },
	@{ Root = 'e_srivijaya'; SourceFile = $paths.Vanilla00 },
	@{ Root = 'e_amur'; SourceFile = $paths.Vanilla00 }
)

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

$sourceTextByFile = @{}
$sourceNodesByTitle = @{}
$inventoryRows = New-Object System.Collections.Generic.List[object]

foreach ($spec in $managedVanillaSpecs) {
	$sourceFile = [string]$spec.SourceFile
	if (-not $sourceTextByFile.ContainsKey($sourceFile)) {
		if (-not (Test-Path -LiteralPath $sourceFile)) {
			throw "Missing source file: $sourceFile"
		}
		$sourceTextByFile[$sourceFile] = Read-TextUtf8 -Path $sourceFile
	}

	$blockText = Get-NamedBlockText -Text $sourceTextByFile[$sourceFile] -Name ([string]$spec.Root)
	if ([string]::IsNullOrWhiteSpace($blockText)) {
		throw "Failed to locate root $($spec.Root) in $sourceFile"
	}
	if ($spec.ContainsKey('RemoveNestedNames')) {
		$blockText = Remove-NestedBlocksByName -Text $blockText -Names @([string[]]$spec.RemoveNestedNames)
	}

	$parsedNodes = Parse-TitleTree -Text $blockText -SourceRootTitle ([string]$spec.Root) -SourceFileLabel (Split-Path -Leaf $sourceFile) -ProvinceIdMap $orijinalTracking
	foreach ($node in $parsedNodes.Values) {
		$sourceNodesByTitle[[string]$node.title_id] = $node
		$inventoryRows.Add([pscustomobject]@{
			source_title_id = [string]$node.title_id
			source_tier = [string]$node.tier
			cluster_key = Get-ClusterKeyForNode -Node $node
			source_root_title = [string]$node.root_title
			source_kingdom = Get-PathTitleByPrefix -Node $node -Prefix 'k_'
			source_duchy = Get-PathTitleByPrefix -Node $node -Prefix 'd_'
			source_county = Get-PathTitleByPrefix -Node $node -Prefix 'c_'
			source_file = [string]$node.source_file
			source_title_path = [string]$node.path
			source_province_count = [int]$node.descendant_province_ids.Count
		}) | Out-Null
	}
}

$modNodesById = Parse-TitleTree -Text (Read-TextUtf8 -Path $paths.ModSource) -SourceRootTitle '' -SourceFileLabel '00_landed_titles.txt'
$liveNodesById = Parse-TitleTree -Text (Read-TextUtf8 -Path $paths.CurrentLive) -SourceRootTitle '' -SourceFileLabel '00_landed_titles.txt'
$normalizedCandidateIndex = @{}
Add-NormalizedCandidateIndexEntries -NodesById $modNodesById -Index $normalizedCandidateIndex

$finalToSourceExactMap = @{}
foreach ($row in (Read-CsvUtf8 -Path $paths.ProvinceRelationMaster)) {
	if (
		$row.source_province_id -match '^\d+$' -and
		$row.target_province_id -match '^\d+$' -and
		([string]$row.classification).Trim().ToLowerInvariant() -eq 'exact' -and
		([string]$row.status).Trim().ToLowerInvariant() -eq 'mapped'
	) {
		$finalToSourceExactMap[[string]$row.target_province_id] = [int]$row.source_province_id
	}
}

$existingRows = @(Read-CsvUtf8 -Path $masterPath)
$existingBySource = @{}
foreach ($row in $existingRows) {
	$key = if ($row.PSObject.Properties.Name -contains 'source_title_id') { [string]$row.source_title_id } else { [string]$row.vanilla_title_id }
	$existingBySource[$key] = $row
}

$masterRows = New-Object System.Collections.Generic.List[object]
$sortedSourceNodes = @($sourceNodesByTitle.Values | Sort-Object @{ Expression = { [string]$_.root_title }; Descending = $false }, @{ Expression = { Get-TierRank -Tier ([string]$_.tier) }; Descending = $false }, @{ Expression = { [string]$_.path }; Descending = $false })

foreach ($sourceNode in $sortedSourceNodes) {
	$autoRow = Resolve-CanonicalMappingV2 -SourceNode $sourceNode -ModNodesById $modNodesById -LiveNodesById $liveNodesById -NormalizedCandidateIndex $normalizedCandidateIndex -FinalToSourceExactMap $finalToSourceExactMap
	$existingRow = $null
	if ($existingBySource.ContainsKey([string]$sourceNode.title_id)) {
		$existingRow = $existingBySource[[string]$sourceNode.title_id]
	}
	$preserveExisting = $null -ne $existingRow -and -not ([string]$existingRow.notes).Trim().StartsWith('auto:')

	$canonicalTitleId = Merge-EditableValue -ExistingValue $(if ($preserveExisting) { [string]$(if ($existingRow.PSObject.Properties.Name -contains 'canonical_title_id') { $existingRow.canonical_title_id } else { $existingRow.mod_title_id }) } else { '' }) -AutoValue ([string]$autoRow.canonical_title_id)
	$canonicalTier = Merge-EditableValue -ExistingValue $(if ($preserveExisting) { [string]$(if ($existingRow.PSObject.Properties.Name -contains 'canonical_tier') { $existingRow.canonical_tier } else { $existingRow.mod_tier }) } else { '' }) -AutoValue ([string]$autoRow.canonical_tier)
	$canonicalNamespace = Merge-EditableValue -ExistingValue $(if ($preserveExisting) { [string]$(if ($existingRow.PSObject.Properties.Name -contains 'canonical_namespace') { $existingRow.canonical_namespace } else { '' }) } else { '' }) -AutoValue ([string]$autoRow.canonical_namespace)
	$relationType = Merge-EditableValue -ExistingValue $(if ($preserveExisting) { [string]$existingRow.relation_type } else { '' }) -AutoValue ([string]$autoRow.relation_type)
	$rewriteAllowed = Normalize-YesNo -Value (Merge-EditableValue -ExistingValue $(if ($preserveExisting) { [string]$existingRow.rewrite_allowed } else { '' }) -AutoValue ([string]$autoRow.rewrite_allowed))
	$status = Normalize-Status -Value (Merge-EditableValue -ExistingValue $(if ($preserveExisting) { [string]$existingRow.status } else { '' }) -AutoValue ([string]$autoRow.status))
	$notes = Merge-EditableValue -ExistingValue $(if ($preserveExisting) { [string]$existingRow.notes } else { '' }) -AutoValue ([string]$autoRow.notes)

	$masterRows.Add([pscustomobject]@{
		source_title_id = [string]$sourceNode.title_id
		source_tier = [string]$sourceNode.tier
		canonical_title_id = [string]$canonicalTitleId
		canonical_tier = [string]$canonicalTier
		canonical_namespace = [string]$canonicalNamespace
		cluster_key = Get-ClusterKeyForNode -Node $sourceNode
		relation_type = [string]$relationType
		rewrite_allowed = [string]$rewriteAllowed
		source_root_title = [string]$sourceNode.root_title
		source_kingdom = Get-PathTitleByPrefix -Node $sourceNode -Prefix 'k_'
		source_duchy = Get-PathTitleByPrefix -Node $sourceNode -Prefix 'd_'
		source_county = Get-PathTitleByPrefix -Node $sourceNode -Prefix 'c_'
		source_file = [string]$sourceNode.source_file
		source_title_path = [string]$sourceNode.path
		status = [string]$status
		notes = [string]$notes
		auto_candidate_title_id = [string]$autoRow.auto_candidate_title_id
		auto_candidate_tier = [string]$autoRow.auto_candidate_tier
		auto_match_method = [string]$autoRow.auto_match_method
		auto_source_province_count = [string]$autoRow.auto_source_province_count
		auto_expected_source_province_count = [string]$autoRow.auto_expected_source_province_count
		auto_candidate_province_count = [string]$autoRow.auto_candidate_province_count
		auto_overlap_count = [string]$autoRow.auto_overlap_count
		auto_source_coverage = [string]$autoRow.auto_source_coverage
		auto_candidate_coverage = [string]$autoRow.auto_candidate_coverage
	}) | Out-Null
}

Export-CsvUtf8 -Rows $masterRows -Path $masterPath
Export-CsvUtf8 -Rows $inventoryRows -Path $inventoryPath

$mappedCount = @($masterRows | Where-Object { $_.status -eq 'mapped' }).Count
$manualReviewCount = @($masterRows | Where-Object { $_.status -eq 'manual_review' }).Count
$identityCount = @($masterRows | Where-Object { $_.status -eq 'mapped' -and $_.source_title_id -eq $_.canonical_title_id }).Count
$contextualCount = @($masterRows | Where-Object { $_.relation_type -eq 'contextual' }).Count
$exactCount = @($masterRows | Where-Object { $_.relation_type -eq 'exact' }).Count
$modCanonicalCount = @($masterRows | Where-Object { $_.canonical_namespace -eq 'mod' }).Count
$vanillaCanonicalCount = @($masterRows | Where-Object { $_.canonical_namespace -eq 'vanilla' }).Count

$summaryLines = @(
	'# Title Relation Master Seed Summary',
	'',
	('- master path: `{0}`' -f $masterPath),
	('- inventory path: `{0}`' -f $inventoryPath),
	(''),
	('## Counts'),
	(''),
	('- source titles inventoried: {0}' -f $inventoryRows.Count),
	('- mapped rows: {0}' -f $mappedCount),
	('- manual review rows: {0}' -f $manualReviewCount),
	('- exact rows: {0}' -f $exactCount),
	('- contextual rows: {0}' -f $contextualCount),
	('- identity mappings: {0}' -f $identityCount),
	('- mod canonical rows: {0}' -f $modCanonicalCount),
	('- vanilla canonical rows: {0}' -f $vanillaCanonicalCount)
)

Write-TextUtf8 -Path $summaryPath -Text (($summaryLines -join "`r`n") + "`r`n")
