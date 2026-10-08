# Checks what is already installed, downloads only what is missing, then sets it up.
# Java: keep it when it is already the latest. Ask before replacing an older Java.
# Eclipse: remove an existing install, then install the web package
#          (Eclipse IDE for Enterprise Java and Web Developers, installer choice 2).
# Tomcat: ask for 9, 10.1, or the latest.
# Oracle 21c XE: install only when it is missing. Login id and password are both system.
# A notes file is written to the Downloads folder.
#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\dev',
    [string]$OracleInstallDir = 'C:\app\oracle\product\21.0.0',
    [string]$OracleZip,
    [switch]$SkipJava,
    [switch]$SkipEclipse,
    [switch]$SkipTomcat,
    [switch]$SkipOracle
)

$ErrorActionPreference = 'Continue'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch { }

$OracleZipName = 'OracleXE213_Win64.zip'
$OracleUrl = 'https://download.oracle.com/otn-pub/otn_software/OracleXE213_Win64.zip'
$OracleSha256 = '939742c3305c466566a55f607638621b6aa7033a183175f6bcd6cffb48e6bc3f'
$OracleDownloadPage = 'https://www.oracle.com/database/technologies/xe-downloads.html'
$OracleLogin = 'system'
$OraclePassword = 'system'
# The XE installer rejects "system". This is used only during setup, then changed.
$OracleInstallerPassword = 'System2026Temp'

$script:Report = New-Object System.Collections.Generic.List[string]
$script:Info = New-Object System.Collections.Generic.List[string]
$script:StopRequested = $false
$script:StopInProgress = $false
$script:NotesWritten = $false
$script:NotesPath = ''
$script:StepLabel = ''
$script:SetupStatePath = ''
$script:ChildLogIndex = 0
$script:LastChildErrLog = ''
$script:LastChildOutLog = ''
$script:ChildPids = New-Object System.Collections.Generic.List[int]
$script:UnfinishedFiles = New-Object System.Collections.Generic.List[string]
$script:UnfinishedDirs = New-Object System.Collections.Generic.List[string]
$script:CleanupLog = New-Object System.Collections.Generic.List[string]

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==== $Message ====" -ForegroundColor Cyan
}

function Add-Result {
    param([string]$Status, [string]$Message)
    $line = '{0,-6} {1}' -f $Status, $Message
    $script:Report.Add($line)
    if ($Status -eq 'OK') {
        Write-Host $line -ForegroundColor Green
    } elseif ($Status -eq 'SKIP') {
        Write-Host $line -ForegroundColor Yellow
    } else {
        Write-Host $line -ForegroundColor Red
    }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Relaunch-AsAdministrator {
    param($Bound)
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add('-NoProfile')
    $parts.Add('-ExecutionPolicy')
    $parts.Add('Bypass')
    $parts.Add('-File')
    $parts.Add('"{0}"' -f $PSCommandPath)
    foreach ($key in $Bound.Keys) {
        $value = $Bound[$key]
        if ($value -is [switch]) {
            if ($value.IsPresent) { $parts.Add("-$key") }
        } else {
            $parts.Add("-$key")
            $parts.Add('"{0}"' -f $value)
        }
    }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList ($parts -join ' ')
}

function Read-MenuChoice {
    param([string]$Title, [string[]]$Options)
    while ($true) {
        Write-Host ""
        Write-Host $Title
        for ($i = 0; $i -lt $Options.Count; $i++) {
            Write-Host ("  {0}  {1}" -f ($i + 1), $Options[$i])
        }
        $answer = Read-Host 'Type a number and press Enter'
        if ($script:StopRequested) { throw 'Setup was stopped.' }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Options.Count) {
            return $number
        }
        Write-Host "Type a number from 1 to $($Options.Count)." -ForegroundColor Yellow
    }
}

function Get-WingetPath {
    $command = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path $alias) { return $alias }

    $package = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($package) {
        $candidate = Join-Path $package.InstallLocation 'winget.exe'
        if (Test-Path $candidate) { return $candidate }
    }

    throw 'Windows Package Manager (winget) is not installed. Install App Installer from the Microsoft Store, then run this setup again. https://aka.ms/getwinget'
}

function Test-WingetIdInstalled {
    param([string]$Winget, [string]$Id)
    $output = & $Winget list --id $Id -e --accept-source-agreements --disable-interactivity 2>&1 | Out-String
    if ($output -match 'No installed package found' -or $output -match 'No package found') {
        return $false
    }
    return ($output -match [regex]::Escape($Id))
}

function Install-WingetId {
    param(
        [string]$Id,
        [string]$Label,
        [switch]$Force,
        [int]$ExpectedSeconds = 180
    )
    $winget = Get-WingetPath
    if (-not $Force -and (Test-WingetIdInstalled -Winget $winget -Id $Id)) {
        Write-Host "$Label is already installed."
        return $true
    }

    Write-Host "Downloading and installing $Label..."
    $argList = @(
        'install', '--id', $Id, '-e', '--silent',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
    )
    if ($Force) { $argList += '--force' }
    $progressLabel = $script:StepLabel
    if (-not $progressLabel) { $progressLabel = $Label }
    $process = Start-SetupProcess -FilePath $winget -ArgumentList $argList
    $exitCode = Wait-SetupProcess -Process $process -Label $progressLabel -ExpectedSeconds $ExpectedSeconds
    if ($exitCode -eq 0 -or (Test-WingetIdInstalled -Winget $winget -Id $Id)) {
        return $true
    }
    return $false
}

function Set-MachineVariable {
    param([string]$Name, [string]$Value)
    [Environment]::SetEnvironmentVariable($Name, $Value, 'Machine')
    Set-Item -Path "Env:$Name" -Value $Value
}

function Add-MachinePathEntry {
    param([string]$Directory)
    if (-not (Test-Path $Directory)) { return }
    $current = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if (-not $current) { $current = '' }
    foreach ($part in ($current -split ';')) {
        if ($part.TrimEnd('\') -ieq $Directory.TrimEnd('\')) { return }
    }
    $updated = $current.TrimEnd(';') + ';' + $Directory
    [Environment]::SetEnvironmentVariable('Path', $updated, 'Machine')
    $env:Path = $Directory + ';' + $env:Path
}

function Test-PortFree {
    param([int]$Port)
    $listener = $null
    try {
        $listener = New-Object System.Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        if ($listener) {
            try { $listener.Stop() } catch { }
        }
    }
}

function Get-FreeGigabytes {
    param([string]$DriveLetter)
    $drive = Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue
    if (-not $drive) { return 0 }
    return [math]::Round($drive.Free / 1GB, 1)
}

function Format-ElapsedText {
    param([double]$Seconds)
    if ($Seconds -lt 0) { $Seconds = 0 }
    $total = [int][math]::Floor($Seconds)
    $minutes = [math]::Floor($total / 60)
    $remain = $total % 60
    return ('{0}m {1:d2}s' -f $minutes, $remain)
}

function Format-ExpectedDetail {
    param([double]$ElapsedSeconds, [int]$ExpectedSeconds)
    $elapsedText = Format-ElapsedText $ElapsedSeconds
    if ($ExpectedSeconds -le 0) {
        return "elapsed $elapsedText  still working"
    }
    $left = $ExpectedSeconds - $ElapsedSeconds
    if ($left -le 0) {
        return "elapsed $elapsedText  past the usual time, still working"
    }
    $usualMin = [int][math]::Max(1, [math]::Round($ExpectedSeconds / 60.0))
    return "elapsed $elapsedText  about $(Format-ElapsedText $left) left  (usual time $usualMin min)"
}

function Write-SetupProgressLine {
    param(
        [string]$Label,
        [int]$Percent,
        [string]$Detail
    )
    if (-not $Label) { $Label = 'Working' }
    if ($Percent -lt 0) { $Percent = 0 }
    if ($Percent -gt 100) { $Percent = 100 }
    $width = 20
    $filled = [int][math]::Floor($width * $Percent / 100)
    if ($filled -gt $width) { $filled = $width }
    $bar = ('#' * $filled) + ('-' * ($width - $filled))
    $text = '{0}  [{1}] {2,3}%  {3}' -f $Label, $bar, $Percent, $Detail
    $consoleWidth = 100
    try {
        if ([Console]::WindowWidth -gt 20) { $consoleWidth = [Console]::WindowWidth - 1 }
    } catch { }
    if ($text.Length -gt $consoleWidth) {
        $text = $text.Substring(0, $consoleWidth)
    } else {
        $text = $text.PadRight($consoleWidth)
    }
    Write-Host ("`r" + $text) -NoNewline
}

function Clear-SetupProgressLine {
    Write-Host ''
}

function Assert-SetupContinue {
    if ($script:StopRequested) { throw 'Setup was stopped.' }
}

function Test-SetupStopped {
    param($Failure)
    if ($script:StopRequested) { return $true }
    if (-not $Failure) { return $false }
    $exception = $Failure.Exception
    if ($exception -is [System.Management.Automation.PipelineStoppedException]) { return $true }
    if ($exception -and $exception.Message -eq 'Setup was stopped.') { return $true }
    return $false
}

function ConvertTo-SetupStateJson {
    $children = (@($script:ChildPids) | ForEach-Object { [string]$_ }) -join ','
    $files = (@($script:UnfinishedFiles) | ForEach-Object {
        '"' + ($_.Replace('\', '\\').Replace('"', '\"')) + '"'
    }) -join ','
    $directories = (@($script:UnfinishedDirs) | ForEach-Object {
        '"' + ($_.Replace('\', '\\').Replace('"', '\"')) + '"'
    }) -join ','
    return '{"pid":' + $PID + ',"children":[' + $children + '],"files":[' + $files + '],"directories":[' + $directories + ']}'
}

function Save-SetupRunState {
    if (-not $script:SetupStatePath) { return }
    if ($script:ChildPids.Count -eq 0 -and $script:UnfinishedFiles.Count -eq 0 -and $script:UnfinishedDirs.Count -eq 0) {
        if (Test-Path -LiteralPath $script:SetupStatePath) {
            Remove-Item -LiteralPath $script:SetupStatePath -Force -ErrorAction SilentlyContinue
        }
        return
    }
    $parent = Split-Path $script:SetupStatePath -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -Path $script:SetupStatePath -Value (ConvertTo-SetupStateJson) -Encoding ASCII
}

function Add-UnfinishedFile {
    param([string]$Path)
    if (-not $Path) { return }
    if (-not $script:UnfinishedFiles.Contains($Path)) { [void]$script:UnfinishedFiles.Add($Path) }
    Save-SetupRunState
}

function Remove-UnfinishedFile {
    param([string]$Path)
    [void]$script:UnfinishedFiles.Remove($Path)
    Save-SetupRunState
}

function Add-UnfinishedDirectory {
    param([string]$Path)
    if (-not $Path) { return }
    if (-not $script:UnfinishedDirs.Contains($Path)) { [void]$script:UnfinishedDirs.Add($Path) }
    Save-SetupRunState
}

function Remove-UnfinishedDirectory {
    param([string]$Path)
    [void]$script:UnfinishedDirs.Remove($Path)
    Save-SetupRunState
}

function Register-ChildProcess {
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return }
    if (-not $script:ChildPids.Contains($ProcessId)) { [void]$script:ChildPids.Add($ProcessId) }
    Save-SetupRunState
}

function Unregister-ChildProcess {
    param([int]$ProcessId)
    [void]$script:ChildPids.Remove($ProcessId)
    Save-SetupRunState
}

function Remove-UnfinishedPath {
    param([string]$Path)
    if (-not $Path) { return }
    if ($Path -like '*oracle-password-pending.txt') {
        $oracleService = Get-Service -Name 'OracleServiceXE' -ErrorAction SilentlyContinue
        if ($oracleService) { return }
    }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    [void]$script:CleanupLog.Add($Path)
}

function Clear-UnfinishedWork {
    foreach ($procId in @($script:ChildPids)) {
        $child = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if ($child) {
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
            [void]$script:CleanupLog.Add("Stopped process $procId")
        }
    }
    $script:ChildPids.Clear()
    foreach ($file in @($script:UnfinishedFiles)) { Remove-UnfinishedPath -Path $file }
    $script:UnfinishedFiles.Clear()
    foreach ($dir in @($script:UnfinishedDirs)) { Remove-UnfinishedPath -Path $dir }
    $script:UnfinishedDirs.Clear()
    if ($script:SetupStatePath -and (Test-Path -LiteralPath $script:SetupStatePath)) {
        Remove-Item -LiteralPath $script:SetupStatePath -Force -ErrorAction SilentlyContinue
    }
}

function Complete-SetupRunState {
    $script:ChildPids.Clear()
    $script:UnfinishedFiles.Clear()
    $script:UnfinishedDirs.Clear()
    if ($script:SetupStatePath -and (Test-Path -LiteralPath $script:SetupStatePath)) {
        Remove-Item -LiteralPath $script:SetupStatePath -Force -ErrorAction SilentlyContinue
    }
}

function Clear-InterruptedSetup {
    if (-not $script:SetupStatePath -or -not (Test-Path -LiteralPath $script:SetupStatePath)) { return }
    $state = $null
    try {
        $state = Get-Content -LiteralPath $script:SetupStatePath -Raw -ErrorAction Stop | ConvertFrom-Json
    } catch {
        Remove-Item -LiteralPath $script:SetupStatePath -Force -ErrorAction SilentlyContinue
        return
    }
    $oldPid = 0
    try { $oldPid = [int]$state.pid } catch { }
    if ($oldPid -gt 0 -and $oldPid -ne $PID) {
        $alive = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
        if ($alive) {
            Write-Host "Another setup is still running (process $oldPid). Close it, then run this again." -ForegroundColor Yellow
            Read-Host 'Press Enter to close' | Out-Null
            exit 1
        }
    }
    foreach ($procId in @($state.children)) {
        if (-not $procId) { continue }
        $number = 0
        if (-not [int]::TryParse([string]$procId, [ref]$number)) { continue }
        if ($number -le 0) { continue }
        $child = Get-Process -Id $number -ErrorAction SilentlyContinue
        if ($child) {
            Stop-Process -Id $number -Force -ErrorAction SilentlyContinue
            [void]$script:CleanupLog.Add("Stopped process $number")
        }
    }
    foreach ($file in @($state.files)) { Remove-UnfinishedPath -Path ([string]$file) }
    foreach ($dir in @($state.directories)) { Remove-UnfinishedPath -Path ([string]$dir) }
    Remove-Item -LiteralPath $script:SetupStatePath -Force -ErrorAction SilentlyContinue
    if ($script:CleanupLog.Count -gt 0) {
        Write-Host 'Cleaned up unfinished files from a setup that was closed.' -ForegroundColor Yellow
        foreach ($line in $script:CleanupLog) { Write-Host "  $line" }
        $script:CleanupLog.Clear()
    }
}

function Start-SetupProcess {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList
    )
    Assert-SetupContinue
    $script:ChildLogIndex++
    $outLog = Join-Path $env:TEMP ("dev-setup-{0}-{1}.out.log" -f $PID, $script:ChildLogIndex)
    $errLog = Join-Path $env:TEMP ("dev-setup-{0}-{1}.err.log" -f $PID, $script:ChildLogIndex)
    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    $script:LastChildOutLog = $outLog
    $script:LastChildErrLog = $errLog
    Register-ChildProcess -ProcessId $process.Id
    return $process
}

function Wait-SetupProcess {
    param(
        $Process,
        [string]$Label,
        [int]$ExpectedSeconds = 60,
        [int]$TimeoutSeconds = 0
    )
    if (-not $Label) { $Label = 'Working' }
    $started = Get-Date
    try {
        while (-not $Process.HasExited) {
            if ($script:StopRequested) {
                Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
                [void]$script:CleanupLog.Add("Stopped process $($Process.Id)")
                throw 'Setup was stopped.'
            }
            $elapsed = ((Get-Date) - $started).TotalSeconds
            if ($TimeoutSeconds -gt 0 -and $elapsed -ge $TimeoutSeconds) {
                Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
                throw "Timed out after $TimeoutSeconds seconds."
            }
            $percent = 0
            if ($ExpectedSeconds -gt 0) {
                $percent = [int][math]::Min(95, [math]::Floor(($elapsed / $ExpectedSeconds) * 100))
            }
            Write-SetupProgressLine -Label $Label -Percent $percent -Detail (Format-ExpectedDetail -ElapsedSeconds $elapsed -ExpectedSeconds $ExpectedSeconds)
            Start-Sleep -Seconds 1
        }
    } finally {
        Unregister-ChildProcess -ProcessId $Process.Id
        Clear-SetupProgressLine
    }
    return $Process.ExitCode
}

function Write-DownloadProgress {
    param(
        [string]$Label,
        [int64]$Received,
        [int64]$Total,
        [double]$ElapsedSeconds,
        [double]$BytesPerSecond
    )
    $elapsedText = Format-ElapsedText $ElapsedSeconds
    $speedText = 'speed starting...'
    if ($BytesPerSecond -ge 1) {
        $megabytes = $BytesPerSecond / 1MB
        if ($megabytes -ge 10) { $speedText = '{0:N0} MB/s' -f $megabytes }
        else { $speedText = '{0:N1} MB/s' -f $megabytes }
    }
    $percent = 0
    $leftText = ''
    if ($Total -gt 0) {
        $percent = [int][math]::Min(99, [math]::Floor(100.0 * $Received / $Total))
        if ($Received -ge $Total) { $percent = 100 }
        if ($BytesPerSecond -ge 1 -and $Received -lt $Total) {
            $leftText = '  about ' + (Format-ElapsedText (($Total - $Received) / $BytesPerSecond)) + ' left'
        }
    }
    Write-SetupProgressLine -Label $Label -Percent $percent -Detail "$speedText  elapsed $elapsedText$leftText"
}

function Get-RemoteContentLength {
    param([string]$Url, [string]$Cookie)
    $curlArgs = @('-sI', '-L', '--max-time', '20', '--retry', '2')
    if ($Cookie) { $curlArgs += @('-A', 'Mozilla/5.0', '-b', $Cookie) }
    $curlArgs += $Url
    $length = [int64]0
    try {
        $text = (& curl.exe @curlArgs 2>$null | Out-String)
        if ($text) {
            foreach ($line in ($text -split '\r?\n')) {
                if ($line -match '(?i)^Content-Length:\s*(\d+)') {
                    $length = [int64]$Matches[1]
                }
            }
        }
    } catch { }
    return $length
}

function Get-ChildErrorTail {
    if (-not $script:LastChildErrLog -or -not (Test-Path -LiteralPath $script:LastChildErrLog)) { return '' }
    $tail = @(Get-Content -LiteralPath $script:LastChildErrLog -Tail 3 -ErrorAction SilentlyContinue)
    return ($tail -join ' ').Trim()
}

function Save-RemoteFile {
    param(
        [string]$Url,
        [string]$Destination,
        [string]$Cookie,
        [string]$Label,
        [int64]$FallbackBytes = 0
    )
    if (-not $Label) { $Label = $script:StepLabel }
    if (-not $Label) { $Label = 'Download' }
    Assert-SetupContinue
    $destinationDir = Split-Path $Destination -Parent
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
    $partial = "$Destination.partial"
    if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
    Add-UnfinishedFile -Path $partial

    Write-Host 'Checking download size...'
    $total = Get-RemoteContentLength -Url $Url -Cookie $Cookie
    if ($total -le 0) { $total = $FallbackBytes }

    $curlArgs = @('-L', '--fail', '--retry', '3', '--retry-delay', '2', '-s', '-S', '-o', $partial)
    if ($Cookie) { $curlArgs += @('-A', 'Mozilla/5.0', '-b', $Cookie) }
    $curlArgs += $Url
    $process = Start-SetupProcess -FilePath 'curl.exe' -ArgumentList $curlArgs
    $started = Get-Date
    $samples = New-Object System.Collections.Generic.List[object]
    try {
        while (-not $process.HasExited) {
            if ($script:StopRequested) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                [void]$script:CleanupLog.Add("Stopped process $($process.Id)")
                throw 'Setup was stopped.'
            }
            $received = [int64]0
            if (Test-Path -LiteralPath $partial) { $received = [int64](Get-Item -LiteralPath $partial).Length }
            $now = Get-Date
            $samples.Add([pscustomobject]@{ At = $now; Bytes = $received })
            while ($samples.Count -gt 5) { $samples.RemoveAt(0) }
            $speed = 0.0
            if ($samples.Count -ge 2) {
                $first = $samples[0]
                $last = $samples[$samples.Count - 1]
                $span = ($last.At - $first.At).TotalSeconds
                if ($span -ge 0.5 -and $last.Bytes -ge $first.Bytes) {
                    $speed = ($last.Bytes - $first.Bytes) / $span
                }
            }
            Write-DownloadProgress -Label $Label -Received $received -Total $total -ElapsedSeconds (($now - $started).TotalSeconds) -BytesPerSecond $speed
            Start-Sleep -Seconds 1
        }
    } catch {
        Unregister-ChildProcess -ProcessId $process.Id
        Clear-SetupProgressLine
        if (-not (Test-SetupStopped $_)) {
            if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
            Remove-UnfinishedFile -Path $partial
        }
        throw
    }

    Unregister-ChildProcess -ProcessId $process.Id
    Clear-SetupProgressLine
    if ($script:StopRequested) { throw 'Setup was stopped.' }
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $partial)) {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
        Remove-UnfinishedFile -Path $partial
        $errTail = Get-ChildErrorTail
        if ($errTail) { throw "Download failed for $Url. $errTail" }
        throw "Download failed for $Url"
    }
    Move-Item -LiteralPath $partial -Destination $Destination -Force
    Remove-UnfinishedFile -Path $partial
}

function Test-FileHashMatch {
    param(
        [string]$Path,
        [string]$Algorithm,
        [string]$Expected,
        [int]$ExpectedSeconds = 60
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    Assert-SetupContinue
    $label = $script:StepLabel
    if (-not $label) { $label = 'Check file' }
    Write-Host 'Checking the downloaded file...'
    $shell = [powershell]::Create()
    [void]$shell.AddScript({
        param($filePath, $hashAlgorithm)
        (Get-FileHash -LiteralPath $filePath -Algorithm $hashAlgorithm).Hash
    }).AddArgument($Path).AddArgument($Algorithm)
    $handle = $shell.BeginInvoke()
    $started = Get-Date
    try {
        while (-not $handle.IsCompleted) {
            if ($script:StopRequested) {
                try { $shell.Stop() } catch { }
                throw 'Setup was stopped.'
            }
            $elapsed = ((Get-Date) - $started).TotalSeconds
            $percent = 0
            if ($ExpectedSeconds -gt 0) {
                $percent = [int][math]::Min(95, [math]::Floor(($elapsed / $ExpectedSeconds) * 100))
            }
            Write-SetupProgressLine -Label $label -Percent $percent -Detail (Format-ExpectedDetail -ElapsedSeconds $elapsed -ExpectedSeconds $ExpectedSeconds)
            Start-Sleep -Seconds 1
        }
        $result = @($shell.EndInvoke($handle))
        if ($shell.Streams.Error.Count -gt 0) { return $false }
        $actual = [string]$result[0]
        return ($actual -eq $Expected)
    } finally {
        Clear-SetupProgressLine
        $shell.Dispose()
    }
}

function Find-SavedFile {
    param([string]$FileName, [string]$DownloadsDirectory)
    $places = @(
        (Join-Path $DownloadsDirectory $FileName),
        (Join-Path (Join-Path $env:USERPROFILE 'Downloads') $FileName),
        (Join-Path $PSScriptRoot $FileName)
    )
    foreach ($place in $places) {
        if ($place -and (Test-Path $place)) {
            return (Resolve-Path $place).Path
        }
    }
    return $null
}

function Get-JdkDetails {
    param([string]$JdkPath)
    $releaseFile = Join-Path $JdkPath 'release'
    $javaExe = Join-Path $JdkPath 'bin\java.exe'
    if (-not (Test-Path $javaExe)) { return $null }
    $feature = 0
    $version = ''
    if (Test-Path $releaseFile) {
        $match = Select-String -Path $releaseFile -Pattern 'JAVA_VERSION="(\d+)([^"]*)"' | Select-Object -First 1
        if ($match) {
            $raw = $match.Matches[0].Groups[1].Value + $match.Matches[0].Groups[2].Value
            if ($raw -match '^1\.(\d+)') {
                $feature = [int]$Matches[1]
            } else {
                $feature = [int]$match.Matches[0].Groups[1].Value
            }
            $version = $raw
        }
    }
    if ($feature -eq 0) { return $null }
    return [pscustomobject]@{
        Home = $JdkPath
        Feature = $feature
        Version = $version
    }
}

function Get-InstalledJdks {
    $roots = @(
        'C:\Program Files\Eclipse Adoptium',
        'C:\Program Files\Java',
        'C:\Program Files\Microsoft',
        'C:\Program Files\Amazon Corretto',
        'C:\Program Files\Zulu',
        'C:\Program Files\BellSoft'
    )
    $homes = New-Object System.Collections.Generic.List[string]
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $homes.Add($_.FullName)
        }
    }
    if ($env:JAVA_HOME) { $homes.Add($env:JAVA_HOME) }

    $found = @()
    $seen = @{}
    foreach ($jdkPath in $homes) {
        if (-not $jdkPath) { continue }
        $key = $jdkPath.TrimEnd('\').ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $details = Get-JdkDetails -JdkPath $jdkPath
        if ($details) { $found += $details }
    }
    return $found | Sort-Object Feature, Version -Descending
}

function Get-LatestJavaFeature {
    try {
        $info = Invoke-RestMethod -Uri 'https://api.adoptium.net/v3/info/available_releases' -UseBasicParsing
        $latest = [int]$info.most_recent_feature_release
        if ($latest -gt 0) { return $latest }
    } catch {
        Write-Host "Could not reach Adoptium. Using Java 27 as the latest release." -ForegroundColor Yellow
    }
    return 27
}

function Find-JdkByFeature {
    param([int]$Feature)
    $match = Get-InstalledJdks | Where-Object { $_.Feature -eq $Feature } | Select-Object -First 1
    if ($match) { return $match.Home }
    return $null
}

function Install-JdkFeature {
    param([int]$Feature, [string]$DownloadsDirectory)
    $packageId = "EclipseAdoptium.Temurin.$Feature.JDK"
    $winget = Get-WingetPath
    & $winget show --id $packageId -e --accept-source-agreements --disable-interactivity | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $installed = Install-WingetId -Id $packageId -Label "Temurin JDK $Feature" -ExpectedSeconds 300
        if (-not $installed) { throw "winget could not install $packageId." }
        return
    }

    $pattern = "OpenJDK${Feature}U-jdk_x64_windows_hotspot*.msi"
    $existing = $null
    foreach ($dir in @($DownloadsDirectory, (Join-Path $env:USERPROFILE 'Downloads'), $PSScriptRoot)) {
        if (-not (Test-Path $dir)) { continue }
        $hit = Get-ChildItem $dir -File -Filter $pattern -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($hit -and $hit.Length -gt 20MB) {
            $existing = $hit.FullName
            break
        }
    }

    $msi = $existing
    if (-not $msi) {
        $msi = Join-Path $DownloadsDirectory "OpenJDK${Feature}U-jdk_x64_windows_hotspot.msi"
        $url = "https://api.adoptium.net/v3/installer/latest/$Feature/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk"
        Write-Host "The winget package was not found. Downloading the JDK $Feature installer..."
        Save-RemoteFile -Url $url -Destination $msi
    } else {
        Write-Host "Using the JDK installer that is already downloaded:"
        Write-Host "  $msi"
    }

    if ((Get-Item $msi).Length -lt 20MB) {
        throw 'The JDK download is not a real installer.'
    }
    $process = Start-SetupProcess -FilePath 'msiexec.exe' -ArgumentList @('/i', $msi, '/qn', '/norestart')
    $exitCode = Wait-SetupProcess -Process $process -Label $script:StepLabel -ExpectedSeconds 120
    if ($exitCode -ne 0 -and $exitCode -ne 3010) {
        throw "The JDK installer failed with exit code $exitCode."
    }
}

function Resolve-EclipseExecutable {
    param($Item)
    if (-not $Item) { return $null }
    if ($Item.LinkType -and $Item.Target) {
        $target = @($Item.Target) | Select-Object -First 1
        if ($target -and (Test-Path -LiteralPath $target)) {
            return Get-Item -LiteralPath $target
        }
    }
    return $Item
}

function Find-EclipseExecutable {
    $direct = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\eclipse.exe'),
        (Join-Path $env:ProgramFiles 'WinGet\Links\eclipse.exe')
    )
    foreach ($path in $direct) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return Resolve-EclipseExecutable (Get-Item -LiteralPath $path)
        }
    }

    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'),
        (Join-Path $env:ProgramFiles 'WinGet\Packages'),
        (Join-Path ${env:ProgramFiles(x86)} 'WinGet\Packages'),
        "$env:ProgramFiles\Eclipse Foundation",
        "${env:ProgramFiles(x86)}\Eclipse Foundation",
        "$env:LOCALAPPDATA\Programs",
        "$env:LOCALAPPDATA\Eclipse",
        "$env:USERPROFILE\eclipse",
        "$env:USERPROFILE\Eclipse"
    )
    $found = @()
    foreach ($root in $roots) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        $found += Get-ChildItem -Path $root -Filter 'eclipse.exe' -Recurse -Depth 6 -ErrorAction SilentlyContinue
    }

    $shortcutRoots = @(
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:PUBLIC 'Desktop'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
    )
    $shell = $null
    foreach ($root in $shortcutRoots) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        if (-not $shell) { $shell = New-Object -ComObject WScript.Shell }
        Get-ChildItem $root -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $shortcut = $shell.CreateShortcut($_.FullName)
                if ($shortcut.TargetPath -match 'eclipse\.exe$' -and (Test-Path -LiteralPath $shortcut.TargetPath)) {
                    $found += Get-Item -LiteralPath $shortcut.TargetPath
                }
            } catch { }
        }
    }

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($root in $uninstallRoots) {
        Get-ItemProperty $root -ErrorAction SilentlyContinue | ForEach-Object {
            $location = $_.InstallLocation
            if ($location) {
                $candidate = Join-Path $location 'eclipse.exe'
                if (Test-Path -LiteralPath $candidate) { $found += Get-Item -LiteralPath $candidate }
                $nested = Join-Path $location 'eclipse\eclipse.exe'
                if (Test-Path -LiteralPath $nested) { $found += Get-Item -LiteralPath $nested }
            }
            if ($_.DisplayIcon -match '^(.*eclipse\.exe)') {
                $iconPath = $Matches[1].Trim('"')
                if (Test-Path -LiteralPath $iconPath) { $found += Get-Item -LiteralPath $iconPath }
            }
        }
    }

    $resolved = @()
    foreach ($item in $found) {
        $exe = Resolve-EclipseExecutable $item
        if ($exe) { $resolved += $exe }
    }
    return $resolved | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Remove-EclipseCompletely {
    Get-Process -Name 'eclipse' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $winget = Get-WingetPath
    $installedList = & $winget list --accept-source-agreements --disable-interactivity 2>&1 | Out-String
    $packageIds = @(
        'EclipseFoundation.Eclipse.JEE',
        'EclipseFoundation.Eclipse.Java',
        'EclipseFoundation.Eclipse.CPP',
        'EclipseFoundation.Eclipse.EmbedCPP',
        'EclipseFoundation.Eclipse.Committers',
        'EclipseFoundation.Eclipse.RCP',
        'EclipseFoundation.Eclipse.DSL',
        'EclipseFoundation.Eclipse.Modeling',
        'EclipseFoundation.Eclipse.Scout',
        'EclipseFoundation.Eclipse.PHP'
    )
    foreach ($packageId in $packageIds) {
        if ($installedList -notmatch [regex]::Escape($packageId)) { continue }
        Write-Host "Uninstalling $packageId..."
        & $winget uninstall --id $packageId -e --silent --purge --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            & $winget uninstall --id $packageId -e --silent --accept-source-agreements --disable-interactivity
        }
    }

    $eclipseExe = Find-EclipseExecutable
    while ($eclipseExe) {
        $folder = $eclipseExe.Directory.FullName
        Write-Host "Removing leftover Eclipse folder:"
        Write-Host "  $folder"
        Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
        $eclipseExe = Find-EclipseExecutable
        if ($eclipseExe -and $eclipseExe.Directory.FullName -eq $folder) { break }
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcutRoots = @(
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:PUBLIC 'Desktop'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
    )
    foreach ($root in $shortcutRoots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $shortcut = $shell.CreateShortcut($_.FullName)
                if ($shortcut.TargetPath -match 'eclipse\.exe$') {
                    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                }
            } catch { }
        }
    }
}

function Set-EclipseJavaVm {
    param([string]$IniPath, [string]$JavawPath)
    $lines = @(Get-Content -Path $IniPath)
    $clean = New-Object System.Collections.Generic.List[string]
    $skipNext = $false
    foreach ($line in $lines) {
        if ($skipNext) {
            $skipNext = $false
            continue
        }
        if ($line.Trim() -eq '-vm') {
            $skipNext = $true
            continue
        }
        $clean.Add($line)
    }

    $output = New-Object System.Collections.Generic.List[string]
    $inserted = $false
    foreach ($line in $clean) {
        if (-not $inserted -and $line.Trim() -eq '-vmargs') {
            $output.Add('-vm')
            $output.Add($JavawPath)
            $inserted = $true
        }
        $output.Add($line)
    }
    if (-not $inserted) {
        $output.Insert(0, $JavawPath)
        $output.Insert(0, '-vm')
    }
    Set-Content -Path $IniPath -Value $output.ToArray() -Encoding ASCII
}

function New-DesktopShortcut {
    param([string]$Name, [string]$TargetPath, [string]$WorkingDirectory)
    $shell = New-Object -ComObject WScript.Shell
    foreach ($desktop in @((Join-Path $env:USERPROFILE 'Desktop'), (Join-Path $env:PUBLIC 'Desktop'))) {
        if (-not (Test-Path $desktop)) { continue }
        $shortcut = $shell.CreateShortcut((Join-Path $desktop "$Name.lnk"))
        $shortcut.TargetPath = $TargetPath
        $shortcut.WorkingDirectory = $WorkingDirectory
        $shortcut.Save()
    }
}

function Get-TomcatCatalog {
    return @(
        [pscustomobject]@{
            Key = '9'
            Label = 'Tomcat 9 (9.0.122, javax.servlet)'
            Version = '9.0.122'
            MajorPath = '9'
            RuntimeName = 'Apache Tomcat v9.0'
            Servlet = 'javax.servlet'
            ServiceName = 'DevTomcat9'
            Sha512 = '0a899d7aa42a0c563c3df282b5b5f597db9718221b211fec40343f8938dca39c7d3ae25e29ffabe519af9e089e25a2c3b062f1f8dddd7c0977d487ebb6175d78'
        },
        [pscustomobject]@{
            Key = '10.1'
            Label = 'Tomcat 10.1 (10.1.60, jakarta.servlet)'
            Version = '10.1.60'
            MajorPath = '10'
            RuntimeName = 'Apache Tomcat v10.1'
            Servlet = 'jakarta.servlet'
            ServiceName = 'DevTomcat10'
            Sha512 = '0ce586fb15b528d417ef4dd0e479529c9c92fe19f3942be239aa098fd99e14e7b76c96046258f400fa25c239fbba55a1509d046db17846e6144d4feeb17d32e4'
        },
        [pscustomobject]@{
            Key = 'latest'
            Label = 'Latest (Tomcat 11.0.26, jakarta.servlet)'
            Version = '11.0.26'
            MajorPath = '11'
            RuntimeName = 'Apache Tomcat v11.0'
            Servlet = 'jakarta.servlet'
            ServiceName = 'DevTomcat11'
            Sha512 = '13e866438d5732dbe35ca4dbd0eb668255f158c96e81dff092dff153b537ac8f20006c3e86b0ff5df8c7c5cc07be28dceb223592318de37378d85de07c5fdbc1'
        }
    )
}

function Get-InstalledTomcatVersion {
    param([string]$TomcatHome)
    $notes = Join-Path $TomcatHome 'RELEASE-NOTES'
    if (-not (Test-Path $notes)) { return $null }
    $match = Select-String -Path $notes -Pattern 'Apache Tomcat Version (\d+\.\d+\.\d+)' | Select-Object -First 1
    if ($match) { return $match.Matches[0].Groups[1].Value }
    return $null
}

function Remove-ManagedTomcatService {
    param([string]$TomcatHome)
    foreach ($name in @('DevTomcat', 'DevTomcat9', 'DevTomcat10', 'DevTomcat11')) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $service) { continue }
        if ($service.Status -eq 'Running') {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
        }
        $serviceBat = Join-Path $TomcatHome 'bin\service.bat'
        if (Test-Path $serviceBat) {
            Push-Location (Split-Path $serviceBat -Parent)
            try { & cmd.exe /c "service.bat uninstall $name" } finally { Pop-Location }
        }
        & sc.exe delete $name | Out-Null
    }
}

function Test-DirectAdministrator {
    try {
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $members = Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop
        foreach ($member in $members) {
            if ($member.SID -eq $me) { return $true }
        }
        return $false
    } catch {
        return $null
    }
}

function Clear-OracleInstallerVariables {
    foreach ($scope in @('Process', 'User', 'Machine')) {
        foreach ($name in @('ORACLE_HOME', 'TNS_ADMIN')) {
            $current = [Environment]::GetEnvironmentVariable($name, $scope)
            if ($current) {
                Write-Host "Removing $scope variable $name so the Oracle installer can run."
                [Environment]::SetEnvironmentVariable($name, $null, $scope)
            }
        }
    }
    Remove-Item Env:ORACLE_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:TNS_ADMIN -ErrorAction SilentlyContinue
}

function Get-ListenerPort {
    param([string]$OracleHome, [int]$Fallback)
    $lsnrctl = Join-Path $OracleHome 'bin\lsnrctl.exe'
    if (-not (Test-Path $lsnrctl)) { return $Fallback }
    $env:ORACLE_HOME = $OracleHome
    $status = & $lsnrctl status 2>&1 | Out-String
    $match = [regex]::Match($status, 'PORT\s*=\s*(\d+)')
    if ($match.Success) { return [int]$match.Groups[1].Value }
    return $Fallback
}

function Set-OraclePasswordToSystem {
    param(
        [string]$OracleHome,
        [int]$Port,
        [string]$InstallerPassword
    )
    $sqlplus = Join-Path $OracleHome 'bin\sqlplus.exe'
    if (-not (Test-Path $sqlplus)) { throw 'sqlplus.exe was not found.' }

    $sqlFile = Join-Path $env:TEMP 'set-oracle-system-login.sql'
    $sqlLines = @(
        'WHENEVER SQLERROR CONTINUE',
        'ALTER PROFILE DEFAULT LIMIT PASSWORD_VERIFY_FUNCTION NULL;',
        'ALTER PROFILE DEFAULT LIMIT PASSWORD_LIFE_TIME UNLIMITED;',
        'WHENEVER SQLERROR EXIT SQL.SQLCODE',
        'ALTER USER SYS IDENTIFIED BY "system";',
        'ALTER USER SYSTEM IDENTIFIED BY "system";',
        'ALTER PLUGGABLE DATABASE ALL OPEN;',
        'ALTER SESSION SET CONTAINER=XEPDB1;',
        'WHENEVER SQLERROR CONTINUE',
        'ALTER PROFILE DEFAULT LIMIT PASSWORD_VERIFY_FUNCTION NULL;',
        'ALTER PROFILE DEFAULT LIMIT PASSWORD_LIFE_TIME UNLIMITED;',
        'WHENEVER SQLERROR EXIT SQL.SQLCODE',
        'ALTER USER SYSTEM IDENTIFIED BY "system";',
        'ALTER USER PDBADMIN IDENTIFIED BY "system";',
        'EXIT'
    )
    Set-Content -Path $sqlFile -Value $sqlLines -Encoding ASCII

    $env:ORACLE_HOME = $OracleHome
    $env:ORACLE_SID = 'XE'
    $connect = "sys/$InstallerPassword@//127.0.0.1:${Port}/XE as sysdba"
    $ok = $false
    try {
        for ($try = 1; $try -le 12; $try++) {
            Assert-SetupContinue
            Write-Host "Setting the Oracle login to system/system (try $try of 12)..."
            & $sqlplus -s $connect "@$sqlFile"
            if ($LASTEXITCODE -eq 0) {
                $ok = $true
                break
            }
            for ($second = 0; $second -lt 15; $second++) {
                if ($script:StopRequested) { throw 'Setup was stopped.' }
                Start-Sleep -Seconds 1
            }
        }
    } finally {
        Remove-Item $sqlFile -Force -ErrorAction SilentlyContinue
    }
    if (-not $ok) {
        throw 'Oracle installed, but the login could not be changed to system/system yet. Try again after the database has finished starting.'
    }
}

function Write-SetupNotes {
    if ($script:NotesWritten) { return }
    if (-not $userDownloads) { return }
    $script:NotesWritten = $true
    $infoPath = Join-Path $userDownloads 'dev-setup-info.txt'
    $script:NotesPath = $infoPath
    $shownListener = if ($listenerPort -eq 0) { 1521 } else { $listenerPort }
    $shownEm = if ($emPort -eq 0) { 5550 } else { $emPort }

    $script:Info.Add("Java, Eclipse, Tomcat, and Oracle setup")
    $script:Info.Add("Saved: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    $script:Info.Add("PC: $osCaption")
    $script:Info.Add("This file: $infoPath")
    $script:Info.Add('')
    $script:Info.Add('JAVA')
    if ($jdkHome) {
        $script:Info.Add("Version: $jdkVersionText")
        $script:Info.Add("JAVA_HOME: $jdkHome")
        $script:Info.Add("java.exe: $(Join-Path $jdkHome 'bin\java.exe')")
    } else {
        $script:Info.Add('Java was not set up.')
    }
    $script:Info.Add('')
    $script:Info.Add('ECLIPSE')
    $script:Info.Add('Package: Eclipse IDE for Enterprise Java and Web Developers')
    $script:Info.Add('Installer choice: 2, web development')
    if ($eclipsePath) {
        $script:Info.Add("eclipse.exe: $eclipsePath")
    } else {
        $script:Info.Add('Eclipse path was not found.')
    }
    $script:Info.Add('')
    $script:Info.Add('TOMCAT')
    if ($tomcatVersionText) {
        $script:Info.Add("Version: $tomcatVersionText")
        $script:Info.Add("CATALINA_HOME: $tomcatHome")
        $script:Info.Add("Home page: http://127.0.0.1:$tomcatPort/")
        $script:Info.Add("Manager page: http://127.0.0.1:$tomcatPort/manager/html")
        if ($installTomcat) {
            $script:Info.Add("Manager id: $tomcatUser")
            $script:Info.Add("Manager password: $tomcatPassword")
        } else {
            $script:Info.Add('Manager id and password were left as they were.')
        }
        if ($tomcatServlet) { $script:Info.Add("Servlet API: $tomcatServlet") }
        $script:Info.Add("Start: $(Join-Path $InstallRoot 'Start-Tomcat.cmd')")
        $script:Info.Add("Stop: $(Join-Path $InstallRoot 'Stop-Tomcat.cmd')")
        $script:Info.Add("Eclipse server type: $tomcatRuntimeName")
    } else {
        $script:Info.Add('Tomcat was not set up.')
    }
    $script:Info.Add('')
    $script:Info.Add('ORACLE DATABASE 21c XE')
    if ($oraclePasswordForNotes) {
        $script:Info.Add("Status: $oracleNote")
        $script:Info.Add("Login id: $OracleLogin")
        $script:Info.Add("Password: $oraclePasswordForNotes")
        $script:Info.Add("ORACLE_HOME: $oracleHome")
        $script:Info.Add("Listener port: $shownListener")
        $script:Info.Add("Service name: XEPDB1")
        $script:Info.Add("JDBC URL: jdbc:oracle:thin:@//127.0.0.1:${shownListener}/XEPDB1")
        $script:Info.Add("SQL*Plus: sqlplus ${OracleLogin}/${oraclePasswordForNotes}@//127.0.0.1:${shownListener}/XEPDB1")
        $script:Info.Add("EM Express: https://127.0.0.1:${shownEm}/em")
        $jdbc = Get-ChildItem (Join-Path $oracleHome 'jdbc\lib') -Filter 'ojdbc*.jar' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($jdbc) { $script:Info.Add("JDBC driver: $($jdbc.FullName)") }
    } else {
        $script:Info.Add("Status: $oracleNote")
        if ($oracleHome) { $script:Info.Add("ORACLE_HOME: $oracleHome") }
    }
    $script:Info.Add('')
    $script:Info.Add('ADD TOMCAT IN ECLIPSE')
    $script:Info.Add('1. Open Eclipse and choose a workspace.')
    $script:Info.Add('2. Window > Preferences > Server > Runtime Environments > Add.')
    $script:Info.Add("3. Choose $tomcatRuntimeName, then Next.")
    $script:Info.Add("4. Set the directory to $tomcatHome and choose the JDK shown above.")
    $script:Info.Add('5. Finish. Then File > New > Other > Server, and choose the same Tomcat version.')
    $script:Info.Add('')
    $script:Info.Add('SETUP RESULT')
    $script:Report | ForEach-Object { $script:Info.Add($_) }

    Set-Content -Path $infoPath -Value $script:Info.ToArray() -Encoding ASCII
    try {
        $account = "$env:USERDOMAIN\$env:USERNAME"
        & icacls.exe $infoPath /inheritance:r /grant:r "${account}:(R,W)" | Out-Null
    } catch {
        Write-Host "Could not lock down $infoPath." -ForegroundColor Yellow
    }
}

function Stop-Setup {
    param([switch]$Cancelled)
    if ($script:StopInProgress) { exit 1 }
    $script:StopInProgress = $true
    $script:StopRequested = $true
    Clear-SetupProgressLine
    Clear-UnfinishedWork
    if ($Cancelled) {
        $already = $false
        foreach ($line in $script:Report) {
            if ($line -match 'Setup was stopped') { $already = $true }
        }
        if (-not $already) { Add-Result 'FAIL' 'Setup was stopped.' }
    }
    try { Write-SetupNotes } catch { }
    Write-Host ''
    if ($Cancelled) {
        Write-Host 'Setup was stopped.' -ForegroundColor Yellow
    } else {
        Write-Host 'Setup stopped because a step failed.' -ForegroundColor Red
    }
    if ($script:CleanupLog.Count -gt 0) {
        Write-Host 'Cleaned up:'
        foreach ($line in $script:CleanupLog) { Write-Host "  $line" }
    }
    Write-Host ''
    Write-Host '==== Summary ====' -ForegroundColor Cyan
    $script:Report | ForEach-Object { Write-Host $_ }
    if ($script:NotesPath) {
        Write-Host ''
        Write-Host 'Paths, ids, and passwords were saved to:'
        Write-Host "  $($script:NotesPath)"
    }
    Write-Host ''
    try { Read-Host 'Press Enter to close' | Out-Null } catch { }
    exit 1
}

function Resolve-SetupFailure {
    param($Failure)
    if (Test-SetupStopped $Failure) { Stop-Setup -Cancelled }
    Add-Result 'FAIL' $Failure.Exception.Message
    Stop-Setup
}

function Register-SetupCancelKey {
    try {
        [Console]::TreatControlCAsInput = $false
        $null = [Console]::add_CancelKeyPress({
            param($sender, $eventArgs)
            $eventArgs.Cancel = $true
            $script:StopRequested = $true
            foreach ($procId in @($script:ChildPids)) {
                try { Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue } catch { }
            }
        })
    } catch { }
}

$setupStopSource = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

public class SetupStop {
    public delegate bool ControlHandler(int ctrlType);

    [DllImport("Kernel32")]
    public static extern bool SetConsoleCtrlHandler(ControlHandler handler, bool add);

    public static string StatePath;
    public static ControlHandler Handler;

    public static void Install() {
        Handler = new ControlHandler(OnSignal);
        SetConsoleCtrlHandler(Handler, true);
    }

    public static bool OnSignal(int ctrlType) {
        if (ctrlType == 2 || ctrlType == 5 || ctrlType == 6) {
            Cleanup();
            return true;
        }
        return false;
    }

    public static void Cleanup() {
        try {
            if (string.IsNullOrEmpty(StatePath) || !File.Exists(StatePath)) return;
            string text = File.ReadAllText(StatePath);
            KillChildren(text);
            DeletePaths(text, "files");
            DeletePaths(text, "directories");
            try { File.Delete(StatePath); } catch { }
        } catch { }
    }

    static void KillChildren(string text) {
        Match block = Regex.Match(text, "\"children\"\\s*:\\s*\\[([^\\]]*)\\]");
        if (!block.Success) return;
        foreach (Match n in Regex.Matches(block.Groups[1].Value, "\\d+")) {
            try {
                Process.GetProcessById(int.Parse(n.Value)).Kill();
            } catch { }
        }
    }

    static void DeletePaths(string text, string key) {
        Match block = Regex.Match(text, "\"" + key + "\"\\s*:\\s*\\[([^\\]]*)\\]");
        if (!block.Success) return;
        foreach (Match p in Regex.Matches(block.Groups[1].Value, "\"((?:\\\\\\\\|[^\"])*)\"")) {
            string path = p.Groups[1].Value.Replace("\\\\", "\\");
            try {
                if (Directory.Exists(path)) Directory.Delete(path, true);
                else if (File.Exists(path)) File.Delete(path);
            } catch { }
        }
    }
}
'@

try { Add-Type -TypeDefinition $setupStopSource } catch { }
Register-SetupCancelKey

trap {
    if ($script:StopInProgress) { break }
    $stopped = $script:StopRequested
    if (-not $stopped -and $_.Exception) {
        if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { $stopped = $true }
        elseif ($_.Exception.Message -eq 'Setup was stopped.') { $stopped = $true }
    }
    if ($stopped) { Stop-Setup -Cancelled }
    break
}

if (-not (Test-Administrator)) {
    Write-Host "Requesting Administrator permission..."
    Relaunch-AsAdministrator -Bound $PSBoundParameters
    exit
}

if ($InstallRoot -match '\s' -or $OracleInstallDir -match '\s') {
    Write-Host "Use install folders that do not contain spaces." -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}

if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Host "This setup needs 64-bit Windows." -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
$downloads = Join-Path $InstallRoot 'downloads'
New-Item -ItemType Directory -Force -Path $downloads | Out-Null
$userDownloads = Join-Path $env:USERPROFILE 'Downloads'
New-Item -ItemType Directory -Force -Path $userDownloads | Out-Null
$script:SetupStatePath = Join-Path $InstallRoot 'setup-run.json'
if (([System.Management.Automation.PSTypeName]'SetupStop').Type) {
    [SetupStop]::StatePath = $script:SetupStatePath
    [SetupStop]::Install()
}
Clear-InterruptedSetup

$osCaption = (Get-CimInstance Win32_OperatingSystem).Caption
$ramGb = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$windowsHome = $osCaption -match '\bHome\b'
$oracleAlreadyInstalled = $null -ne (Get-Service -Name 'OracleServiceXE' -ErrorAction SilentlyContinue)
$tomcatHome = Join-Path $InstallRoot 'tomcat'
$installedTomcatVersion = Get-InstalledTomcatVersion -TomcatHome $tomcatHome

Write-Host "PC: $osCaption"
Write-Host "Memory: $ramGb GB"

# ---------- Decide Java ----------
$jdkHome = $null
$jdkVersionText = ''
$installJava = $false
$latestJavaFeature = $null
if (-not $SkipJava) {
    Write-Step 'Check Java'
    $latestJavaFeature = Get-LatestJavaFeature
    $installedJdks = @(Get-InstalledJdks)
    $currentJdk = $installedJdks | Select-Object -First 1
    if (-not $currentJdk) {
        Write-Host "Java is not installed. Java $latestJavaFeature will be downloaded and set up."
        $installJava = $true
    } elseif ($currentJdk.Feature -ge $latestJavaFeature) {
        Write-Host "Java $($currentJdk.Version) is already the latest. It will not be reinstalled."
        $jdkHome = $currentJdk.Home
        $jdkVersionText = $currentJdk.Version
    } else {
        $choice = Read-MenuChoice -Title "Java $($currentJdk.Version) is installed. The latest is Java $latestJavaFeature." -Options @(
            "Download and install Java $latestJavaFeature",
            "Continue with Java $($currentJdk.Version)"
        )
        if ($choice -eq 1) {
            $installJava = $true
        } else {
            Write-Host "Keeping Java $($currentJdk.Version)."
            $jdkHome = $currentJdk.Home
            $jdkVersionText = $currentJdk.Version
        }
    }
}

# ---------- Decide Tomcat ----------
$selectedTomcat = $null
$installTomcat = $false
if (-not $SkipTomcat) {
    Write-Step 'Check Tomcat'
    if ($installedTomcatVersion) {
        Write-Host "Tomcat $installedTomcatVersion is installed at $tomcatHome"
    } else {
        Write-Host "Tomcat is not installed."
    }
    $catalog = @(Get-TomcatCatalog)
    $tomcatChoice = Read-MenuChoice -Title 'Which Tomcat version do you want?' -Options @($catalog | ForEach-Object { $_.Label })
    $selectedTomcat = $catalog[$tomcatChoice - 1]
    if ($installedTomcatVersion -eq $selectedTomcat.Version) {
        Write-Host "Tomcat $($selectedTomcat.Version) is already installed. It will not be downloaded again."
        $installTomcat = $false
    } else {
        if ($installedTomcatVersion) {
            Write-Host "Tomcat $installedTomcatVersion will be replaced with Tomcat $($selectedTomcat.Version)."
        } else {
            Write-Host "Tomcat $($selectedTomcat.Version) will be downloaded and set up."
        }
        $installTomcat = $true
    }
}

# ---------- Java install ----------
if ($SkipJava) {
    Add-Result 'SKIP' 'Java skipped by request.'
    $kept = Get-InstalledJdks | Select-Object -First 1
    if ($kept) {
        $jdkHome = $kept.Home
        $jdkVersionText = $kept.Version
    }
} elseif ($installJava) {
    Write-Step "Install Java $latestJavaFeature"
    $script:StepLabel = 'Step 1 of 4  Java'
    try {
        Install-JdkFeature -Feature $latestJavaFeature -DownloadsDirectory $downloads
        $jdkHome = Find-JdkByFeature -Feature $latestJavaFeature
        if (-not $jdkHome) { throw "Java $latestJavaFeature installed, but its folder was not found." }
        $installedNow = Get-JdkDetails -JdkPath $jdkHome
        $jdkVersionText = $installedNow.Version
        Set-MachineVariable -Name 'JAVA_HOME' -Value $jdkHome
        Add-MachinePathEntry -Directory (Join-Path $jdkHome 'bin')
        & (Join-Path $jdkHome 'bin\java.exe') -version
        Add-Result 'OK' "Java $jdkVersionText installed. JAVA_HOME=$jdkHome"
    } catch {
        Resolve-SetupFailure $_
    }
} elseif ($jdkHome) {
    try {
        Set-MachineVariable -Name 'JAVA_HOME' -Value $jdkHome
        Add-MachinePathEntry -Directory (Join-Path $jdkHome 'bin')
        Add-Result 'OK' "Using Java $jdkVersionText. JAVA_HOME=$jdkHome"
    } catch {
        Resolve-SetupFailure $_
    }
}

# ---------- Eclipse ----------
$eclipsePath = ''
if ($SkipEclipse) {
    Add-Result 'SKIP' 'Eclipse skipped by request.'
} else {
    Write-Step 'Eclipse IDE for Enterprise Java and Web Developers'
    $script:StepLabel = 'Step 2 of 4  Eclipse'
    try {
        $eclipse = Find-EclipseExecutable
        $alreadyJee = $eclipse -and ($eclipse.FullName -match 'Eclipse\.JEE|eclipse-jee')
        if ($eclipse -and -not $alreadyJee) {
            Write-Host "Eclipse is already installed. Removing it, then installing a fresh web-development copy."
            Remove-EclipseCompletely
            $eclipse = $null
            Add-Result 'OK' 'Old Eclipse installation was removed.'
        }
        if (-not $eclipse) {
            Write-Host "Eclipse is not installed. A fresh web-development copy will be installed."
            $eclipseInstalled = Install-WingetId -Id 'EclipseFoundation.Eclipse.JEE' -Label 'Eclipse IDE for Enterprise Java and Web Developers' -Force -ExpectedSeconds 480
            if (-not $eclipseInstalled) {
                throw 'winget could not install Eclipse IDE for Enterprise Java and Web Developers.'
            }
            $eclipse = Find-EclipseExecutable
        } else {
            Write-Host "Eclipse is already installed. It will not be downloaded again."
            Write-Host "  $($eclipse.FullName)"
        }
        if (-not $eclipse) { throw 'Eclipse installed, but eclipse.exe was not found.' }
        $eclipsePath = $eclipse.FullName
        if ($jdkHome) {
            $javaw = Join-Path $jdkHome 'bin\javaw.exe'
            $ini = Join-Path $eclipse.DirectoryName 'eclipse.ini'
            if ((Test-Path $javaw) -and (Test-Path $ini)) {
                Set-EclipseJavaVm -IniPath $ini -JavawPath $javaw
            }
        }
        New-DesktopShortcut -Name 'Eclipse IDE' -TargetPath $eclipse.FullName -WorkingDirectory $eclipse.DirectoryName
        Add-Result 'OK' "Eclipse web package is ready at $eclipsePath"
    } catch {
        if (Test-SetupStopped $_) { Stop-Setup -Cancelled }
        Add-Result 'FAIL' $_.Exception.Message
        Write-Host "Eclipse was not finished. Setup will continue with Tomcat." -ForegroundColor Yellow
    }
}

# ---------- Tomcat ----------
$tomcatPort = 8080
$tomcatUser = 'admin'
$tomcatPassword = 'admin'
$tomcatServlet = ''
$tomcatRuntimeName = 'Apache Tomcat'
$tomcatVersionText = $installedTomcatVersion
if ($SkipTomcat) {
    Add-Result 'SKIP' 'Tomcat skipped by request.'
} elseif (-not $selectedTomcat) {
    Add-Result 'FAIL' 'Tomcat version was not selected.'
    Stop-Setup
} elseif (-not $installTomcat) {
    $tomcatVersionText = $installedTomcatVersion
    $tomcatServlet = $selectedTomcat.Servlet
    $tomcatRuntimeName = $selectedTomcat.RuntimeName
    Set-MachineVariable -Name 'CATALINA_HOME' -Value $tomcatHome
    if ($jdkHome) { Set-MachineVariable -Name 'JAVA_HOME' -Value $jdkHome }
    Add-Result 'OK' "Tomcat $tomcatVersionText is already set up at $tomcatHome"
} elseif (-not $jdkHome) {
    Add-Result 'FAIL' 'Tomcat needs a JDK, and the Java step did not finish.'
    Stop-Setup
} else {
    Write-Step "Install Tomcat $($selectedTomcat.Version)"
    $script:StepLabel = 'Step 3 of 4  Tomcat'
    try {
        $free = Get-FreeGigabytes -DriveLetter 'C'
        if ($free -lt 2) { throw "Drive C: has $free GB free. Tomcat setup needs at least 2 GB." }

        $tomcatVersionText = $null
        Remove-ManagedTomcatService -TomcatHome $tomcatHome
        if (Test-Path $tomcatHome) {
            Remove-Item $tomcatHome -Recurse -Force
        }
        Add-UnfinishedDirectory -Path $tomcatHome

        $zipName = "apache-tomcat-$($selectedTomcat.Version)-windows-x64.zip"
        $zipPath = Find-SavedFile -FileName $zipName -DownloadsDirectory $downloads
        $zipOk = $zipPath -and (Test-FileHashMatch -Path $zipPath -Algorithm 'SHA512' -Expected $selectedTomcat.Sha512)
        if (-not $zipOk) {
            $zipPath = Join-Path $downloads $zipName
            if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
            $url = "https://archive.apache.org/dist/tomcat/tomcat-$($selectedTomcat.MajorPath)/v$($selectedTomcat.Version)/bin/$zipName"
            Write-Host "Downloading $zipName..."
            Save-RemoteFile -Url $url -Destination $zipPath
            $zipOk = Test-FileHashMatch -Path $zipPath -Algorithm 'SHA512' -Expected $selectedTomcat.Sha512
        } else {
            Write-Host "Using the Tomcat archive that is already downloaded:"
            Write-Host "  $zipPath"
        }
        if (-not $zipOk) { throw 'The Tomcat download did not match the published checksum.' }

        $staging = Join-Path $InstallRoot 'tomcat-staging'
        if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $staging | Out-Null
        Add-UnfinishedDirectory -Path $staging
        $tarProcess = Start-SetupProcess -FilePath 'tar.exe' -ArgumentList @('-xf', $zipPath, '-C', $staging)
        $tarCode = Wait-SetupProcess -Process $tarProcess -Label $script:StepLabel -ExpectedSeconds 60
        if ($tarCode -ne 0) { throw 'Could not extract Tomcat.' }
        $extracted = Get-ChildItem $staging -Directory | Where-Object { $_.Name -like 'apache-tomcat-*' } | Select-Object -First 1
        if (-not $extracted) { throw 'The Tomcat archive did not contain the expected folder.' }
        Move-Item $extracted.FullName $tomcatHome
        Remove-UnfinishedDirectory -Path $tomcatHome
        Remove-UnfinishedDirectory -Path $staging
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue

        if (-not (Test-PortFree -Port 8080)) { $tomcatPort = 8081 }
        if ($tomcatPort -ne 8080) {
            $serverXml = Join-Path $tomcatHome 'conf\server.xml'
            $serverText = Get-Content $serverXml -Raw
            $serverText = $serverText.Replace('<Connector port="8080" protocol="HTTP/1.1"', "<Connector port=`"$tomcatPort`" protocol=`"HTTP/1.1`"")
            Set-Content -Path $serverXml -Value $serverText -Encoding ASCII
        }

        $usersXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users xmlns="http://tomcat.apache.org/xml"
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xsi:schemaLocation="http://tomcat.apache.org/xml tomcat-users.xsd"
              version="1.0">
  <role rolename="manager-gui"/>
  <role rolename="manager-script"/>
  <user username="$tomcatUser" password="$tomcatPassword" roles="manager-gui,manager-script"/>
</tomcat-users>
"@
        Set-Content -Path (Join-Path $tomcatHome 'conf\tomcat-users.xml') -Value $usersXml -Encoding ASCII
        Set-Content -Path (Join-Path $tomcatHome 'bin\setenv.bat') -Encoding ASCII -Value @(
            "set `"JAVA_HOME=$jdkHome`"",
            'set "CATALINA_OPTS=-Xms256m -Xmx512m"'
        )
        Set-MachineVariable -Name 'CATALINA_HOME' -Value $tomcatHome
        Set-MachineVariable -Name 'JAVA_HOME' -Value $jdkHome
        Add-MachinePathEntry -Directory (Join-Path $tomcatHome 'bin')

        $startCmd = Join-Path $InstallRoot 'Start-Tomcat.cmd'
        $stopCmd = Join-Path $InstallRoot 'Stop-Tomcat.cmd'
        Set-Content -Path $startCmd -Encoding ASCII -Value @(
            '@echo off',
            "set `"JAVA_HOME=$jdkHome`"",
            "set `"CATALINA_HOME=$tomcatHome`"",
            'call "%CATALINA_HOME%\bin\startup.bat"'
        )
        Set-Content -Path $stopCmd -Encoding ASCII -Value @(
            '@echo off',
            "set `"JAVA_HOME=$jdkHome`"",
            "set `"CATALINA_HOME=$tomcatHome`"",
            'call "%CATALINA_HOME%\bin\shutdown.bat"'
        )

        $serviceName = $selectedTomcat.ServiceName
        Push-Location (Join-Path $tomcatHome 'bin')
        try {
            & cmd.exe /c "service.bat install $serviceName"
            if ($LASTEXITCODE -eq 0) {
                Set-Service -Name $serviceName -StartupType Automatic -ErrorAction Stop
                Start-Service -Name $serviceName -ErrorAction Stop
            } else {
                & cmd.exe /c "`"$startCmd`""
            }
        } catch {
            & cmd.exe /c "`"$startCmd`""
        } finally {
            Pop-Location
        }

        $ready = $false
        for ($try = 0; $try -lt 10; $try++) {
            if ($script:StopRequested) { throw 'Setup was stopped.' }
            Write-SetupProgressLine -Label $script:StepLabel -Percent (10 * $try) -Detail ("elapsed $(Format-ElapsedText ($try * 3))  waiting for Tomcat")
            & curl.exe -fsS -o NUL "http://127.0.0.1:$tomcatPort/"
            if ($LASTEXITCODE -eq 0) { $ready = $true; break }
            Start-Sleep -Seconds 3
        }
        Clear-SetupProgressLine
        $tomcatVersionText = $selectedTomcat.Version
        $tomcatServlet = $selectedTomcat.Servlet
        $tomcatRuntimeName = $selectedTomcat.RuntimeName
        if ($ready) {
            Add-Result 'OK' "Tomcat $tomcatVersionText is running at http://127.0.0.1:$tomcatPort/"
        } else {
            Add-Result 'FAIL' "Tomcat $tomcatVersionText is installed, but http://127.0.0.1:$tomcatPort/ did not answer yet. Run $startCmd"
            Stop-Setup
        }
    } catch {
        Resolve-SetupFailure $_
    }
}

# ---------- Oracle ----------
$listenerPort = 1521
$emPort = 5500
$oracleHome = ''
$oraclePasswordForNotes = ''
$oracleNote = ''
$extractRoot = $null
if ($SkipOracle) {
    Add-Result 'SKIP' 'Oracle skipped by request.'
    $oracleNote = 'Oracle setup was skipped.'
} elseif ($oracleAlreadyInstalled) {
    $candidateHome = Join-Path $OracleInstallDir 'dbhomeXE'
    if (Test-Path (Join-Path $candidateHome 'bin\sqlplus.exe')) { $oracleHome = $candidateHome }
    $pendingPassword = Join-Path $InstallRoot 'oracle-password-pending.txt'
    if ((Test-Path $pendingPassword) -and $oracleHome) {
        try {
            $listenerPort = Get-ListenerPort -OracleHome $oracleHome -Fallback 1521
            Set-OraclePasswordToSystem -OracleHome $oracleHome -Port $listenerPort -InstallerPassword $OracleInstallerPassword
            Remove-Item $pendingPassword -Force
            $oraclePasswordForNotes = $OraclePassword
            $oracleNote = 'Installed by this setup. Login id and password are both system.'
            Add-Result 'OK' 'Oracle Database 21c XE is installed. Login id and password are both system.'
        } catch {
            if (Test-SetupStopped $_) { Stop-Setup -Cancelled }
            Add-Result 'FAIL' $_.Exception.Message
            $oracleNote = "Oracle is installed, but the login is not system yet. Temporary password: $OracleInstallerPassword"
            Stop-Setup
        }
    } else {
        Add-Result 'OK' 'Oracle Database 21c XE is already installed. It was not downloaded again.'
        $oracleNote = 'Oracle Database 21c XE was already installed. The existing password was kept.'
    }
} elseif ($windowsHome) {
    Add-Result 'SKIP' 'Oracle 21c XE does not support Windows Home. Java, Eclipse, and Tomcat can still be used.'
    $oracleNote = 'Oracle was not installed because this PC is Windows Home.'
} elseif ($ramGb -lt 2) {
    Add-Result 'SKIP' "Oracle 21c XE needs at least 2 GB of memory. This PC has $ramGb GB."
    $oracleNote = "Oracle was not installed because this PC has $ramGb GB of memory."
} else {
    Write-Step 'Oracle Database 21c Express Edition'
    $script:StepLabel = 'Step 4 of 4  Oracle'
    Write-Host "Oracle is not installed. It will be downloaded and set up."
    Write-Host "Login id: $OracleLogin"
    Write-Host "Password: $OraclePassword"
    $directAdmin = Test-DirectAdministrator
    if ($directAdmin -eq $false) {
        Add-Result 'SKIP' 'Oracle was not installed. Sign in as a user that is a direct member of Administrators, then run setup again.'
        $oracleNote = 'Oracle was not installed. The Windows user must be a direct member of Administrators.'
    } else {
        try {
            $free = Get-FreeGigabytes -DriveLetter 'C'
            if ($free -lt 12) { throw "Drive C: has $free GB free. Oracle setup needs at least 12 GB." }

            if (-not (Test-PortFree -Port 1521)) { $listenerPort = 0 }
            if (-not (Test-PortFree -Port 5500)) { $emPort = 0 }

            $zipPath = $null
            if ($OracleZip -and (Test-Path $OracleZip)) { $zipPath = (Resolve-Path $OracleZip).Path }
            if (-not $zipPath) { $zipPath = Find-SavedFile -FileName $OracleZipName -DownloadsDirectory $downloads }
            $oracleVerified = $zipPath -and (Test-FileHashMatch -Path $zipPath -Algorithm 'SHA256' -Expected $OracleSha256 -ExpectedSeconds 120)
            if ($zipPath -and -not $oracleVerified) {
                Write-Host "A file named $OracleZipName was found, but it is not the official installer." -ForegroundColor Yellow
                $zipPath = $null
            }
            if ($oracleVerified) {
                Write-Host "Using the Oracle installer that is already downloaded:"
                Write-Host "  $zipPath"
            } else {
                $zipPath = Join-Path $downloads $OracleZipName
                Write-Host "Trying the Oracle download (about 1.8 GB)..."
                $downloaded = $true
                try {
                    Save-RemoteFile -Url $OracleUrl -Destination $zipPath -Cookie 'oraclelicense=accept-securebackup-cookie' -FallbackBytes 1932735283
                } catch {
                    if (Test-SetupStopped $_) { throw }
                    $downloaded = $false
                }
                if ($downloaded -and (Test-FileHashMatch -Path $zipPath -Algorithm 'SHA256' -Expected $OracleSha256 -ExpectedSeconds 120)) {
                    $oracleVerified = $true
                } else {
                    if (Test-Path $zipPath) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
                    Write-Host ""
                    Write-Host "Oracle requires a free Oracle account and a license acceptance." -ForegroundColor Yellow
                    Write-Host "1. Sign in on the page that is about to open."
                    Write-Host "2. Download Oracle Database 21c Express Edition for Windows (64-bit)."
                    Write-Host "3. Save the zip as:"
                    Write-Host "   $zipPath"
                    Start-Process $OracleDownloadPage
                    Read-Host "Press Enter after the zip is saved there"
                    if ($script:StopRequested) { throw 'Setup was stopped.' }
                    if (Test-FileHashMatch -Path $zipPath -Algorithm 'SHA256' -Expected $OracleSha256 -ExpectedSeconds 120) {
                        $oracleVerified = $true
                    }
                }
            }
            if (-not $oracleVerified) {
                throw "OracleXE213_Win64.zip is missing or is not the official file. Save it to $zipPath and run setup again."
            }

            $extractRoot = Join-Path $InstallRoot 'oracle-extract'
            Add-UnfinishedDirectory -Path $extractRoot
            if (Test-Path $extractRoot) { Remove-Item $extractRoot -Recurse -Force }
            New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
            Write-Host "Extracting Oracle. This is a large archive..."
            $tarProcess = Start-SetupProcess -FilePath 'tar.exe' -ArgumentList @('-xf', $zipPath, '-C', $extractRoot)
            $tarCode = Wait-SetupProcess -Process $tarProcess -Label $script:StepLabel -ExpectedSeconds 240
            if ($tarCode -ne 0) { throw 'Could not extract the Oracle installer.' }

            $setupExe = Get-ChildItem $extractRoot -Filter 'setup.exe' -Recurse | Select-Object -First 1
            if (-not $setupExe) { throw 'setup.exe was not inside the Oracle zip.' }

            $rspPath = Join-Path $setupExe.DirectoryName 'XEInstall.rsp'
            Set-Content -Path $rspPath -Encoding ASCII -Value @(
                "INSTALLDIR=$OracleInstallDir\",
                "PASSWORD=$OracleInstallerPassword",
                "LISTENER_PORT=$listenerPort",
                "EMEXPRESS_PORT=$emPort",
                'CHAR_SET=AL32UTF8',
                'DB_DOMAIN='
            )

            Clear-OracleInstallerVariables
            $setupLog = Join-Path $InstallRoot 'oracle-setup.log'
            if (Test-Path $setupLog) { Remove-Item $setupLog -Force }
            $argumentLine = "/s /v`"RSP_FILE=$rspPath`" /v`"/L*v $setupLog`" /v`"/qn`""
            Write-Host "Installing Oracle. This often takes 15 to 25 minutes."
            $process = Start-Process -FilePath $setupExe.FullName -ArgumentList $argumentLine -WorkingDirectory $setupExe.DirectoryName -PassThru
            Register-ChildProcess -ProcessId $process.Id
            $oracleStarted = Get-Date
            $deadline = $oracleStarted.AddMinutes(45)
            $installOk = $false
            $nextLogCheck = $oracleStarted
            try {
                while ((Get-Date) -lt $deadline) {
                    if ($script:StopRequested) {
                        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                        [void]$script:CleanupLog.Add("Stopped process $($process.Id)")
                        throw 'Setup was stopped.'
                    }
                    $elapsed = ((Get-Date) - $oracleStarted).TotalSeconds
                    $percent = [int][math]::Min(95, [math]::Floor(($elapsed / 1200) * 100))
                    Write-SetupProgressLine -Label $script:StepLabel -Percent $percent -Detail (Format-ExpectedDetail -ElapsedSeconds $elapsed -ExpectedSeconds 1200)
                    if ($process.HasExited -and $process.ExitCode -ne 0) {
                        throw "Oracle setup.exe exited with code $($process.ExitCode). See $setupLog"
                    }
                    if ((Get-Date) -ge $nextLogCheck) {
                        $nextLogCheck = (Get-Date).AddSeconds(5)
                        if (Test-Path $setupLog) {
                            $logText = Get-Content $setupLog -Raw -ErrorAction SilentlyContinue
                            $statusMatch = [regex]::Match($logText, 'Installation success or error status:\s*(\d+)')
                            if ($statusMatch.Success) {
                                $installOk = ([int]$statusMatch.Groups[1].Value -eq 0)
                                break
                            }
                        }
                    }
                    Start-Sleep -Seconds 1
                }
            } finally {
                Clear-SetupProgressLine
            }
            if (-not $installOk) {
                $service = Get-Service -Name 'OracleServiceXE' -ErrorAction SilentlyContinue
                if ($service -and $process.HasExited -and $process.ExitCode -eq 0) { $installOk = $true }
            }
            if (-not $installOk) {
                throw "Oracle did not report a successful install. See $setupLog"
            }
            Unregister-ChildProcess -ProcessId $process.Id

            $oracleHome = Join-Path $OracleInstallDir 'dbhomeXE'
            if (Test-Path (Join-Path $oracleHome 'bin\sqlplus.exe')) {
                Set-MachineVariable -Name 'ORACLE_HOME' -Value $oracleHome
                Set-MachineVariable -Name 'ORACLE_SID' -Value 'XE'
                Add-MachinePathEntry -Directory (Join-Path $oracleHome 'bin')
                $listenerPort = Get-ListenerPort -OracleHome $oracleHome -Fallback $(if ($listenerPort -eq 0) { 1521 } else { $listenerPort })
            }

            $pendingPassword = Join-Path $InstallRoot 'oracle-password-pending.txt'
            Set-Content -Path $pendingPassword -Value 'pending' -Encoding ASCII
            Set-OraclePasswordToSystem -OracleHome $oracleHome -Port $listenerPort -InstallerPassword $OracleInstallerPassword
            Remove-Item $pendingPassword -Force -ErrorAction SilentlyContinue
            $oraclePasswordForNotes = $OraclePassword
            $oracleNote = 'Installed by this setup. Login id and password are both system.'
            Remove-UnfinishedDirectory -Path $extractRoot
            Remove-Item $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
            Add-Result 'OK' 'Oracle Database 21c XE installed. Login id and password are both system.'
        } catch {
            if (Test-SetupStopped $_) { Stop-Setup -Cancelled }
            Add-Result 'FAIL' $_.Exception.Message
            $oracleNote = $_.Exception.Message
            $pendingPassword = Join-Path $InstallRoot 'oracle-password-pending.txt'
            $oracleService = Get-Service -Name 'OracleServiceXE' -ErrorAction SilentlyContinue
            if ((Test-Path $pendingPassword) -and $oracleService) {
                $oracleNote = "$oracleNote Temporary password until it is switched to system: $OracleInstallerPassword"
            } elseif (Test-Path $pendingPassword) {
                Add-UnfinishedFile -Path $pendingPassword
            }
            Stop-Setup
        }
    }
}

# ---------- Notes in Downloads ----------
Complete-SetupRunState
Write-SetupNotes

Write-Host ""
Write-Host "==== Summary ====" -ForegroundColor Cyan
$script:Report | ForEach-Object { Write-Host $_ }
Write-Host ""
if ($script:NotesPath) {
    Write-Host "Paths, ids, and passwords were saved to:"
    Write-Host "  $($script:NotesPath)"
}
Write-Host "Open a new terminal before using java or sqlplus, so the new PATH is loaded."
Write-Host ""
Read-Host "Press Enter to close"
