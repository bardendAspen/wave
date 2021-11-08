
# $bedfordShareImageFolder = "\\abelnr1.corp.aspentech.com\BedfordShare\LiveImages\LI-W10"
# $vmHome = "F:\testVM"
# #$vmAdminCred = New-Object System.Management.Automation.PSCredential ("Admin", (ConvertTo-SecureString "Aspen100" -AsPlainText -Force))
# #$domainCred = New-Object System.Management.Automation.PSCredential ("qae\engqe", (ConvertTo-SecureString "ENGtop001" -AsPlainText -Force))
# $adminCred = Import-Clixml "admin.ps1.crd"
# $engqeCred = Import-Clixml "engqe.ps1.crd"
# $corpCred = Import-Clixml "corp.ps1.crd"

# Get the latest live image
# $latestImage = (Get-ChildItem (Join-Path $bedfordShareImageFolder "*.vhdx") | Sort-Object CreationTime -Descending)[0].FullName

# Define the vm parameters
#$vmName = "bardendW10-1"
# $vmAdminCred = New-Object System.Management.Automation.PSCredential ("$($vmName)\Admin", $adminCred.Password) 
# $externalSwitchList = Get-VMSwitch -SwitchType External
# if ($null -eq $externalSwitchList) {
#     $switch = "autoExtSwitch"
#     # Create new external switch
#     $netAdapter = (Get-NetAdapter -Name "Ethernet*" -Physical).Name
#     New-VMSwitch -Name $switch -NetAdapterName $netAdapter -AllowManagementOS $true
# } else {
#     $switch = $externalSwitchList[0].Name
# }
# $memStart = 2GB
# $processorCount = "4"
# $vmPath = Join-path $vmHome $vmName
# $vhdPath = Join-path $vmPath (Split-Path $latestImage -Leaf)

# Create the new vm
New-Item -Path $vmPath -ItemType Directory -Force | Out-Null
Copy-Item -Path $latestImage -Destination $vhdPath
New-VM -Name $vmName -MemoryStartupBytes $memStart -VHDPath $vhdPath -Path $vmPath -SwitchName $switch
Set-VM -Name $vmName -ProcessorCount $processorCount

# Start the vm and put it on the domain, do initial configurations  
Start-VM -Name $vmName
Wait-VM -Name $vmName
$session = New-PSSession -VMName $vmName -Credential $vmAdminCred
Invoke-Command -Session $session -ScriptBlock {
    # Add computer to domain and rename
    Add-Computer -DomainName "qae" -NewName $Using:vmName -Credential $Using:domainCred
}
Remove-PSSession $session
Restart-VM -VMName $vmName -Force -Wait

# Add current user as an admin
$member = "$($env:USERDOMAIN)\$($env:USERNAME)"
$session = New-PSSession -VMName $vmName -Credential $vmAdminCred
Invoke-Command -Session $session -ScriptBlock {Add-LocalGroupMember -Group "Administrators" -Member $Using:member}
Remove-PSSession $session


$session = New-PSSession -ComputerName "$($vmName).qae.aspentech.com" -Authentication Credssp -Credential $corpCred
$aesTargetVersion = "14.0"
$mediaServer = "\\HQAZRNDFS01\Upload$\aspenONEV$($aesTargetVersion)"
# Media search path
$mediaSearch = Join-Path $mediaServer "AES\Current\X64\*.iso"
$mediaPath = (Get-ChildItem $Using:mediaSearch | Sort-Object CreationTime -Descending)[0].FullName

Copy-Item $mediaPath -Destination "C:\Users\BARDEND\Desktop\" -ToSession $session