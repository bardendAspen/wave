$installLocation = "C:\Program Files\WindowsPowerShell\Modules\wave"
# Load the manifest
$manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'wave.psd1')
# Load the wave system config
###########$waveSystemConfig = Import-PowerShellDataFile (Join-Path $PSScriptRoot "\bin\system.conf.psd1")
# Load wave package config
$wavePackagesConfig = Import-PowerShellDataFile (Join-Path $PSScriptRoot '\bin\packages.conf.psd1')
# Define/load user variables
$userFilesPath = "C:\Users\$($env:USERNAME)\Documents\wave"
$userTemplatesPath = Join-Path $userFilesPath "templates"
$waveTemplatesPath = Join-Path $PSScriptRoot '\bin\templates'
$waveUserConfig = Import-PowerShellDataFile (Join-Path $userFilesPath "wave.conf.psd1")
$userAdminCredPath = Join-Path $userFilesPath "admin.ps1.crd"
$userCorpCredPath = Join-Path $userFilesPath "corp.ps1.crd"
$userTemplates = Get-ChildItem (Join-Path $userTemplatesPath "*.psd1")
$waveTemplates = Get-ChildItem (Join-Path $waveTemplatesPath "*.psd1")
$allTemplates = $userTemplates.BaseName + $waveTemplates.BaseName

# Version string
function versionCMD {
    return "v$($manifest.ModuleVersion)"
}

function waveHeader {
    return "wave $(versionCMD)
2021 Ryan Barden <ryan.barden@aspentech.com>
"
}

# Main function
function wave {
    param(
        [Parameter(Position=0)]
        [ValidateSet("deploy", "templates", "packages", "credentials", "update", "help", "version", "info")]
        # The command to run
        [string]$command,
        # The rest of the arguments
        [Parameter(Position=1, ValueFromRemainingArguments=$true)]
        $args
    )
    switch ($command) {
        "deploy"      { Invoke-Command -ScriptBlock $deployCMD -ArgumentList $args }
        "templates"   { templatesCMD $args }
        "packages"    { packagesCMD }
        "credentials" { credentialsCMD $args }
        "update"      { updateCMD }
        "help"        { helpCMD $args }
        "version"     { versionCMD }
        "info"        { infoCMD }
        Default       { helpCMD }
    }
}
Export-ModuleMember -Function wave

## Layer 1 commands
$deployCMD = {
    # Parameter help description
    param(
        [Parameter(Position=0)]
        [string]$vmName,
        [Parameter(Position=1)]
        [string]$template=$waveUserConfig.DefaultTemplate
    )

    # Check for vm name
    if (!$vmName) {
        deployHelp
        "Please provide a name for the new virtual machine. See above for more information."
        break
    }

    # Check vm name length
    if ($vmName.ToCharArray().Count -gt 15) {
        "Invalid VM Name $($vmName)" 
        ""
        "The net bios name is limited to 15 characters"
        break
    }

    # Check for and load template
    if (Test-Path (Join-Path $userTemplatesPath "$($template).psd1")) {
        $waveTemplate = Import-PowerShellDataFile (Join-Path $userTemplatesPath "$($template).psd1")
    } elseif (Test-Path (Join-Path $waveTemplatesPath "$($template).psd1")) {
        $waveTemplate = Import-PowerShellDataFile (Join-Path $waveTemplatesPath "$($template).psd1")
    } else {
        "No template found with the name $($template)"
        break
    }

    ## Main deployment script
    # Check for credenitals
    if ((Test-Path $userAdminCredPath) -and (Test-Path $userCorpCredPath)) {
        # Import and pass
        $adminCred = Import-Clixml $userAdminCredPath
        $corpCred = Import-Clixml $userCorpCredPath
    } else {
        # Prompt for credentials
        ""
        "No stored credentials detected. If you would like to store these credentials in an encrypted file and skip this step, run 'wave credentials store'."
        "If you choose to do this, you will need to refresh your corp credentials when you change them by running 'wave credentials refresh'. You can remove all credentials at any time with 'wave credentials purge'."
        ""
        "Please enter password for the default local Admin"
        $admin = Read-Host "Password" -AsSecureString
        ""
        "Please enter password for $($env:USERDOMAIN)\$($env:USERNAME)"
        $corpUser = Read-Host "Password" -AsSecureString

        # Create credential objects
        $adminCred = New-Object -typename System.Management.Automation.PSCredential -argumentlist "Admin",$admin
        $corpCred = New-Object -typename System.Management.Automation.PSCredential -argumentlist "$($env:USERDOMAIN)\$($env:USERNAME)",$corpUser
    }

    # Check for update
    $updateMessage = waveUpdateIsAvailable
    if ($updateMessage) {
        ""
        "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        "  wave update available. Please update wave"
        "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    }

    "$(waveHeader)"
    "Gathering information and preparing the deployment - $((Get-Date).ToString())"
    # Get the latest image
    $baseImage = getBaseImagePath -os $waveTemplate.virtualMachineSpecs.operatingSystem -region $waveUserConfig.location

    # Get package lists
    $waveWebPackages = (Compare-Object -ReferenceObject @($wavePackagesConfig.WaveWebPackages.Keys) -DifferenceObject $waveTemplate.softwarePackages.wavePackages -ExcludeDifferent -IncludeEqual).InputObject
    $waveLocalPackages = (Compare-Object -ReferenceObject @($wavePackagesConfig.AspenPackageRepo.WavePackages.Keys) -DifferenceObject $waveTemplate.softwarePackages.wavePackages -ExcludeDifferent -IncludeEqual).InputObject
    $waveRequiredPackages = @($wavePackagesConfig.AspenPackageRepo.RequiredPackages.Keys)

    # Get the number of packages
    $totalPackages = $waveWebPackages.Count + $waveLocalPackages.Count + $waveRequiredPackages.Count

    # Define the local vm admin cred
    $vmAdminCred = New-Object System.Management.Automation.PSCredential ("$($vmName)\Admin", $adminCred.Password)
    
    # Check for external switch
    $externalSwitchList = Get-VMSwitch -SwitchType External
    if ($null -eq $externalSwitchList) {
        $switch = "waveExtSwitch"
        " - No external switch detected. Creating new switch: $($switch)"
        # Create new external switch
        $netAdapter = (Get-NetAdapter -Name "Ethernet*" -Physical).Name
        New-VMSwitch -Name $switch -NetAdapterName $netAdapter -AllowManagementOS $true
    } else {
        $switch = $externalSwitchList[0].Name
    }
    # Define new vm paths
    $vmPath = Join-path $waveUserConfig.virtualMachineStorage $vmName
    $vhdPath = Join-path $vmPath (Split-Path $baseImage -Leaf)
    $baseImageSourcePath = Split-Path $baseImage
    $baseImageFileName = Split-Path $baseImage -Leaf

    # Print info to console
    ""
    " $($vmName).$($waveUserConfig.domain).aspentech.com"
    "-----------------------------------"
    " Operating System..$($waveTemplate.virtualMachineSpecs.operatingSystem)"
    " Startup RAM.......$($waveTemplate.virtualMachineSpecs.startupMemory/1GB) GB"
    " CPUs..............$($waveTemplate.virtualMachineSpecs.cpus)"
    " Switch............$($switch)"
    " VM Storage........$($vmPath)"
    " Packages..........$($totalPackages)"
    ""

    ### Begin building the vm
    $totalSteps = 7
    ## Create the new vm
    # Get base image
    Write-Progress -Id 0 -Activity "Building $($vmName)" -Status 'Getting Base Image' -PercentComplete ((100/$totalSteps)*0)
    New-Item -Path $vmPath -ItemType Directory -Force | Out-Null
    #Copy-Item -Path $baseImage -Destination $vhdPath
    #Start-BitsTransfer -Source $baseImage -Destination $vhdPath -DisplayName "Base Image Download" -Description "Destination: $($vhdPath)"
    Start-RoboCopy -SourceDirectory $baseImageSourcePath -DestinationDirectory $vmPath -FileName $baseImageFileName -ParentId 0 -Id 1
    # Create vm
    Write-Progress -Id 0 -Activity "Building $($vmName)" -Status 'Creating VM' -PercentComplete ((100/$totalSteps)*1)
    if ($waveTemplate.virtualMachineSpecs.operatingSystem -eq "Windows11") {
        New-VM -Name $vmName -MemoryStartupBytes $waveTemplate.virtualMachineSpecs.startupMemory -VHDPath $vhdPath -Path $vmPath -SwitchName $switch -Generation 2 | Out-Null
    } else {
        New-VM -Name $vmName -MemoryStartupBytes $waveTemplate.virtualMachineSpecs.startupMemory -VHDPath $vhdPath -Path $vmPath -SwitchName $switch | Out-Null
    }
    
    Set-VM -Name $vmName -ProcessorCount $waveTemplate.virtualMachineSpecs.cpus -AutomaticCheckpointsEnabled $false

    ## Start the vm and put it on the domain
    # Start VM and open session
    Write-Progress -Id 0 -Activity "Building $($vmName)" -Status 'Starting VM and opening a session' -PercentComplete ((100/$totalSteps)*2)
    Start-VM -Name $vmName
    Wait-VM -Name $vmName
    $session = New-PSSession -VMName $vmName -Credential $adminCred

    ## Domain Join New ##
    $domainController = Get-DomainController -domainName $waveUserConfig.domain
    # Try to join and rename
    Write-Progress -Id 0 -Activity "Building $($vmName)" -Status 'Renaming & joining the domain' -PercentComplete ((100/$totalSteps)*3)
    try {
        $tryRename = $false
        Invoke-Command -Session $session -ScriptBlock {Add-Computer -DomainName $Using:waveUserConfig.domain -NewName $Using:vmName -Server $Using:domainController -Credential $Using:corpCred -Force 3>$null} -ErrorAction Stop
        Remove-PSSession $session
        Stop-VM -Name $vmName
        Start-VM -Name $vmName
        Wait-VM  -Name $vmName
    }
    catch {
        # "Initial domain join failed"
        # "  $($_.Exception)"
        $tryRename = $true
    }

    if ($tryRename) {
        Write-Progress -Id 1 -ParentId 0 -Activity "Retry Domain Join" -Status "Adding to workgroup" -PercentComplete 0
        # Rename the machine on the workgroup
        try {
            Invoke-Command -Session $session -ScriptBlock {Add-Computer -WorkgroupName "WAVETEMP" -NewName $Using:vmName -Credential $Using:corpCred -Force 3>$null} -ErrorAction Stop
        }
        catch {
            "Unable to join the machine to a workgroup. This is a known issue likely caused by a machine with the same"
            "name already having an account on the domain controller. You can finish setting the vm up manually or try"
            "again with a new name."
            Write-Error $_.Exception -ErrorAction Stop
        }
        # Restart the machine
        Remove-PSSession $session
        Stop-VM -Name $vmName
        Start-VM -Name $vmName
        Wait-VM  -Name $vmName
        # Init the retry loop
        $retry = $true
        $retryCount = 0
        do {
            $retryCount++
            Write-Progress -Id 1 -ParentId 0 -Activity "Retry Domain Join" -Status "Attempt $($retryCount)/10" -PercentComplete ($retryCount*10)
            $session = New-PSSession -VMName $vmName -Credential $vmAdminCred
            try {
                Invoke-Command -Session $session -ScriptBlock {Add-Computer -DomainName $Using:waveUserConfig.domain -Server $Using:domainController -Credential $Using:corpCred -Force 3>$null} -ErrorAction Stop
                $retry = $false
                Write-Progress -Id 1 -ParentId 0 -Activity "Retry Domain Join" -Status "Attempt $($retryCount)" -Completed
            }
            catch {
                if ($retryCount -ge 10) {
                    "Unable to join the machine to the domain. This is a known issue likely caused by a machine with the same"
                    "name already having an account on the domain controller. You can finish setting the vm up manually or try"
                    "again with a new name."
                    #Write-Error $_.Exception.InnerException.Message -ErrorAction Stop
                    Write-Error $_.Exception -ErrorAction Stop
                } 
            }
            Remove-PSSession $session
            Stop-VM -Name $vmName
            Start-VM -Name $vmName
            Wait-VM  -Name $vmName
        } while ($retry)
    }
    
    #### DOMAIN JOIN OLD #####
    # # Rename the machine
    # Write-Progress -Id 0 -Activity "Building $($vmName)" -Status 'Rename the machine' -PercentComplete ((100/$totalSteps)*4)
    # Invoke-Command -Session $session -ScriptBlock {
    #     #Add-Computer -DomainName $Using:waveUserConfig.domain -NewName $Using:vmName -Credential $Using:corpCred -WhatIf
    #     Rename-Computer -NewName $Using:vmName -Force 3>$null
    #     # $tryCount = 0
    #     # while ($true) {
    #     #     try {
    #     #         $tryCount++
    #     #         Write-Progress -Id 0 -Activity "Building $($Using:vmName)" -Status "Join Domain - Attempt $($tryCount)" -PercentComplete ((100/$Using:totalSteps)*4)
    #     #         Add-Computer -DomainName $Using:waveUserConfig.domain -Credential $Using:corpCred -Force -ErrorAction Stop 3>$null
    #     #         break
    #     #     }
    #     #     catch {
    #     #         if ($tryCount -ge 10) {
    #     #             Write-Error $_.Exception.InnerException.Message -ErrorAction Stop
    #     #         }
    #     #         Start-Sleep -Seconds 1
    #     #     }
    #     # }
    # }
    # Remove-PSSession $session
    # Stop-VM -Name $vmName
    # Start-VM -Name $vmName
    # Wait-VM  -Name $vmName

    # # Add to the domain
    # Write-Progress -Id 0 -Activity "Building $($vmName)" -Status 'Joining The Domain' -PercentComplete ((100/$totalSteps)*4)
    # $retry = $true
    # $retryCount = 0
    # do {
    #     $session = New-PSSession -VMName $vmName -Credential $adminCred
    #     try {
    #         $retryCount++
    #         Write-Progress -Id 0 -Activity "Building $($vmName)" -Status "Joining The Domain Attempt $($retryCount)" -PercentComplete ((100/$totalSteps)*4)
    #         Invoke-Command -Session $session -ScriptBlock {Add-Computer -DomainName $Using:waveUserConfig.domain -Credential $Using:corpCred -Force 3>$null} -ErrorAction Stop
    #         $retry = $false
    #     }
    #     catch {
    #         if ($retryCount -ge 10) {
    #             "Unable to join the machine to the domain. This is a known issue likely caused by a machine with the same"
    #             "already haveing an account on the domina controller. You can finish setting the vm up manually or try"
    #             "again with a new name."
    #             Write-Error $_.Exception.InnerException.Message -ErrorAction Stop
    #         } else {
    #             #Start-Sleep -Seconds 1
    #             Remove-PSSession $session
    #             Stop-VM -Name $vmName
    #             Start-VM -Name $vmName
    #             Wait-VM  -Name $vmName
    #         }    
    #     }
    #     # "Removing Session"
    #     # Remove-PSSession $session
    #     # Stop-VM -Name $vmName
    #     # Start-VM -Name $vmName
    #     # Wait-VM  -Name $vmName
    # } while ($retry)
    # # Invoke-Command -Session $session -ScriptBlock {
    # #     Add-Computer -DomainName $Using:waveUserConfig.domain -Credential $Using:corpCred -Force 3>$null
    # # }
    # Remove-PSSession $session
    # Stop-VM -Name $vmName
    # Start-VM -Name $vmName
    # Wait-VM  -Name $vmName
    ##############################

    ## Post domain configuration
    # Add current user as an admin
    Write-Progress -Id 0 -Activity "Building $($vmName)" -Status 'Adding Current User' -PercentComplete ((100/$totalSteps)*4)
    $member = "$($env:USERDOMAIN)\$($env:USERNAME)"
    $session = New-PSSession -VMName $vmName -Credential $vmAdminCred
    Invoke-Command -Session $session -ScriptBlock {Add-LocalGroupMember -Group "Administrators" -Member $Using:member}
    Remove-PSSession $session

    # # Install packages
    $session = New-PSSession -VMName $vmName -Credential $corpCred
    Write-Progress -Id 0 -Activity "Building $($vmName)" -Status 'Installing Packages' -PercentComplete ((100/$totalSteps)*5)
    # Create temp install file
    $tempInstallDirectory = "C:\tempInstall"
    Invoke-Command -Session $session -ScriptBlock {New-Item $Using:tempInstallDirectory -ItemType Directory | Out-Null}
    $packNum = 0
    # Install Required Package
    foreach ($package in $waveRequiredPackages) {
        Write-Progress -Id 1 -ParentId 0 -Activity "Installing Package $($packNum+1)/$($totalPackages)" -Status $package -PercentComplete ((100/$totalPackages)*$packNum)
        $uri = Join-Path "\\$($wavePackagesConfig.AspenPackageRepo.hosts[$waveUserConfig.location])" $wavePackagesConfig.AspenPackageRepo.RequiredPackages[$package].Uri
        $uriRoot = Split-Path $uri
        $uriLeaf = (Split-Path $uri -Leaf)
        $installerArguments = $wavePackagesConfig.AspenPackageRepo.RequiredPackages[$package].Args
        $installerPath = Join-Path $tempInstallDirectory $uriLeaf
        Invoke-Command -Session $session -ScriptBlock {
            # Download packages
            #Start-BitsTransfer -Source $Using:uri -Destination $Using:installerPath -DisplayName "Downloading Package" -Description $Using:uri
            robocopy $Using:uriRoot $Using:tempInstallDirectory $Using:uriLeaf /NJS /NJH > $null
            # Install Package
            Start-Process $Using:installerPath -Wait -ArgumentList $Using:installerArguments
        }
        $packNum ++
    }
    # Install Local Packages
    foreach ($package in $waveLocalPackages) {
        Write-Progress -Id 1 -ParentId 0 -Activity "Installing Package $($packNum+1)/$($totalPackages)" -Status $package -PercentComplete ((100/$totalPackages)*$packNum)
        $uri = Join-Path "\\$($wavePackagesConfig.AspenPackageRepo.hosts[$waveUserConfig.location])" $wavePackagesConfig.AspenPackageRepo.WavePackages[$package].Uri
        $uriRoot = Split-Path $uri
        $uriLeaf = (Split-Path $uri -Leaf)
        $installerPath = Join-Path $tempInstallDirectory $uriLeaf
        # Check For Visual Studio
        $isVisualStudio = $package -in @("VisualStudioEnterprise2017","VisualStudioEnterprise2019","VisualStudioEnterprise2022")
        $vsConfigDeclared = $waveTemplate.SoftwarePackages.VisualStudioConfigFile -ne $null
        if ($isVisualStudio -and $vsConfigDeclared) {
            $configURI = Join-Path "\\$($wavePackagesConfig.AspenPackageRepo.hosts[$waveUserConfig.location])" $wavePackagesConfig.AspenPackageRepo.VisualStudioConfigFiles[$waveTemplate.SoftwarePackages.VisualStudioConfigFile]
            $configInstallPath = Join-Path $tempInstallDirectory "$($waveTemplate.SoftwarePackages.VisualStudioConfigFile).vsconfig"
            $installerArguments = "$($wavePackagesConfig.AspenPackageRepo.WavePackages[$package].Args) --config $($configInstallPath)"
            Invoke-Command -Session $session -ScriptBlock {
                # Download packages
                robocopy $Using:uriRoot $Using:tempInstallDirectory $Using:uriLeaf /NJS /NJH > $null
                Copy-Item -Path $Using:configURI -Destination $Using:configInstallPath
                # Install Package
                Start-Process $Using:installerPath -Wait -ArgumentList $Using:installerArguments
            }
        } else {
            $installerArguments = $wavePackagesConfig.AspenPackageRepo.WavePackages[$package].Args
            Invoke-Command -Session $session -ScriptBlock {
                # Download packages
                #Start-BitsTransfer -Source $Using:uri -Destination $Using:installerPath -DisplayName "Downloading Package" -Description $Using:uri
                robocopy $Using:uriRoot $Using:tempInstallDirectory $Using:uriLeaf /NJS /NJH > $null
                # Install Package
                if ($Using:installerArguments) {
                    Start-Process $Using:installerPath -Wait -ArgumentList $Using:installerArguments
                } else {
                    Start-Process $Using:installerPath -Wait
                }
            }
        }
        $packNum ++
    }
    # Install Web Packages
    foreach ($package in $waveWebPackages) {
        Write-Progress -Id 1 -ParentId 0 -Activity "Installing Package $($packNum+1)/$($totalPackages)" -Status $package -PercentComplete ((100/$totalPackages)*$packNum)
        $uri = $wavePackagesConfig.WaveWebPackages[$package].Uri
        $installerArguments = $wavePackagesConfig.WaveWebPackages[$package].Args
        $installerPath = Join-Path $tempInstallDirectory "$($package).$($wavePackagesConfig.WaveWebPackages[$package].InstallerType)"
        Invoke-Command -Session $session -ScriptBlock {
            # Download packages
            cmd /c "curl -L `"$($Using:uri)`" --output `"$($Using:installerPath)`" 2>&0"
            #Start-BitsTransfer -Source $Using:uri -Destination $Using:installerPath -DisplayName "Downloading Package" -Description $Using:uri
            # Install Package
            Start-Process $Using:installerPath -Wait -ArgumentList $Using:installerArguments
        }
        $packNum ++
    }
    # Run winget installs
    # foreach ($wingetID in $waveTemplate.softwarePackages.wingetPackages) {
    #     Write-Progress -Id 1 -ParentId 0 -Activity "Installing Package $($packNum)/$($totalPackages)" -Status $wingetID -PercentComplete ((100/$totalPackages)*$packNum)
    #     Invoke-Command -Session $session -ScriptBlock {winget install --id $Using:wingetID}
    #     $packNum ++
    # }
    Write-Progress -Id 1 -ParentId 0 -Activity "Installing Package $($packNum)/$($totalPackages)" -Status "Complete" -Completed
    Remove-PSSession $session
    
    # Install Aspen Software
    Write-Progress -Id 0 -Activity "Building $($vmName)" -Status 'Installing Aspen Software' -PercentComplete ((100/$totalSteps)*6)

    Write-Progress -Id 0 -Activity "Building $($vmName)" -Status 'Final Restart' -PercentComplete ((100/$totalSteps)*7)
    Restart-VM -VMName $vmName -Force -Wait
    "$($vmName).$($waveUserConfig.domain).aspentech.com is ready. Have fun."
    # Update message
    if ($updateMessage) {
        ""
        "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        "  wave update available. Please update wave"
        "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    }
}
function templatesCMD {
    # Parameter help description
    param(
        [Parameter(Position=0)]
        $templateCommand
    )

    switch ($templateCommand) {
        "list"                                 { getTemplateList }
        {$templateCommand -in ($allTemplates)} { getTemplateInfo $templateCommand }
        Default                                { templatesHelp }
    }

}
function packagesCMD {
    ""
    "  -- Operating Systems --"
    $wavePackagesConfig.LiveImages.operatingSystems.Keys | Sort-Object | Format-Wide {$_} -AutoSize -Force
    "  -- wave Packages --"
    $wavePackagesConfig.WaveWebPackages.Keys + $wavePackagesConfig.AspenPackageRepo.WavePackages.Keys | Sort-Object | Format-Wide {$_} -AutoSize -Force
    "winget and chocolatey packages are currently not supported but may be added in the future."
}
function credentialsCMD {
    param(
        [Parameter(Position=0)]
        [string]$arg
    )
    switch ($arg) {
        "store"   { storeUserCredentials }
        "refresh" { refreshCorpCredentials }
        "purge"   { purgeCredentials }
        Default   { credentialsHelp }
    }
}
function updateCMD {
    # Check for available updates
    if (waveUpdateIsAvailable) {
        # Get update command string 
        $cmdString = getAdminUpdateString
        "Calling elevated process"
        # Start command as admin
        Start-Process powershell -ArgumentList $cmdString -Verb RunAs -Wait
        "wave has been updated"
        "please restart powershell before using wave"
    } else {
        "wave is up to date."
    }
}
function helpCMD {
    param(
        [Parameter(Position=0)]
        [string]$arg
    )
    switch ($arg) {
        "deploy"      { deployHelp }
        "templates"   { templatesHelp }
        "credentials" { credentialsHelp }
        Default       { generalHelp }
    }
}
function infoCMD {
    return "$(waveHeader)
  User Config File..$(Join-Path $userFilesPath "wave.conf.psd1")
  VM Storage path...$($waveUserConfig.virtualMachineStorage)
  Domain............$($waveUserConfig.domain)
  Location..........$($waveUserConfig.location)
  Default Template..$($waveUserConfig.DefaultTemplate)
"
}

## Documentation functions/help
function generalHelp {
    return "$(waveHeader)
Wave automates virtual evironments from the command line.

usage: wave [<command>] [<arguments>]

The following commands are available:
    deploy       Deploys given template or the default if no option is passed
    templates    List or create new environment templates
    packages     List supported operating systems and packages for use in template files
    credentials  Store, refresh, or remove saved credentials
    update       Checks for wave updates
    help         Display help

For details on a specific command, pass it to help: wave help <command>

The following commands display wave information:
    version  Display installed wave version
    info     Display wave info
"
}
function deployHelp {
    return "$(waveHeader)
The deploy command creates a new VM following the specifications defined in the template passed as an argument. The defualt template is used if one is not specified by the user.

usage: wave deploy <name> [<template>]

example: wave deploy NewVM MyTemplate

The following arguments are available:
    name         Required. Name of the vm being created. Must be less than 15 characters.
    template     Optional. Deploys the given template. If blank the default template will be used.
"
}
function templatesHelp {
    return "$(waveHeader)
The templates command helps manage and view user templates. If no argument is specified, wave will show this page.

usage: wave templates [<argument>]

example: wave templates list
example: wave templates MyTemplate

The following arguments are available:
    list         Lists templates available to user
    template     Displays information about the given template
"
}
function credentialsHelp {
    return "$(waveHeader)
The credentials command helps store, refresh or purge user credentials. If no argument is specified, wave will show this page.

usage: wave credentials [<argument>]

example: wave credentials store

The following arguments are available:
    store        Stores encrypted credentials on disk. Allows user to skip credential prompts.
    refresh      Refreshes users corp credentials. Run this after changing your password.
    purge        Permanently removes all stored credentials .
"
}

## supporting functions
function getTemplateList {
    ""
    "  -- wave Templates --"
    $waveTemplates | Format-Wide -Property BaseName -AutoSize
    "  -- User Templates --"
    $userTemplates | Format-Wide -Property BaseName -AutoSize
}
function getTemplateInfo {
    param(
        [Parameter(Position=0)]
        $template
    )
    if (Test-Path (Join-Path $userTemplatesPath "$($template).psd1")) {
        $waveTemplate = Import-PowerShellDataFile (Join-Path $userTemplatesPath "$($template).psd1")
    } elseif (Test-Path (Join-Path $waveTemplatesPath "$($template).psd1")) {
        $waveTemplate = Import-PowerShellDataFile (Join-Path $waveTemplatesPath "$($template).psd1")
    } else {
        "No template found with the name $($template)"
        break
    }
    ""
    "$($template):"
    "  $($waveTemplate.virtualMachineSpecs.operatingSystem)"
    "  $($waveTemplate.virtualMachineSpecs.cpus) CPUs"
    "  $($waveTemplate.virtualMachineSpecs.startupMemory/1GB) GBs Startup Ram"
    "Packages:"
    $waveTemplate.softwarePackages.wavePackages | Format-Wide {$_} -AutoSize -Force
}
function getUserCredentials {
    if ((Test-Path $userAdminCredPath) -and (Test-Path $userCorpCredPath)) {
        # Import and pass
    } else {
        # Prompt for credentials
        "No stored credentials detected. If you would like to store these credentials in an encrypted file and skip this step, run 'wave credentials store'. If you choose to do this, you will need to refresh your corp credentials when you change them by running 'wave credentials refresh'. You can remove all credentials at any time with 'wave credentials purge'."
        ""
        "Please enter password for the default local Admin"
        $admin = Read-Host "Password" -AsSecureString
        ""
        "Please enter password for $($env:USERDOMAIN)\$($env:USERNAME)"
        $corpUser = Read-Host "Password" -AsSecureString

        # Export credential object to encrypted file on disk
        $adminCred = New-Object -typename System.Management.Automation.PSCredential -argumentlist "Admin",$admin
        $corpCred = New-Object -typename System.Management.Automation.PSCredential -argumentlist "$($env:USERDOMAIN)\$($env:USERNAME)",$corpUser
        
    }
    return $adminCred,$corpCred
}
function storeUserCredentials {
    "Please enter password for the default local Admin"
    $admin = Read-Host "Password" -AsSecureString
    ""
    "Please enter password for $($env:USERDOMAIN)\$($env:USERNAME)"
    $corpUser = Read-Host "Password" -AsSecureString

    # Export credential object to encrypted file on disk
    New-Object -typename System.Management.Automation.PSCredential -argumentlist "Admin",$admin | Export-CliXml $userAdminCredPath
    New-Object -typename System.Management.Automation.PSCredential -argumentlist "$($env:USERDOMAIN)\$($env:USERNAME)",$corpUser | Export-CliXml $userCorpCredPath
}
function refreshCorpCredentials {
    "Please enter password for $($env:USERDOMAIN)\$($env:USERNAME)"
    $corpUser = Read-Host "Password" -AsSecureString

    # Export credential object to encrypted file on disk
    New-Object -typename System.Management.Automation.PSCredential -argumentlist "$($env:USERDOMAIN)\$($env:USERNAME)",$corpUser | Export-CliXml $userCorpCredPath
}
function purgeCredentials {
    Remove-Item $userAdminCredPath -Force
    Remove-Item $userCorpCredPath -Force
}
function getBaseImagePath {
    param ($os,$region)
    $searchPath = Join-Path (Join-Path "\\$($wavePackagesConfig.LiveImages.hosts[$region])" $wavePackagesConfig.LiveImages.operatingSystems[$os].path) "*.vhdx"
    return (Get-ChildItem $searchPath | Sort-Object CreationTime -Descending)[0].FullName
}
function waveUpdateIsAvailable {
    $currentVersion = $manifest.ModuleVersion
    $searchPath = Join-Path (Join-Path "\\$($wavePackagesConfig.AspenPackageRepo.hosts[$waveUserConfig.location])" $wavePackagesConfig.AspenPackageRepo.packages.wave) "*.zip"
    $latestVersion = (Get-ChildItem $searchPath | Sort-Object Name -Descending)[0].BaseName
    if ($latestVersion -eq $currentVersion) {
        return $false
    } else {
        return $true
    }
}
function getAdminUpdateString {
    $searchPath = Join-Path (Join-Path "\\$($wavePackagesConfig.AspenPackageRepo.hosts[$waveUserConfig.location])" $wavePackagesConfig.AspenPackageRepo.packages.wave) "*.zip"
    $latestPackage = (Get-ChildItem $searchPath | Sort-Object Name -Descending)[0]
    $latestPackageName = $latestPackage.Name
    $latestPackageBaseName = $latestPackage.BaseName
    $latestPackagePath = $latestPackage.FullName
    $stagingDirectory = Join-Path $env:TEMP "waveInstall"
    $localPackage = Join-Path $stagingDirectory $latestPackageName
    $localUnpacked = Join-Path $stagingDirectory $latestPackageBaseName
    $newInstallPath = Join-Path $installLocation $latestPackageBaseName
    $oldInstallPath = Join-Path $installLocation $manifest.ModuleVersion
    return "New-Item '$($stagingDirectory)' -ItemType Directory -Force; Start-BitsTransfer '$($latestPackagePath)' '$($localPackage)'; Expand-Archive '$($localPackage)' '$($stagingDirectory)'; Copy-Item -Path '$($localUnpacked)' -Destination '$($newInstallPath)' -Recurse; Remove-Item '$($oldInstallPath)' -Recurse; Remove-Item '$($stagingDirectory)' -Recurse;"
}
function Start-RoboCopy {
    param (
        [Parameter(Mandatory=$true)]
        $SourceDirectory,
        [Parameter(Mandatory=$true)]
        $DestinationDirectory,
        [Parameter(Mandatory=$true)]
        $FileName,
        $ParentId = 0,
        $Id = $ParentId + 1
    )
    
    $tempOutFile = Join-Path $env:TEMP "roboProgress.txt"
    $jobInfo = Start-Job -ScriptBlock {robocopy $Using:SourceDirectory $Using:DestinationDirectory $Using:FileName /NJS /NJH > $Using:tempOutFile}
    Start-Sleep -Milliseconds 500
    $idx = 0
    #$wheel = "||||||||////////--------\\\\\\\\"
    $wheel = "|/-\"
    $wheelCount = $wheel.ToCharArray().Count
    while ($true) {
        if (Test-Path $tempOutFile) {
            if (Get-Content $tempOutFile -Tail 1) {
                if ((Get-Content $tempOutFile -Tail 1).Contains("%")) {
                    break
                }
            }
        }
    }
    while ($jobInfo.State -ne 'Completed') {
        $percentComplete = (Get-Content $tempOutFile -Tail 1).Split('%')[0].Trim()
        Write-Progress -Activity "Downloading [$($wheel[$idx%$wheelCount])]" -Status $FileName -PercentComplete $percentComplete -Id $Id -ParentId $ParentId
        $idx++
        Start-Sleep -Milliseconds 250
    }
    Write-Progress -Activity "Finished" -Status $FileName -Completed -Id $Id -ParentId $ParentId
    $jobInfo | Remove-Job
    Remove-Item $tempOutFile
}
function Get-DomainController {
    param (
        [Parameter(Mandatory=$true)]
        $domainName
    )
    $domainControllers = @{
        qae = @(
            "AZQAEDC01.qae.aspentech.com",
            "HQQAEDC01.qae.aspentech.com",
            "AZSINQAEDC01.qae.aspentech.com",
            "shqaedc01.qae.aspentech.com"
        )
        rnd = @(
            "AZRNDDC01.rnd.aspentech.com",
            "hqrnddc01.rnd.aspentech.com",
            "HOURNDDC01.rnd.aspentech.com",
            "shrnddc01.rnd.aspentech.com",
            "AZSINRNDDC01.rnd.aspentech.com"
        )
    }
    $netConnectionResults = $domainControllers[$domainName] | ForEach-Object {Test-NetConnection $_} | Select-Object -Property ComputerName,@{N="RoundTripTime";E={$_.PingReplyDetails.RoundtripTime}},@{N="Status";E={$_.PingReplyDetails.Status}}
    $sortedList = $netConnectionResults | Sort-Object -Property RoundtripTime | Where-Object {$_.Status -eq "Success"}
    return $sortedList[0].ComputerName
}