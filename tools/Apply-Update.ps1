param([switch]$Launch)
$ErrorActionPreference = 'Stop'
$workspacePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stagedPath = [System.IO.Path]::GetFullPath((Join-Path $workspacePath 'artifacts\publish\TapMyPC-next'))
$installedPath = [System.IO.Path]::GetFullPath((Join-Path $workspacePath 'artifacts\publish\TapMyPC'))
$installedExecutable = Join-Path $installedPath 'TapMyPC.exe'
if (-not (Test-Path -LiteralPath (Join-Path $stagedPath 'TapMyPC.exe'))) {
    throw 'Build the staged release first. See docs/setup.md.'
}
$running = @(Get-Process -Name 'TapMyPC' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $installedExecutable })
if ($running.Count -gt 0) {
    throw 'Exit TapMyPC using its tray menu first. This cancels pending power timers. Then run this script again.'
}
# Preserve the original executable location so startup and program-scoped firewall rules remain applicable.
# Only copy files produced by publish; never delete files or modify per-user settings.
New-Item -ItemType Directory -Path $installedPath -Force | Out-Null
Get-ChildItem -LiteralPath $stagedPath -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $installedPath $_.Name) -Force
}
Write-Output "Updated TapMyPC at $installedPath"
if ($Launch) { Start-Process -FilePath $installedExecutable -WindowStyle Hidden }
