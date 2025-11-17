# --- Configuration Variables (REPLACE THESE) ---
# NOTE: Using backticks (`) for line continuation to keep config clean
$URL = "XXX.app.liongard.com"
$Key = "PasteKeyHere"
$Secret = "PasteSecretHere"
$EnvironmentName = "PasteEnvironmentName/RMM Variable"

# --- Script Configuration ---
$Folder = 'C:\Liongard'
$LogFile = "$Folder\ScriptInstall.log"
$MsiPath = "$Folder\LiongardAgent-lts.msi"
$DownloadUri = "https://agents.static.liongard.com/LiongardAgent-lts.msi"
$MinMsiSize = 10485760    # 10 MB in bytes (minimum expected size)
$MinFreeSpaceMB = 200     # Minimum required free disk space (MB)
$AgentService = "LiongardAgent" # Name of the installed service

# --- Proxy Configuration (Optional) ---
# Uncomment and configure if a Web Proxy is required for internet access
# If using a proxy, you may need to run PowerShell as the user with access to the proxy.
# $ProxyUrl = "http://proxy.corp.com:8080"
# $ProxyCredential = Get-Credential # Prompts user for credentials if needed

# Function for both console and file logging
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] $Message"
    Write-Host $LogEntry
    # Add-Content needs to use -Encoding to avoid BOM issues with some RMM tools
    Add-Content -Path $LogFile -Value $LogEntry -Encoding Default -ErrorAction SilentlyContinue
}

# --- Initialization and Setup ---
Write-Log "--- Starting Liongard Agent Installation Script ---"
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Write-Log "Set Security Protocol to TLS 1.2 successfully."
}
catch {
    $ErrorMessage = "ERROR: Failed to set TLS 1.2 protocol. This may cause download failure. $_"
    Write-Log $ErrorMessage
    Write-Error $ErrorMessage
}

# --- Check for Existing Agent ---
Write-Log "Checking for previous installs of Liongard Agent..."
$ProductNames = @('Liongard Agent', 'RoarAgent')
$ExistingAgent = $ProductNames | ForEach-Object {
    Get-WmiObject -Class Win32_Product -Filter "Name = '$_'" -ErrorAction SilentlyContinue
}

if ($ExistingAgent) {
    Write-Log "A previous install of the Liongard Agent was found! Installation stopped."
    Exit 0
}
else {
    Write-Log "No Liongard Agent install was found. Proceeding with installation."
}

# --- Folder Check, Creation, and Writable Test ---
Write-Log "Checking if folder [$Folder] exists..."
if (-not (Test-Path -Path $Folder)) {
    try {
        Write-Log "Path doesn't exist. Attempting to create Liongard folder in C:..."
        New-Item -Path $Folder -ItemType Directory | Out-Null
        Write-Log "[$Folder] was created successfully."
    }
    catch {
        $ErrorMessage = "ERROR: Failed to create folder [$Folder]. Check script permissions. $_"
        Write-Log $ErrorMessage
        Write-Error $ErrorMessage
        Write-Log "Terminating Script."
        Exit 1
    }
}
else {
    Write-Log "Path [$Folder] exists."
}

# Added: Destination Path Writable Check
$TestFile = "$Folder\write_test.tmp"
try {
    "Test" | Out-File $TestFile -Encoding ASCII -Force
    Remove-Item $TestFile -Force
    Write-Log "Successfully verified write access to $Folder."
}
catch {
    $ErrorMessage = "ERROR: Write access test failed on $Folder. Check script and user permissions. $_"
    Write-Log $ErrorMessage
    Write-Error $ErrorMessage
    Write-Log "Terminating Script."
    Exit 1
}

# --- ADDED: Disk Space Check ---
Write-Log "Checking for minimum $MinFreeSpaceMB MB of free space on C: drive..."
try {
    $Disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
    $FreeSpaceMB = [System.Math]::Round($Disk.FreeSpace / 1MB, 0)
    
    if ($FreeSpaceMB -lt $MinFreeSpaceMB) {
        $ErrorMessage = "ERROR: Insufficient free disk space. Required $MinFreeSpaceMB MB, available $FreeSpaceMB MB."
        Write-Log $ErrorMessage
        Write-Error $ErrorMessage
        Write-Log "Terminating Script."
        Exit 1
    }
    Write-Log "Disk space check passed. Available free space: $FreeSpaceMB MB."
}
catch {
    $ErrorMessage = "WARNING: Failed to retrieve disk space information. Proceeding with warning. $_"
    Write-Log $ErrorMessage
}

# --- Basic Connectivity Test ---
Write-Log "Testing basic internet connectivity (Google DNS 8.8.8.8)..."
if (-not (Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
    $ErrorMessage = "ERROR: Basic connectivity test failed. Check network cables/settings."
    Write-Log $ErrorMessage
    Write-Error $ErrorMessage
    Write-Log "Terminating Script."
    Exit 1
}
Write-Log "Basic connectivity check passed."

# --- MSI Installer Download with Robust Error Handling ---
Write-Log "Attempting to download installer from [$DownloadUri]..."
try {
    # Build IWR parameters, including proxy if configured
    $IWRParams = @{
        Uri          = $DownloadUri
        OutFile      = $MsiPath
        ErrorAction  = 'Stop'
        UseBasicParsing = $true # Use this for compatibility
    }
    
    # Check for optional Proxy configuration
    if ($PSBoundParameters.ContainsKey('ProxyUrl')) {
        $IWRParams.Proxy = $ProxyUrl
        Write-Log "Using explicit proxy: $ProxyUrl"
        if ($PSBoundParameters.ContainsKey('ProxyCredential')) {
            $IWRParams.ProxyCredential = $ProxyCredential
            Write-Log "Using explicit proxy credentials."
        }
    }

    # Execute download
    Invoke-WebRequest @IWRParams
    
    # Post-Download File Existence & Size Verification
    if (-not (Test-Path $MsiPath)) {
        throw "Download command succeeded but file $MsiPath was not found."
    }
    
    $MsiInfo = Get-Item $MsiPath
    if ($MsiInfo.Length -lt $MinMsiSize) {
        $ErrorSize = "$($MsiInfo.Length) bytes"
        throw "Downloaded file size ($ErrorSize) is too small (expected > $MinMsiSize bytes). The download likely failed or was corrupted."
    }
    
    Write-Log "Liongard Agent installer downloaded successfully and passed size verification."
}
catch {
    $ErrorMessage = "FATAL ERROR: Installer download failed. Common issues: Network, Firewall, Proxy, or DNS. Specific Error: $($_.Exception.Message)"
    Write-Log $ErrorMessage
    Write-Error $ErrorMessage
    
    Remove-Item $MsiPath -Force -ErrorAction SilentlyContinue
    Write-Log "Terminating Script due to download failure."
    Exit 1
}

# --- Installation ---
Write-Log "Installing the Liongard Agent..."
# Arguments need to be safe for RMM systems/executables
$InstallArgs = "/i `"$MsiPath`" LIONGARDURL=$URL LIONGARDACCESSKEY=$Key LIONGARDACCESSSECRET=$Secret LIONGARDENVIRONMENT=`"$EnvironmentName`" LIONGARDAGENTNAME=`"$env:computername`" /qn /norestart /L*V `"$Folder\AgentInstall.log`""

try {
    Write-Log "Executing msiexec..."
    # Use Start-Process with -Wait for synchronous, reliable execution
    Start-Process -FilePath "msiexec.exe" -ArgumentList $InstallArgs -Wait -NoNewWindow
    
    Write-Log "msiexec process finished. Checking installation status..."
    
    # Post-Installation Log Verification (MSI Success Code)
    $MsiLog = "$Folder\AgentInstall.log"
    Start-Sleep -Seconds 5 # Give log a moment to write
    
    if (-not (Test-Path $MsiLog)) {
        Write-Log "WARNING: Installation log file not found at $MsiLog. Cannot confirm MSI success via log."
    }
    elseif ((Get-Content $MsiLog | Select-String -Pattern "Product: Liongard Agent -- Installation operation successfully completed\.")) {
        Write-Log "Installation log shows SUCCESS."
    }
    else {
        $ErrorMessage = "ERROR: Installation log exists but does NOT show successful completion message. Check $MsiLog for MSI error codes."
        Write-Log $ErrorMessage
        Write-Error $ErrorMessage
        Write-Log "Terminating Script due to installation error."
        Exit 1
    }

    # Service Status Verification
    Start-Sleep -Seconds 10 # Give service time to initialize
    $Service = Get-Service -Name $AgentService -ErrorAction SilentlyContinue
    if ($Service -and $Service.Status -eq "Running") {
        Write-Log "Verification SUCCESS: Liongard Agent service is running."
    }
    else {
        $ErrorMessage = "WARNING: Liongard Agent service ($AgentService) not found or not running after installation. Check installation log."
        Write-Log $ErrorMessage
        Write-Error $ErrorMessage
    }
}
catch {
    $ErrorMessage = "FATAL ERROR: Agent installation failed during msiexec execution. Specific Error: $($_.Exception.Message)"
    Write-Log $ErrorMessage
    Write-Error $ErrorMessage
    Write-Log "Terminating Script."
    Exit 1
}

Write-Log "--- Script Finished Successfully ---"
Exit 0
