Synopsis
============
Executes a script block against a remote runspace. Remotely can be used with Pester for executing script blocks on a remote system.

Description
======================
The contents on the Remotely block are executed on a remote runspace. The connection information of the runspace is supplied in a CSV file of the format:

```
ComputerName,Username,Password
ComputerName1,Username1,Password1
ComputerName2,Username2,Password2
```

The filename must be `machineConfig.csv`.

The CSV file is expected to be placed next to this file. 

If the CSV file is not found or username is not specified, the machine name is ignored and runspace to localhost
is created for executing the script block.

If the password has a ',' then it needs to be escaped by using quotes like: 

```
ComputerName,Username,Password
ComputerName1,Username1,Password1
ComputerName2,Username2,"Some,other,password"
```

To get access to the streams, use GetVerbose, GetDebugOutput, GetError, GetProgressOutput,
GetWarning on the resultant object.

Example
============
Usage in Pester:

```powershell
Describe "Add-Numbers" {
    It "adds positive numbers" {
        Remotely { 2 + 3 } | Should Be 5
    }

    It "gets verbose message" {
        $sum = Remotely { Write-Verbose -Verbose "Test Message" }
        $sum.GetVerbose() | Should Be "Test Message"
    }

    It "can pass parameters to remote block" {
        $num = 10
        $process = Remotely { param($number) $number + 1 } -ArgumentList $num
        $process | Should Be 11
    }
}
```

Links
============
* https://github.com/PowerShell/Remotely
* https://github.com/pester/Pester

Running Tests
=============
Pester-based tests are located in ```<branch>/Remotely.Tests.ps1```

* Ensure Pester is installed on the machine
* Run tests:
    .\Remotely.Tests.ps1

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
