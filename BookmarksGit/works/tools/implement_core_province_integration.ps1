$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script:GitPrefix = (((& git rev-parse --show-prefix) 2>$null) | Out-String).Trim()

function Get-Utf8NoBomEncoding {
	return New-Object System.Text.UTF8Encoding($false)
}

function Read-TextUtf8 {
	param(
		[Parameter(Mandatory = $true)][string]$Path
	)

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

	$encoding = Get-Utf8NoBomEncoding
	[System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Read-HeadOrWorkingText {
	param(
		[Parameter(Mandatory = $true)][string]$RelativePath,
		[Parameter(Mandatory = $true)][string]$WorkingPath
	)

	$gitRelativePath = (($script:GitPrefix + ($RelativePath -replace '\\', '/')) -replace '//', '/')
	$psi = New-Object System.Diagnostics.ProcessStartInfo
	$psi.FileName = 'git'
	$psi.Arguments = ('show HEAD:{0}' -f $gitRelativePath)
	$psi.WorkingDirectory = (Get-Location).Path
	$psi.UseShellExecute = $false
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true
	$psi.CreateNoWindow = $true

	$process = New-Object System.Diagnostics.Process
	$process.StartInfo = $psi
	[void]$process.Start()
	$memory = New-Object System.IO.MemoryStream
	$process.StandardOutput.BaseStream.CopyTo($memory)
	$stderr = $process.StandardError.ReadToEnd()
	$process.WaitForExit()

	if ($process.ExitCode -eq 0) {
		$encoding = Get-Utf8NoBomEncoding
		$text = $encoding.GetString($memory.ToArray())
		if ($text.Length -gt 0 -and [int][char]$text[0] -eq 0xFEFF) {
			return $text.Substring(1)
		}
		return $text
	}

	return Read-TextUtf8 -Path $WorkingPath
}

function Read-CsvUtf8 {
	param(
		[Parameter(Mandatory = $true)][string]$Path
	)

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
	param(
		[Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
	)
	return [System.Text.RegularExpressions.Regex]::Split($Text, "`r?`n")
}

function Strip-LineComment {
	param(
		[Parameter(Mandatory = $true)][AllowEmptyString()][string]$Line
	)

	$index = $Line.IndexOf('#')
	if ($index -lt 0) {
		return $Line
	}
	return $Line.Substring(0, $index)
}

function Get-BraceDelta {
	param(
		[Parameter(Mandatory = $true)][AllowEmptyString()][string]$Line
	)

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
					})
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
				})
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
			for ($i = [int]$block.StartIndex; $i -le [int]$block.EndIndex; $i++) {
				$skipLine[$i] = $true
			}
		}
	}

	$outputLines = New-Object System.Collections.Generic.List[string]
	for ($i = 0; $i -lt $lines.Length; $i++) {
		if (-not $skipLine.ContainsKey($i)) {
			$outputLines.Add($lines[$i])
		}
	}

	while ($outputLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($outputLines[$outputLines.Count - 1])) {
		$outputLines.RemoveAt($outputLines.Count - 1)
	}

	if ($AppendBlocks.Count -gt 0) {
		$outputLines.Add('')
		$outputLines.Add('# -----------------------------------------------------------------------------')
		$outputLines.Add("# $MarkerComment")
		$outputLines.Add('# -----------------------------------------------------------------------------')
		$outputLines.Add('')

		for ($i = 0; $i -lt $AppendBlocks.Count; $i++) {
			foreach ($appendLine in (Split-Lines -Text $AppendBlocks[$i])) {
				$outputLines.Add([string]$appendLine)
			}
			if ($i -lt ($AppendBlocks.Count - 1)) {
				$outputLines.Add('')
			}
		}
	}

	return (($outputLines -join "`r`n").TrimEnd() + "`r`n")
}

function Get-NumericHistoryBlocksFromDirectory {
	param(
		[Parameter(Mandatory = $true)][string]$DirectoryPath
	)

	$map = @{}
	$duplicateRows = New-Object System.Collections.Generic.List[object]
	$files = Get-ChildItem -Path $DirectoryPath -Filter '*.txt' | Sort-Object Name
	foreach ($file in $files) {
		$text = Read-TextUtf8 -Path $file.FullName
		$blocks = Get-TopLevelBlocks -Text $text
		foreach ($block in $blocks) {
			if ($block.Name -match '^\d+$') {
				if ($map.ContainsKey($block.Name)) {
					$duplicateRows.Add([pscustomobject]@{
						id = $block.Name
						existing_file = $map[$block.Name].File
						duplicate_file = $file.Name
					})
				}
				else {
					$map[$block.Name] = [pscustomobject]@{
						Id = [int]$block.Name
						File = $file.Name
						Text = $block.Text
					}
				}
			}
		}
	}

	return [pscustomobject]@{
		Map = $map
		Duplicates = $duplicateRows
	}
}

function Get-BaronyProvinceMapFromText {
	param(
		[Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
	)

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
				$baronyName = $matches[1]
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
			$output.Add($line)
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
		[Parameter(Mandatory = $true)]$VanillaOldToFinal,
		[Parameter(Mandatory = $true)]$ModBaronyProvinceMap,
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
				$baronyName = $matches[1]
				$depth = Get-BraceDelta -Line $line
			}
			$output.Add($line)
			if ($inBarony -and $depth -le 0) {
				$inBarony = $false
				$baronyName = ''
			}
		}
		else {
			if ($line -match '^(\s*province\s*=\s*)(\d+)(\s*(#.*)?)$') {
				$oldId = [int]$matches[2]
				if ($VanillaOldToFinal.ContainsKey($oldId)) {
					$newId = $VanillaOldToFinal[$oldId]
					$ReportRows.Add([pscustomobject]@{
						root = $Root
						barony = $baronyName
						old_vanilla_id = $oldId
						final_new_id = $newId
						status = 'rewritten'
					})
					$line = $matches[1] + $newId + $matches[3]
				}
				elseif ($ModBaronyProvinceMap.ContainsKey($baronyName)) {
					$newId = $ModBaronyProvinceMap[$baronyName]
					$ReportRows.Add([pscustomobject]@{
						root = $Root
						barony = $baronyName
						old_vanilla_id = $oldId
						final_new_id = $newId
						status = 'fallback_mod_barony'
					})
					$line = $matches[1] + $newId + $matches[3]
				}
				else {
					$ReportRows.Add([pscustomobject]@{
						root = $Root
						barony = $baronyName
						old_vanilla_id = $oldId
						final_new_id = ''
						status = 'missing_mapping_barony_removed'
					})
					if (-not $missingBaronies.Contains($baronyName)) {
						$missingBaronies.Add($baronyName)
					}
				}
			}

			$output.Add($line)
			$depth += Get-BraceDelta -Line $line
			if ($depth -eq 0) {
				$inBarony = $false
				$baronyName = ''
			}
		}
	}

	$rewritten = ($output -join "`r`n")
	if ($missingBaronies.Count -gt 0) {
		return Remove-NestedBlocksByName -Text $rewritten -Names $missingBaronies.ToArray()
	}
	return $rewritten
}

function Rewrite-ProvinceHistoryBlockId {
	param(
		[Parameter(Mandatory = $true)][string]$BlockText,
		[Parameter(Mandatory = $true)][int]$NewId
	)

	$lines = Split-Lines -Text $BlockText
	if ($lines.Length -eq 0) {
		return $BlockText
	}
	if ($lines[0] -match '^(\s*)\d+(\s*=\s*\{.*)$') {
		$lines[0] = $matches[1] + $NewId + $matches[2]
	}
	return ($lines -join "`r`n")
}

function Parse-LocatorText {
	param(
		[Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
		[string]$SourceLabel = '<text>'
	)

	$lines = Split-Lines -Text $text

	$instancesLine = -1
	for ($i = 0; $i -lt $lines.Length; $i++) {
		if ($lines[$i] -match '^\s*instances\s*=\s*\{') {
			$instancesLine = $i
			break
		}
	}
	if ($instancesLine -lt 0) {
		throw "instances block not found in $SourceLabel"
	}

	$headerLines = New-Object System.Collections.Generic.List[string]
	foreach ($headerLine in $lines[0..$instancesLine]) {
		$headerLines.Add([string]$headerLine)
	}

	$instanceRows = New-Object System.Collections.Generic.List[object]
	$footerLines = $null
	$depth = 0
	$inBlock = $false
	$blockStart = -1

	for ($i = $instancesLine + 1; $i -lt $lines.Length; $i++) {
		$line = $lines[$i]
		if (-not $inBlock) {
			if ($line -match '^\s*\{\s*$') {
				$inBlock = $true
				$blockStart = $i
				$depth = Get-BraceDelta -Line $line
			}
			elseif ($line -match '^\s*\}\s*$') {
				$footerLines = $lines[$i..($lines.Length - 1)]
				break
			}
		}
		else {
			$depth += Get-BraceDelta -Line $line
			if ($depth -eq 0) {
				$blockText = ($lines[$blockStart..$i] -join "`r`n")
				if ($blockText -notmatch '(?m)^\s*id\s*=\s*(-?\d+)') {
					$inBlock = $false
					$blockStart = -1
					continue
				}
				$instanceRows.Add([pscustomobject]@{
					Id = [int]$matches[1]
					Text = $blockText
				})
				$inBlock = $false
				$blockStart = -1
			}
		}
	}

	if ($null -eq $footerLines) {
		throw "Failed to find locator footer in $SourceLabel"
	}

	return [pscustomobject]@{
		HeaderLines = $headerLines
		FooterLines = $footerLines
		Instances = $instanceRows
	}
}

function Parse-LocatorFile {
	param(
		[Parameter(Mandatory = $true)][string]$Path
	)

	$text = Read-TextUtf8 -Path $Path
	return Parse-LocatorText -Text $text -SourceLabel $Path
}

function Rewrite-LocatorBlockId {
	param(
		[Parameter(Mandatory = $true)][string]$BlockText,
		[Parameter(Mandatory = $true)][int]$NewId
	)

	$lines = Split-Lines -Text $BlockText
	for ($i = 0; $i -lt $lines.Length; $i++) {
		if ($lines[$i] -match '^(\s*id\s*=\s*)-?\d+(\s*(#.*)?)$') {
			$lines[$i] = $matches[1] + $NewId + $matches[2]
			break
		}
	}
	return ($lines -join "`r`n")
}

function Group-LocatorInstancesById {
	param(
		[Parameter(Mandatory = $true)]$Instances
	)

	$grouped = @{}
	foreach ($instance in $Instances) {
		$key = [string]$instance.Id
		if (-not $grouped.ContainsKey($key)) {
			$grouped[$key] = New-Object System.Collections.Generic.List[string]
		}
		$grouped[$key].Add($instance.Text)
	}
	return $grouped
}

function Normalize-InstanceText {
	param(
		[Parameter(Mandatory = $true)][string]$Text
	)
	return (($Text -replace '\s+', ' ').Trim())
}

function Build-LocatorText {
	param(
		[Parameter(Mandatory = $true)]$HeaderLines,
		[Parameter(Mandatory = $true)]$FooterLines,
		[Parameter(Mandatory = $true)][string[]]$InstanceBlocks
	)

	$output = New-Object System.Collections.Generic.List[string]
	foreach ($headerLine in $HeaderLines) {
		$output.Add([string]$headerLine)
	}
	foreach ($block in $InstanceBlocks) {
		foreach ($instanceLine in (Split-Lines -Text $block)) {
			$output.Add([string]$instanceLine)
		}
	}
	foreach ($footerLine in $FooterLines) {
		$output.Add([string]$footerLine)
	}
	return (($output -join "`r`n").TrimEnd() + "`r`n")
}

$repoRoot = (Get-Location).Path
$worksRoot = Join-Path $repoRoot 'Works'
$generatedRoot = Join-Path $worksRoot 'analysis\generated\core_province_integration'
if (-not (Test-Path -LiteralPath $generatedRoot)) {
	New-Item -ItemType Directory -Path $generatedRoot -Force | Out-Null
}

$paths = @{
	FinalMaster = Join-Path $worksRoot 'analysis\generated\final_master_preserve_old_ids.csv'
	FinalModlu = Join-Path $worksRoot 'analysis\generated\final_modlu_tracking_preserve_old_ids.csv'
	FinalOrijinal = Join-Path $worksRoot 'analysis\generated\final_orijinal_tracking_preserve_old_ids.csv'
	ModHistoryDir = Join-Path $repoRoot 'history\provinces'
	VanillaHistoryDir = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\history\provinces'
	ModLandedTitles = Join-Path $repoRoot 'common\landed_titles\00_landed_titles.txt'
	VanillaCommonBase = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\common\landed_titles'
	ModHistoryTitlesDir = Join-Path $repoRoot 'history\titles'
	VanillaHistoryTitlesDir = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\history\titles'
	ModAdjacencies = Join-Path $repoRoot 'map_data\adjacencies.csv'
	VanillaAdjacencies = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\map_data\adjacencies.csv'
	IslandRegion = Join-Path $repoRoot 'map_data\island_region.txt'
	VanillaIslandRegion = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\map_data\island_region.txt'
	MapObjectDir = Join-Path $repoRoot 'gfx\map\map_object_data'
	VanillaMapObjectDir = 'C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game\gfx\map\map_object_data'
	GeneratedOracleDir = 'C:\Users\bsgho\Documents\Paradox Interactive\Crusader Kings III\generated'
}

$finalMasterRows = Read-CsvUtf8 -Path $paths.FinalMaster
$modluRows = Read-CsvUtf8 -Path $paths.FinalModlu
$orijinalRows = Read-CsvUtf8 -Path $paths.FinalOrijinal

$finalIdSet = @{}
$finalPreferredSource = @{}
$vanillaOldToFinal = @{}
$modOldToFinal = @{}
$candidateRows = New-Object System.Collections.Generic.List[object]

foreach ($row in $finalMasterRows) {
	$finalId = [int]$row.final_new_id
	$finalIdSet[$finalId] = $true
	$finalPreferredSource[$finalId] = $row.preferred_source_subset
	if ($row.row_type -eq 'candidate') {
		$candidateRows.Add($row)
	}
}

foreach ($row in $orijinalRows) {
	$vanillaOldToFinal[[int]$row.old_id] = [int]$row.final_new_id
}
foreach ($row in $modluRows) {
	$modOldToFinal[[int]$row.old_id] = [int]$row.final_new_id
}

$historyCoverageRows = New-Object System.Collections.Generic.List[object]
$historySourceDataMod = Get-NumericHistoryBlocksFromDirectory -DirectoryPath $paths.ModHistoryDir
$historySourceDataVanilla = Get-NumericHistoryBlocksFromDirectory -DirectoryPath $paths.VanillaHistoryDir

$historyBlocksOutput = New-Object System.Collections.Generic.List[string]
$historyBlocksOutput.Add('# Auto-generated by Works/tools/implement_core_province_integration.ps1')
$historyBlocksOutput.Add('# Core province integration: modlu_kalan from mod, orijinal_dogu from vanilla with final ID rewrite.')
$historyBlocksOutput.Add('')

foreach ($row in ($candidateRows | Sort-Object { [int]$_.final_new_id })) {
	$finalId = [int]$row.final_new_id
	$preferredSubset = $row.preferred_source_subset
	if ($preferredSubset -eq 'modlu_kalan') {
		$sourceId = [int]$row.modlu_old_id
		$lookup = $historySourceDataMod.Map
		$sourceLabel = 'modlu'
	}
	elseif ($preferredSubset -eq 'orijinal_dogu') {
		$sourceId = [int]$row.orijinal_old_id
		$lookup = $historySourceDataVanilla.Map
		$sourceLabel = 'orijinal'
	}
	else {
		continue
	}

	if ($lookup.ContainsKey([string]$sourceId)) {
		$blockText = $lookup[[string]$sourceId].Text
		if ($sourceId -ne $finalId) {
			$blockText = Rewrite-ProvinceHistoryBlockId -BlockText $blockText -NewId $finalId
		}
		$historyBlocksOutput.Add($blockText)
		$historyBlocksOutput.Add('')
		$historyCoverageRows.Add([pscustomobject]@{
			final_new_id = $finalId
			source_subset = $preferredSubset
			source_old_id = $sourceId
			source_file = $lookup[[string]$sourceId].File
			status = 'ok'
		})
	}
	else {
		$historyCoverageRows.Add([pscustomobject]@{
			final_new_id = $finalId
			source_subset = $preferredSubset
			source_old_id = $sourceId
			source_file = ''
			status = 'missing_history_block'
		})
	}
}

$historyOutputPath = Join-Path $paths.ModHistoryDir '00_MB_PROVINCES.txt'
Write-TextUtf8 -Path $historyOutputPath -Text (($historyBlocksOutput -join "`r`n").TrimEnd() + "`r`n")
Export-CsvUtf8 -Rows $historyCoverageRows -Path (Join-Path $generatedRoot 'history_provinces_merge_report.csv')
Export-CsvUtf8 -Rows $historySourceDataMod.Duplicates -Path (Join-Path $generatedRoot 'history_provinces_mod_duplicates.csv')
Export-CsvUtf8 -Rows $historySourceDataVanilla.Duplicates -Path (Join-Path $generatedRoot 'history_provinces_vanilla_duplicates.csv')

$landedReplacementSpecs = @(
	@{ Root = 'e_viet'; File = Join-Path $paths.VanillaCommonBase '00_landed_titles.txt' },
	@{ Root = 'e_tibet'; File = Join-Path $paths.VanillaCommonBase '00_landed_titles.txt' },
	@{ Root = 'h_china'; File = Join-Path $paths.VanillaCommonBase '02_china.txt' },
	@{ Root = 'e_suvarnabhumi'; File = Join-Path $paths.VanillaCommonBase '03_seasia.txt' },
	@{ Root = 'e_brunei'; File = Join-Path $paths.VanillaCommonBase '03_seasia.txt' },
	@{ Root = 'e_kambuja'; File = Join-Path $paths.VanillaCommonBase '03_seasia.txt' },
	@{ Root = 'e_nusantara'; File = Join-Path $paths.VanillaCommonBase '06_philippines.txt' },
	@{ Root = 'e_japan'; File = Join-Path $paths.VanillaCommonBase '01_japan.txt' },
	@{ Root = 'k_chrysanthemum_throne'; File = Join-Path $paths.VanillaCommonBase '01_japan.txt' },
	@{ Root = 'e_goryeo'; File = Join-Path $paths.VanillaCommonBase '05_goryeo.txt' },
	@{ Root = 'k_yongson_throne'; File = Join-Path $paths.VanillaCommonBase '05_goryeo.txt' }
)

$landedBlocksByFile = @{}
foreach ($spec in $landedReplacementSpecs) {
	if (-not $landedBlocksByFile.ContainsKey($spec.File)) {
		$landedBlocksByFile[$spec.File] = Get-TopLevelBlocks -Text (Read-TextUtf8 -Path $spec.File)
	}
}

$landedAppendedBlocks = New-Object System.Collections.Generic.List[string]
$landedProvinceRewriteRows = New-Object System.Collections.Generic.List[object]
$modLandedHeadText = Read-HeadOrWorkingText -RelativePath 'common/landed_titles/00_landed_titles.txt' -WorkingPath $paths.ModLandedTitles
$modBaronyProvinceMap = Get-BaronyProvinceMapFromText -Text $modLandedHeadText

foreach ($spec in $landedReplacementSpecs) {
	$block = $landedBlocksByFile[$spec.File] | Where-Object { $_.Name -eq $spec.Root } | Select-Object -First 1
	if ($null -eq $block) {
		throw "Failed to locate common landed title root $($spec.Root) in $($spec.File)"
	}
	$blockText = $block.Text
	$rewrittenBlock = Rewrite-LandedTitleBlockProvinceIds `
		-BlockText $blockText `
		-Root $spec.Root `
		-VanillaOldToFinal $vanillaOldToFinal `
		-ModBaronyProvinceMap $modBaronyProvinceMap `
		-ReportRows $landedProvinceRewriteRows
	$landedAppendedBlocks.Add($rewrittenBlock)
}

$modLandedOriginal = $modLandedHeadText
$landedRootsToRemove = @(
	'e_viet',
	'e_tibet',
	'h_china',
	'e_goryeo',
	'e_brunei',
	'e_kambuja',
	'e_burma',
	'e_japan',
	'e_nusantara',
	'k_yongson_throne',
	'k_chrysanthemum_throne',
	'e_suvarnabhumi',
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
$modLandedRewritten = Remove-TopLevelBlocksAndAppend `
	-OriginalText $modLandedOriginal `
	-RemoveNames $landedRootsToRemove `
	-AppendBlocks $landedAppendedBlocks `
	-MarkerComment 'Imported vanilla east landed title roots'
Write-TextUtf8 -Path $paths.ModLandedTitles -Text $modLandedRewritten
Export-CsvUtf8 -Rows $landedProvinceRewriteRows -Path (Join-Path $generatedRoot 'landed_titles_vanilla_province_rewrite_report.csv')

$historyTitleSources = @{
	h_china = Join-Path $paths.VanillaHistoryTitlesDir 'e_china.txt'
	e_tibet = Join-Path $paths.VanillaHistoryTitlesDir '00_other_titles.txt'
	e_goryeo = Join-Path $paths.VanillaHistoryTitlesDir 'e_goryeo.txt'
	k_yongson_throne = Join-Path $paths.VanillaHistoryTitlesDir 'e_goryeo.txt'
	e_japan = Join-Path $paths.VanillaHistoryTitlesDir 'e_japan.txt'
	k_chrysanthemum_throne = Join-Path $paths.VanillaHistoryTitlesDir 'e_japan.txt'
	e_kambuja = Join-Path $paths.VanillaHistoryTitlesDir 'e_khmer.txt'
}
$historyTitleTargets = @{
	'00_ASIA_CHINA.txt' = @('h_china')
	'00_OTHER.txt' = @('e_tibet')
	'00_ASIA_NORTH.txt' = @('e_goryeo', 'k_yongson_throne')
	'00_ASIA_JAPAN.txt' = @('e_japan', 'k_chrysanthemum_throne')
	'00_ASIA_SOUTH.txt' = @('e_kambuja')
}

$historyTitleBlocksBySource = @{}
foreach ($root in $historyTitleSources.Keys) {
	$filePath = $historyTitleSources[$root]
	if (-not $historyTitleBlocksBySource.ContainsKey($filePath)) {
		$historyTitleBlocksBySource[$filePath] = Get-TopLevelBlocks -Text (Read-TextUtf8 -Path $filePath)
	}
}

$historyTitleReportRows = New-Object System.Collections.Generic.List[object]
foreach ($targetFileName in $historyTitleTargets.Keys) {
	$targetPath = Join-Path $paths.ModHistoryTitlesDir $targetFileName
	$targetOriginal = Read-HeadOrWorkingText -RelativePath ("history/titles/{0}" -f $targetFileName) -WorkingPath $targetPath
	$roots = $historyTitleTargets[$targetFileName]
	$appendBlocks = New-Object System.Collections.Generic.List[string]

	foreach ($root in $roots) {
		$sourceFile = $historyTitleSources[$root]
		$block = $historyTitleBlocksBySource[$sourceFile] | Where-Object { $_.Name -eq $root } | Select-Object -First 1
		if ($null -eq $block) {
			throw "Failed to locate history title root $root in $sourceFile"
		}
		$appendBlocks.Add($block.Text)
		$historyTitleReportRows.Add([pscustomobject]@{
			target_file = $targetFileName
			root = $root
			source_file = Split-Path -Leaf $sourceFile
			status = 'imported'
		})
	}

	$targetRewritten = Remove-TopLevelBlocksAndAppend `
		-OriginalText $targetOriginal `
		-RemoveNames $roots `
		-AppendBlocks $appendBlocks `
		-MarkerComment 'Imported vanilla east title history roots'
	Write-TextUtf8 -Path $targetPath -Text $targetRewritten
}
Export-CsvUtf8 -Rows $historyTitleReportRows -Path (Join-Path $generatedRoot 'history_titles_merge_report.csv')

$adjacencyRowsOutput = New-Object System.Collections.Generic.List[object]
$adjacencyStaleRows = New-Object System.Collections.Generic.List[object]
$adjacencyInvalidRows = New-Object System.Collections.Generic.List[object]
$adjacencySeen = @{}

function Convert-AdjacencyRow {
	param(
		[Parameter(Mandatory = $true)]$Row,
		[Parameter(Mandatory = $true)][string]$SourceKind
	)

	$result = [ordered]@{
		From = $Row.From
		To = $Row.To
		Type = $Row.Type
		Through = $Row.Through
		start_x = $Row.start_x
		start_y = $Row.start_y
		stop_x = $Row.stop_x
		stop_y = $Row.stop_y
		Comment = $Row.Comment
	}

	$relevantFinalIds = New-Object System.Collections.Generic.List[int]
	$unmapped = New-Object System.Collections.Generic.List[string]

	foreach ($columnName in @('From', 'To', 'Through')) {
		$value = [string]$Row.$columnName
		$parsedId = 0
		if ([int]::TryParse($value, [ref]$parsedId) -and $parsedId -gt 0) {
			if ($SourceKind -eq 'modlu') {
				if ($modOldToFinal.ContainsKey($parsedId)) {
					$mapped = $modOldToFinal[$parsedId]
					$result[$columnName] = [string]$mapped
					$relevantFinalIds.Add($mapped)
				}
				else {
					$unmapped.Add("$columnName=$parsedId")
				}
			}
			else {
				if ($vanillaOldToFinal.ContainsKey($parsedId)) {
					$mapped = $vanillaOldToFinal[$parsedId]
					$result[$columnName] = [string]$mapped
					$relevantFinalIds.Add($mapped)
				}
				else {
					$unmapped.Add("$columnName=$parsedId")
				}
			}
		}
	}

	return [pscustomobject]@{
		Result = [pscustomobject]$result
		RelevantFinalIds = $relevantFinalIds
		Unmapped = $unmapped
	}
}

$modAdjText = Read-HeadOrWorkingText -RelativePath 'map_data/adjacencies.csv' -WorkingPath $paths.ModAdjacencies
$modAdjRows = $modAdjText | ConvertFrom-Csv -Delimiter ';'
$vanillaAdjRows = Import-Csv -Path $paths.VanillaAdjacencies -Delimiter ';'

foreach ($row in $modAdjRows) {
	$converted = Convert-AdjacencyRow -Row $row -SourceKind 'modlu'
	if ($converted.Unmapped.Count -gt 0) {
		$adjacencyStaleRows.Add([pscustomobject]@{
			source = 'modlu'
			comment = $row.Comment
			unmapped = ($converted.Unmapped -join '; ')
			action = 'dropped'
		})
		continue
	}

	$touchesOriginal = $false
	foreach ($finalId in $converted.RelevantFinalIds) {
		if ($finalPreferredSource[$finalId] -eq 'orijinal_dogu') {
			$touchesOriginal = $true
			break
		}
	}
	if ($touchesOriginal) {
		continue
	}

	$key = (($converted.Result.PSObject.Properties | ForEach-Object { $_.Value }) -join ';')
	if (-not $adjacencySeen.ContainsKey($key)) {
		$adjacencySeen[$key] = $true
		$adjacencyRowsOutput.Add($converted.Result)
	}
}

foreach ($row in $vanillaAdjRows) {
	$converted = Convert-AdjacencyRow -Row $row -SourceKind 'orijinal'
	if ($converted.Unmapped.Count -gt 0) {
		$adjacencyStaleRows.Add([pscustomobject]@{
			source = 'orijinal'
			comment = $row.Comment
			unmapped = ($converted.Unmapped -join '; ')
			action = 'dropped'
		})
		continue
	}

	$touchesOriginal = $false
	foreach ($finalId in $converted.RelevantFinalIds) {
		if ($finalPreferredSource[$finalId] -eq 'orijinal_dogu') {
			$touchesOriginal = $true
			break
		}
	}
	if (-not $touchesOriginal) {
		continue
	}

	$key = (($converted.Result.PSObject.Properties | ForEach-Object { $_.Value }) -join ';')
	if (-not $adjacencySeen.ContainsKey($key)) {
		$adjacencySeen[$key] = $true
		$adjacencyRowsOutput.Add($converted.Result)
	}
}

foreach ($row in $adjacencyRowsOutput) {
	foreach ($columnName in @('From', 'To', 'Through')) {
		$value = [string]$row.$columnName
		$parsedId = 0
		if ([int]::TryParse($value, [ref]$parsedId) -and $parsedId -gt 0) {
			if (-not $finalIdSet.ContainsKey($parsedId)) {
				$adjacencyInvalidRows.Add([pscustomobject]@{
					file = 'map_data/adjacencies.csv'
					column = $columnName
					invalid_id = $parsedId
					comment = $row.Comment
				})
			}
		}
	}
}

$adjacencyHeader = 'From;To;Type;Through;start_x;start_y;stop_x;stop_y;Comment'
$adjacencyLines = New-Object System.Collections.Generic.List[string]
$adjacencyLines.Add($adjacencyHeader)
foreach ($row in $adjacencyRowsOutput) {
	$adjacencyLines.Add(('{0};{1};{2};{3};{4};{5};{6};{7};{8}' -f $row.From, $row.To, $row.Type, $row.Through, $row.start_x, $row.start_y, $row.stop_x, $row.stop_y, $row.Comment))
}
Write-TextUtf8 -Path $paths.ModAdjacencies -Text (($adjacencyLines -join "`r`n") + "`r`n")
Export-CsvUtf8 -Rows $adjacencyStaleRows -Path (Join-Path $generatedRoot 'stale_old_vanilla_id_report.csv')
Export-CsvUtf8 -Rows $adjacencyInvalidRows -Path (Join-Path $generatedRoot 'invalid_final_id_report.csv')

$currentIslandText = Read-HeadOrWorkingText -RelativePath 'map_data/island_region.txt' -WorkingPath $paths.IslandRegion
Write-TextUtf8 -Path $paths.IslandRegion -Text $currentIslandText
$islandReportRows = @(
	[pscustomobject]@{
		file = 'map_data/island_region.txt'
		action = 'unchanged'
		reason = 'No provinces = { } numeric entries detected; current file kept as mod-west baseline for core pass.'
	}
)
Export-CsvUtf8 -Rows $islandReportRows -Path (Join-Path $generatedRoot 'island_region_pass_report.csv')

$locatorFiles = @(
	'building_locators.txt',
	'special_building_locators.txt',
	'player_stack_locators.txt',
	'combat_locators.txt',
	'siege_locators.txt',
	'activities.txt'
)

$locatorOracleDiffRows = New-Object System.Collections.Generic.List[object]
$locatorValidationRows = New-Object System.Collections.Generic.List[object]
$locatorMissingRows = New-Object System.Collections.Generic.List[object]

foreach ($locatorFile in $locatorFiles) {
	$modLocatorSourceText = Read-HeadOrWorkingText -RelativePath ("gfx/map/map_object_data/{0}" -f $locatorFile) -WorkingPath (Join-Path $paths.MapObjectDir $locatorFile)
	$modLocator = Parse-LocatorText -Text $modLocatorSourceText -SourceLabel ("HEAD:gfx/map/map_object_data/{0}" -f $locatorFile)
	$vanillaLocator = Parse-LocatorFile -Path (Join-Path $paths.VanillaMapObjectDir $locatorFile)
	$oracleLocator = Parse-LocatorFile -Path (Join-Path $paths.GeneratedOracleDir $locatorFile)

	$modGroups = Group-LocatorInstancesById -Instances $modLocator.Instances
	$vanillaGroups = Group-LocatorInstancesById -Instances $vanillaLocator.Instances
	$oracleGroups = Group-LocatorInstancesById -Instances $oracleLocator.Instances
	$outputBlocks = New-Object System.Collections.Generic.List[string]

	if ($modGroups.ContainsKey('0')) {
		$seenZero = @{}
		foreach ($block in $modGroups['0']) {
			$key = Normalize-InstanceText -Text $block
			if (-not $seenZero.ContainsKey($key)) {
				$seenZero[$key] = $true
				$outputBlocks.Add($block)
			}
		}
		if ($vanillaGroups.ContainsKey('0')) {
			foreach ($block in $vanillaGroups['0']) {
				$key = Normalize-InstanceText -Text $block
				if (-not $seenZero.ContainsKey($key)) {
					$seenZero[$key] = $true
					$outputBlocks.Add($block)
				}
			}
		}
	}

	foreach ($row in ($candidateRows | Sort-Object { [int]$_.final_new_id })) {
		$finalId = [int]$row.final_new_id
		$subset = $row.preferred_source_subset
		if ($subset -eq 'modlu_kalan') {
			$key = [string]$finalId
			if ($modGroups.ContainsKey($key)) {
				foreach ($block in $modGroups[$key]) {
					$outputBlocks.Add($block)
				}
			}
			elseif ($oracleGroups.ContainsKey($key)) {
				foreach ($block in $oracleGroups[$key]) {
					$outputBlocks.Add($block)
				}
				$locatorMissingRows.Add([pscustomobject]@{
					file = $locatorFile
					final_new_id = $finalId
					source_subset = $subset
					source_old_id = $row.modlu_old_id
					status = 'fallback_generated_for_missing_mod'
				})
			}
			else {
				$locatorMissingRows.Add([pscustomobject]@{
					file = $locatorFile
					final_new_id = $finalId
					source_subset = $subset
					source_old_id = $row.modlu_old_id
					status = 'missing_mod_locator'
				})
			}
		}
		elseif ($subset -eq 'orijinal_dogu') {
			$oldId = [int]$row.orijinal_old_id
			$key = [string]$oldId
			if ($vanillaGroups.ContainsKey($key)) {
				foreach ($block in $vanillaGroups[$key]) {
					$outputBlocks.Add((Rewrite-LocatorBlockId -BlockText $block -NewId $finalId))
				}
			}
			elseif ($oracleGroups.ContainsKey([string]$finalId)) {
				foreach ($block in $oracleGroups[[string]$finalId]) {
					$outputBlocks.Add($block)
				}
				$locatorMissingRows.Add([pscustomobject]@{
					file = $locatorFile
					final_new_id = $finalId
					source_subset = $subset
					source_old_id = $oldId
					status = 'fallback_generated_for_missing_vanilla'
				})
			}
			else {
				$locatorMissingRows.Add([pscustomobject]@{
					file = $locatorFile
					final_new_id = $finalId
					source_subset = $subset
					source_old_id = $oldId
					status = 'missing_vanilla_locator'
				})
			}
		}
	}

	$finalText = Build-LocatorText -HeaderLines $modLocator.HeaderLines -FooterLines $modLocator.FooterLines -InstanceBlocks $outputBlocks.ToArray()
	Write-TextUtf8 -Path (Join-Path $paths.MapObjectDir $locatorFile) -Text $finalText

	$writtenLocator = Parse-LocatorFile -Path (Join-Path $paths.MapObjectDir $locatorFile)
	$writtenGroups = Group-LocatorInstancesById -Instances $writtenLocator.Instances

	foreach ($groupKey in $writtenGroups.Keys) {
		$idValue = [int]$groupKey
		if ($idValue -gt 0 -and -not $finalIdSet.ContainsKey($idValue)) {
			$locatorValidationRows.Add([pscustomobject]@{
				file = $locatorFile
				check = 'invalid_final_id'
				id = $idValue
				value = 'present'
			})
		}
		if ($idValue -ne 0 -and $writtenGroups[$groupKey].Count -gt 1) {
			$locatorValidationRows.Add([pscustomobject]@{
				file = $locatorFile
				check = 'duplicate_positive_id'
				id = $idValue
				value = $writtenGroups[$groupKey].Count
			})
		}
	}

	$allKeys = New-Object System.Collections.Generic.HashSet[string]
	foreach ($key in $writtenGroups.Keys) { [void]$allKeys.Add($key) }
	foreach ($key in $oracleGroups.Keys) { [void]$allKeys.Add($key) }
	foreach ($key in $allKeys) {
		$mergedCount = 0
		$oracleCount = 0
		if ($writtenGroups.ContainsKey($key)) { $mergedCount = $writtenGroups[$key].Count }
		if ($oracleGroups.ContainsKey($key)) { $oracleCount = $oracleGroups[$key].Count }
		$mergedNormalized = ''
		$oracleNormalized = ''
		if ($mergedCount -gt 0) {
			$mergedNormalized = (($writtenGroups[$key] | ForEach-Object { Normalize-InstanceText -Text $_ }) -join ' || ')
		}
		if ($oracleCount -gt 0) {
			$oracleNormalized = (($oracleGroups[$key] | ForEach-Object { Normalize-InstanceText -Text $_ }) -join ' || ')
		}
		$status =
			if ($mergedCount -eq 0) { 'oracle_only' }
			elseif ($oracleCount -eq 0) { 'merged_only' }
			elseif ($mergedCount -ne $oracleCount) { 'count_mismatch' }
			elseif ($mergedNormalized -ne $oracleNormalized) { 'text_mismatch' }
			else { 'match' }

		if ($status -ne 'match') {
			$locatorOracleDiffRows.Add([pscustomobject]@{
				file = $locatorFile
				id = $key
				status = $status
				merged_count = $mergedCount
				oracle_count = $oracleCount
			})
		}
	}
}

Export-CsvUtf8 -Rows $locatorMissingRows -Path (Join-Path $generatedRoot 'locator_missing_report.csv')
Export-CsvUtf8 -Rows $locatorValidationRows -Path (Join-Path $generatedRoot 'locator_validation_report.csv')
Export-CsvUtf8 -Rows $locatorOracleDiffRows -Path (Join-Path $generatedRoot 'locator_oracle_diff_report.csv')

$summaryLines = @(
	'# Core Province Integration Summary',
	'',
	('- history/provinces merged candidates: {0}' -f (($historyCoverageRows | Where-Object { $_.status -eq 'ok' }).Count)),
	('- history/provinces missing blocks: {0}' -f (($historyCoverageRows | Where-Object { $_.status -ne 'ok' }).Count)),
	('- landed_titles imported roots: {0}' -f $landedReplacementSpecs.Count),
	('- history/titles imported roots: {0}' -f $historyTitleReportRows.Count),
	('- adjacencies merged rows: {0}' -f $adjacencyRowsOutput.Count),
	('- adjacencies dropped stale rows: {0}' -f $adjacencyStaleRows.Count),
	('- locator missing rows: {0}' -f $locatorMissingRows.Count),
	('- locator validation flags: {0}' -f $locatorValidationRows.Count),
	('- locator oracle diffs: {0}' -f $locatorOracleDiffRows.Count)
)
Write-TextUtf8 -Path (Join-Path $generatedRoot 'core_province_integration_summary.md') -Text (($summaryLines -join "`r`n") + "`r`n")
