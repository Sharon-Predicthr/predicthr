# Create a fix branch properly from origin/main using git plumbing
Write-Host "Creating fix branch with proper history..." -ForegroundColor Cyan

# Get the commit hash of origin/main
$mainCommit = git rev-parse origin/main
Write-Host "Base commit: $mainCommit" -ForegroundColor Gray

# Create a new branch pointing to origin/main
git branch -D fix-database-folder-final 2>$null
git branch fix-database-folder-final origin/main

# Get the tree hash of origin/main
$mainTree = git rev-parse "$mainCommit^{tree}"

# Get all files from origin/main
$allFiles = git ls-tree -r --name-only origin/main

# Get files with problematic paths
$problematicFiles = $allFiles | Where-Object { $_ -like "database /*" }

Write-Host "Found $($problematicFiles.Count) files to fix" -ForegroundColor Yellow

# Create a temporary index
$tempIndex = ".git/index.fix"
Remove-Item $tempIndex -ErrorAction SilentlyContinue
$env:GIT_INDEX_FILE = $tempIndex

# Initialize index from main tree
git read-tree $mainTree

# Fix each problematic file
foreach ($oldPath in $problematicFiles) {
    $newPath = $oldPath -replace "^database /", "database/"
    
    # Get file info from old path
    $oldEntry = git ls-tree -r origin/main -- "$oldPath"
    if ($oldEntry) {
        $parts = $oldEntry -split '\s+'
        $mode = $parts[0]
        $type = $parts[1]
        $hash = $parts[2]
        $path = $parts[3]
        
        Write-Host "  Fixing: $oldPath -> $newPath" -ForegroundColor Gray
        
        # Remove old path from index
        git update-index --remove "$oldPath" 2>$null
        
        # Add file with new path
        git update-index --add --cacheinfo "$mode,$hash,$newPath"
    }
}

# Write the new tree
$newTree = git write-tree
Write-Host "Created new tree: $newTree" -ForegroundColor Gray

# Create a commit
$commitMessage = "Fix: Remove trailing space from database folder name`n`nThis commit fixes the repository structure by removing the trailing space from the database folder name, making it compatible with Windows file systems."
$newCommit = git commit-tree -p $mainCommit -m $commitMessage $newTree

Write-Host "Created commit: $newCommit" -ForegroundColor Gray

# Update branch to point to new commit
git update-ref refs/heads/fix-database-folder-final $newCommit

# Clean up
Remove-Item $tempIndex -ErrorAction SilentlyContinue
$env:GIT_INDEX_FILE = $null

Write-Host "`nFix branch created successfully!" -ForegroundColor Green
Write-Host "Branch: fix-database-folder-final" -ForegroundColor Cyan
Write-Host "Commit: $newCommit" -ForegroundColor Cyan

