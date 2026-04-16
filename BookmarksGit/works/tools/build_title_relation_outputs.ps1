param(
	[switch]$Apply
)

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

function Strip-QuotedStrings {
	param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

	return [regex]::Replace($Text, '"[^"]*"', '""')
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

function Get-TitleTokenMatches {
	param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

	return [regex]::Matches($Text, "(?<![A-Za-z0-9_\/\.\-'])([ehkdcb]_[A-Za-z0-9_\/\.\-']+)(?![A-Za-z0-9_\/\.\-'])")
}

function Validate-MasterRows {
	param([Parameter(Mandatory = $true)]$Rows)

	$requiredColumns = @(
		'source_title_id',
		'source_tier',
		'canonical_title_id',
		'canonical_tier',
		'canonical_namespace',
		'relation_type',
		'rewrite_allowed',
		'source_root_title',
		'notes',
		'status'
	)

	if ($Rows.Count -eq 0) {
		throw 'title_relation_master.csv is empty.'
	}

	$columns = @($Rows[0].PSObject.Properties.Name)
	foreach ($column in $requiredColumns) {
		if ($columns -notcontains $column) {
			throw "title_relation_master.csv missing required column: $column"
		}
	}
}

function Get-ScanTargets {
	param([Parameter(Mandatory = $true)][string]$RepoRoot)

	$targets = @(
		@{ Category = 'history/titles'; Path = Join-Path $RepoRoot 'history\titles'; Filter = '*.txt' },
		@{ Category = 'history/provinces'; Path = Join-Path $RepoRoot 'history\provinces'; Filter = '*.txt' },
		@{ Category = 'map_data/geographical_regions'; Path = Join-Path $RepoRoot 'map_data\geographical_regions'; Filter = '*.txt' },
		@{ Category = 'common/scripted_effects'; Path = Join-Path $RepoRoot 'common\scripted_effects'; Filter = '*.txt' },
		@{ Category = 'common/on_action'; Path = Join-Path $RepoRoot 'common\on_action'; Filter = '*.txt' },
		@{ Category = 'common/scripted_triggers'; Path = Join-Path $RepoRoot 'common\scripted_triggers'; Filter = '*.txt' },
		@{ Category = 'common/script_values'; Path = Join-Path $RepoRoot 'common\script_values'; Filter = '*.txt' },
		@{ Category = 'events'; Path = Join-Path $RepoRoot 'events'; Filter = '*.txt' }
	)

	return @($targets | Where-Object { Test-Path -LiteralPath $_.Path })
}

function Build-RewriteText {
	param(
		[Parameter(Mandatory = $true)][string]$Text,
		[Parameter(Mandatory = $true)]$Mappings
	)

	$result = $Text
	foreach ($mapping in @($Mappings | Sort-Object @{ Expression = { $_.source_title_id.Length }; Descending = $true }, @{ Expression = { $_.source_title_id }; Descending = $false })) {
		$pattern = "(?<![A-Za-z0-9_\/\.\-'])" + [regex]::Escape([string]$mapping.source_title_id) + "(?![A-Za-z0-9_\/\.\-'])"
		$result = [regex]::Replace($result, $pattern, [string]$mapping.canonical_title_id)
	}
	return $result
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$generatedRoot = Join-Path $repoRoot 'Works\analysis\generated\title_relation_mapping'
$masterPath = Join-Path $repoRoot 'Works\map_data_sources\title_relation_master.csv'
$inventoryPath = Join-Path $generatedRoot 'title_relation_source_inventory.csv'
$safeMapPath = Join-Path $generatedRoot 'title_relation_safe_rewrite_map.csv'
$manualReviewPath = Join-Path $generatedRoot 'title_relation_manual_review.csv'
$coveragePath = Join-Path $generatedRoot 'title_relation_coverage.csv'
$referenceHitsPath = Join-Path $generatedRoot 'title_relation_reference_hits.csv'
$rewriteCandidatesPath = Join-Path $generatedRoot 'title_relation_rewrite_candidates.csv'
$applyReportPath = Join-Path $generatedRoot 'title_relation_apply_report.csv'
$summaryPath = Join-Path $generatedRoot 'title_relation_outputs_summary.md'
New-Item -ItemType Directory -Path $generatedRoot -Force | Out-Null

$masterRows = @(Read-CsvUtf8 -Path $masterPath)
$inventoryRows = @(Read-CsvUtf8 -Path $inventoryPath)
Validate-MasterRows -Rows $masterRows

$masterBySource = @{}
foreach ($row in $masterRows) {
	$masterBySource[[string]$row.source_title_id] = $row
}

$coverageRows = New-Object System.Collections.Generic.List[object]
foreach ($inventoryRow in $inventoryRows) {
	$masterRow = $null
	if ($masterBySource.ContainsKey([string]$inventoryRow.source_title_id)) {
		$masterRow = $masterBySource[[string]$inventoryRow.source_title_id]
	}

	$coverageRows.Add([pscustomobject]@{
		source_title_id = [string]$inventoryRow.source_title_id
		source_tier = [string]$inventoryRow.source_tier
		cluster_key = [string]$inventoryRow.cluster_key
		source_root_title = [string]$inventoryRow.source_root_title
		in_master = if ($null -ne $masterRow) { 'yes' } else { 'no' }
		status = if ($null -ne $masterRow) { Normalize-Status -Value ([string]$masterRow.status) } else { '' }
		relation_type = if ($null -ne $masterRow) { [string]$masterRow.relation_type } else { '' }
		rewrite_allowed = if ($null -ne $masterRow) { Normalize-YesNo -Value ([string]$masterRow.rewrite_allowed) } else { '' }
		canonical_namespace = if ($null -ne $masterRow) { [string]$masterRow.canonical_namespace } else { '' }
		canonical_title_id = if ($null -ne $masterRow) { [string]$masterRow.canonical_title_id } else { '' }
	}) | Out-Null
}

$missingInMasterRows = @($coverageRows | Where-Object { $_.in_master -ne 'yes' })

$safeRewriteRows = @(
	$masterRows | Where-Object {
		(Normalize-Status -Value ([string]$_.status)) -eq 'mapped' -and
		(Normalize-YesNo -Value ([string]$_.rewrite_allowed)) -eq 'yes' -and
		(@('exact', 'contextual') -contains ([string]$_.relation_type)) -and
		-not [string]::IsNullOrWhiteSpace([string]$_.canonical_title_id) -and
		([string]$_.source_title_id -ne [string]$_.canonical_title_id)
	}
)

$manualReviewRows = @(
	$masterRows | Where-Object {
		(Normalize-Status -Value ([string]$_.status)) -eq 'manual_review'
	} | Sort-Object source_root_title, source_tier, source_title_path
)

Export-CsvUtf8 -Rows $safeRewriteRows -Path $safeMapPath
Export-CsvUtf8 -Rows $manualReviewRows -Path $manualReviewPath
Export-CsvUtf8 -Rows $coverageRows -Path $coveragePath

$scanTargets = @(Get-ScanTargets -RepoRoot $repoRoot)
$safeRewriteBySource = @{}
foreach ($row in $safeRewriteRows) {
	$safeRewriteBySource[[string]$row.source_title_id] = $row
}

$allTrackedBySource = @{}
foreach ($row in $masterRows) {
	$allTrackedBySource[[string]$row.source_title_id] = $row
}

$referenceHits = New-Object System.Collections.Generic.List[object]
$rewriteCandidateHits = New-Object System.Collections.Generic.List[object]
$applyRows = New-Object System.Collections.Generic.List[object]

foreach ($target in $scanTargets) {
	$files = Get-ChildItem -Path $target.Path -Recurse -File -Filter $target.Filter | Sort-Object FullName
	foreach ($file in $files) {
		$fileHitCounts = @{}
		$fileLineHits = @{}
		$text = Read-TextUtf8 -Path $file.FullName
		$lineNumber = 0

		foreach ($line in (Split-Lines -Text $text)) {
			$lineNumber++
			$visible = Strip-QuotedStrings -Text (Strip-LineComment -Line $line)
			foreach ($match in (Get-TitleTokenMatches -Text $visible)) {
				$titleId = [string]$match.Groups[1].Value
				if (-not $allTrackedBySource.ContainsKey($titleId)) {
					continue
				}
				if (-not $fileHitCounts.ContainsKey($titleId)) {
					$fileHitCounts[$titleId] = 0
					$fileLineHits[$titleId] = New-Object System.Collections.Generic.List[string]
				}
				$fileHitCounts[$titleId] = [int]$fileHitCounts[$titleId] + 1
				if ($fileLineHits[$titleId].Count -lt 20) {
					$fileLineHits[$titleId].Add([string]$lineNumber) | Out-Null
				}
			}
		}

		foreach ($titleId in ($fileHitCounts.Keys | Sort-Object)) {
			$row = $allTrackedBySource[$titleId]
			$hitRow = [pscustomobject]@{
				category = [string]$target.Category
				file_path = [string]$file.FullName.Substring($repoRoot.Length).TrimStart('\')
				source_title_id = [string]$row.source_title_id
				canonical_title_id = [string]$row.canonical_title_id
				canonical_namespace = [string]$row.canonical_namespace
				status = Normalize-Status -Value ([string]$row.status)
				relation_type = [string]$row.relation_type
				rewrite_allowed = Normalize-YesNo -Value ([string]$row.rewrite_allowed)
				occurrence_count = [int]$fileHitCounts[$titleId]
				line_numbers = ($fileLineHits[$titleId] -join '|')
			}
			$referenceHits.Add($hitRow) | Out-Null

			if ($safeRewriteBySource.ContainsKey($titleId)) {
				$rewriteCandidateHits.Add($hitRow) | Out-Null
			}
		}
	}
}

Export-CsvUtf8 -Rows $referenceHits -Path $referenceHitsPath
Export-CsvUtf8 -Rows $rewriteCandidateHits -Path $rewriteCandidatesPath

if ($Apply) {
	$hitsByFile = @{}
	foreach ($hit in $rewriteCandidateHits) {
		$key = [string]$hit.file_path
		if (-not $hitsByFile.ContainsKey($key)) {
			$hitsByFile[$key] = New-Object System.Collections.Generic.List[object]
		}
		$hitsByFile[$key].Add($safeRewriteBySource[[string]$hit.source_title_id]) | Out-Null
	}

	foreach ($filePathKey in ($hitsByFile.Keys | Sort-Object)) {
		$absolutePath = Join-Path $repoRoot $filePathKey
		$originalText = Read-TextUtf8 -Path $absolutePath
		$rewrittenText = Build-RewriteText -Text $originalText -Mappings $hitsByFile[$filePathKey]
		if ($rewrittenText -ne $originalText) {
			Write-TextUtf8 -Path $absolutePath -Text $rewrittenText
			$applyRows.Add([pscustomobject]@{
				file_path = $filePathKey
				rewrite_count = @($hitsByFile[$filePathKey]).Count
				status = 'rewritten'
			}) | Out-Null
		}
		else {
			$applyRows.Add([pscustomobject]@{
				file_path = $filePathKey
				rewrite_count = @($hitsByFile[$filePathKey]).Count
				status = 'no_change'
			}) | Out-Null
		}
	}
}

Export-CsvUtf8 -Rows $applyRows -Path $applyReportPath

$summaryLines = @(
	'# Title Relation Outputs Summary',
	'',
	('- master rows: {0}' -f $masterRows.Count),
	('- inventory rows: {0}' -f $inventoryRows.Count),
	('- missing inventory rows in master: {0}' -f $missingInMasterRows.Count),
	('- safe rewrite rows: {0}' -f $safeRewriteRows.Count),
	('- manual review rows: {0}' -f $manualReviewRows.Count),
	('- reference hits: {0}' -f $referenceHits.Count),
	('- rewrite candidate hits: {0}' -f $rewriteCandidateHits.Count),
	('- apply mode: {0}' -f $(if ($Apply) { 'yes' } else { 'no' }))
)

Write-TextUtf8 -Path $summaryPath -Text (($summaryLines -join "`r`n") + "`r`n")
