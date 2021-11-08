## Important locations
$installLocation = "C:\Program Files\WindowsPowerShell\Modules\wave"
$searchPath = "\\abelnr1.corp.aspentech.com\AspenPackageRepo\wave\*.zip"

## Variables for the cmd string
$latestPackage = (Get-ChildItem $searchPath | Sort-Object Name -Descending)[0]
$latestPackageName = $latestPackage.Name
$latestPackageBaseName = $latestPackage.BaseName
$latestPackagePath = $latestPackage.FullName
$stagingDirectory = Join-Path $env:TEMP "waveInstall"
$localPackage = Join-Path $stagingDirectory $latestPackageName
$localUnpacked = Join-Path $stagingDirectory $latestPackageBaseName
$newInstallPath = Join-Path $installLocation $latestPackageBaseName

## Install command string
$adminInstallCmdString = "New-Item '$($stagingDirectory)' -ItemType Directory -Force; Start-BitsTransfer '$($latestPackagePath)' '$($localPackage)'; Expand-Archive '$($localPackage)' '$($stagingDirectory)'; Copy-Item -Path '$($localUnpacked)' -Destination '$($newInstallPath)' -Recurse; Remove-Item '$($stagingDirectory)' -Recurse;"

## Check for previous install
if (Test-Path $installLocation) {
    "Previous installation detected. Please contact ryan.barden@aspentech.com for help."
    break
}

"
+---------------------------------------+
|        wave installation guide        |
+---------------------------------------+

Welcome to the wave installation guide! 

  This installer will first open a seperate elevated terminal to install the wave system. If prompted by windows, please accept the UAC.

  Once the system install is finished, the elevated terminal will close and the wave configuration will begin in this terminal.

  Press 'Enter' to start the installation or 'ctrl-c' to quit...
"
Read-Host

## Install wave
$installProc = Start-Process powershell -ArgumentList $adminInstallCmdString -Verb RunAs -PassThru
$wheel = "-\|/"
while (!$installProc.HasExited) {
    Write-Host -NoNewline "`rInstalling wave [$($wheel[$wid%4])]"
    $wid++
    Start-Sleep -Milliseconds 250
}
Write-Host "`rInstall complete. Begin Configuration"


# Start configuration
$ootbTemplateExample = Join-Path $newInstallPath "\bin\templates\wave.BaseWindows10.psd1"
$userFilesPath = "C:\Users\$($env:USERNAME)\Documents\wave"
$backupPath = Join-Path "C:\Users\$($env:USERNAME)\Documents" "wave_$(Get-Date -Format FileDate).zip"
$userTemplatesPath = Join-Path $userFilesPath "templates"
$waveUserConfigPath = Join-Path $userFilesPath "wave.conf.psd1"
$userExampleTemplate = Join-Path $userTemplatesPath "ExampleTemplate.psd1"

# Test path
if (Test-Path $userFilesPath) {
    ""
    "Previous wave user configuration has been detected. Wave will backup this information here:"
    "  $($backupPath)"
    "Contact ryan.barden@aspentech.com for instructions on how to restore these files after completeing the configuration process."
    "It is still possible you may lose any templates you have. Press 'ctr-c' to abort."
    Read-Host -Prompt "press any key to continue"
    Compress-Archive $userFilesPath $backupPath
    Remove-Item $userFilesPath -Force
} else {
    New-Item -Path $userFilesPath -ItemType Directory -Force | Out-Null
    New-Item -Path $userTemplatesPath -ItemType Directory -Force | Out-Null
}
""
"Welcome to wave configuration. To complete the installation please answer the following questions."
"Answers can be changed by modifying your config file '$($waveUserConfigPath)' at any time"
""
"Please enter a path where you would like wave to store new VM's"
$vmPath = Read-Host -Prompt "Path"
""
"Please enter the number corresponding to the domain you can join machines to"
"  [1] qae - quality members and testers"
"  [2] rnd - developers"
do {
    try {
        [ValidateSet('1','2')]$domainNum = Read-Host "Number" 
    } catch {}
} until ($?)
""
"Please enter the number corresponding to the office location closest to you"
"  [1] Bedford"
"  [2] Mexico City"
"  [3] Shanghai"
do {
    try {
        [ValidateSet('1','2','3')]$locationNum = Read-Host "Number" 
    } catch {}
} until ($?)

if ($domainNum -eq '1') {
    $domain = 'qae'
} elseif ($domainNum -eq '2') {
    $domain = 'rnd'
}

if ($locationNum -eq '1') {
    $location = 'bedford'
} elseif ($locationNum -eq '2') {
    $location = 'mexico'
} elseif ($locationNum -eq '3') {
    $location = 'shanghai'
}

$configContent = "@{
    VirtualMachineStorage = '$($vmPath)'
    Domain = '$($domain)'
    Location = '$($location)'
    DefaultTemplate = 'wave.BaseWindows10'
}"

Set-Content -Path $waveUserConfigPath -Value $configContent -Encoding UTF8 -Force
Copy-Item -Path $ootbTemplateExample -Destination $userExampleTemplate