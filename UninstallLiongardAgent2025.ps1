<#
.SYNOPSIS
    Liongard Agent REMOVAL - Production Ready (v1.0)
.DESCRIPTION
    - Detects Liongard Agent via Registry (Fast/Safe).
    - Stops Service -> Uninstalls via MSI -> Cleans Program Files.
    - RMM Safe: Runs silently if non-interactive.
    - Human Safe: Asks for confirmation if run manually (unless -Force is used).
#>
param(
    [switch]$Force # Use this switch to skip the "Are you sure?" prompt when running manually
)

# --- 0. Setup & Logging ---
$Folder         = "$env:ProgramData\Liongard"
$LogFile        = "$Folder\ScriptUninstall.log"
# We log to ProgramData so the log survives the uninstall of Program Files
if (-not (Test-Path -Path $Folder)) { New-Item -Path $Folder -ItemType Directory -ErrorAction SilentlyContinue | Out-Null }

function Write-Log {
    param( [string]$Message, [string]$Type="INFO" )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Type] $Message"
    Write-Host $LogEntry
    Add-Content -Path $LogFile -Value $LogEntry -Encoding Default -ErrorAction SilentlyContinue
}

function Exit-Smart {
    param ([int]$Code)
    if ([Environment]::UserInteractive) {
        Write-Host "`n---------------------------------------------------"
        if ($Code -ne 0) { Write-Host "UNINSTALL FAILED (Exit Code $Code) - Check logs." -ForegroundColor Red }
        else { Write-Host "UNINSTALL COMPLETED SUCCESSFULLY" -ForegroundColor Green }
        Write-Host "---------------------------------------------------"
        Read-Host "Press Enter to close this window..."
    }
    Exit $Code
}

Write-Log "--- Starting Liongard Agent UNINSTALLATION ---"

# --- 1. Safety Check (The Friendly Gatekeeper) ---
if ([Environment]::UserInteractive -and -not $Force) {
    Write-Host "`nWARNING: You are about to completely remove the Liongard Agent from: $env:COMPUTERNAME" -ForegroundColor Yellow
    $Confirm = Read-Host "Are you sure you want to continue? (y/n)"
    if ($Confirm -notmatch "^[Yy]") {
        Write-Log "Uninstall cancelled by user." "INFO"
        Exit-Smart 0
    }
}

# --- 2. Detection Logic ---
Write-Log "Scanning for Liongard Agent..."

# Check Service
$Service = Get-Service | Where-Object { $_.Name -like "*Liongard*" -or $_.DisplayName -like "*Liongard*" } | Select-Object -First 1

# Check Registry (HKLM and Wow6432Node)
$UninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

$AgentReg = $null
foreach ($Key in $UninstallKeys) {
    $Result = Get-ChildItem -Path $Key -ErrorAction SilentlyContinue | 
              Get-ItemProperty | 
              Where-Object { $_.DisplayName -like "Liongard Agent*" } | 
              Select-Object -First 1
    if ($Result) { $AgentReg = $Result; break }
}

if (-not $Service -and -not $AgentReg) {
    Write-Log "Liongard Agent not found on this system." "WARN"
    Exit-Smart 0
}

# --- 3. Stop Service ---
if ($Service) {
    if ($Service.Status -eq 'Running') {
        Write-Log "Stopping Service: $($Service.Name)..."
        try {
            Stop-Service $Service.Name -Force -ErrorAction Stop
            Start-Sleep -Seconds 5
        }
        catch {
            Write-Log "Failed to stop service. Attempting uninstall anyway. Error: $_" "WARN"
        }
    } else {
        Write-Log "Service found but already stopped."
    }
}

# --- 4. MSI Removal ---
if ($AgentReg) {
    $UninstallString = $AgentReg.UninstallString
    
    # Parse the GUID from the uninstall string (usually "MsiExec.exe /I{GUID}")
    if ($UninstallString -match "{.*}") {
        $ProductCode = $matches[0]
        Write-Log "Found Product Code: $ProductCode"
        Write-Log "Executing Silent Uninstall..."
        
        try {
            $Proc = Start-Process "msiexec.exe" -ArgumentList "/x $ProductCode /qn /norestart" -Wait -PassThru
            
            if ($Proc.ExitCode -eq 0) {
                Write-Log "MSI Removal Successful."
            } elseif ($Proc.ExitCode -eq 3010) {
                Write-Log "MSI Removal Successful (Reboot Required)." "WARN"
            } else {
                Write-Log "MSI Removal returned non-zero exit code: $($Proc.ExitCode)" "ERROR"
                # We don't exit here; we continue to try to clean up files
            }
        } catch {
            Write-Log "Failed to execute MSI uninstall: $_" "ERROR"
        }
    } else {
        Write-Log "Could not parse Product Code from registry string: $UninstallString" "ERROR"
    }
} else {
    Write-Log "No Registry key found. Skipping MSI removal step."
}

# --- 5. Cleanup ---
Start-Sleep -Seconds 5 # Allow file handles to release

$Binaries = "$env:ProgramFiles\Liongard"
# Note: We leave ProgramData\Liongard intentionally so logs remain for audit purposes. 
# If you want to delete logs too, add: Remove-Item "$env:ProgramData\Liongard" -Recurse -Force

if (Test-Path $Binaries) {
    Write-Log "Cleaning up binaries in $Binaries..."
    try {
        Remove-Item $Binaries -Recurse -Force -ErrorAction Stop
        Write-Log "Binaries folder deleted."
    } catch {
        Write-Log "Could not fully delete binary folder (Files might be locked): $_" "WARN"
    }
}

# --- 6. Verification ---
$RemainingService = Get-Service | Where-Object { $_.Name -like "*Liongard*" }
if (-not $RemainingService) {
    Write-Log "SUCCESS: Liongard Agent has been removed."
    Exit-Smart 0
} else {
    Write-Log "WARNING: The Liongard service still appears to be present." "ERROR"
    Exit-Smart 1
}
