$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Read-CsvUtf8 {
	param(
		[Parameter(Mandatory = $true)][string]$Path
	)

	$text = [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
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

	$dir = Split-Path -Parent $Path
	if ($dir -and -not (Test-Path -LiteralPath $dir)) {
		New-Item -ItemType Directory -Path $dir -Force | Out-Null
	}
	$Rows | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
}

function Write-TextUtf8 {
	param(
		[Parameter(Mandatory = $true)][string]$Path,
		[Parameter(Mandatory = $true)][string]$Text
	)

	$dir = Split-Path -Parent $Path
	if ($dir -and -not (Test-Path -LiteralPath $dir)) {
		New-Item -ItemType Directory -Path $dir -Force | Out-Null
	}
	[System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-GapCategory {
	param(
		[string]$Name
	)

	$value = [string]$Name
	if ([string]::IsNullOrWhiteSpace($value)) {
		return 'blank_name'
	}

	$lower = $value.ToLowerInvariant()
	if ($lower -match 'sea_|river_|lake_|ocean|channel|strait|bay|gulf|delta|coast|sea |river |lake ') {
		return 'maritime_or_water'
	}
	if ($lower -match 'mountain|mountains|wasteland|desert|forest|jungle|steppe|hills|marsh|taiga|glacier') {
		return 'terrain_or_impassable'
	}
	if ($lower -match 'east indian ocean ti|gobi|himalaya|lakes east of burma') {
		return 'terrain_or_impassable'
	}
	return 'named_land_or_special'
}

$repoRoot = (Get-Location).Path
$generatedRoot = Join-Path $repoRoot 'Works\analysis\generated\core_province_integration'
$reportPath = Join-Path $generatedRoot 'history_provinces_merge_report.csv'
$masterPath = Join-Path $repoRoot 'Works\analysis\generated\final_master_preserve_old_ids.csv'

$reportRows = Read-CsvUtf8 -Path $reportPath
$masterRows = Read-CsvUtf8 -Path $masterPath
$masterById = @{}
foreach ($row in $masterRows) {
	$masterById[[int]$row.final_new_id] = $row
}

$classifiedRows = New-Object System.Collections.Generic.List[object]
foreach ($row in $reportRows) {
	if ($row.status -ne 'missing_history_block') {
		continue
	}
	$finalId = [int]$row.final_new_id
	$master = $masterById[$finalId]
	$name = if ($master) { $master.effective_name } else { '' }
	$category = Get-GapCategory -Name $name
	$class = if ($category -eq 'named_land_or_special') { 'needs_manual_review' } else { 'likely_benign_or_low_priority' }

	$classifiedRows.Add([pscustomobject]@{
		final_new_id = $finalId
		source_subset = $row.source_subset
		effective_name = $name
		source_origin = if ($master) { $master.source_origin } else { '' }
		primary_status = if ($master) { $master.primary_status } else { '' }
		gap_category = $category
		review_class = $class
	})
}

$csvPath = Join-Path $generatedRoot 'history_provinces_missing_classification.csv'
Export-CsvUtf8 -Rows $classifiedRows -Path $csvPath

$counts = $classifiedRows | Group-Object gap_category | Sort-Object Count -Descending
$subsetCounts = $classifiedRows | Group-Object source_subset | Sort-Object Name
$reviewCounts = $classifiedRows | Group-Object review_class | Sort-Object Name

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# History Provinces Missing Classification')
$lines.Add('')
$lines.Add(('- total missing_history_block rows: {0}' -f $classifiedRows.Count))
$lines.Add('')
$lines.Add('## By Review Class')
foreach ($group in $reviewCounts) {
	$lines.Add(('- {0}: {1}' -f $group.Name, $group.Count))
}
$lines.Add('')
$lines.Add('## By Category')
foreach ($group in $counts) {
	$lines.Add(('- {0}: {1}' -f $group.Name, $group.Count))
}
$lines.Add('')
$lines.Add('## By Source Subset')
foreach ($group in $subsetCounts) {
	$lines.Add(('- {0}: {1}' -f $group.Name, $group.Count))
}

$mdPath = Join-Path $generatedRoot 'history_provinces_missing_classification.md'
Write-TextUtf8 -Path $mdPath -Text (($lines -join "`r`n") + "`r`n")
