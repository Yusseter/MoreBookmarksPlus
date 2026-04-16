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
			if ($line -match '^\s*([A-Za-z0-9_@:\.\-\?]+)\s*=\s*\{') {
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

function Get-NumericHistoryBlocksFromDirectory {
	param([Parameter(Mandatory = $true)][string]$DirectoryPath)

	$map = @{}
	$files = Get-ChildItem -Path $DirectoryPath -Filter '*.txt' | Sort-Object Name
	foreach ($file in $files) {
		$text = Read-TextUtf8 -Path $file.FullName
		$blocks = Get-TopLevelBlocks -Text $text
		foreach ($block in $blocks) {
			if ($block.Name -match '^\d+$' -and -not $map.ContainsKey($block.Name)) {
				$map[$block.Name] = [pscustomobject]@{
					Id = [string]$block.Name
					File = $file.Name
					Text = [string]$block.Text
				}
			}
		}
	}
	return $map
}

function Rewrite-ProvinceBlockId {
	param(
		[Parameter(Mandatory = $true)][string]$BlockText,
		[Parameter(Mandatory = $true)][string]$TargetId
	)

	$lines = Split-Lines -Text $BlockText
	if ($lines.Length -eq 0) {
		return $BlockText
	}

	$lines[0] = [regex]::Replace($lines[0], '^\s*\d+\s*=', ('{0} =' -f $TargetId), 1)
	return ($lines -join "`r`n")
}

function Apply-ReplacementsToHistoryText {
	param(
		[Parameter(Mandatory = $true)][string]$OriginalText,
		[Parameter(Mandatory = $true)]$ReplacementById
	)

	$lines = Split-Lines -Text $OriginalText
	$blocks = Get-TopLevelBlocks -Text $OriginalText
	$blockByStart = @{}
	foreach ($block in $blocks) {
		$blockByStart[[int]$block.StartIndex] = $block
	}

	$used = New-Object System.Collections.Generic.HashSet[string]
	$outputLines = New-Object System.Collections.Generic.List[string]
	$i = 0
	while ($i -lt $lines.Length) {
		if ($blockByStart.ContainsKey($i)) {
			$block = $blockByStart[$i]
			if ($block.Name -match '^\d+$' -and $ReplacementById.ContainsKey($block.Name)) {
				foreach ($replacementLine in (Split-Lines -Text $ReplacementById[$block.Name])) {
					$outputLines.Add([string]$replacementLine) | Out-Null
				}
				[void]$used.Add([string]$block.Name)
			}
			else {
				foreach ($existingLine in $lines[$block.StartIndex..$block.EndIndex]) {
					$outputLines.Add([string]$existingLine) | Out-Null
				}
			}
			$i = [int]$block.EndIndex + 1
			continue
		}

		$outputLines.Add([string]$lines[$i]) | Out-Null
		$i++
	}

	$remainingIds = @($ReplacementById.Keys | Where-Object { -not $used.Contains([string]$_) } | Sort-Object {[int]$_})
	if ($remainingIds.Count -gt 0) {
		while ($outputLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($outputLines[$outputLines.Count - 1])) {
			$outputLines.RemoveAt($outputLines.Count - 1)
		}
		$outputLines.Add('') | Out-Null
		$outputLines.Add('# -----------------------------------------------------------------------------') | Out-Null
		$outputLines.Add('# Province relation exact history appends') | Out-Null
		$outputLines.Add('# -----------------------------------------------------------------------------') | Out-Null
		$outputLines.Add('') | Out-Null
		foreach ($id in $remainingIds) {
			foreach ($replacementLine in (Split-Lines -Text $ReplacementById[$id])) {
				$outputLines.Add([string]$replacementLine) | Out-Null
			}
			$outputLines.Add('') | Out-Null
		}
	}

	return (($outputLines -join "`r`n").TrimEnd() + "`r`n")
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$generatedRoot = Join-Path $repoRoot 'works\analysis\generated\province_relation_mapping'
$masterPath = Join-Path $repoRoot 'works\map_data_sources\province_relation_master.csv'
$reportPath = Join-Path $generatedRoot 'province_relation_history_apply_report.csv'
$summaryPath = Join-Path $generatedRoot 'province_relation_history_apply_summary.md'
$sourceHistoryDir = 'C:\Program Files (x86)\Steam\steamapps\workshop\content\1158310\2216670956\0backup\history\provinces'
$targetPaths = @(
	(Join-Path $repoRoot 'history\provinces\00_MB_PROVINCES.txt'),
	(Join-Path $repoRoot 'test_files\history\provinces\00_MB_PROVINCES.txt')
)

New-Item -ItemType Directory -Path $generatedRoot -Force | Out-Null

$masterRows = @(
	Read-CsvUtf8 -Path $masterPath | Where-Object {
		$_.classification -eq 'exact' -and $_.status -eq 'mapped' -and $_.apply_to_history -eq 'yes'
	}
)

$sourceBlocksById = Get-NumericHistoryBlocksFromDirectory -DirectoryPath $sourceHistoryDir
$replacementById = @{}
$reportRows = New-Object System.Collections.Generic.List[object]

foreach ($row in $masterRows) {
	$sourceId = [string]$row.source_province_id
	$targetId = [string]$row.target_province_id
	if (-not $sourceBlocksById.ContainsKey($sourceId)) {
		$reportRows.Add([pscustomobject]@{
			target_path = ''
			source_province_id = $sourceId
			target_province_id = $targetId
			source_file = ''
			status = 'missing_source_block'
			message = 'No source history block found in backup history/provinces.'
		}) | Out-Null
		continue
	}

	$replacementById[$targetId] = Rewrite-ProvinceBlockId -BlockText ([string]$sourceBlocksById[$sourceId].Text) -TargetId $targetId
}

foreach ($targetPath in $targetPaths) {
	if (-not (Test-Path -LiteralPath $targetPath)) {
		$reportRows.Add([pscustomobject]@{
			target_path = $targetPath
			source_province_id = ''
			target_province_id = ''
			source_file = ''
			status = 'missing_target_file'
			message = 'Target history file does not exist.'
		}) | Out-Null
		continue
	}

	$originalText = Read-TextUtf8 -Path $targetPath
	$updatedText = Apply-ReplacementsToHistoryText -OriginalText $originalText -ReplacementById $replacementById
	Write-TextUtf8 -Path $targetPath -Text $updatedText

	foreach ($row in $masterRows) {
		$sourceId = [string]$row.source_province_id
		$targetId = [string]$row.target_province_id
		$reportRows.Add([pscustomobject]@{
			target_path = $targetPath
			source_province_id = $sourceId
			target_province_id = $targetId
			source_file = if ($sourceBlocksById.ContainsKey($sourceId)) { [string]$sourceBlocksById[$sourceId].File } else { '' }
			status = if ($sourceBlocksById.ContainsKey($sourceId)) { 'applied' } else { 'missing_source_block' }
			message = if ($sourceBlocksById.ContainsKey($sourceId)) { 'Exact source history block applied to target province ID.' } else { 'No source history block found.' }
		}) | Out-Null
	}
}

Export-CsvUtf8 -Rows $reportRows -Path $reportPath

$appliedCount = @($reportRows | Where-Object { $_.status -eq 'applied' }).Count
$missingSourceCount = @($reportRows | Where-Object { $_.status -eq 'missing_source_block' }).Count
$missingTargetCount = @($reportRows | Where-Object { $_.status -eq 'missing_target_file' }).Count

$summaryLines = @(
	'# Province Relation History Apply Summary',
	'',
	('- exact rows requested: `{0}`' -f $masterRows.Count),
	('- applied rows: `{0}`' -f $appliedCount),
	('- missing source blocks: `{0}`' -f $missingSourceCount),
	('- missing target files: `{0}`' -f $missingTargetCount),
	'',
	('Report: `{0}`' -f $reportPath)
)

Write-TextUtf8 -Path $summaryPath -Text (($summaryLines -join "`r`n") + "`r`n")
