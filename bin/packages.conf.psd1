@{
    AspenPackageRepo = @{
        # Repo host for local files
        hosts = @{
            bedford = "abelnr1.corp.aspentech.com"
            mexico = "leonk1.corp.aspentech.com"
        }
        # Local file packages
        packages = @{
            wave = "AspenPackageRepo\wave"
        }
        # Wave Packages
        WavePackages = @{
            Chrome = @{
                Uri = 'AspenPackageRepo\Chrome\googlechromestandaloneenterprise64.msi'
                Args = '/qn /norestart'
            }
            Python3 = @{
                Uri = 'AspenPackageRepo\Python3\python-3.10.0-amd64.exe'
                Args = '/install /quiet InstallAllUsers=1 PrependPath=1'
            }
            MicrosoftOffice365 = @{
                Uri = 'AspenPackageRepo\MicrosoftOffice365\OfficeSetup.exe'
                Args = ''
            }
            Perforce = @{
                Uri = 'AspenPackageRepo\Perforce\p4vinst64.exe'
                Args = '/quiet /suppressmsgboxes /NORESTART'
            }
            VisualStudioEnterprise2017 = @{
                Uri = 'AspenPackageRepo\VisualStudioEnterprise2017\vs_Enterprise.exe'
                Args = '--quiet --norestart'
            }
            VisualStudioEnterprise2019 = @{
                Uri = 'AspenPackageRepo\VisualStudioEnterprise2019\vs_enterprise__1844053857.1572632540.exe'
                Args = '--quiet --norestart'
            }
            VisualStudioEnterprise2022 = @{
                Uri = 'AspenPackageRepo\VisualStudioEnterprise2022\vs_enterprise__1844053857.1572632540.exe'
                Args = '--quiet --norestart'
            }
        }
        # VS Config files
        VisualStudioConfigFiles = @{
            ABEV14 = 'AspenPackageRepo\VisualStudioConfigFiles\ABEV14.VS2019.vsconfig'
        }
        # Required packages
        RequiredPackages = @{
            CrowdStrike = @{
                Uri = 'AspenPackageRepo\CrowdStrike14304\WindowsSensor14304.exe'
                Args = '/install /quiet /norestart CID=C9988F75A22349588F0BA8FAFDBACB62-15 NO_START=1'
            }
        }
    }
    # Web packages
    WaveWebPackages = @{
        Git = @{
            Uri = 'https://github.com/git-for-windows/git/releases/download/v2.33.1.windows.1/Git-2.33.1-64-bit.exe'
            Args = '/VERYSILENT /NORESTART /suppressmsgboxes'
            InstallerType = 'exe'
        }
        # VisualStudioCode = @{
        #     Uri = 'https://code.visualstudio.com/sha/download?build=stable&os=win32-x64'
        #     Args = '/verysilent /suppressmsgboxes /MERGETASKS=!runcode'
        #     InstallerType = 'exe'
        # }
    }

    # Live Images
    LiveImages = @{
        hosts = @{
            bedford = "abelnr1.corp.aspentech.com"
            mexico = "leonk1.corp.aspentech.com"
        }
        operatingSystems = @{
            Windows10 = @{
                path = "AspenPackageRepo\LiveImages\LI-W10"
                name = "LI-W10-ENT"
            }
            Windows11 = @{
                path = "AspenPackageRepo\LiveImages\LI-W11"
                name = "W11Template"
            }
            WindowsServer2019 = @{
                path = "AspenPackageRepo\LiveImages\LI-S19"
                name = "LI-S19"
            }
            WindowsServer2022= @{
                path = "AspenPackageRepo\LiveImages\LI-S22"
                name = "LI-S22"
            }
            # WindowsServer2016 = @{
            #     path = "AspenPackageRepo\LiveImages\LI-S16"
            #     name = ""
            # }
        }
    }

    # Aspen Media paths
    AspenMedia = @{
        hosts = @{
            bedford = "hqazrndfs01.corp.aspentech.com"
            mexico = "leonk1.corp.aspentech.com"
        }
        path = "upload$" 
    }
}