param(
    [string]$RepoRoot = (Get-Location).Path,
    [string[]]$RgbList = @('135,36,34')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pngPath = Join-Path $RepoRoot 'map_data/provinces.png'
$reportDir = Join-Path $RepoRoot 'Works/analysis/generated/provinces_rgb_components'
$null = New-Item -ItemType Directory -Path $reportDir -Force

Add-Type -AssemblyName System.Drawing

$csharp = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class ComponentInfo {
    public int Index;
    public int PixelCount;
    public int MinX = int.MaxValue;
    public int MinY = int.MaxValue;
    public int MaxX = -1;
    public int MaxY = -1;
}

public static class RgbComponentAnalyzer {
    private static Bitmap LoadAs32bpp(string path) {
        using (var original = new Bitmap(path)) {
            return original.Clone(new Rectangle(0, 0, original.Width, original.Height), PixelFormat.Format32bppArgb);
        }
    }

    public static List<ComponentInfo> Analyze(string path, int key) {
        var components = new List<ComponentInfo>();
        using (var bmp = LoadAs32bpp(path)) {
            var rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
            var data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try {
                var bytes = new byte[Math.Abs(data.Stride) * bmp.Height];
                Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);

                var mask = new bool[bmp.Width * bmp.Height];
                for (int y = 0; y < bmp.Height; y++) {
                    int rowOffset = y * data.Stride;
                    for (int x = 0; x < bmp.Width; x++) {
                        int offset = rowOffset + (x * 4);
                        int pixelKey = (bytes[offset + 2] << 16) | (bytes[offset + 1] << 8) | bytes[offset];
                        if (pixelKey == key) {
                            mask[y * bmp.Width + x] = true;
                        }
                    }
                }

                var visited = new bool[bmp.Width * bmp.Height];
                int[] dx = new int[] { 1, -1, 0, 0 };
                int[] dy = new int[] { 0, 0, 1, -1 };
                int componentIndex = 0;

                var queue = new Queue<int>();
                for (int y = 0; y < bmp.Height; y++) {
                    for (int x = 0; x < bmp.Width; x++) {
                        int startIdx = y * bmp.Width + x;
                        if (!mask[startIdx] || visited[startIdx]) {
                            continue;
                        }

                        var component = new ComponentInfo();
                        component.Index = componentIndex++;
                        visited[startIdx] = true;
                        queue.Enqueue(startIdx);

                        while (queue.Count > 0) {
                            int current = queue.Dequeue();
                            int cx = current % bmp.Width;
                            int cy = current / bmp.Width;

                            component.PixelCount++;
                            if (cx < component.MinX) component.MinX = cx;
                            if (cy < component.MinY) component.MinY = cy;
                            if (cx > component.MaxX) component.MaxX = cx;
                            if (cy > component.MaxY) component.MaxY = cy;

                            for (int i = 0; i < 4; i++) {
                                int nx = cx + dx[i];
                                int ny = cy + dy[i];
                                if (nx < 0 || ny < 0 || nx >= bmp.Width || ny >= bmp.Height) {
                                    continue;
                                }
                                int nextIdx = ny * bmp.Width + nx;
                                if (!mask[nextIdx] || visited[nextIdx]) {
                                    continue;
                                }
                                visited[nextIdx] = true;
                                queue.Enqueue(nextIdx);
                            }
                        }

                        components.Add(component);
                    }
                }
            }
            finally {
                bmp.UnlockBits(data);
            }
        }
        return components;
    }
}
"@

Add-Type -TypeDefinition $csharp -ReferencedAssemblies System.Drawing

foreach ($rgb in $RgbList) {
    $parts = $rgb -split ','
    $key = (([int]$parts[0] -shl 16) -bor ([int]$parts[1] -shl 8) -bor [int]$parts[2])
    $components = [RgbComponentAnalyzer]::Analyze($pngPath, $key) | Sort-Object PixelCount -Descending
    $safeName = ($rgb -replace ',', '_')
    $csvPath = Join-Path $reportDir ("rgb_{0}_components.csv" -f $safeName)
    $mdPath = Join-Path $reportDir ("rgb_{0}_components.md" -f $safeName)

    $rows = foreach ($component in $components) {
        [pscustomobject]@{
            rgb = $rgb
            component_index = $component.Index
            pixel_count = $component.PixelCount
            bbox = '{0},{1} -> {2},{3}' -f $component.MinX, $component.MinY, $component.MaxX, $component.MaxY
            min_x = $component.MinX
            min_y = $component.MinY
            max_x = $component.MaxX
            max_y = $component.MaxY
        }
    }

    $rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

    $md = @(
        "# RGB component analysis for $rgb",
        '',
        ('- component_count: `{0}`' -f $rows.Count),
        ('- total_pixels: `{0}`' -f (($rows | Measure-Object pixel_count -Sum).Sum)),
        '',
        'Largest components:'
    )
    foreach ($row in ($rows | Select-Object -First 20)) {
        $md += ('- component `{0}`: `{1}` px, bbox `{2}`' -f $row.component_index, $row.pixel_count, $row.bbox)
    }
    Set-Content -Path $mdPath -Value ($md -join "`r`n") -Encoding UTF8
    Write-Host "Wrote $csvPath"
    Write-Host "Wrote $mdPath"
}
