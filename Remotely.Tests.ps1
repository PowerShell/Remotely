$VerbosePreference = "continue"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
If((Get-Module | Select-Object Name -ExpandProperty Name) -contains "Remotely") {
    Remove-Module "Remotely"
}
$mod_path = $here.trimend("\") + "\Remotely.psm1"
Import-Module $mod_path

Describe "Add-Numbers" {
   
    It "can execute script" {
            Remotely { 1 + 1 } | Should Be 2
    }

    It "can return an array" {
        $returnObjs = Remotely { 1..10 }
        $returnObjs.count | Should Be 10
    }

    It "can return a hashtable" {
        $returnObjs = Remotely { @{Value = 2} }
        $returnObjs["Value"] | Should Be 2
    }

    It "can get verbose message" {
        $output = Remotely { Write-Verbose -Verbose "Verbose Message" }
        $output.GetVerbose() | Should Be "Verbose Message"
    }

    It "can get error message" {
        $output = Remotely { Write-Error "Error Message" }
        $output.GetError() | Should Be "Error Message"
    }

    It "can get warning message" {
        $output = Remotely { Write-Warning "Warning Message" }
        $output.GetWarning() | Should Be "Warning Message"
    }

    It "can get debug message" {
        $output = Remotely { 
                $originalPreference = $DebugPreference
                $DebugPreference = "continue"
                Write-Debug "Debug Message" 
                $DebugPreference = $originalPreference
            }
        $output.GetDebugOutput() | Should Be "Debug Message"
    }

    It "can get progress message" {
        $output = Remotely { Write-Progress -Activity "Test" -Status "Testing" -Id 1 -PercentComplete 100 -SecondsRemaining 0 }
        $output.GetProgressOutput().Activity | Should Be "Test"
        $output.GetProgressOutput().StatusDescription | Should Be "Testing"
        $output.GetProgressOutput().ActivityId | Should Be 1
    }

    It 'can return $false as a value' {
        $output = Remotely { $false }
        $output | Should Be $false
    }

    It 'can return throw messages' {
        $output = Remotely { throw 'bad' }
        $output.GetError().FullyQualifiedErrorId | Should Be 'bad'
    }
    
    It "can get remote sessions" {
        Remotely { 1 + 1 } | Should Be 2
        $remoteSessions = Get-RemoteSession

        $remoteSessions | ForEach-Object { $remoteSessions.Name -match "Remotely"  | Should Be $true} 
    }
    
    It "can pass parameters to remote block" {
        $num = 10
        $process = Remotely { param($number) $number + 1 } -ArgumentList $num
        $process | Should Be 11
    }

    It "can get target of the remotely block" {
        $output = Remotely { 1 } 
        $output.RemotelyTarget | Should Be "localhost"
    }

    It "can handle delete sessions" {
        Remotely { 1 + 1 } | Should Be 2
        $previousSession = Get-RemoteSession 
        $previousSession | Remove-PSSession

        ##New session should be created
        Remotely { 1 + 1 } | Should Be 2
        $newSession = Get-RemoteSession
        $previousSession.Name | Should Not Be $newSession.Name
    }
    
    It "can execute against more than 1 remote machines" {
        $nodes = @{}
        $nodes.add('localhost',$null)
        $nodes.add([string]$env:computername,$null)
        
        try {
            $results = Remotely { 1 + 1 } -Nodes $nodes
            $results.Count | Should Be 2
        
            foreach($result in $results) {
                $result | Should Be 2 
            }
        }
        catch{
            $_.FullyQualifiedErrorId | Should Be $null
        }
        finally {
        }
    }
    
    It "can clear remote sessions" {
        Clear-RemoteSession
        Get-PSSession -Name Remotely* | Should Be $null                
    }
}