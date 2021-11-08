@{
    # Hardware and os details for the new vm
    virtualMachineSpecs = @{
        # For a list of supported operating systems, run "wave packages"
        operatingSystem = "Windows10"
        cpus = 4
        startupMemory = 2GB
    }
    # Software packages
    softwarePackages = @{
        # For a list of supported wave packages, run "wave packages"
        wavePackages = @(
            "Chrome",
            "MicrosoftOffice365",
            "Perforce",
            "Git",
            "VisualStudioEnterprise2019"
        )
        # Optional config file if vs is installed
        VisualStudioConfigFile = "ABEV14"
        # Use winget id's to specify package
        wingetPackages = @(
            # "Winget.ID1",
            # "Winget.ID2"
        )
        # Choco package names
        chocolateyPackages = @(
            # "PackageName",
            # "PackageName"
        )
        aspenMedia = @{}
    }
}