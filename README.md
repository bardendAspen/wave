# wave
### Wave automates virtual environments
````
"The Future is now. The future is wave."           
    -Oyindasola Sodeinde
````
> The project is in beta. Feedback is welcome, and that feedback might lead to big (maybe even breaking) changes.

## Installing wave

To install wave, make sure your computer meets the following requirements
* OS is Windows 10 or Server 2016 or later
* Powershell execution policy set to RemoteSigned
* Hyper-V enabled
* User is a member of Hyper-V Admins group

To install wave, paste the following command in a powershell console.
````
Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression (Get-Content '\\abelnr1.corp.aspentech.com\AspenPackageRepo\wave\installWave.ps1' -Raw)
````
Follow the instructions presented in the console. 

### Update wave

It is strongly recommended that you manually update wave before each use. This will ensure that you have the most up to date packages and avoid failed installations. To update wave run the following command
````
wave update
````
The console must be restarted for changes to take effect.

## Quick Start
After installing wave, follow this guide to get familiar with the basics of wave. This will show you how to create a Windows 10 machine using the 'deploy' command. The syntax of the deploy command is as follows
````
wave deploy <name> [<template>]
````
`<name>` is a requreied parameter that specifies the name of your new VM. For personal VM's, its best practice to prefix your name with your corp username. These machines are put on the domain and this will help avoid two users using the same name for a machine. For example my corp username is 'bardend' so a good VM name for me to use would be 'bardend-VM01'.

`[<template>]` is an optional parameter used to specify the name of a template file. Template files are used to specify things like VM specs, operating system, and packages. If no template name is given the default template will be used. For this example we will emit this parameter and use the default template which is a Windows 10 base image. For more information on changing the default template as well as creating and using them, see the templates section.

>Please note that the vm name must adhere to rules for netbios names. Standard names may contain letters (a-z, A-Z), numbers (0-9), and hyphens (-), but no spaces, underscores ( _ ), or periods (.). The name may not consist entirely of digits, and may not be longer than 15 characters. 

To create a VM named bardend-VM01 using the default template, in a powershell console run the following command (remember to use your own corp name instead of 'bardend' if you are following along)
````
wave deploy bardend-VM01
````
You will be prompted to enter two sets of credentials before wave begins building the VM. The first is the default password we use for the local Admin account of all our virtual machines. You should know this but if you dont contact ryan.barde@aspentech.com. The second password will be the password for your corp account. 

>To skip entering credentials in the future, you can run the following command once wave has finished
>````
>wave credentials store
>````
>This will store the credentials and wave will no longer prompt you for them every time

Wave should now begin building your new VM, once ready wave will notify yuo it is done in the console and you will be free to log on to the computer using your corp account.

Fore more information on the deploy command, run
````
wave help deploy
````
>Take care when using the help command that you dont accidentally run 'wave deploy help', as this will create a VM called 'help'.
