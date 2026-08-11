<#
.SYNOPSIS
    Install Ollama on Windows with local file and Mirror acceleration support.

.DESCRIPTION
    Downloads and installs Ollama with automatic local file detection and Mirror speed optimization.

    Features:
    - Auto-detect local files in script directory
    - Auto-select fastest Mirror for GitHub downloads

    Environment variables:
        OLLAMA_VERSION       Target version (default: latest stable)
        OLLAMA_INSTALL_DIR   Custom install directory
        OLLAMA_UNINSTALL     Set to 1 to uninstall Ollama
        OLLAMA_DEBUG         Enable verbose output
        OLLAMA_MIRROR        Custom Mirror list (space-separated)

.EXAMPLE
    .\install-ollama-local.ps1

.EXAMPLE
    $env:OLLAMA_VERSION = "0.32.9"; .\install-ollama-local.ps1

.LINK
    https://github.com/ollama/ollama
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

trap {
    Write-Host ">>> ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ">>> Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}

# ========================================
# 环境变量检测
# ========================================
Write-Host ">>> Detecting environment variables..." -ForegroundColor Gray

$Version = if ($env:OLLAMA_VERSION) { $env:OLLAMA_VERSION } else { "" }
$InstallDir = if ($env:OLLAMA_INSTALL_DIR) { $env:OLLAMA_INSTALL_DIR } else { "" }
$Uninstall = $env:OLLAMA_UNINSTALL -eq "1"
$DebugInstall = [bool]$env:OLLAMA_DEBUG

Write-Host "  [CONFIG] OLLAMA_VERSION = '$Version'" -ForegroundColor DarkGray
Write-Host "  [CONFIG] OLLAMA_INSTALL_DIR = '$InstallDir'" -ForegroundColor DarkGray
Write-Host "  [CONFIG] OLLAMA_UNINSTALL = '$Uninstall'" -ForegroundColor DarkGray
Write-Host "  [CONFIG] OLLAMA_DEBUG = '$DebugInstall'" -ForegroundColor DarkGray
Write-Host "  [CONFIG] OLLAMA_MIRROR = '$($env:OLLAMA_MIRROR)'" -ForegroundColor DarkGray

$Script:MirrorList = @(
    "https://gh-proxy.com",
    "https://ghfile.geekertao.top",
    "https://cdn.gh-proxy.com",
    "https://gh.927223.xyz",
    "https://ghproxy.net",
    "https://github.tbap.top",
    "https://cdn.akaere.online",
    "https://tvv.tw",
    "https://jiashu.1win.eu.org",
    "https://github.dpik.top",
    "https://gh.bugdey.us.kg",
    "https://gh.dpik.top",
    "https://gh.felicity.ac.cn",
    "https://down.mxw.xx.kg",
    "https://down.mxw.qzz.io",
    "https://github.mxw.qzz.io",
    "https://gh.inkchills.cn",
    "https://github.chenc.dev",
    "https://gh.jjj.gv.uy",
    "https://gh.acmsz.top",
    "https://gh.b52m.cn",
    "https://gitproxy.mrhjx.cn",
    "https://gh.jasonzeng.dev",
    "https://gp.zkitefly.eu.org",
    "https://fastgit.cc",
    "https://gh.sixyin.com",
    "https://github.ednovas.xyz",
    "https://ghproxy.imciel.com",
    "https://github.xxlab.tech",
    "https://ghproxy.cxkpro.top",
    "https://ghfast.top",
    "https://git.669966.xyz",
    "https://ghp.keleyaa.com",
    "https://githubdog.com",
    "https://js.jiangss.shop",
    "https://ghproxy.monkeyray.net",
    "https://g.z321.cc.cd",
    "https://777.z321.cc.cd",
    "https://gg.z321.cc.cd",
    "https://g.blfrp.cn",
    "https://gh.noki.icu",
    "https://gh.my-website.ccwu.cc",
    "https://github.nswrz.cn",
    "https://xsadwsd.kdns.fr",
    "https://gh.qfmc0721.cc.cd",
    "https://gh.zhai.edu.pl",
    "https://gh.07150721.xyz",
    "https://ghproxy.felicity.land"
)

if ($env:OLLAMA_MIRROR) {
    $Script:MirrorList = $env:OLLAMA_MIRROR -split ' '
    Write-Host "  [MIRROR] Using custom Mirror list: $($Script:MirrorList.Count) mirrors" -ForegroundColor DarkGray
}
else {
    Write-Host "  [MIRROR] Using default Mirror list: $($Script:MirrorList.Count) mirrors" -ForegroundColor DarkGray
}

$Script:SpeedTestTimeout = 5
$InnoSetupUninstallGuid = "{44E83376-CE68-45EB-8FC1-393500EB558C}_is1"

function Get-ScriptDirectory {
    if ($PSVersionTable.PSVersion.Major -ge 3) {
        return $PSScriptRoot
    }
    return Split-Path -Parent $MyInvocation.MyCommand.Path
}

function Write-Status {
    param([string]$Message)
    if ($DebugInstall) { Write-Host $Message }
}

function Write-Step {
    param([string]$Message)
    Write-Host ">>> $Message" -ForegroundColor Cyan
}

function Test-LocalFile {
    param([string]$FileName)

    $scriptDir = Get-ScriptDirectory
    $scriptPath = Join-Path $scriptDir $FileName
    $cwdPath = Join-Path (Get-Location) $FileName

    Write-Status "  [LOCAL] Checking for: $FileName"
    Write-Status "  [LOCAL] Script dir: $scriptDir"
    Write-Status "  [LOCAL] Current dir: $(Get-Location)"

    # 优先检查脚本目录
    if (Test-Path $scriptPath) {
        $fileInfo = Get-Item $scriptPath
        $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        Write-Status "  [LOCAL] Found in script dir! Size: $fileSizeMB MB"
        return $scriptPath
    }
    # 备选：检查当前工作目录
    elseif (Test-Path $cwdPath) {
        $fileInfo = Get-Item $cwdPath
        $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        Write-Status "  [LOCAL] Found in current dir! Size: $fileSizeMB MB"
        return $cwdPath
    }
    else {
        Write-Status "  [LOCAL] Not found"
        return $null
    }
}

function Test-MirrorSpeed {
    param([string]$Mirror, [string]$Url)

    $testUrl = if ($Mirror) { "$Mirror/$Url" } else { $Url }
    Write-Status "  [SPEED] Testing: $testUrl"
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $request = [System.Net.HttpWebRequest]::Create($testUrl)
        $request.AllowAutoRedirect = $true
        $request.Timeout = $Script:SpeedTestTimeout * 1000
        $request.ReadWriteTimeout = $Script:SpeedTestTimeout * 1000
        $response = $request.GetResponse()
        $stopwatch.Stop()
        $response.Close()
        $elapsed = $stopwatch.ElapsedMilliseconds
        Write-Status "  [SPEED] Result: $elapsed ms"
        return $elapsed
    }
    catch {
        Write-Status "  [SPEED] Failed: $($_.Exception.Message)"
        return 0
    }
}

function Select-BestMirror {
    param([string]$Url)

    Write-Status "  [MIRROR] Selecting best Mirror for: $Url"
    Write-Status "  [MIRROR] Total Mirrors to test: $($Script:MirrorList.Count)"
    
    $bestMirror = $Script:MirrorList[0]
    $bestSpeed = 0
    $testedCount = 0

    foreach ($mirror in $Script:MirrorList) {
        $testedCount++
        Write-Status "  [MIRROR] [$testedCount/$($Script:MirrorList.Count)] Testing: $mirror"
        $speed = Test-MirrorSpeed -Mirror $mirror -Url $Url

        if ($speed -gt $bestSpeed) {
            $bestSpeed = $speed
            $bestMirror = $mirror
            Write-Status "  [MIRROR] [*] New best: $mirror ($speed ms)"
        }
    }
    
    Write-Status "  [MIRROR] Selection complete. Best: $bestMirror ($bestSpeed ms)"
    return $bestMirror
}

function Get-DownloadUrl {
    param([string]$OriginalUrl)

    Write-Status "  [DOWNLOAD] ====== Get-DownloadUrl() ======"
    Write-Status "  [DOWNLOAD] Input URL: $OriginalUrl"
    
    if ($OriginalUrl -notmatch "github\.com") {
        Write-Status "  [DOWNLOAD] [BRANCH] Non-GitHub URL, using directly"
        Write-Status "  [DOWNLOAD] Final URL: $OriginalUrl"
        return $OriginalUrl
    }

    Write-Status "  [DOWNLOAD] [BRANCH] GitHub URL detected"
    Write-Status "  [DOWNLOAD] Checking for local file..."

    $fileName = [System.IO.Path]::GetFileName($OriginalUrl)
    Write-Status "  [DOWNLOAD] Extracted filename: $fileName"

    $localFile = Test-LocalFile -FileName $fileName
    if ($localFile) {
        Write-Status "  [DOWNLOAD] [BRANCH] LOCAL file found!"
        Write-Status "  [DOWNLOAD] [BRANCH] Using local file: $localFile"
        Write-Status "  [DOWNLOAD] Final URL: LOCAL:$localFile"
        return "LOCAL:$localFile"
    }
    else {
        Write-Status "  [DOWNLOAD] [BRANCH] No local file found"
    }

    Write-Status "  [DOWNLOAD] No local file, selecting best Mirror..."
    $bestMirror = Select-BestMirror -Url $OriginalUrl
    Write-Status "  [DOWNLOAD] Best mirror: $bestMirror"

    Write-Status "  [DOWNLOAD] Comparing speeds..."
    $officialSpeed = Test-MirrorSpeed -Mirror "" -Url $OriginalUrl
    Write-Status "  [DOWNLOAD] Official speed: $officialSpeed ms"
    
    $mirrorSpeed = Test-MirrorSpeed -Mirror $bestMirror -Url $OriginalUrl
    Write-Status "  [DOWNLOAD] Mirror speed: $mirrorSpeed ms"

    if ($officialSpeed -eq 0 -or $mirrorSpeed -lt $officialSpeed) {
        Write-Status "  [DOWNLOAD] [BRANCH] Choosing MIRROR"
        Write-Status "  [DOWNLOAD] [BRANCH] Reason: mirror faster ($mirrorSpeed ms) or official unavailable ($officialSpeed ms)"
        Write-Status "  [DOWNLOAD] [BRANCH] Selected mirror: $bestMirror"
        $finalDownloadUrl = "$bestMirror/$OriginalUrl"
        Write-Status "  [DOWNLOAD] [BRANCH] Full URL: $finalDownloadUrl"
        Write-Status "  [DOWNLOAD] ====== Get-DownloadUrl() COMPLETE ======"
        return $finalDownloadUrl
    }

    Write-Status "  [DOWNLOAD] [BRANCH] Choosing OFFICIAL GitHub"
    Write-Status "  [DOWNLOAD] [BRANCH] Reason: official speed ($officialSpeed ms) >= mirror speed ($mirrorSpeed ms)"
    Write-Status "  [DOWNLOAD] Final URL: $OriginalUrl"
    Write-Status "  [DOWNLOAD] ====== Get-DownloadUrl() COMPLETE ======"
    return $OriginalUrl
}

function Test-Signature {
    param([string]$FilePath)

    $sig = Get-AuthenticodeSignature -FilePath $FilePath
    if ($sig.Status -ne "Valid") {
        Write-Status "  Signature status: $($sig.Status)"
        return $false
    }

    $subject = $sig.SignerCertificate.Subject
    if ($subject -notmatch "(^|, )O=Ollama Inc\.(,|$)") {
        Write-Status "  Unexpected signer: $subject"
        return $false
    }

    Write-Status "  Signature valid: $subject"
    return $true
}

function Find-InnoSetupInstall {
    $possibleKeys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$InnoSetupUninstallGuid",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$InnoSetupUninstallGuid",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$InnoSetupUninstallGuid"
    )

    foreach ($key in $possibleKeys) {
        if (Test-Path $key) {
            Write-Status "  Found install at: $key"
            return $key
        }
    }
    return $null
}

function Update-SessionPath {
    if ($InstallDir) {
        $ollamaDir = $InstallDir
    }
    else {
        $ollamaDir = Join-Path $env:LOCALAPPDATA "Programs\Ollama"
    }

    if (Test-Path $ollamaDir) {
        $currentPath = $env:PATH -split ';'
        if ($ollamaDir -notin $currentPath) {
            $env:PATH = "$ollamaDir;$env:PATH"
            Write-Status "  Added $ollamaDir to session PATH"
        }
    }
}

function Invoke-Download {
    param([string]$Url, [string]$OutFile)

    Write-Status "  [DOWNLOAD] Starting download..."
    Write-Status "  [DOWNLOAD] URL: $Url"
    Write-Status "  [DOWNLOAD] Output: $OutFile"
    
    $downloadStartTime = [DateTime]::Now
    Write-Status "  [DOWNLOAD] Download start time: $($downloadStartTime.ToString('HH:mm:ss.fff'))"
    
    try {
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.AllowAutoRedirect = $true
        $response = $request.GetResponse()
        $totalBytes = $response.ContentLength
        $totalSizeMB = if ($totalBytes -gt 0) { [math]::Round($totalBytes / 1MB, 2) } else { "Unknown" }
        Write-Status "  [DOWNLOAD] File size: $totalSizeMB MB"
        
        $stream = $response.GetResponseStream()
        $fileStream = [System.IO.FileStream]::new($OutFile, [System.IO.FileMode]::Create)
        $buffer = [byte[]]::new(65536)
        $totalRead = 0
        $lastUpdate = [DateTime]::MinValue
        $barWidth = 40

        try {
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $fileStream.Write($buffer, 0, $read)
                $totalRead += $read
                $now = [DateTime]::UtcNow
                if (($now - $lastUpdate).TotalMilliseconds -ge 250) {
                    if ($totalBytes -gt 0) {
                        $pct = [math]::Min(100.0, ($totalRead / $totalBytes) * 100)
                        $filled = [math]::Floor($barWidth * $pct / 100)
                        $bar = ('#' * $filled) + (' ' * ($barWidth - $filled))
                        Write-Host -NoNewline "`r  $bar $($pct.ToString('0.0'))%"
                    }
                    else {
                        Write-Host -NoNewline "`r  $([math]::Round($totalRead / 1MB, 1)) MB downloaded..."
                    }
                    $lastUpdate = $now
                }
            }
            $downloadEndTime = [DateTime]::Now
            $downloadDuration = $downloadEndTime - $downloadStartTime
            $durationSeconds = $downloadDuration.TotalSeconds
            
            if ($totalBytes -gt 0) {
                $completeBar = '#' * $barWidth
                Write-Host "`r  $completeBar 100.0%"
            }
            else {
                Write-Host "`r  $([math]::Round($totalRead / 1MB, 1)) MB downloaded.          "
            }
            Write-Status "  [DOWNLOAD] Download complete: $([math]::Round($totalRead / 1MB, 2)) MB"
            Write-Status "  [DOWNLOAD] Download end time: $($downloadEndTime.ToString('HH:mm:ss.fff'))"
            Write-Status "  [DOWNLOAD] Download duration: $($durationSeconds.ToString('0.0')) seconds"
        }
        finally {
            $fileStream.Close()
            $stream.Close()
            $response.Close()
        }
    }
    catch {
        $downloadEndTime = [DateTime]::Now
        $downloadDuration = $downloadEndTime - $downloadStartTime
        Write-Status "  [DOWNLOAD] [BRANCH-ERROR] Download failed after $($downloadDuration.TotalSeconds.ToString('0.0')) seconds"
        Write-Status "  [DOWNLOAD] Failed: $($_.Exception.Message)"
        throw "Download failed for ${Url}: $($_.Exception.Message)"
    }
}

function Invoke-Uninstall {
    Write-Step "Uninstalling Ollama"
    $regKey = Find-InnoSetupInstall
    if (-not $regKey) {
        Write-Host ">>> Ollama is not installed."
        return
    }
    $uninstallString = (Get-ItemProperty -Path $regKey).UninstallString
    if (-not $uninstallString) {
        Write-Warning "No uninstall string found in registry"
        return
    }
    $uninstallExe = $uninstallString -replace '"', ''
    if (-not (Test-Path $uninstallExe)) {
        Write-Warning "Uninstaller not found at: $uninstallExe"
        return
    }
    Write-Step "Launching uninstaller..."
    Start-Process -FilePath $uninstallExe -Wait
    if (Find-InnoSetupInstall) {
        Write-Warning "Uninstall may not have completed"
    }
    else {
        Write-Host ">>> Ollama has been uninstalled."
    }
}

function Invoke-Install {
    Write-Step "Starting Ollama installation"
    Write-Status "  [INSTALL] ====== Installation Process Starting ======"
    Write-Status "  [INSTALL] Version: $Version"
    Write-Status "  [INSTALL] InstallDir: $InstallDir"
    Write-Status "  [INSTALL] Mirror count: $($Script:MirrorList.Count)"

    if ($Version) {
        $originalUrl = "https://github.com/ollama/ollama/releases/download/v$Version/OllamaSetup.exe"
        Write-Status "  [INSTALL] [BRANCH] Version specified: v$Version"
        Write-Status "  [INSTALL] [BRANCH] URL type: SPECIFIC VERSION"
    }
    else {
        $originalUrl = "https://github.com/ollama/ollama/releases/latest/download/OllamaSetup.exe"
        Write-Status "  [INSTALL] [BRANCH] No version specified, using LATEST"
        Write-Status "  [INSTALL] [BRANCH] URL type: LATEST"
    }
    Write-Status "  [INSTALL] Original URL: $originalUrl"

    Write-Step "Checking download options..."
    Write-Status "  [INSTALL] ====== Download Source Selection ======"
    Write-Status "  [INSTALL] Calling Get-DownloadUrl()..."
    
    $finalUrl = Get-DownloadUrl -OriginalUrl $originalUrl
    
    Write-Status "  [INSTALL] Get-DownloadUrl() returned: $finalUrl"
    Write-Status "  [INSTALL] Final selected URL: $finalUrl"
    Write-Status "  [INSTALL] ====== Download Source Selection Complete ======"
    Write-Step "Downloading Ollama"

    $tempInstaller = Join-Path $env:TEMP "OllamaSetup.exe"
    Write-Status "  [INSTALL] Temp file: $tempInstaller"

    if ($finalUrl.StartsWith("LOCAL:")) {
        $localFile = $finalUrl.Substring(6)
        Write-Step "Copying from local file: $localFile"
        Write-Status "  [INSTALL] [BRANCH] Using LOCAL file"
        $fileSize = [math]::Round((Get-Item $localFile).Length / 1MB, 2)
        Write-Status "  [INSTALL] Local file size: $fileSize MB"
        Write-Status "  [INSTALL] Copying to temp location..."
        Copy-Item -Path $localFile -Destination $tempInstaller -Force
        Write-Status "  [INSTALL] [BRANCH] Copy complete"
    }
    else {
        Write-Status "  [INSTALL] [BRANCH] Using NETWORK download"
        Write-Status "  [INSTALL] Download URL: $finalUrl"
        Invoke-Download -Url $finalUrl -OutFile $tempInstaller
    }

    Write-Step "Verifying signature"
    Write-Status "  [INSTALL] Checking installer signature..."
    if (-not (Test-Signature -FilePath $tempInstaller)) {
        Write-Status "  [INSTALL] [BRANCH-ERROR] Signature verification FAILED"
        Write-Status "  [INSTALL] Cleaning up temp file..."
        Remove-Item $tempInstaller -Force -ErrorAction SilentlyContinue
        throw "Installer signature verification failed"
    }
    Write-Status "  [INSTALL] [BRANCH] Signature verified successfully"

    $installerArgs = "/VERYSILENT /NORESTART /SUPPRESSMSGBOXES"
    if ($InstallDir) { 
        $installerArgs += " /DIR=`"$InstallDir`""
        Write-Status "  [INSTALL] Custom install dir: $InstallDir"
    }
    Write-Status "  [INSTALL] Installer args: $installerArgs"

    Write-Step "Installing Ollama"
    Write-Status "  [INSTALL] ====== Running Installer ======"
    Write-Status "  [INSTALL] Creating upgrade marker..."

    $markerDir = Join-Path $env:LOCALAPPDATA "Ollama"
    $markerFile = Join-Path $markerDir "upgraded"
    if (-not (Test-Path $markerDir)) {
        New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
        Write-Status "  [INSTALL] Created marker directory: $markerDir"
    }
    New-Item -ItemType File -Path $markerFile -Force | Out-Null
    Write-Status "  [INSTALL] Created marker file: $markerFile"

    Write-Status "  [INSTALL] Starting installer..."
    $proc = Start-Process -FilePath $tempInstaller -ArgumentList $installerArgs -PassThru
    Write-Status "  [INSTALL] Installer PID: $($proc.Id), waiting for completion..."
    $proc.WaitForExit()
    Write-Status "  [INSTALL] Installer exit code: $($proc.ExitCode)"

    if ($proc.ExitCode -ne 0) {
        Write-Status "  [INSTALL] [BRANCH-ERROR] Installer FAILED with code: $($proc.ExitCode)"
        Write-Status "  [INSTALL] Cleaning up temp file..."
        Remove-Item $tempInstaller -Force -ErrorAction SilentlyContinue
        throw "Installation failed with exit code $($proc.ExitCode)"
    }

    Write-Status "  [INSTALL] [BRANCH] Installer completed successfully"
    Write-Status "  [INSTALL] Cleaning up temp file..."
    Remove-Item $tempInstaller -Force -ErrorAction SilentlyContinue
    Write-Status "  [INSTALL] Updating session PATH..."
    Update-SessionPath
    Write-Status "  [INSTALL] ====== Installation Complete ======"
    Write-Host ">>> Install complete. Run 'ollama' from the command line."
}

if ($Uninstall) {
    Invoke-Uninstall
}
else {
    Invoke-Install
}
