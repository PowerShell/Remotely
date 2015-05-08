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

If the password has a ',' then it needs to be escaped by using quotes like: 
ComputerName,Username,Password
machinename,user,"Some,password"

To get access to the streams GetVerbose, GetDebugOutput, GetError, GetProgressOutput, GetWarning can be used on the resultant object.

.PARAMETER Test
The script block that should throw an exception if the expectation of the test is not met.

.PARAMETER ArgumentList
Arguments that will be passed to the script block.

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
}

.LINK
https://github.com/PowerShell/Remotely
https://github.com/pester/Pester
#>

param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ScriptBlock] $test = {},

        [Parameter(Mandatory = $false, Position = 1)]
        $ArgumentList
    )

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

    if(-not $testjob.ChildJobs[0].Output)
    {
        [object] $outputStream = New-Object psobject
    }
    else
    {
        [object] $outputStream = $testjob.ChildJobs[0].Output | % { $_ }
    }

    $errorStream =    CopyStreams $testjob.ChildJobs[0].Error
    $verboseStream =  CopyStreams $testjob.ChildJobs[0].Verbose
    $debugStream =    CopyStreams $testjob.ChildJobs[0].Debug
    $warningStream =  CopyStreams $testjob.ChildJobs[0].Warning
    $progressStream = CopyStreams $testjob.ChildJobs[0].Progress    
    
    $allStreams = @{ 
                        Error = $errorStream
                        Verbose = $verboseStream
                        DebugOutput = $debugStream
                        Warning = $warningStream
                        ProgressOutput = $progressStream
                    }
    
    $outputStream = Add-Member -InputObject $outputStream -PassThru -MemberType NoteProperty -Name __Streams -Value $allStreams
    $outputStream = Add-Member -InputObject $outputStream -PassThru -MemberType ScriptMethod -Name GetError -Value { return $this.__Streams.Error }
    $outputStream = Add-Member -InputObject $outputStream -PassThru -MemberType ScriptMethod -Name GetVerbose -Value { return $this.__Streams.Verbose }
    $outputStream = Add-Member -InputObject $outputStream -PassThru -MemberType ScriptMethod -Name GetDebugOutput -Value { return $this.__Streams.DebugOutput }
    $outputStream = Add-Member -InputObject $outputStream -PassThru -MemberType ScriptMethod -Name GetProgressOutput -Value { return $this.__Streams.ProgressOutput }
    $outputStream = Add-Member -InputObject $outputStream -PassThru -MemberType ScriptMethod -Name GetWarning -Value { return $this.__Streams.Warning }
    
    $testjob | Remove-Job -Force
    ,$outputStream
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
            if([String]::IsNullOrEmpty($item.UserName))
            {
                Write-Verbose "No username specified. Creating session to localhost." 
                CreateLocalSession
            }
            else
            {
                $password = ConvertTo-SecureString -String $item.Password -AsPlainText -Force
		        $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $item.Username,$password
                
                if(-not $script:sessionsHashTable.ContainsKey($item.ComputerName))
                {                                   
                    $sessionName = "Remotely" + (Get-Random).ToString()                                        

                    $sessionInfo = CreateSessionInfo -Session (New-PSSession -ComputerName $item.ComputerName -Credential $cred -Name $sessionName) -Credential $cred
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
   if(-not $script:sessionsHashTable.ContainsKey("localhost"))
    {
        $sessionName = "Remotely" + (Get-Random).ToString()
        
        $sessionInfo = CreateSessionInfo -Session (New-PSSession -ComputerName localhost -Name $sessionName)

        $script:sessionsHashTable.Add("localhost", $sessionInfo)
    } 
}

function CreateSessionInfo
{
    param(
        [Parameter(Position=0, Mandatory=$true)] [ValidateNotNullOrEmpty()] [System.Management.Automation.Runspaces.PSSession] $Session,
        [System.Management.Automation.PSCredential] $Credential
        )

    return [PSCustomObject] @{ Session = $Session; Credential = $Credential }
}

function CheckAndReconnect
{
    param([Parameter(Position=0, Mandatory=$true)] [ValidateNotNullOrEmpty()] $sessionInfo)

    if($sessionInfo.Session.State -ne [System.Management.Automation.Runspaces.RunspaceState]::Opened)
    {
        Write-Verbose "Unexpected session state: $sessionInfo.Session.State for machine $($sessionInfo.Session.ComputerName). Re-creating session" 
        
        if($sessionInfo.Session.ComputerName -ne "localhost")
        {
            $sessionInfo.Session = New-PSSession -ComputerName $sessionInfo.Session.ComputerName -Credential $sessionInfo.Credential
        }
        else
        {
            $sessionInfo.Session = New-PSSession -ComputerName 'localhost'
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
