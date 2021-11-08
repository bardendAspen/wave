@{
    # Hardware and os details for the new vm
    virtualMachineSpecs = @{
        # For a list of supported operating systems, run "wave packages"
        operatingSystem = ""
        cpus = 4
        startupMemory = 2GB
    }
    # Software packages
    softwarePackages = @{
        # For a list of supported wave packages, run "wave packages"
        wavePackages = @(
            # "Example.Package1.Name",
            # "Example.Package2.Name"
        )
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