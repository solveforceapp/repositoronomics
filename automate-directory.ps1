# automate-directory.ps1
# This script enforces the a–z directory structure and file population as per all_term_pages.csv
# 1. Parses all_term_pages.csv for required files
# 2. Creates missing .html files with a standard template
# 3. Removes extra .html files not in the CSV
# 4. Adds .gitkeep to empty folders
# 5. Pulls, commits, and pushes changes

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $repoRoot

# 1. Pull latest changes
git pull --rebase

# 2. Parse CSV and build file map
$csvPath = Join-Path $repoRoot 'all_term_pages.csv'
$csv = Import-Csv -Path $csvPath
$folderMap = @{}
foreach ($row in $csv) {
    $dir = [System.IO.Path]::GetFileName($row.Directory)
    if (-not $folderMap.ContainsKey($dir)) { $folderMap[$dir] = @() }
    $folderMap[$dir] += $row.Name
}

# 3. For each a–z folder, enforce file presence and generate index.html
foreach ($letter in 'a'..'z') {
    $folder = Join-Path $repoRoot $letter
    if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
    $requiredFiles = $folderMap[$letter]
    if ($null -eq $requiredFiles) { $requiredFiles = @() }
    $existingFiles = Get-ChildItem -Path $folder -Filter '*.html' -Name -ErrorAction SilentlyContinue
    # Create missing files
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $folder $file
        if (-not (Test-Path $filePath)) {
            Set-Content -Path $filePath -Value "<html>\n<head>\n  <title>$file</title>\n  <link rel='stylesheet' href='../style.css'>\n</head>\n<body>\n  <header>\n    <nav>\n      <a href='../index.html'>Home</a>\n    </nav>\n  </header>\n  <main>\n    <h1>$file</h1>\n    <p>Placeholder for $file</p>\n  </main>\n</body>\n</html>"
        }
        # If file exists, do NOT overwrite (preserve original content)
    }
    # Remove extra files
    foreach ($file in $existingFiles) {
        if ($file -notin $requiredFiles -and $file -ne 'index.html') {
            Remove-Item (Join-Path $folder $file) -Force
        }
    }
    # Generate index.html for the folder
    $indexPath = Join-Path $folder 'index.html'
    $links = ''
    foreach ($file in $requiredFiles | Sort-Object) {
        $links += '      <li><a href="' + $file + '">' + $file + '</a></li>`n'
    }
    $indexHtml = @"
<!DOCTYPE html>
<html lang=\"en\">
<head>
  <meta charset=\"UTF-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Terms: $($letter.ToString().ToUpper())</title>
  <link rel=\"stylesheet\" href=\"../style.css\">
</head>
<body>
  <header>
    <nav>
      <a href=\"../index.html\">Home</a> |
      <a href=\"../about.html\">About</a> |
      <a href=\"../contact.html\">Contact</a>
    </nav>
  </header>
  <main>
    <h1>Terms: $($letter.ToString().ToUpper())</h1>
    <ul>
$links+    </ul>
  </main>
</body>
</html>
"@
    Set-Content -Path $indexPath -Value $indexHtml
    # Add .gitkeep if folder is empty (no .html except index.html)
    $htmlCount = (Get-ChildItem -Path $folder -Filter '*.html' -Name -ErrorAction SilentlyContinue | Where-Object { $_ -ne 'index.html' }).Count
    if ($htmlCount -eq 0) {
        Set-Content -Path (Join-Path $folder '.gitkeep') -Value ''
    } else {
        Remove-Item -Path (Join-Path $folder '.gitkeep') -ErrorAction SilentlyContinue
    }
}

# 4. Stage, commit, and push changes
git add .
$changes = git status --porcelain
if ($changes) {
    git commit -m "Automated: Sync a–z folders and term pages with all_term_pages.csv"
    git push
}

# 5. Verify remote matches local
git fetch origin
$local = git rev-parse HEAD
$remote = git rev-parse "@{u}"
if ($local -ne $remote) {
    Write-Host "Warning: Local and remote are out of sync!" -ForegroundColor Red
} else {
    Write-Host "Automation complete. Local and remote are in sync." -ForegroundColor Green
}
