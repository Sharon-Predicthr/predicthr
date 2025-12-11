# Extract all folders from commit 481c6a0 (before the fix)
# This commit has folders with trailing spaces that Windows can't handle normally

$baseCommit = "481c6a0"
Write-Host "Extracting folders from commit $baseCommit..." -ForegroundColor Cyan

# Get all files from the commit, excluding the problematic database folder (we already have the fixed version)
$allFiles = git ls-tree -r --name-only $baseCommit | Where-Object { $_ -notlike "database /*" }

$foldersToFix = @("api", "deploy", "dev-data", "dev-tools", "docker", "docs", "environment", "scripts", "web-app")

foreach ($folder in $foldersToFix) {
    Write-Host "Processing folder: $folder" -ForegroundColor Yellow
    
    # Get all files in this folder from the commit
    $folderFiles = $allFiles | Where-Object { $_ -like "$folder/*" }
    
    if ($folderFiles) {
        foreach ($filePath in $folderFiles) {
            # Get file hash from commit
            $treeEntry = git ls-tree $baseCommit -- "$filePath"
            if ($treeEntry) {
                $parts = $treeEntry -split '\s+'
                $mode = $parts[0]
                $hash = $parts[2]
                
                # Ensure directory exists
                $dir = Split-Path -Parent $filePath
                if ($dir -and -not (Test-Path $dir)) {
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                }
                
                # Get file content and write it
                git cat-file blob $hash | Out-File -FilePath $filePath -Encoding utf8 -NoNewline
                Write-Host "  Extracted: $filePath" -ForegroundColor Gray
            }
        }
    }
}

Write-Host "`nAll folders extracted!" -ForegroundColor Green

