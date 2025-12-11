# Script to create a fix branch from origin/main and fix the database folder paths
Write-Host "Creating fix branch from origin/main..." -ForegroundColor Cyan

# Create a new branch pointing to origin/main
git branch fix-database-folder-final origin/main

# Get the commit hash of origin/main
$mainCommit = git rev-parse origin/main
Write-Host "Base commit: $mainCommit" -ForegroundColor Gray

# Get all files with problematic paths
$problematicFiles = git ls-tree -r --name-only origin/main | Where-Object { $_ -like "database /*" }
Write-Host "Found $($problematicFiles.Count) files with problematic paths" -ForegroundColor Yellow

# Create a temporary index
$GIT_INDEX_FILE = ".git/index.fix"
$env:GIT_INDEX_FILE = $GIT_INDEX_FILE

# Read the tree from origin/main
git read-tree origin/main

# Process each problematic file
foreach ($oldPath in $problematicFiles) {
    $newPath = $oldPath -replace "^database /", "database/"
    Write-Host "Fixing: $oldPath -> $newPath" -ForegroundColor Gray
    
    # Get the file hash from the old path
    $treeEntry = git ls-tree origin/main -- "$oldPath"
    if ($treeEntry) {
        $fileHash = ($treeEntry -split '\s+')[2]
        $fileMode = ($treeEntry -split '\s+')[0]
        
        # Add the file to the index with the new path
        git update-index --add --cacheinfo "$fileMode,$fileHash,$newPath"
    }
}

# Remove old paths from index
foreach ($oldPath in $problematicFiles) {
    git update-index --remove "$oldPath" 2>$null
}

# Create a commit
Write-Host "Creating commit..." -ForegroundColor Cyan
$treeHash = git write-tree
$commitHash = git commit-tree -p origin/main -m "Fix: Remove trailing space from database folder name" $treeHash

# Update the branch to point to new commit
git update-ref refs/heads/fix-database-folder-final $commitHash

# Clean up
Remove-Item $GIT_INDEX_FILE -ErrorAction SilentlyContinue
$env:GIT_INDEX_FILE = $null

Write-Host "Fix branch created: fix-database-folder-final" -ForegroundColor Green
Write-Host "Commit hash: $commitHash" -ForegroundColor Gray

