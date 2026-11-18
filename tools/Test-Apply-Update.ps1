$ErrorActionPreference = 'Stop'
$workspacePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixtureRoot = Join-Path $workspacePath ('artifacts\update-script-check\' + [Guid]::NewGuid().ToString('N'))
$fixtureTools = Join-Path $fixtureRoot 'tools'
$fixtureStaged = Join-Path $fixtureRoot 'artifacts\publish\TapMyPC-next'
$fixtureInstalled = Join-Path $fixtureRoot 'artifacts\publish\TapMyPC'
New-Item -ItemType Directory -Path $fixtureTools, $fixtureStaged, $fixtureInstalled -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $workspacePath 'tools\Apply-Update.ps1') -Destination $fixtureTools
$files = @{
    'TapMyPC.exe' = 'test executable placeholder - never launched'
    'TapMyPC.deps.json' = 'test dependency metadata'
    'runtimes\win\lib\net10.0\System.Management.dll' = 'Windows runtime dependency'
    'resources with spaces\nested\test.dat' = 'nested resource'
}
foreach ($relative in $files.Keys) {
    $path = Join-Path $fixtureStaged $relative
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($path)) -Force | Out-Null
    [IO.File]::WriteAllText($path, $files[$relative])
}
[IO.File]::WriteAllText((Join-Path $fixtureInstalled 'keep.txt'), 'preserve existing files')
[IO.File]::WriteAllText((Join-Path $fixtureInstalled 'TapMyPC.deps.json'), 'old metadata')
& (Join-Path $fixtureTools 'Apply-Update.ps1')
foreach ($relative in $files.Keys) {
    $installedFile = Join-Path $fixtureInstalled $relative
    if (-not (Test-Path -LiteralPath $installedFile)) { throw ('Missing installed file: ' + $relative) }
    if ((Get-FileHash -LiteralPath $installedFile).Hash -ne (Get-FileHash -LiteralPath (Join-Path $fixtureStaged $relative)).Hash) {
        throw ('Installed content mismatch: ' + $relative)
    }
}
if ([IO.File]::ReadAllText((Join-Path $fixtureInstalled 'keep.txt')) -ne 'preserve existing files') {
    throw 'Existing installation files must be preserved.'
}
Write-Output 'PASS: recursive runtime/resource copy, existing-file replacement, and preservation.'