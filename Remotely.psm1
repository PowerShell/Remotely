function Remotely {
<#
.SYNOPSIS
Executes a script block against a remote runspace. Remotely can be used with Pester for executing script blocks on remote system.

.DESCRIPTION
The contents on the Remotely block are executed on a remote runspace. The connection information of the runspace is supplied in a CSV file of the format:

ComputerName,Username,Password
machinename,user,password

The file name must be machineConfig.csv

The CSV file is expected to be placed next to this file. 

If the CSV file is not found or username is not specified, the machine name is ignored and runspace to localhost
is created for executing the script block.

If the ConfigurationName is not in the CSV file, Remotely will default to Microsoft.PowerShell.

If the password has a ',' then it needs to be escaped by using quotes like: 
ComputerName,Username,Password,ConfigurationName
machinename,user,"Some,password",Microsoft.Powershell

To get access to the streams GetVerbose, GetDebugOutput, GetError, GetProgressOutput, GetWarning can be used on the resultant object.

.PARAMETER Test
The script block that should throw an exception if the expectation of the test is not met.

.PARAMETER ArgumentList
Arguments that will be passed to the script block.

.PARAMETER NoSession
The switch opts to use the script block without using any powershell sessions, but local runspace.

.EXAMPLE

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

    It "adds positive numbers with NoSession" {
        Remotely { 2 + 3 } -NoSession | Should Be 5
    }
}

.LINK
https://github.com/PowerShell/Remotely
https://github.com/pester/Pester
#>

param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ScriptBlock] $test = {},

        [Parameter(Mandatory = $false, Position = 1)]
        $ArgumentList, 

        [Parameter(Mandatory = $false, Position =2)]
        [switch]$NoSession
    )

    $results = @()

    if(-not $NoSession.IsPresent)
    {
        if($script:sessionsHashTable -eq $null)
        {
            $script:sessionsHashTable = @{}
        }

        $machineConfigFile = Join-Path $PSScriptRoot "machineConfig.CSV"

        CreateSessions -machineConfigFile $machineConfigFile

        $sessions = @()

        foreach($sessionInfo in $script:sessionsHashTable.Values.GetEnumerator())
        {
            CheckAndReConnect -sessionInfo $sessionInfo
            $sessions += $sessionInfo.Session
        }

        if($sessions.Count -le 0)
        {
            throw "No sessions are available"
        }

        $testjob = Invoke-Command -Session $sessions -ScriptBlock $test -AsJob -ArgumentList $ArgumentList | Wait-Job
            
        foreach($childJob in $testjob.ChildJobs)
        {
            $outputStream = ConstructOutputStream -resultObj $childJob.Output -streamSource $childJob

            if($childJob.State -eq 'Failed')
            {
	            $childJob | Receive-Job -ErrorAction SilentlyContinue -ErrorVariable jobError
	            $outputStream.__Streams.Error = $jobError
            }

            $results += ,$outputStream
        }

        $testjob | Remove-Job -Force
    }
    else
    {        
        $ps = [Powershell]::Create()
        $ps.runspace = [runspacefactory]::CreateRunspace()
        $ps.runspace.open()

        try
        {
            $res = $ps.AddScript($test.ToString()).AddArgument($ArgumentList).Invoke()        
        }
        catch
        {
            $executionError = $_.Exception.InnerException.ErrorRecord
        }

        $outputStream = ConstructOutputStream -resultObj $res -streamSource $ps.Streams
        
        if(($ps.Streams.Error.Count -eq 0) -and ($ps.HadErrors))
        {
            $outputStream.__streams.Error = $executionError;
        }

        $results += ,$outputStream

        $ps.Dispose()
    }

    $results
}

function ConstructOutputStream
{
    param(
        $resultObj,
        $streamSource
    )

    if($resultObj.Count -eq 0)
    {
        [object] $outputStream = New-Object psobject
    }
    else
    {
        [object] $outputStream = $resultObj | % { $_ }
    }

    $errorStream =    CopyStreams $streamSource.Error
    $verboseStream =  CopyStreams $streamSource.Verbose
    $debugStream =    CopyStreams $streamSource.Debug
    $warningStream =  CopyStreams $streamSource.Warning
    $progressStream = CopyStreams $streamSource.Progress    
    
    $allStreams = @{ 
                        Error = $errorStream
                        Verbose = $verboseStream
                        DebugOutput = $debugStream
                        Warning = $warningStream
                        ProgressOutput = $progressStream
                    }
    
    $outputStream = Add-Member -InputObject $outputStream -PassThru -MemberType NoteProperty -Name __Streams -Value $allStreams -Force
    $outputStream = Add-Member -InputObject $outputStream -PassThru -MemberType ScriptMethod -Name GetError -Value { return $this.__Streams.Error } -Force 
    $outputStream = Add-Member -InputObject $outputStream -PassThru -MemberType ScriptMethod -Name GetVerbose -Value { return $this.__Streams.Verbose } -Force 
    $outputStream = Add-Member -InputObject $outputStream -PassThru -MemberType ScriptMethod -Name GetDebugOutput -Value { return $this.__Streams.DebugOutput } -Force
    $outputStream = Add-Member -InputObject $outputStream -PassThru -MemberType ScriptMethod -Name GetProgressOutput -Value { return $this.__Streams.ProgressOutput } -Force
    $outputStream = Add-Member -InputObject $outputStream -PassThru -MemberType ScriptMethod -Name GetWarning -Value { return $this.__Streams.Warning } -Force
    $outputStream = Add-Member -InputObject $outputStream -PassThru -MemberType NoteProperty -Name RemotelyTarget -Value $streamSource.Location -Force
    return $outputStream
}

function CopyStreams
{
    param( [Parameter(Position=0, Mandatory=$true)] $inputStream) 

    $outStream = New-Object 'System.Management.Automation.PSDataCollection[PSObject]'

    foreach($item in $inputStream)
    {
        $outStream.Add($item)
    }

    $outStream.Complete()

    ,$outStream
}

function CreateSessions
{
    param([string] $machineConfigFile)
                
    if(Test-Path $machineConfigFile)
    {
        Write-Verbose "Found machine configuration file: $machineConfigFile"

        $machineInfo = Import-Csv $machineConfigFile

        foreach($item in $machineInfo)
        {
            $configurationName = 'Microsoft.PowerShell'
            if($item.ConfigurationName)
            {
                $configurationName = $item.ConfigurationName
            }

            if([String]::IsNullOrEmpty($item.UserName))
            {
                Write-Verbose "No username specified. Creating session to localhost." 
                CreateLocalSession $item.ComputerName -configurationName $configurationName
            }
            else
            {
                $password = ConvertTo-SecureString -String $item.Password -AsPlainText -Force
		        $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $item.Username,$password
                
                if(-not $script:sessionsHashTable.ContainsKey($item.ComputerName))
                {                                   
                    $sessionName = "Remotely" + (Get-Random).ToString()    

                    Write-Verbose "Creating new session, computer: $($item.ComputerName); ConfigurationName: $($ConfigurationName) "
                    $sessionInfo = CreateSessionInfo -Session (New-PSSession -ComputerName $item.ComputerName -Credential $cred -Name $sessionName -configurationname $configurationName  -ErrorAction Stop) -Credential $cred
                    $script:sessionsHashTable.Add($sessionInfo.session.ComputerName, $sessionInfo)                    
                }               
            }
        }        
    }
    else
    {
        Write-Verbose "No machine configuration file found. Creating session to localhost."
        CreateLocalSession
    }
}

function CreateLocalSession
{    
    param(
    [Parameter(Position=0)] $machineName = 'localhost',
    $configurationName = 'Microsoft.PowerShell'
    )
   
    if(-not $script:sessionsHashTable.ContainsKey($machineName))
    {        
        $sessionName = "Remotely" + (Get-Random).ToString()
        
        Write-Verbose "Creating new local session, ConfigurationName: $($ConfigurationName) "
        $sessionInfo = CreateSessionInfo -Session (New-PSSession -ComputerName $machineName -Name $sessionName -ConfigurationName $configurationName -ErrorAction Stop)

        $script:sessionsHashTable.Add($machineName, $sessionInfo)                
    }     
}

function CreateSessionInfo
{
    param(
        [Parameter(Position=0, Mandatory=$true)] [ValidateNotNullOrEmpty()] [System.Management.Automation.Runspaces.PSSession] $Session,
        [System.Management.Automation.PSCredential] $Credential
        )

    return [PSCustomObject] @{ Session = $Session; Credential = $Credential; ConfigurationName=$Session.ConfigurationName  }
}

function CheckAndReconnect
{
    param([Parameter(Position=0, Mandatory=$true)] [ValidateNotNullOrEmpty()] $sessionInfo)

    if($sessionInfo.Session.State -ne [System.Management.Automation.Runspaces.RunspaceState]::Opened)
    {
        Write-Verbose "Unexpected session state: $sessionInfo.Session.State for machine $($sessionInfo.Session.ComputerName). Re-creating session" 
        
        if($sessionInfo.Session.ComputerName -ne "localhost")
        {
            $sessionInfo.Session = New-PSSession -ComputerName $sessionInfo.Session.ComputerName -Credential $sessionInfo.Credential  -configurationname $sessionInfo.ConfigurationName
        }
        else
        {
            Write-Verbose "Creating local session with configurationname:$sessionInfo.ConfigurationName"
            $sessionInfo.Session = New-PSSession -ComputerName 'localhost' -configurationname $sessionInfo.ConfigurationName
        }
    }
}

function Clear-RemoteSession
{
    foreach($sessionInfo in $script:sessionsHashTable.Values.GetEnumerator())
    {
        Remove-PSSession $sessionInfo.Session
    }

    $script:sessionsHashTable.Clear()
}

function Get-RemoteSession
{
    $sessions = @()
    foreach($sessionInfo in $script:sessionsHashTable.Values.GetEnumerator())
    {
        $sessions += $sessionInfo.Session
    }

    $sessions
}
