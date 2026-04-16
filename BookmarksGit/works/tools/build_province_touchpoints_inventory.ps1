$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $repoRoot

$outDir = Join-Path $repoRoot 'Works/analysis/generated'
if (-not (Test-Path -LiteralPath $outDir)) {
	New-Item -ItemType Directory -Path $outDir | Out-Null
}

$rows = [System.Collections.Generic.List[object]]::new()

function Add-Row {
	param(
		[string]$Path,
		[string]$Category,
		[string]$Reason,
		[string]$Priority = 'core',
		[string]$Evidence = ''
	)

	$rows.Add([pscustomobject]@{
		path = ($Path -replace '\\','/')
		category = $Category
		priority = $Priority
		reason = $Reason
		evidence = $Evidence
	})
}

function Add-DirectoryFiles {
	param(
		[string]$Dir,
		[string]$Filter,
		[string]$Category,
		[string]$Reason,
		[string]$Priority = 'core',
		[string]$Evidence = ''
	)

	if (-not (Test-Path -LiteralPath $Dir)) { return }
	Get-ChildItem -Path $Dir -Filter $Filter -File | Sort-Object Name | ForEach-Object {
		Add-Row -Path $_.FullName.Substring($repoRoot.Length + 1) -Category $Category -Reason $Reason -Priority $Priority -Evidence $Evidence
	}
}

Add-Row -Path 'map_data/provinces.png' -Category 'map_data_core' -Reason 'Ana province piksel haritasi; RGB alanlari province kimligini belirler.' -Evidence 'pixel province map'
Add-Row -Path 'map_data/definition.csv' -Category 'map_data_core' -Reason 'Province ID -> RGB -> isim tanim tablosu.' -Evidence 'id;r;g;b;name'
Add-Row -Path 'map_data/default.map' -Category 'map_data_core' -Reason 'Haritanin hangi definition/provinces dosyalarini kullandigini ve impassable/sea zone gibi baglantili yapilari belirler.' -Evidence 'definitions / provinces / impassable_mountains'
Add-Row -Path 'map_data/adjacencies.csv' -Category 'map_data_core' -Reason 'Province-to-province adjacency gecislerini tanimlar.' -Evidence 'adjacency lines'
Add-Row -Path 'map_data/island_region.txt' -Category 'map_data_core' -Reason 'Ada region mantiginda province gruplarini etkiler.' -Evidence 'island region province grouping'
Add-DirectoryFiles -Dir 'map_data/geographical_regions' -Filter '*.txt' -Category 'map_data_regions' -Reason 'Geographical region tanimlari; province/title tabanli bolge kullanimlari burada tutulur.' -Evidence 'geographical_region'

Add-DirectoryFiles -Dir 'history/provinces' -Filter '*.txt' -Category 'history_provinces' -Reason 'Dogrudan province history: holding, terrain, culture, faith, buildings, special_building vb.' -Evidence 'holding / terrain / buildings / special_building'
Add-DirectoryFiles -Dir 'common/landed_titles' -Filter '*.txt' -Category 'landed_titles' -Reason 'County/barony hiyerarsisi province-title baglantisini belirler.' -Evidence 'county/barony structure'
Add-DirectoryFiles -Dir 'history/titles' -Filter '*.txt' -Category 'history_titles' -Reason 'Title history province baglantili de-jure, capital ve holder akisini etkiler.' -Evidence 'capital / de_jure_liege / title history'

Add-DirectoryFiles -Dir 'gfx/map/map_object_data' -Filter '*.txt' -Category 'map_object_data' -Reason 'Map object locator ve province uzerine bagli gorsel/oyunsal yerlesim dosyalari.' -Evidence 'locator / building / siege / combat / activity'
Add-DirectoryFiles -Dir 'gfx/map/map_object_data/generated' -Filter '*.txt' -Category 'map_object_generated' -Reason 'Generated map object helper dosyalari; locator/placement turevleri.' -Priority 'secondary' -Evidence 'generated map object helpers'

$secondaryPatterns = @(
	'\bprovince:[0-9]+\b',
	'\bprovince\s*=\s*[0-9]+\b',
	'\bprovince_id\s*=\s*[0-9]+\b',
	'\btitle:[bc]_[A-Za-z0-9_]+\b',
	'\b(title|county|barony|capital|de_jure_liege|has_title)\s*=\s*(title:)?[bc]_[A-Za-z0-9_]+\b',
	'^\s*[A-Za-z0-9_]+\s*=\s*(title:)?[bc]_[A-Za-z0-9_]+\b',
	'\blocation\s*=\s*title:[bc]_',
	'\bcapital\s*=\s*[bc]_',
	'\bprovince\s*=\s*title:[bc]_'
)

$secondaryArgs = @(
	'-l',
	'-g', '*.txt',
	'-g', '*.gui',
	'-g', '*.csv',
	'-g', '*.yml'
)

foreach ($pattern in $secondaryPatterns) {
	$secondaryArgs += @('-e', $pattern)
}

$secondaryArgs += @(
	'common',
	'events',
	'history',
	'gfx',
	'gui',
	'--glob', '!history/provinces/**',
	'--glob', '!history/titles/**',
	'--glob', '!common/landed_titles/**',
	'--glob', '!gfx/map/map_object_data/**',
	'--glob', '!Works/**'
)

$secondaryFiles = @()
try {
	$secondaryFiles = & rg @secondaryArgs 2>$null
} catch {
	$secondaryFiles = @()
}

$secondaryFiles = $secondaryFiles | Where-Object { $_ -and $_.Trim() -ne '' } | Sort-Object -Unique

foreach ($file in $secondaryFiles) {
	$evidence = ''
	try {
		$matchLine = & rg -n -m 1 -e '\bprovince:[0-9]+\b|\bprovince\s*=\s*[0-9]+\b|\bprovince_id\s*=\s*[0-9]+\b|\btitle:[bc]_[A-Za-z0-9_]+\b|\b(title|county|barony|capital|de_jure_liege|has_title)\s*=\s*(title:)?[bc]_[A-Za-z0-9_]+\b|^\s*[A-Za-z0-9_]+\s*=\s*(title:)?[bc]_[A-Za-z0-9_]+\b|\blocation\s*=\s*title:[bc]_|\bcapital\s*=\s*[bc]_|\bprovince\s*=\s*title:[bc]_' -- $file 2>$null | Select-Object -First 1
		if ($matchLine) { $evidence = $matchLine.Trim() }
	} catch {}

	Add-Row -Path $file -Category 'secondary_province_touchpoint' -Reason 'Core map aileleri disinda sabit province ID, sabit barony/county title referansi veya sabit title mappingi iceren dosya.' -Priority 'secondary' -Evidence $evidence
}

$rows = $rows | Sort-Object category, path

$csvPath = Join-Path $outDir 'province_touchpoints_inventory.csv'
$rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8

$summaryPath = Join-Path $outDir 'province_touchpoints_inventory.md'
$sb = [System.Text.StringBuilder]::new()
$null = $sb.AppendLine('# Province Touchpoints Inventory')
$null = $sb.AppendLine()
$null = $sb.AppendLine('Bu dosya mod icinde province ile dogrudan veya dolayli ilgilenen dosya ailelerini listeler.')
$null = $sb.AppendLine()

$categoryGroups = $rows | Group-Object category | Sort-Object Name
foreach ($group in $categoryGroups) {
	$null = $sb.AppendLine("## $($group.Name)")
	$null = $sb.AppendLine()
	$null = $sb.AppendLine("- Dosya sayisi: $($group.Count)")
	$null = $sb.AppendLine("- Ornek neden: $($group.Group[0].reason)")
	$null = $sb.AppendLine()
	$group.Group | Select-Object -First 25 | ForEach-Object {
		$null = $sb.AppendLine("- $($_.path)")
	}
	if ($group.Count -gt 25) {
		$null = $sb.AppendLine("- devam: toplam $($group.Count) dosya; tam liste icin province_touchpoints_inventory.csv dosyasina bak.")
	}
	$null = $sb.AppendLine()
}

$null = $sb.AppendLine('## Kisa Sonuc')
$null = $sb.AppendLine()
$null = $sb.AppendLine('- Province merge sonrasi ilk bakilacak core aileler: map_data_core, history_provinces, landed_titles, history_titles, map_object_data.')
$null = $sb.AppendLine('- secondary_province_touchpoint kategorisi yalnizca sabit province ID veya sabit barony/county title referansi iceren ek dosyalari gosterir.')

[System.IO.File]::WriteAllText($summaryPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))

$countPath = Join-Path $outDir 'province_touchpoints_category_counts.csv'
$rows |
	Group-Object category |
	Sort-Object Name |
	ForEach-Object {
		[pscustomobject]@{
			category = $_.Name
			count = $_.Count
		}
	} |
	Export-Csv -Path $countPath -NoTypeInformation -Encoding utf8

Write-Output "Wrote: $csvPath"
Write-Output "Wrote: $summaryPath"
Write-Output "Wrote: $countPath"
