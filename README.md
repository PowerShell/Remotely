Note
============
See forked project at https://github.com/DexterPOSH/PSRemotely.

Synopsis
============
Executes a script block against a remote runspace. Remotely can be used with Pester for executing script blocks on a remote system.

Description
======================
The contents on the Remotely block are executed on a remote runspace. The connection information of the runspace is supplied using the -Nodes parameter or as the argument to the first positional parameter. By default, this assumes the local credentials have access to the remote session configuration on the target nodes.

To get access to the streams, use GetVerbose, GetDebugOutput, GetError, GetProgressOutput,
GetWarning on the resultant object.

Example
============
Usage in Pester:

```powershell
$my_creds = Get-Credential
$node1_hash = @{}
$node1_hash.add("authentication","credssp")
$node1_hash.add("credential",$my_creds)

# All k,v pairs in $node1_hash are passed to New-PSSession for the specific node.
$remotely_nodes = @{}
$remotely_nodes.add("localhost",$node1_hash)

Describe "Add-Numbers" {
    It "adds positive numbers on a remote system" {
        Remotely -Nodes $remotely_nodes -ScriptBlock { 2 + 3 } | Should Be 5
    }

    It "gets verbose message" {
        $sum = Remotely -Nodes $remotely_nodes -ScriptBlock { Write-Verbose -Verbose "Test Message" }
        $sum.GetVerbose() | Should Be "Test Message"
    }

    It "can pass parameters to remote block with different credentials" {
        $num = 10
        $process = Remotely -Nodes $remotely_nodes -ScriptBlock { Param($number) $number + 1 } -ArgumentList $num
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
