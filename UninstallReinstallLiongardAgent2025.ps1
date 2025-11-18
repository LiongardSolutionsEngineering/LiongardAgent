<#
.SYNOPSIS
    Liongard Agent RE-INSTALLATION - Production Ready (v2.3)
.DESCRIPTION
    - Actions: Downloads fresh MSI -> Removes Old Agent (if present) -> Installs New Agent.
    - Enforced Inputs: Friendly loop for humans, graceful exit for RMMs.
    - Race Condition Fix: Waits for MSI logs to flush.
    - Deep Error Analysis: Explains failures (401, Invalid URL, etc).
#>
param(
    [string]$Url,
    [string]$AccessKey,
    [string]$AccessSecret,
    [string]$Environment
)

# --- 0. Setup & Logging ---
$Folder          = "$env:ProgramData\Liongard"
$LogFile         = "$Folder\ScriptReinstall.log"
$TranscriptPath  = "$Folder\TranscriptReinstall.txt"

if (-not (Test-Path -Path $Folder)) { New-Item -Path $Folder -ItemType Directory -ErrorAction SilentlyContinue | Out-Null }

try { Start-Transcript -Path $TranscriptPath -Append -Force -ErrorAction Stop } 
catch { Write-Host "WARNING: Transcript failed. Proceeding without it." -ForegroundColor Yellow }

function Write-Log {
    param( [string]$Message, [string]$Type="INFO" )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Type] $Message"
    Write-Host $LogEntry
    Add-Content -Path $LogFile -Value $LogEntry -Encoding Default -ErrorAction SilentlyContinue
}

function Exit-Smart {
    param ([int]$Code)
    Stop-Transcript -ErrorAction SilentlyContinue
    if ([Environment]::UserInteractive) {
        Write-Host "`n---------------------------------------------------"
        if ($Code -ne 0) { Write-Host "SCRIPT FAILED (Exit Code $Code) - Check logs above." -ForegroundColor Red }
        else { Write-Host "SCRIPT FINISHED SUCCESSFULLY" -ForegroundColor Green }
        Write-Host "---------------------------------------------------"
        Read-Host "Press Enter to close this window..."
    }
    Exit $Code
}

# --- 1. The "Friendly Enforcer" Input Function ---
function Get-RequiredInput {
    param ( [string]$CurrentValue, [string]$PromptName )

    # 1. If passed via RMM/Param, use it.
    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) { return $CurrentValue }

    # 2. If RMM (Headless), we can't ask. Return null to trigger graceful failure.
    if (-not [Environment]::UserInteractive) { return $null }

    # 3. Interactive Loop (The Friendly Reminder)
    $Val = $null
    do {
        $Val = Read-Host "`n$PromptName (Required)"
        if ([string]::IsNullOrWhiteSpace($Val)) {
            Write-Host "   [!] We can't proceed without the $PromptName." -ForegroundColor Yellow
            Write-Host "       Please enter it to continue." -ForegroundColor Gray
        }
    } until (-not [string]::IsNullOrWhiteSpace($Val))
    
    return $Val
}

Write-Log "--- Starting Liongard Agent RE-INSTALLATION (v2.3) ---"

# --- 2. Get Inputs (with Enforcement) ---
$Url          = Get-RequiredInput -CurrentValue $Url          -PromptName "1. Liongard URL"
$AccessKey    = Get-RequiredInput -CurrentValue $AccessKey    -PromptName "2. Access Key ID"
$AccessSecret = Get-RequiredInput -CurrentValue $AccessSecret -PromptName "3. Access Key Secret"

if ([string]::IsNullOrWhiteSpace($Environment) -and [Environment]::UserInteractive) {
    $Environment = Read-Host "`n4. Environment Name (Optional - Press Enter to skip)"
}

# --- 3. RMM Graceful Handling (Validation) ---
if (-not $Url -or -not $AccessKey -or -not $AccessSecret) {
    Write-Log "FATAL ERROR: Missing required variables." "ERROR"
    Write-Log "If running via RMM, you MUST pass these as script arguments." "ERROR"
    Exit-Smart 1
}

# --- 4. Sanitization ---
if ($Url -match "https://") { $Url = $Url -replace "https://","" -replace "/","" }
if ($Url -notmatch "\.app\.liongard\.com") {
    $Url = "$Url.app.liongard.com"
    Write-Log "Auto-corrected URL to: $Url"
}

$MsiPath         = "$env:TEMP\LiongardAgent-lts.msi" 
$DownloadUri     = "https://agents.static.liongard.com/LiongardAgent-lts.msi"
$MinMsiSize      = 10485760 
$MinFreeSpaceMB  = 200
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# --- 5. Download FRESH MSI (Before Uninstalling) ---
# We download first to ensure we don't break an existing agent if internet is down
Write-Log "Downloading Latest MSI..."
try {
    $Disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" | Select-Object FreeSpace
    if (([math]::Round($Disk.FreeSpace / 1MB)) -lt $MinFreeSpaceMB) { throw "Insufficient disk space." }

    Invoke-WebRequest -Uri $DownloadUri -OutFile $MsiPath -UseBasicParsing -ErrorAction Stop
    if ((Get-Item $MsiPath).Length -lt $MinMsiSize) { throw "File too small/Corrupt download." }
}
catch { Write-Log "Download failed: $_" "ERROR"; Exit-Smart 1 }

# --- 6. Detection & Removal Logic ---
Write-Log "Checking for existing Liongard Agent..."
$ExistingService = Get-Service | Where-Object { $_.Name -like "*Liongard*" -or $_.DisplayName -like "*Liongard*" }

if ($ExistingService) {
    Write-Log "Existing Agent Found: $($ExistingService.Name). Preparing to uninstall..."
    
    # Stop Service
    if ($ExistingService.Status -eq 'Running') {
        Write-Log "Stopping Service..."
        Stop-Service $ExistingService.Name -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    }

    # Find Product Code via Registry (Safer/Faster than Win32_Product)
    $UninstallKey = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall -ErrorAction SilentlyContinue |
        Get-ItemProperty | Where-Object { $_.DisplayName -like "*Liongard Agent*" } | Select-Object -First 1

    if ($UninstallKey) {
        $UninstallString = $UninstallKey.UninstallString
        if ($UninstallString -match "MsiExec.exe") {
            # Extract GUID from string like "MsiExec.exe /I{GUID}"
            $ProductCode = $UninstallString -replace "MsiExec.exe", "" -replace "/I", "" -replace "/X", ""
            $ProductCode = $ProductCode.Trim()
            
            Write-Log "Uninstalling Product Code: $ProductCode"
            $Proc = Start-Process "msiexec.exe" -ArgumentList "/x $ProductCode /qn /norestart" -Wait -PassThru
            
            if ($Proc.ExitCode -ne 0 -and $Proc.ExitCode -ne 3010) {
                Write-Log "Uninstall returned exit code $($Proc.ExitCode). Attempting to continue anyway..." "WARN"
            } else {
                Write-Log "Uninstall command completed."
            }
        }
    } else {
        Write-Log "Could not find MSI Product Code in Registry. Proceeding with overwrite attempt." "WARN"
    }

    # Optional: Cleanup Program Files (Leaves ProgramData logs alone)
    $ProgFiles = "$env:ProgramFiles\Liongard"
    if (Test-Path $ProgFiles) { 
        Write-Log "Cleaning up installation directory..."
        Remove-Item $ProgFiles -Recurse -Force -ErrorAction SilentlyContinue 
    }
    
    Start-Sleep -Seconds 5 # Let the OS breathe
} else {
    Write-Log "No existing agent detected. Proceeding with fresh install."
}

# --- 7. Install New Agent ---
Write-Log "Installing Fresh Liongard Agent..."
$EnvArg = if (-not [string]::IsNullOrWhiteSpace($Environment)) { "LIONGARDENVIRONMENT=`"$Environment`"" } else { "" }
$InstallLog = "$Folder\AgentInstall.log"
$InstallArgs = "/i `"$MsiPath`" LIONGARDURL=$Url LIONGARDACCESSKEY=$AccessKey LIONGARDACCESSSECRET=$AccessSecret $EnvArg LIONGARDAGENTNAME=`"$env:computername`" /qn /norestart /L*V `"$InstallLog`""

try {
    $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $InstallArgs -Wait -PassThru -NoNewWindow
    
    if ($Process.ExitCode -ne 0 -and $Process.ExitCode -ne 3010) { 
        $FailureReason = "Unknown MSI Error (Code $($Process.ExitCode))"
        Start-Sleep -Seconds 2 # Wait for log flush
        
        if (Test-Path $InstallLog) {
            $LogContent = Get-Content $InstallLog
            $Validation = $LogContent | Select-String -Pattern "INVALIDMSG = (.*)" | Select-Object -Last 1
            $StandardErr = $LogContent | Select-String -Pattern "Product: .* -- Error \d+" | Select-Object -Last 1
            $InternalErr = $LogContent | Select-String -Pattern "Note: 1: \d+ 2: (.*)" | Select-Object -Last 1
            
            if ($Validation) { $FailureReason = "INPUT ERROR: $($Validation.Matches.Groups[1].Value)" }
            elseif ($StandardErr) { $FailureReason = "SYSTEM ERROR: $($StandardErr.Line)" }
            elseif ($InternalErr) { $FailureReason = "INSTALLER ERROR: $($InternalErr.Matches.Groups[1].Value)" }
        }
        throw $FailureReason
    }
}
catch { Write-Log "$_" "ERROR"; Exit-Smart 1 }

# --- 8. Verification ---
Write-Log "Verifying Service Startup (Max 120s)..."
$Retry = 0; $Started = $false; $DetectedServiceName = $null
do {
    Start-Sleep -Seconds 5
    $Service = Get-Service | Where-Object { $_.Name -like "*Liongard*" -or $_.DisplayName -like "*Liongard*" } | Select-Object -First 1
    if ($Service -and $Service.Status -eq "Running") { $DetectedServiceName = $Service.Name; $Started = $true }
    $Retry++
} until ($Started -or $Retry -ge 24)

if ($Started) { 
    Write-Log "SUCCESS: Service '$DetectedServiceName' is Running." 
    Remove-Item $MsiPath -Force -ErrorAction SilentlyContinue
    Exit-Smart 0
} else { 
    Write-Log "WARNING: Service installed but not running." "WARN"
    Exit-Smart 1
}
