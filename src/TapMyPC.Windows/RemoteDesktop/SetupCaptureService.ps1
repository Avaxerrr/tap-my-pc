param(
    [ValidateSet('Configure','Start','Stop','Save','ResetPassword')]
    [string]$Operation = 'Configure',
    [ValidateRange(5,60)]
    [int]$MaxFps = 25,
    [bool]$KeepWallpaper = $true,
    [string]$PipeName,
    [uint32]$ParentProcessId
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$env:PSModulePath = Join-Path $PSHOME 'Modules'
$serviceName = 'uvnc_service'
$programFiles = [Environment]::GetFolderPath('ProgramFiles')
$installDir = Join-Path $programFiles 'uvnc\UltraVNC'
$serverExe = Join-Path $installDir 'winvnc.exe'
$configDir = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'UltraVNC'
$config = Join-Path $configDir 'ultravnc.ini'
$stagingDir = $null
$installer = $null
$managedService = $false
$setupStage = 'checking UltraVNC'
$newPassword = $null

$script:setupReader = $null
$script:setupWriter = $null
$script:setupPipe = $null
$script:hasLocalInstaller = $false

function Connect-SetupPipe {
    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class TapMyPcSetupPipe {
    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetNamedPipeServerProcessId(SafePipeHandle pipe, out uint processId);
}
"@
    $script:setupPipe = [IO.Pipes.NamedPipeClientStream]::new('.', $PipeName, [IO.Pipes.PipeDirection]::InOut,
        [IO.Pipes.PipeOptions]::None, [Security.Principal.TokenImpersonationLevel]::Identification)
    $script:setupPipe.Connect(12000)
    $serverProcess = [uint32]0
    if (![TapMyPcSetupPipe]::GetNamedPipeServerProcessId($script:setupPipe.SafePipeHandle, [ref]$serverProcess) -or
        $serverProcess -ne $ParentProcessId) {
        throw 'Could not verify the TapMyPC setup window.'
    }
    $encoding = [Text.UTF8Encoding]::new($false)
    $script:setupReader = [IO.StreamReader]::new($script:setupPipe, $encoding, $false, 1024, $true)
    $script:setupWriter = [IO.StreamWriter]::new($script:setupPipe, $encoding, 1024, $true)
    $script:setupWriter.AutoFlush = $true
    $chosen = $script:setupReader.ReadLine()
    if ($null -eq $chosen) { throw 'The TapMyPC setup window closed.' }
    if ($chosen -ne '' -and $chosen -notmatch '\A[\x20-\x7e]{1,8}\z') { throw 'Invalid VNC password.' }
    $source = $script:setupReader.ReadLine()
    if ($source -notin 'download', 'local') { throw 'Invalid UltraVNC installer source.' }
    $script:hasLocalInstaller = $source -eq 'local'
    return $chosen
}

function Publish-SetupEvent([hashtable]$Event) {
    if (!$script:setupWriter) { return $false }
    try {
        $script:setupWriter.WriteLine(($Event | ConvertTo-Json -Compress))
        return $true
    } catch [System.IO.IOException] {
        return $false
    }
}

function Report-SetupProgress([string]$Message) {
    [void](Publish-SetupEvent @{ progress = $Message })
}

function Stop-UltraVnc {
    $current = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($current -and $current.Status -ne 'Stopped') {
        Stop-Service -Name $serviceName
        $current.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(10))
    }
}

function Disable-UltraVncFirewallRules {
    $rules = @(Get-NetFirewallRule -DisplayName 'UltraVNC Server TCP','UltraVNC Server UDP' -ErrorAction SilentlyContinue)
    foreach ($rule in $rules) {
        if ($rule.Direction -ne 'Inbound' -or $rule.Enabled -ne 'True') { continue }
        $program = ($rule | Get-NetFirewallApplicationFilter).Program
        if ($program -and [Environment]::ExpandEnvironmentVariables($program) -ieq $serverExe) {
            $rule | Disable-NetFirewallRule
        }
    }
}

function Set-LoopbackConfiguration {
    $settings = @{
        AllowLoopback = '1'
        LoopbackOnly = '1'
        SocketConnect = '1'
        HTTPConnect = '0'
        FileTransferEnabled = '0'
        AuthRequired = '1'
        UseRegistry = '0'
        PortNumber = '5900'
        AutoPortSelect = '0'
        UseDSMPlugin = '0'
        MSLogonRequired = '0'
        NewMSLogon = '0'
        InputsEnabled = '1'
        LocalInputsDisabled = '0'
        DisableTrayIcon = '1'
    }
    foreach ($key in $settings.Keys) {
        if (![TapMyPcIni]::WritePrivateProfileString('admin', $key, $settings[$key], $config)) {
            throw "Couldn't update the UltraVNC setting $key."
        }
    }
}

function Set-ViewerPassword([string]$ChosenPassword) {
    # UltraVNC expects an eight-byte VNC password in a Windows INI structure.
    # Use the established storage format only for this local compatibility credential.
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $clear = [byte[]]::new(8)
    $randomByte = [byte[]]::new(1)
    $limit = 256 - (256 % $alphabet.Length)
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    $des = [Security.Cryptography.DES]::Create()
    try {
        if ($ChosenPassword) {
            [void][Text.Encoding]::ASCII.GetBytes($ChosenPassword, 0, $ChosenPassword.Length, $clear, 0)
        } else {
            for ($i = 0; $i -lt $clear.Length; $i++) {
                do { $random.GetBytes($randomByte) } while ($randomByte[0] -ge $limit)
                $clear[$i] = [byte][char]$alphabet[$randomByte[0] % $alphabet.Length]
            }
        }
        $des.Mode = 'ECB'
        $des.Padding = 'None'
        # VNC uses reversed bit order for each byte of the legacy INI key.
        $des.Key = [byte[]](232, 74, 214, 96, 196, 114, 26, 224)
        $encryptor = $des.CreateEncryptor()
        try { $encoded = $encryptor.TransformFinalBlock($clear, 0, $clear.Length) }
        finally { $encryptor.Dispose() }
        if (![TapMyPcIni]::WritePrivateProfileString('TapMyPC', 'SetupPasswordPending', '1', $config) -or
            ![TapMyPcIni]::WritePrivateProfileString('admin', 'Secure', '0', $config) -or
            ![TapMyPcIni]::WritePrivateProfileStruct('UltraVNC', 'passwd', $encoded, $encoded.Length, $config)) {
            throw 'Could not save the new viewer password.'
        }
        if (!$ChosenPassword) { return [Text.Encoding]::ASCII.GetString($clear) }
    } finally {
        [Array]::Clear($clear, 0, $clear.Length)
        $des.Dispose()
        $random.Dispose()
    }
}

function Confirm-ServicePath {
    $entry = Get-CimInstance Win32_Service -Filter "Name = 'uvnc_service'"
    if (!$entry -or $entry.PathName -ine ('"' + $serverExe + '" -service')) {
        throw 'TapMyPC could not verify the UltraVNC service path. Check your UltraVNC installation.'
    }
}

function Get-UltraVncRelease {
    $site = [uri]'https://uvnc.com/downloads/ultravnc.html'
    $index = (Invoke-WebRequest -UseBasicParsing -MaximumRedirection 0 -Uri $site -TimeoutSec 25).Content
    $latest = [regex]::Match($index, 'Latest\s+release\s+version:\s*UltraVNC\s+(?<version>\d+\.\d+\.\d+\.\d+)\s*(?=<)', 'IgnoreCase')
    if (!$latest.Success) { throw 'Could not identify the latest stable UltraVNC release on the official download site.' }

    $version = [version]$latest.Groups['version'].Value
    $releaseSlug = $version.ToString().Replace('.', '-')
    $articlePattern = 'href\s*=\s*"(?<path>/downloads/ultravnc/\d+-ultravnc-' + $releaseSlug + '\.html)"'
    $articleLink = [regex]::Match($index, $articlePattern, 'IgnoreCase')
    if (!$articleLink.Success) { throw "Could not find the download page for UltraVNC $version." }

    $article = (Invoke-WebRequest -UseBasicParsing -MaximumRedirection 0 -Uri ([uri]::new($site, $articleLink.Groups['path'].Value)) -TimeoutSec 25).Content
    $fileName = 'UltraVNC_' + $version.ToString().Replace('.', '') + '_x64_Setup.exe'
    $hashPattern = 'SHA256\s+hash\s+of\s+' + [regex]::Escape($fileName) + '\s*:\s*<br\s*/?\s*>\s*(?<hash>[a-f0-9]{64})(?![a-f0-9])'
    $publishedHash = [regex]::Match($article, $hashPattern, 'IgnoreCase')
    if (!$publishedHash.Success) { throw "Could not find the published SHA-256 checksum for $fileName." }

    # The project's direct-download mirror organizes binaries by release family.
    $family = '{0}{1}00' -f $version.Major, $version.Minor
    $buildFamily = '{0}{1}{2}0' -f $version.Major, $version.Minor, $version.Build
    [pscustomobject]@{
        Version = $version
        Hash = $publishedHash.Groups['hash'].Value
        DownloadUris = @($family, $buildFamily) | Select-Object -Unique | ForEach-Object {
            [uri]"https://uvnc.eu/download/$_/$fileName"
        }
    }
}

function Test-UltraVncSignature([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    $signature.Status -eq 'Valid' -and
        $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -in
            'Open Source Developer Rudi De Vos', 'uvnc bvba'
}

function Receive-Installer([uri]$Uri, [string]$Destination, [version]$Version) {
    $request = [Net.HttpWebRequest][Net.WebRequest]::Create($Uri)
    $request.AllowAutoRedirect = $false
    $request.Timeout = 30000
    # Bound inactivity on each read while allowing an active transfer to finish.
    $request.ReadWriteTimeout = 30000
    try { $response = $request.GetResponse() } catch [Net.WebException] {
        $failure = $_.Exception
        while ($failure -isnot [Net.WebException] -and $failure.InnerException) { $failure = $failure.InnerException }
        if ($failure.Response) {
            $status = [int]$failure.Response.StatusCode
            $failure.Response.Dispose()
            if ($status -eq 404) { return 'Unavailable' }
            if ($status -in 408, 429, 500, 502, 503, 504) { return 'Interrupted' }
        } elseif ($failure.Status -in 'Timeout', 'ConnectFailure', 'ConnectionClosed', 'NameResolutionFailure',
            'ReceiveFailure', 'SendFailure', 'KeepAliveFailure') {
            return 'Interrupted'
        }
        throw
    }

    try {
        if ([int]$response.StatusCode -ne 200) { throw 'The official installer download returned an unexpected response.' }
        $stream = $response.GetResponseStream()
        try {
            $target = [IO.File]::Open($Destination, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try {
                $clock = [Diagnostics.Stopwatch]::StartNew()
                $lastReport = 0
                $received = [long]0
                $buffer = [byte[]]::new(65536)
                while ($true) {
                    try { $count = $stream.Read($buffer, 0, $buffer.Length) }
                    catch [IO.IOException], [Net.WebException] { return 'Interrupted' }
                    if ($count -eq 0) { break }
                    $target.Write($buffer, 0, $count)
                    $received += $count
                    if ($clock.ElapsedMilliseconds - $lastReport -lt 350 -and $received -ne $response.ContentLength) { continue }
                    $lastReport = $clock.ElapsedMilliseconds
                    $progress = @{ progress = ('Downloading UltraVNC {0} · {1:N1} MB' -f $Version, ($received / 1MB)) }
                    if ($response.ContentLength -gt 0) {
                        $progress.percent = [int][Math]::Min(100, [Math]::Floor(100 * $received / $response.ContentLength))
                    }
                    if (!(Publish-SetupEvent $progress)) { throw 'The TapMyPC setup window closed.' }
                }
                if ($received -eq 0 -or ($response.ContentLength -ge 0 -and $received -ne $response.ContentLength)) {
                    return 'Interrupted'
                }
            } finally { $target.Dispose() }
        } finally { $stream.Dispose() }
        return 'Complete'
    } finally { $response.Dispose() }
}

function Get-UltraVncInstaller($Release, [string]$Destination) {
    foreach ($uri in $Release.DownloadUris) {
        Report-SetupProgress "Downloading UltraVNC $($Release.Version)…"
        $result = Receive-Installer $uri $Destination $Release.Version
        if ($result -eq 'Interrupted') {
            Report-SetupProgress 'The UltraVNC download was interrupted. Retrying…'
            Start-Sleep -Seconds 2
            $result = Receive-Installer $uri $Destination $Release.Version
        }
        if ($result -eq 'Complete') { return }
    }
    throw 'Could not download the x64 installer. Use Download UltraVNC manually to get the installer from the official site.'
}

function Receive-LocalInstaller([string]$Destination) {
    Report-SetupProgress 'Reading the selected UltraVNC installer…'
    if (!(Publish-SetupEvent @{ installerRequested = $true })) { throw 'The TapMyPC setup window closed.' }
    $target = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        while ($true) {
            $line = $script:setupReader.ReadLine()
            if ($null -eq $line) { throw 'The TapMyPC setup window closed.' }
            if ($line -eq '') { break }
            $chunk = [Convert]::FromBase64String($line)
            if ($target.Length + $chunk.Length -gt 64MB) { throw 'The selected installer exceeds 64 MB.' }
            $target.Write($chunk, 0, $chunk.Length)
        }
    } finally { $target.Dispose() }
}

function Confirm-UltraVncInstaller($Release, [string]$Path) {
    Report-SetupProgress "Verifying UltraVNC $($Release.Version)…"
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Release.Hash -or
        !(Test-UltraVncSignature $Path) -or
        [version](Get-Item -LiteralPath $Path).VersionInfo.FileVersion -ne $Release.Version) {
        throw "The installer must match the official UltraVNC $($Release.Version) x64 setup file."
    }
}

function Save-CaptureSettings {
    if (![TapMyPcIni]::WritePrivateProfileString('poll', 'MaxFPS', [string]$MaxFps, $config) -or
        ![TapMyPcIni]::WritePrivateProfileString('admin', 'RemoveWallpaper', [string][int](!$KeepWallpaper), $config)) {
        throw 'Could not save the Remote Desktop settings.'
    }
}

function Confirm-LoopbackListener {
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 300
        $listener = @(Get-NetTCPConnection -LocalPort 5900 -State Listen -ErrorAction SilentlyContinue)
    } until ($listener.Count -gt 0 -or [DateTime]::UtcNow -ge $deadline)
    if ($listener.Count -ne 1 -or $listener[0].LocalAddress -ne '127.0.0.1') {
        throw 'UltraVNC did not start with a loopback-only listener on port 5900.'
    }
    $owner = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener[0].OwningProcess)"
    if (!$owner -or $owner.ExecutablePath -ine $serverExe) {
        throw 'Another program is listening on port 5900.'
    }
}

$setupLock = [Threading.Mutex]::new($false, 'Global\TapMyPC.RemoteDesktop.Setup')
$lockHeld = $false
try {
    $chosenPassword = Connect-SetupPipe
    Report-SetupProgress 'Checking the UltraVNC service…'
    try { $lockHeld = $setupLock.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $lockHeld = $true }
    if (!$lockHeld) { throw 'Another Remote Desktop operation is already running.' }
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    $freshInstall = !$service
    $wasRunning = $service -and $service.Status -eq 'Running'
    $previousStartup = if ($service) { $service.StartType } else { 'Manual' }
    if ($freshInstall -and $Operation -ne 'Configure') { throw 'Set up Remote Desktop before managing the capture service.' }
    if ($Operation -eq 'Stop') {
        Report-SetupProgress 'Stopping Remote Desktop…'
        Confirm-ServicePath
        Set-Service -Name $serviceName -StartupType Manual
        Stop-UltraVnc
        exit 0
    }
    if ($freshInstall) {
        $setupStage = 'installing the capture service'
        if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
            throw 'Automatic capture service installation requires x64 Windows.'
        }
        if (Get-NetTCPConnection -LocalPort 5900 -State Listen -ErrorAction SilentlyContinue) {
            throw 'Another process is using port 5900. Stop it before setting up Remote Desktop.'
        }
        $stagingDir = Join-Path $programFiles ('TapMyPC-Setup-' + [Guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $stagingDir)
        $installer = Join-Path $stagingDir 'UltraVNC.exe'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $setupStage = 'checking the official UltraVNC release'
        Report-SetupProgress 'Checking for the latest stable UltraVNC release…'
        $release = Get-UltraVncRelease
        if ($script:hasLocalInstaller) {
            $setupStage = 'reading the selected UltraVNC installer'
            Receive-LocalInstaller $installer
        } else {
            $setupStage = "downloading UltraVNC $($release.Version)"
            Get-UltraVncInstaller $release $installer
        }
        $setupStage = "verifying UltraVNC $($release.Version)"
        Confirm-UltraVncInstaller $release $installer
        $setupStage = "installing UltraVNC $($release.Version)"
        Report-SetupProgress "Installing UltraVNC $($release.Version)…"

        $setup = Start-Process -FilePath $installer -ArgumentList @(
            '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',
            '/COMPONENTS=UltraVNC_Server','/TASKS=!installservice,!startservice'
        ) -WindowStyle Hidden -Wait -PassThru
        if ($setup.ExitCode -ne 0) {
            throw "UltraVNC setup returned error $($setup.ExitCode)."
        }
    }

    if (!(Test-UltraVncSignature $serverExe)) {
        throw 'The installed UltraVNC server signature could not be verified.'
    }
    $registered = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($registered) {
        Confirm-ServicePath
        $managedService = $true
        Set-Service -Name $serviceName -StartupType Manual
        Stop-UltraVnc
    }
    $setupStage = 'configuring UltraVNC firewall rules'
    Report-SetupProgress 'Applying the local-only service settings…'
    Disable-UltraVncFirewallRules
    $setupStage = 'saving local capture settings'
    $configParent = Get-Item -LiteralPath $configDir
    $configFile = Get-Item -LiteralPath $config
    if (!$configParent.PSIsContainer -or $configFile.PSIsContainer -or
        ($configParent.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        ($configFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The UltraVNC configuration path is unexpected.'
    }
    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public static class TapMyPcIni {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool WritePrivateProfileString(string section, string key, string value, string file);

    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool WritePrivateProfileStruct(string section, string key, byte[] value, uint size, string file);

    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
    public static extern uint GetPrivateProfileInt(string section, string key, int fallback, string file);

    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
    public static extern bool GetPrivateProfileStruct(string section, string key, byte[] value, uint size, string file);
}
"@
    Set-LoopbackConfiguration
    if ($freshInstall -or $Operation -eq 'Save') {
        Save-CaptureSettings
    }
    if ($freshInstall -and ![TapMyPcIni]::WritePrivateProfileString('admin', 'BlankMonitorEnabled', '0', $config)) {
        throw 'Could not save the default monitor setting.'
    }

    $passwordChanged = $false
    $storedPassword = [byte[]]::new(8)
    $hasPassword = [TapMyPcIni]::GetPrivateProfileStruct('UltraVNC', 'passwd', $storedPassword, $storedPassword.Length, $config) -and
        ($storedPassword | Where-Object { $_ -ne 0 } | Select-Object -First 1)
    [Array]::Clear($storedPassword, 0, $storedPassword.Length)
    if ($Operation -eq 'ResetPassword' -or $freshInstall -or !$hasPassword -or [TapMyPcIni]::GetPrivateProfileInt('TapMyPC', 'SetupPasswordPending', 0, $config) -eq 1) {
        Report-SetupProgress 'Saving the viewer password…'
        $newPassword = Set-ViewerPassword $chosenPassword
        $passwordChanged = $true
    }

    $setupStage = 'starting the local capture service'
    if ($wasRunning -or $Operation -in 'Configure', 'Start') { Report-SetupProgress 'Starting Remote Desktop…' }
    if (!$registered) {
        $registration = Start-Process -FilePath $serverExe -ArgumentList '-install' -WorkingDirectory $installDir -WindowStyle Hidden -Wait -PassThru
        if ($registration.ExitCode -ne 0) {
            throw 'Windows could not register the UltraVNC service.'
        }
        Confirm-ServicePath
        $managedService = $true
        Set-Service -Name $serviceName -StartupType Manual
    }
    if ($wasRunning -or $Operation -in 'Configure', 'Start') {
        Start-Service -Name $serviceName
        Report-SetupProgress 'Checking that Remote Desktop is listening locally…'
        Confirm-LoopbackListener
    }
    $nextStartup = if ($Operation -in 'Configure', 'Start') { 'Automatic' } else { $previousStartup }
    Set-Service -Name $serviceName -StartupType $nextStartup
    if ($passwordChanged -and (!$newPassword -or (Publish-SetupEvent @{ password = $newPassword }))) {
        [void][TapMyPcIni]::WritePrivateProfileString('TapMyPC', 'SetupPasswordPending', '0', $config)
    }
    exit 0
} catch {
    if ($managedService) {
        try { Stop-UltraVnc } catch { }
    }
    [void](Publish-SetupEvent @{ error = "Could not finish $setupStage. $($_.Exception.Message)" })
    exit 1
} finally {
    if ($installer -and (Test-Path -LiteralPath $installer)) {
        Remove-Item -LiteralPath $installer -ErrorAction SilentlyContinue
    }
    if ($stagingDir -and (Test-Path -LiteralPath $stagingDir) -and !(Get-ChildItem -LiteralPath $stagingDir -Force)) {
        Remove-Item -LiteralPath $stagingDir -ErrorAction SilentlyContinue
    }
    if ($lockHeld) { $setupLock.ReleaseMutex() }
    $setupLock.Dispose()
    if ($script:setupPipe) { $script:setupPipe.Dispose() }
}
