$application = Get-WmiObject -Class Win32_Product -Filter "Name = 'Liongard Agent'"
$application2 = Get-WmiObject -Class Win32_Product -Filter "Name = 'RoarAgent'"
$Folder='C:\Liongard'
$URL="XXX.app.liongard.com" 
$Key="PasteKeyHere" 
$Secret="PasteSecretHere"
$EnvironmentName="PasteEnvironmentName/RMM Variable"

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Checks for previous installs of the Liongard agent and stops if found.
if ($application) {
    Write-Host "A previous install of the Liongard Agent was found! Installation stopped."
    Exit
}
elseif ($application2) {
    Write-Host "A previous install of the Liongard Agent was found! Installation stopped."
    Exit
}
else {
    Write-Host "No Liongard Agent install was found. Proceeding with installation."
}

Start-Sleep -Seconds 10

# Checks if C:\Liongard exists, creates one if not, and downloads the MSI installer.
Write-Host "Checking if folder [$Folder] exists..."
if (Test-Path -Path $Folder) {
    Write-Host "Path exists! Downloading Liongard Agent installer, please wait..."
    Start-Sleep -Seconds 2
    # Downloads the Liongard MSI.
    Invoke-WebRequest -Uri "https://agents.static.liongard.com/LiongardAgent-lts.msi" -OutFile "C:\Liongard\LiongardAgent-lts.msi"
} 
else {
    Write-Host "Path doesn't exist. Creating Liongard folder in C:"
    # Creates the Liongard folder in C:\.
    New-Item -Path 'C:\Liongard' -ItemType Directory
    if (Test-Path -Path $Folder) {
        Write-Host "[$Folder] was created successfully! Downloading Liongard Agent installer, please wait..."
        Start-Sleep -Seconds 2
        # Downloads the Liongard MSI.
        Invoke-WebRequest -Uri "https://agents.static.liongard.com/LiongardAgent-lts.msi" -OutFile "C:\Liongard\LiongardAgent-lts.msi"
    } 
    else {
        Write-Host "Unable to create folder, please check permissions. Terminating Script in 10 Seconds."
        Start-Sleep -Seconds 10
        Exit
    }
}

# Installs the MSI in silent mode, with parameters, and generates a log in the same directory. 
Write-Host "Installing the Liongard Agent. Please wait."
msiexec.exe /i "C:\Liongard\LiongardAgent-lts.msi" LIONGARDURL=$URL LIONGARDACCESSKEY=$Key LIONGARDACCESSSECRET=$Secret LIONGARDENVIRONMENT=`"$EnvironmentName`" LIONGARDAGENTNAME="$env:computername" /qn /norestart /L*V "C:\Liongard\AgentInstall.log"
Start-Sleep -Seconds 2
