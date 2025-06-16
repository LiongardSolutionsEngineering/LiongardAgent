$ServiceCheck =  get-service | Where-Object {($_.DisplayName -contains "Roar Agent") -or ($_.DisplayName -contains "LionGard Agent")}
if (!$ServiceCheck)
{
write-host "Liongard is not found on this device. Exiting Script." -ForegroundColor Yellow
exit
}
else
{
##Download the latest MSI for Liongard Agent software into the C:\Liongard folder.  Also sets the TLS negotiation to 1.2.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$url = "https://agents.static.liongard.com/LiongardAgent-lts.msi"
$path = "C:\Liongard\LiongardAgent-lts.msi"
write-host "Downloading Liongard Agent Uninstaller..." -ForegroundColor Yellow
(New-Object System.Net.WebClient).DownloadFile($url, $path)
##Runs the installer quietly to remove agent
write-host "Uninstalling Liongard Agent..." -ForegroundColor Yellow
##Build Array for msiexec arguments
$Args = @(
    '/x'
    '"{0}"' -f $path
    '/q'
)
##Uninstalls the Liongard MSI using arguments above and waits for it to complete.
Start-Process msiexec.exe -ArgumentList $Args -Wait
write-host "Removing Installer..." -ForegroundColor Yellow
Remove-Item $path -Force
write-host "Uninstall Finished Running" -ForegroundColor Yellow

}