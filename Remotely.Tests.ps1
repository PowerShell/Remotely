# Function to update the table that defines the machineconfig.csv 
# based on test environment variables
Function Update-ConfigContentTable 
{
    param(
        [parameter(Mandatory=$true)]
        [HashTable]$configContentTable
        
    )

    if($global:AppveyorRemotelyUserName -or $global:AppveyorRemotelyPassword)
    {
        $computername = $configContentTable.ComputerName
        if($computername -ieq 'localhost')
        {
            $computername = '127.0.0.1'
        }
        elseif ( $computername -ieq '.')
        {
            $computername = '::1'
        }
        
        $configContentTable.ComputerName = $computername
    }

    if($global:AppveyorRemotelyUserName)
    {
        $configContentTable['Username']=$global:AppveyorRemotelyUserName
    }

    if($global:AppveyorRemotelyPassword)
    {
        $configContentTable['Password']=$global:AppveyorRemotelyPassword
    }

    return $configContentTable
}

Describe "Add-Numbers" {
    BeforeAll {
        $configFile = (join-path $PSScriptRoot 'machineConfig.csv')
        $configContentTable = @{ComputerName = "localhost" }
        Update-ConfigContentTable -configContentTable $configContentTable
        $configContent = @([pscustomobject] $configContentTable) | ConvertTo-Csv -NoTypeInformation
        $configContent | Out-File -FilePath $configFile -Force
    }
    $testcases = @( @{NoSessionValue = $true}, @{NoSessionValue = $false})
   
    It "can execute script with NoSessionValue : <NoSessionValue>" -TestCases $testcases {
            param($NoSessionValue)

            $expectedRemotelyTarget = 'localhost'
            if($configContentTable['Computername'])
            {
                $expectedRemotelyTarget = $configContentTable['Computername']
            }

            $output = Remotely { 1 + 1 } -NoSession:$NoSessionValue 
            $output | Should Be 2

            if($NoSessionValue -eq $true)
            {
                $output.RemotelyTarget | Should BeNullOrEmpty                
            }
            else
            {
                $output.RemotelyTarget | Should Be $expectedRemotelyTarget
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
        $expectedRemotelyTarget = 'localhost'
        if($configContentTable['Computername'])
        {
            $expectedRemotelyTarget = $configContentTable['Computername']
        }
        
        $output = Remotely { 1 } 
        $output.RemotelyTarget | Should Be $expectedRemotelyTarget
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
        $configContentTable = @{ComputerName = "localhost" }
        Update-ConfigContentTable -configContentTable $configContentTable
        $configContentTable2 = @{ComputerName = "." }
        Update-ConfigContentTable -configContentTable $configContentTable2
        $configContent = @([pscustomobject] $configContentTable, [pscustomobject] $configContentTable2) | ConvertTo-Csv -NoTypeInformation
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
        $configContentTable = @{
            ComputerName = "localhost"
            Username = $null
            Password = $null
            ConfigurationName = "Microsoft.PowerShell"
        }
        Update-ConfigContentTable -configContentTable $configContentTable
        $configContent = @([pscustomobject] $configContentTable) | ConvertTo-Csv -NoTypeInformation
        $configContent | Out-File -FilePath $configFile -Force

        it "Should connect when a configurationName is specified" {
           
            $results = Remotely { 1 + 1 }  
        
            $results | Should Be 2 
        }
    }

    Context "Invalid configuration name" {
        
        Write-Verbose "Clearing remote session..." -Verbose
        Clear-RemoteSession 
        $configContentTable = @{
            ComputerName = "localhost"
            Username = $null
            Password = $null
            ConfigurationName = "Microsoft.PowerShell2"
        }
        Update-ConfigContentTable -configContentTable $configContentTable
        $configContent = @([pscustomobject] $configContentTable) | ConvertTo-Csv -NoTypeInformation
        $configContent | Out-File -FilePath $configFile -Force

        $expectedRemotelyTarget = 'localhost'
        if($configContentTable['Computername'])
        {
            $expectedRemotelyTarget = $configContentTable['Computername']
        }

        
        it "Should not connect to an invalid ConfigurationName" {
            {$results = Remotely { 1 + 1 }} | should throw "Connecting to remote server $expectedRemotelyTarget failed with the following error message : The WS-Management service cannot process the request. Cannot find the Microsoft.PowerShell2 session configuration in the WSMan: drive on the $expectedRemotelyTarget computer. For more information, see the about_Remote_Troubleshooting Help topic."
        }  
    }
}
Describe "Clear-RemoteSession" {
    It "can clear remote sessions" {
        Clear-RemoteSession
        Get-PSSession -Name Remotely* | Should Be $null                
    }
} 