Describe "Add-Numbers" {
    $testcases = @( @{NoSessionValue = $true}, @{NoSessionValue = $false})
   
    It "can execute script with NoSessionValue : <NoSessionValue>" -TestCases $testcases {
            param($NoSessionValue)
            $output = Remotely { 1 + 1 } -NoSession:$NoSessionValue 
            $output | Should Be 2

            if($NoSessionValue -eq $true)
            {
                $output.RemotelyTarget | Should BeNullOrEmpty                
            }
            else
            {
                $output.RemotelyTarget | Should Be "localhost"
            }
        }

    It "can return an array with NoSessionValue : <NoSessionValue>" -TestCases $testcases {
        param($NoSessionValue)
        $returnObjs = Remotely { 1..10 } -NoSession:$NoSessionValue
        $returnObjs.count | Should Be 10
    }

    It "can return a hashtable with NoSessionValue : <NoSessionValue>" -TestCases $testcases {
        param($NoSessionValue)
        $returnObjs = Remotely { @{Value = 2} } -NoSession:$NoSessionValue
        $returnObjs["Value"] | Should Be 2
    }

    It "can get verbose message with NoSessionValue : <NoSessionValue>" -TestCases $testcases {
        param($NoSessionValue)
        $output = Remotely { Write-Verbose -Verbose "Verbose Message" } -NoSession:$NoSessionValue
        $output.GetVerbose() | Should Be "Verbose Message"
    }

    It "can get error message with NoSessionValue : <NoSessionValue>" -TestCases $testcases {
        param($NoSessionValue)
        $output = Remotely { Write-Error "Error Message" } -NoSession:$NoSessionValue
        $output.GetError() | Should Be "Error Message"
    }

    It "can get warning message with NoSessionValue : <NoSessionValue>" -TestCases $testcases {
        param($NoSessionValue)
        $output = Remotely { Write-Warning "Warning Message" } -NoSession:$NoSessionValue
        $output.GetWarning() | Should Be "Warning Message"
    }

    It "can get debug message with NoSessionValue : <NoSessionValue>" -TestCases $testcases {
        param($NoSessionValue)
        $output = Remotely -NoSession:$NoSessionValue { 
                $originalPreference = $DebugPreference
                $DebugPreference = "continue"
                Write-Debug "Debug Message" 
                $DebugPreference = $originalPreference
            }
        $output.GetDebugOutput() | Should Be "Debug Message"
    }

    It "can get progress message with NoSessionValue : <NoSessionValue>" -TestCases $testcases {
        param($NoSessionValue)
        $output = Remotely -NoSession:$NoSessionValue { Write-Progress -Activity "Test" -Status "Testing" -Id 1 -PercentComplete 100 -SecondsRemaining 0 }
        $output.GetProgressOutput().Activity | Should Be "Test"
        $output.GetProgressOutput().StatusDescription | Should Be "Testing"
        $output.GetProgressOutput().ActivityId | Should Be 1
    }

    It 'can return $false as a value with NoSessionValue : <NoSessionValue>' -TestCases $testcases {
        param($NoSessionValue)
        $output = Remotely { $false } -NoSession:$NoSessionValue
        $output | Should Be $false
    }

    It 'can return throw messages with NoSessionValue : <NoSessionValue>' -TestCases $testcases {
        param($NoSessionValue)
        $output = Remotely { throw 'bad' } -NoSession:$NoSessionValue
        $output.GetError().FullyQualifiedErrorId | Should Be 'bad'
    }        
    
    It "can pass parameters to remote block with NoSessionValue : <NoSessionValue>" -TestCases $testcases {
        param($NoSessionValue)
        $num = 10
        $process = Remotely { param($number) $number + 1 } -ArgumentList $num -NoSession:$NoSessionValue
        $process | Should Be 11
    }

    It "can get remote sessions" {        
        Remotely { 1 + 1 } | Should Be 2
        $remoteSessions = Get-RemoteSession

        $remoteSessions | % { $remoteSessions.Name -match "Remotely"  | Should Be $true} 
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
        # Testing with no configuration name for compatibility
        $configFile = (join-path $PSScriptRoot 'machineConfig.csv')
        $configContent = @([pscustomobject] @{ComputerName = "localhost" }, [pscustomobject] @{ComputerName = "." }) | ConvertTo-Csv -NoTypeInformation
        $configContent | Out-File -FilePath $configFile -Force
        
        try
        {
            $results = Remotely { 1 + 1 }  
            $results.Count | Should Be 2
        
            foreach($result in $results)
            {
                $result | Should Be 2 
            }
        }
        catch
        {
            $_.FullyQualifiedErrorId | Should Be $null
        }
        finally
        {
            Remove-Item $configFile -ErrorAction SilentlyContinue -Force
        }
    }
}

Describe "ConfigurationName" {
    BeforeAll {
        $configFile = (join-path $PSScriptRoot 'machineConfig.csv')
    }
    AfterAll {
            Remove-Item $configFile -ErrorAction SilentlyContinue -Force
    }
    Context "Default configuration name" {
        $configContent = @([pscustomobject] @{
            ComputerName = "localhost"
            Username = $null
            Password = $null
            ConfigurationName = "Microsoft.PowerShell"
        }) | ConvertTo-Csv -NoTypeInformation
        $configContent | Out-File -FilePath $configFile -Force

        it "Should connect when a configurationName is specified" {
           
            $results = Remotely { 1 + 1 }  
        
            $results | Should Be 2 
        }
    }

    Context "Invalid configuration name" {
        Write-Verbose "Clearing remote session..." -Verbose
        Clear-RemoteSession 
        $configContent = @([pscustomobject] @{
            ComputerName = "localhost"
            Username = $null
            Password = $null
            ConfigurationName = "Microsoft.PowerShell2"
        }) | ConvertTo-Csv -NoTypeInformation
        $configContent | Out-File -FilePath $configFile -Force
        
        it "Should not connect to an invalid ConfigurationName" {
            {$results = Remotely { 1 + 1 }} | should throw "Connecting to remote server localhost failed with the following error message : The WS-Management service cannot process the request. Cannot find the Microsoft.PowerShell2 session configuration in the WSMan: drive on the localhost computer. For more information, see the about_Remote_Troubleshooting Help topic."
        }  
    }
}
Describe "Clear-RemoteSession" {
    It "can clear remote sessions" {
        Clear-RemoteSession
        Get-PSSession -Name Remotely* | Should Be $null                
    }
} 