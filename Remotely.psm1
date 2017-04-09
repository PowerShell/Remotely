function Remotely {
    param (       
        [Parameter(Mandatory = $true, Position = 1)]
        [ScriptBlock] $ScriptBlock,

        [Parameter(Mandatory = $false, Position = 2)]
        $ArgumentList,

        [Parameter(Mandatory = $false, Position = 3)]
        [HashTable] $Nodes = @{'localhost'= $null},

        [Parameter(Mandatory = $false, Position = 4)]
        [Int32] $Timeout = 300
    )

    if ($null -eq $script:sessionsHashTable) {
        $script:sessionsHashTable = @{}
    }
    
    Write-Verbose ("Creating sessions for nodes.")
    CreateSessions -Nodes $Nodes
    
    $sessions = @()
    foreach($sessionInfo in $script:sessionsHashTable.Values.GetEnumerator()) {
        Write-Verbose ("Reconnecting to session: $sessionInfo")
        CheckAndReConnect -sessionInfo $sessionInfo
        $sessions += $sessionInfo.Session
    }

    if($sessions.Count -le 0) {
        Throw "No sessions are available"
    } else {
        $num_sessions = $sessions.count
        Write-Verbose ("Created $num_sessions sessions.")
    }
    
    Write-Verbose ("Invoking job on nodes.")
    $testjob = Invoke-Command -Session $sessions -ScriptBlock $ScriptBlock -AsJob -ArgumentList $ArgumentList | Wait-Job -Timeout $Timeout

    $results = @()

    foreach($childJob in $testjob.ChildJobs) {

        Write-Verbose ("Working on Job: $childJob.")
        if($childJob.Output.Count -eq 0) {
            [object] $outputStream = New-Object psobject
        }
        else {
            [object] $outputStream = $childJob.Output | ForEach-Object { $_ }
        }

        $errorStream =    CopyStreams $childJob.Error
        $verboseStream =  CopyStreams $childJob.Verbose
        $debugStream =    CopyStreams $childJob.Debug
        $warningStream =  CopyStreams $childJob.Warning
        $progressStream = CopyStreams $childJob.Progress    
    
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
        $outputStream = Add-Member -InputObject $outputStream -PassThru -MemberType NoteProperty -Name RemotelyTarget -Value $childJob.Location

        if($childJob.State -eq 'Failed') {
	        $childJob | Receive-Job -ErrorAction SilentlyContinue -ErrorVariable jobError
	        $outputStream.__Streams.Error = $jobError
        }

        $results += ,$outputStream
    }

    $testjob | Remove-Job -Force
    $results
}

function CopyStreams
{
    param
    (
        [Parameter(Position=0, Mandatory=$true)] 
        $inputStream
    ) 

    $outStream = New-Object 'System.Management.Automation.PSDataCollection[PSObject]'

    foreach($item in $inputStream)
    {
        $outStream.Add($item)
    }

    $outStream.Complete()

    ,$outStream
}

function CreateSessions {
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [HashTable] $Nodes = @{'localhost'=$null}
    )

    # Note: case sensitive. Keep keys lower case.
    $default_node_options = @{}
    $default_node_options.Add("sessionoptions",$null)
    $default_node_options.Add("credential",$null)
    $default_node_options.Add("authentication",$null)
    
    $Nodes.keys | ForEach-Object {
        $node_name = $_

        Write-Verbose ("Working on node name $node_name .")
        # Merge given options with default options.
        $node_options = @{}
        $node_val = $nodes[$node_name]
        If($null -eq $node_val) {
        } Else {
            # TODO Assert $node_options -is [HashTable]
            $default_node_options.keys | ForEach-Object {
                $cur_key = $null
                $cur_key = $_
                $node_option_val = $null
                If($node_val.keys -contains $cur_key.ToLower()) {
                    $node_option_val = $node_val[$cur_key]
                } Else {
                    $node_option_val = $default_node_options[$cur_key]
                }
                $node_options.add($cur_key,$node_option_val)
            }
        }
        Write-Verbose ("Final node options: " + ($node_options | out-string))

        If(-not $script:sessionsHashTable.ContainsKey($node_name)) {
            
            $create_session_info_params = @{}
            $new_ps_session_params = @{}
            $new_ps_session_params.add("ComputerName",$node_name)
            $new_ps_session_params.add("Name",("Remotely-" + $node_name))

            If ($node_options.credential) {
                $create_session_info_params.add("Credential",$node.credential)
                $new_ps_session_params.add("Credential",$node.credential)
            }

            If ($node_options.authentication) {
                $new_ps_session_params.add("authentication",$node.authentication)
            }

            Write-Verbose ("Calling new-pssession with the following parameters: " + ($new_ps_session_params | out-string))
            $ps_session = $null
            $ps_session = New-PSSession @new_ps_session_params -Verbose
            $create_session_info_params.add("Session", $ps_session)

            Write-Verbose ("Calling CreateSessionInfo.")
            $sessionInfo = CreateSessionInfo @create_session_info_params
            
            $script:sessionsHashTable.Add($sessionInfo.session.ComputerName, $sessionInfo)              
        }               
    }
}

# function CreateLocalSession
# {    
#     param(
#         [Parameter(Position=0)] $Node = 'localhost'
#     )

#     if(-not $script:sessionsHashTable.ContainsKey($Node))
#     {
#         $sessionInfo = CreateSessionInfo -Session (New-PSSession -ComputerName $Node -Name $sessionName)
#         $script:sessionsHashTable.Add($Node, $sessionInfo)
#     } 
# }

function CreateSessionInfo
{
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Runspaces.PSSession] $Session,

        [Parameter(Position=1)]
        [pscredential] $Credential
    )
    return [PSCustomObject] @{ Session = $Session; Credential = $Credential}
}

function CheckAndReconnect
{
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [ValidateNotNullOrEmpty()] $sessionInfo
    )

    if($sessionInfo.Session.State -ne [System.Management.Automation.Runspaces.RunspaceState]::Opened)
    {
        Write-Verbose "Unexpected session state: $sessionInfo.Session.State for machine $($sessionInfo.Session.ComputerName). Re-creating session" 
        if($sessionInfo.Session.ComputerName -ne 'localhost')
        {
            if ($sessionInfo.Credential)
            {
                $sessionInfo.Session = New-PSSession -ComputerName $sessionInfo.Session.ComputerName -Credential $sessionInfo.Credential
            }
            else
            {
                $sessionInfo.Session = New-PSSession -ComputerName $sessionInfo.Session.ComputerName
            }
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