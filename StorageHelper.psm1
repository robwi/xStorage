# Set Global Module Verbose
$VerbosePreference = 'Continue' 

# Load Localization Data 
Import-LocalizedData LocalizedData -filename xStorage.strings.psd1 -ErrorAction SilentlyContinue
Import-LocalizedData USLocalizedData -filename xStorage.strings.psd1 -UICulture en-US -ErrorAction SilentlyContinue

function New-TerminatingError 
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ErrorType,

        [parameter(Mandatory = $false)]
        [String[]]
        $FormatArgs,

        [parameter(Mandatory = $false)]
        [System.Management.Automation.ErrorCategory]

        $ErrorCategory = [System.Management.Automation.ErrorCategory]::OperationStopped,

        [parameter(Mandatory = $false)]
        [Object]
        $TargetObject = $null
    )

    $errorMessage = $LocalizedData.$ErrorType
    
    if(!$errorMessage)
    {
        $errorMessage = ($LocalizedData.NoKeyFound -f $ErrorType)

        if(!$errorMessage)
        {
            $errorMessage = ("No Localization key found for key: {0}" -f $ErrorType)
        }
    }

    $errorMessage = ($errorMessage -f $FormatArgs)

    $callStack = Get-PSCallStack 

    if($callStack[1] -and $callStack[1].ScriptName)
    {
        $scriptPath = $callStack[1].ScriptName

        $callingScriptName = $scriptPath.Split('\')[-1].Split('.')[0]
    
        $errorId = "$callingScriptName.$ErrorType"
    }
    else
    {
        $errorId = $ErrorType
    }

    Write-Verbose -Message "$($USLocalizedData.$ErrorType -f $FormatArgs) | ErrorType: $errorId"

    $exception = New-Object System.Exception $errorMessage;
    $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $errorId, $ErrorCategory, $TargetObject

    return $errorRecord
}

function Assert-Module 
{ 
    [CmdletBinding()] 
    param 
    ( 
        [parameter(Mandatory = $true)]
        [string]$ModuleName
    ) 

    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    if (!(Get-Module -Name $ModuleName -ListAvailable)) 
    { 
        throw New-TerminatingError -ErrorType ModuleNotInstalled -FormatArgs @($ModuleName)
    } 
    else
    {
        Write-Verbose -Message "PowerShell Module '$ModuleName' is installed on the $env:COMPUTERNAME"
    }
}

function Write-Hashtable
{
    [CmdletBinding()] 
    param 
    ( 
        [parameter(Mandatory = $true)]
        [Hashtable]$Name
    ) 

    $Name.GetEnumerator() | Foreach-Object { Write-Verbose "Key: $($_.Key), Value: $($_.Value)" }
}

#
# This method throws the current error record except if it's of specified category.
#
function New-ExceptCategory
{
    param
    (
        [parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorCategory]$SuppressCategory
    )

    if (!($ErrorRecord.CategoryInfo.Category -eq $SuppressCategory)) 
    {
        throw $ErrorRecord
    }
    else
    {
        Write-Verbose -Message "Suppressing $SuppressCategory, Message: $($ErrorRecord.Exception.Message)" -Verbose
    } 
}

function Get-PhysicalDiskPolicyUsageString
{
    param 
    (
        [parameter(Mandatory = $true)]
        [string]$PhysicalDiskPolicyUsage
    )

    switch ($PhysicalDiskPolicyUsage)
    {
        AutoSelect {return "Auto-Select"}
        ManualSelect {return "Manual-Select"}
        HotSpare {return "Hot Spare"}
        Retired {return "Retired"}
        Journal {return "Journal"}
        Unknown {return "Unknown"}
        default {"The Usage Policy is not valid."}
    }
}

function Get-DisksByMediaType
{
    param 
    (
        [Parameter(Mandatory=$true)]
        [string]$DiskMediaType,

        [string]$StoragePoolFriendlyName
    )
    
    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    if (-not $StoragePoolFriendlyName)
    {
        # Calculating total actual poolable disks on the Rack
        $totalActualDisks = Get-PhysicalDisk | Where-Object {($_.CanPool -eq $true) -and ($_.MediaType -eq $DiskMediaType) -and ($_.BusType -eq "SAS") -and ($_.OperationalStatus -eq "OK")}
    }
    else    
    {
        $storagePool = Get-StoragePool -FriendlyName $StoragePoolFriendlyName -ErrorAction Stop
        # Calculating total disks in the storage pool
        $totalActualDisks = $storagePool | Get-PhysicalDisk | Where-Object {($_.MediaType -eq $DiskMediaType) -and ($_.BusType -eq "SAS") -and ($_.OperationalStatus -eq "OK")}
    }
    
    Write-Verbose -Message "$functionName Found a total of $($totalActualDisks.Count) $DiskMediaType disks in the pool $StoragePoolFriendlyName. "
                    
    $DisksForEachPool = @()
    $DisksForEachPool = $totalActualDisks
    $DisksForEachPool
}

function Initialize-xVirtualDisk
{
    param 
    (
        [string]$VDUniqueId,
        [string]$VDName
    )

    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    $MyHostName = hostname
    Move-ClusterGroup "Available Storage" -Node $MyHostName
    if ($? -eq $false)
    {
        throw New-TerminatingError -ErrorType InitializeVDErrorUnableToMoveClusterGroup -FormatArgs @($MyHostName)
    }

    Write-Verbose -Message "$functionName VDName: $VDName, Prepare the disk for use."
    $vDisk = Get-Disk | ? {$_.UniqueId -match $VDUniqueId}
    if (!($vDisk))
    {
        throw New-TerminatingError -ErrorType NewVDErrorUnableToGetDisk -FormatArgs @($VDName,$VDUniqueId)
    }
    $vDiskNum = $vDisk.Number

    Write-Verbose -Message "$functionName VDName: $VDName, Disk is part of cluster; Put it in maintenance mode before volume creation." 
    $DiskResource = Get-ClusterResource | ?{$_.Name -match $VDName}  
    if (!($DiskResource))
    {
        throw New-TerminatingError -ErrorType NewVDErrorUnableToGetClusterResource -FormatArgs @($VDName)
    }
    Suspend-ClusterResource $DiskResource.Name
    if ($? -eq $false)
    {
        throw New-TerminatingError -ErrorType NewVDErrorUnableToSetMaintenanceMode -FormatArgs @($VDName)
    }
    Start-Sleep -Seconds 2

    Write-Verbose -Message "$functionName VDName: $VDName, Disk Number: $vDiskNum, Clearing IsOffline flag."
    Get-Disk -Number $vDiskNum | Set-Disk -IsOffline $false

    Write-Verbose -Message "$functionName VDName: $VDName, Disk Number: $vDiskNum, Clearing IsReadOnly flag."
    Get-Disk -Number $vDiskNum | Set-Disk -IsReadOnly $false
            
    $newPartition = New-Partition -DiskNumber $vDiskNum -UseMaximumSize
    Start-Sleep -Seconds 2
                
    Format-Volume -Partition $newPartition -FileSystem NTFS -NewFileSystemLabel $VDName -ShortFileNameSupport $false -AllocationUnitSize 64KB -Confirm:$false
    if ($? -eq $false)
    {
        throw New-TerminatingError -ErrorType NewVDErrorUnableToFormatVolume -FormatArgs @($VDName)
    }
    Start-Sleep -Seconds 2

    Write-Verbose -Message "$functionName VDName: $VDName, Putting the disk out of maintenance mode."
    $DiskResource = Get-ClusterResource | ?{$_.Name -match $VDName} 
    Resume-ClusterResource $DiskResource.Name
    if ($? -eq $false)
    {
        throw New-TerminatingError -ErrorType NewVDErrorUnableToResumeClusterResource -FormatArgs @($VDName)
    }
}

function New-xVirtualDisk
{
    [CmdletBinding()]
	param
	(
        [parameter(Mandatory = $true)]
		[System.String]
		$VirtualDiskFriendlyName,

		[parameter(Mandatory = $true)]
		[System.String]
		$StoragePoolFriendlyName,

		[parameter(Mandatory = $true)]
		[System.UInt64]
		$SSDStorageTierSize,

		[parameter(Mandatory = $true)]
		[System.UInt64]
		$HDDStorageTierSize,

		[ValidateSet("Simple","Mirror","Parity")]
		[System.String]
		$ResiliencySettingName,

		[System.String]
		$NumberOfDataCopies,

		[System.UInt16]
		$NumberOfColumns
	) 

    $functionName = $($MyInvocation.MyCommand.Name) + ":"
    
    Write-Verbose -Message "$functionName Going to create virtual disk with friendly name $VirtualDiskFriendlyName in pool $StoragePoolFriendlyName."

    $areSSDsPresent = (Get-DisksByMediaType -DiskMediaType "SSD" -StoragePoolFriendlyName $StoragePoolFriendlyName).Count -gt 0
    $areHDDsPresent = (Get-DisksByMediaType -DiskMediaType "HDD" -StoragePoolFriendlyName $StoragePoolFriendlyName).Count -gt 0

    $ssdTier = $null
    $hddTier = $null
    if ($areSSDsPresent -and $areHDDsPresent)
    {
        if (($SSDStorageTierSize -ne 0) -and ($HDDStorageTierSize -ne 0))
        {   
            # For each pool we would create one abstract SSD tier 
            $ssdTierName = "SSDTier-" + $StoragePoolFriendlyName
            # ErrorAction SilentlyContinue, as we are ok if the storage tier does not exists as we will create it in the next step
            $ssdTier = Get-StorageTier -FriendlyName $ssdTierName -ErrorAction SilentlyContinue
            if (!($ssdTier))
            {
                Write-Verbose -Message "$functionName Creating the SSD Tier name $ssdTierName on Pool $StoragePoolFriendlyName."
                $ssdTier = New-StorageTier -StoragePoolFriendlyName $StoragePoolFriendlyName -FriendlyName $ssdTierName -MediaType SSD 
                if (!($ssdTier))
                {
                    throw New-TerminatingError -ErrorType FailedToCreateSSDTierForPool -FormatArgs @($StoragePoolFriendlyName)
                }
            }
            Write-Verbose -Message "$functionName SSD Tier $ssdTierName on Pool '$StoragePoolFriendlyName' already exists."

            # For each pool we would create one abstract HDD tier 
            $hddTierName = "HDDTier-" + $StoragePoolFriendlyName
            # ErrorAction SilentlyContinue, as we are ok if the storage tier does not exists as we will create it in the next step
            $hddTier = Get-StorageTier -FriendlyName $hddTierName -ErrorAction SilentlyContinue
            if (!($hddTier))
            {
                Write-Verbose -Message "$functionName Creating the HDD Tier name $hddTierName on Pool $StoragePoolFriendlyName."
                $hddTier = New-StorageTier -StoragePoolFriendlyName $StoragePoolFriendlyName -FriendlyName $hddTierName -MediaType HDD
                if (!($hddTier))
                {
                    throw New-TerminatingError -ErrorType FailedToCreateHDDTierForPool -FormatArgs @($StoragePoolFriendlyName)
                }
            }
            else
            {
                Write-Verbose -Message "$functionName HDD Tier $hddTierName on Pool '$StoragePoolFriendlyName' already exists."
            }
        }
    }

    if ($NumberOfDataCopies -eq 'Auto')
    { 
        $NumberOfDataCopies = Get-NumberOfDataCopiesBasedOnEnclosures -StoragePoolFriendlyName $StoragePoolFriendlyName
    }

    Write-Verbose -Message "$functionName Creating Virtual Disk $VirtualDiskFriendlyName in pool $StoragePoolFriendlyName." -Verbose
    $VD = $null
    if( ($ssdTier -ne $null) -and ($hddTier -ne $null))
    {
        $VD = New-VirtualDisk -StoragePoolFriendlyName $StoragePoolFriendlyName -FriendlyName $VirtualDiskFriendlyName -StorageTiers @($ssdTier,$hddTier) -StorageTierSizes @($SSDStorageTierSize,$HDDStorageTierSize) -ResiliencySettingName $ResiliencySettingName -NumberOfDataCopies $NumberOfDataCopies -NumberOfColumns $NumberOfColumns -Verbose
    }
    else
    {
        # If only one type of disks are present we don't use tiering
        $TotalSize = $SSDStorageTierSize + $HDDStorageTierSize
        $VD = New-VirtualDisk -StoragePoolFriendlyName $StoragePoolFriendlyName -FriendlyName $VirtualDiskFriendlyName -Size $TotalSize -ResiliencySettingName $ResiliencySettingName -NumberOfDataCopies $NumberOfDataCopies -NumberOfColumns $NumberOfColumns -Verbose
    }

    if (!($VD))
    {
        throw New-TerminatingError -ErrorType FailedToCreateVirtualDisk -FormatArgs @($VirtualDiskFriendlyName,$StoragePoolFriendlyName)
    }
    else
    {
        Write-Verbose -Message "$functionName Sucessfully created a new Virtual Disk with name $VirtualDiskFriendlyName in pool $StoragePoolFriendlyName. OperationalStatus: $($VD.OperationalStatus), HealthStatus: $($VD.HealthStatus)"
    }

    return $VD
}

function Get-NumberOfDataCopiesBasedOnEnclosures
{
    [CmdletBinding()]
	param
	(
        [parameter(Mandatory = $true)]
		$StoragePoolFriendlyName
	)
    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    $storagePool = Get-StoragePool -FriendlyName $StoragePoolFriendlyName

    $NumberOfDataCopies = 2
    $NumberOfEnclosures = (Get-StorageEnclosure).Count
    if ($NumberOfEnclosures -gt 3)
    {
        Write-Verbose -Message "$functionName Auto detecting number of data copies to be 3 based on the present number of enclosures: $NumberOfEnclosures."
        $NumberOfDataCopies = 3
    }

    return $NumberOfDataCopies
}

function Get-StorageTiersByVirtualDisk
{
    [CmdletBinding()]
	param
	(
        [parameter(Mandatory = $true)]
		$VirtualDisk
	) 

    $ssdStorageTierSize = 0
    $ssdTier = $VirtualDisk | Get-StorageTier -MediaType "SSD" -ErrorAction SilentlyContinue
    if ($ssdTier -ne $null) 
    {
        $ssdStorageTierSize = $ssdTier.Size
    }
    Write-Verbose -Message "$functionName For virtual disk with friendly name $($VirtualDisk.FriendlyName) we found SSDTierSize: $ssdStorageTierSize."

    $hddStorageTierSize = 0
    $hddTier = $VirtualDisk | Get-StorageTier -MediaType "HDD" -ErrorAction SilentlyContinue
    if ($hddTier -ne $null)
    {
        $hddStorageTierSize = $hddTier.Size
    }
    Write-Verbose -Message "$functionName For virtual disk with friendly name $($VirtualDisk.FriendlyName) we found HDDTierSize: $hddStorageTierSize."

    return @($ssdStorageTierSize, $hddStorageTierSize)
}

function Get-FolderPathForPathType
{
    [CmdletBinding()]
    Param
    (   
        [parameter(Mandatory = $true)]     
        [System.String]
        $Path,

        [parameter(Mandatory = $true)]
        [ValidateSet("Folder","CSV")]
        [System.String]
        $PathType,

        [System.Management.Automation.Runspaces.PSSession]
        $ServerSession
    )
    
    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    if( $PathType -eq "Folder")
    {
        return $Path
    }   
    elseif( $PathType -eq "CSV")
    {
        $csVolumeLocalPath = Invoke-Command -Session $ServerSession -ScriptBlock { $csVolume = Get-ClusterSharedVolume | Where-Object {$_.Name -match $using:Path}; $csVolume.SharedVolumeInfo.FriendlyVolumeName } -ArgumentList @($Path)
        if ($csVolumeLocalPath)
        {
            Write-Verbose -Message "$functionName Found a cluster shared volume on $ServerName matching name $Path. The local path is: $csVolumeLocalPath"
            return $csVolumeLocalPath
        }
        else
        {
            throw New-TerminatingError -ErrorType ClusterSharedVolumeNotFound -FormatArgs @($Path) -ErrorCategory ObjectNotFound
        }
    }
}

function Get-RegistryKeyValue
{            
    [CmdletBinding()] 
    param 
    (     
        [Parameter(Mandatory=$true)] 
        [ValidateNotNullOrEmpty()]
        [String]$Key,

        [Parameter(Mandatory=$true)] 
        [ValidateNotNullOrEmpty()]
        [String]$KeyName
    ) 

    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    $regEntry = $null
    $regEntry = Get-ItemProperty -Path $Key -Name $KeyName -ErrorAction SilentlyContinue

    if($regEntry -eq $null) 
    {
        # If we don't find the key then this is the first time we ran this code, we create and set it.
        if (!(Test-Path -Path $Key))
        {
            Write-Verbose "$functionName Creating a new registry path Key '$Key' on $env:COMPUTERNAME" -Verbose
            $null = New-Item -Path $Key -ErrorAction Stop
        }
        Write-Verbose "$functionName Creating a new  Key with name '$KeyName' with value '$true' on $env:COMPUTERNAME" -Verbose
        Set-ItemProperty -Path $Key -Name $KeyName -Value $true -ErrorAction Stop
        
        return $true
    } 
    else 
    {                
        Write-Verbose "$functionName Found Key $Key with key name $KeyName and value '$($regEntry.$KeyName)'" -Verbose
        return $regEntry.$KeyName
    }
}

function Test-PhysicalDisksHealth
{
    # At the end of cleanup check the physical disk status and trace of some are not in a good state i.e. "OK" state.
    $physicalDisks = Get-PhysicalDisk | ? {($_.BusType -eq "SAS")}
    foreach ($physicalDisk in $physicalDisks)
    {
        if ($physicalDisk.OperationalStatus -ne "OK")
        {
            # If some disks are not OK we are not failing right now. Later configuration of pools will fail with the failed disks are below a certain required limits.
            $msg = "$functionName Physical disk with FriendlyName: $($physicalDisk.FriendlyName) and UniqueId: $($physicalDisk.UniqueId) is not OK, OperationalStatus: $($physicalDisk.OperationalStatus) and HealthStatus: $($physicalDisk.HealthStatus)!"
            Write-Verbose -Message $msg -Verbose
            Write-Warning -Message $msg -Verbose
        } 
    }

    # All the physical disk should also be attached to each node.
    $physicalDisks = Get-PhysicalDisk | ? {($_.BusType -eq "SAS") -and ($_.OperationalStatus -eq "OK")}
    $storageNodes = Get-StorageNode
    Write-Verbose -Message "$functionName Count of storage nodes: $($storageNodes.Count-1) and total disks: $($physicalDisks.Count)." -Verbose
    $asymmetricStorage = $false
    foreach ($i in 1..($storageNodes.count-1)) 
    {
        $physicalDisksOnTheNode = $storageNodes[$i] | Get-PhysicalDisk | ? {($_.BusType -eq "SAS") -and ($_.OperationalStatus -eq "OK")}  
        if($physicalDisksOnTheNode.Count -ne $physicalDisks.Count)
        {
            $asymmetricStorage = $true
            Write-verbose -Message "$($storageNodes[$i].Name) has $($physicalDisksOnTheNode.Count) disks whereas there should be $($physicalDisks.Count) disks!" -Verbose
        }
        else
        {
            Write-verbose -Message "$($storageNodes[$i].Name) has $($physicalDisksOnTheNode.Count) disks and is same as disk count $($physicalDisks.Count)." -Verbose
        }

    } 
    if ($asymmetricStorage)
    {
        throw New-TerminatingError -ErrorType NotAllDisksConnectedToEachStorageNode -FormatArgs @($storageNodes[$i].Name)
    }
}

function Update-StorageCache
{
    # Update the storage cache
    #
    Write-Verbose -Message "$functionName Updating Storage Cache after clean-up on all nodes of the Storage cluster." -Verbose
    $storageNodes = Get-StorageNode
    Update-StorageProviderCache -DiscoveryLevel Full 
    Update-StorageProviderCache -DiscoveryLevel Full          
    foreach ($i in 1..($storageNodes.count-1)) 
    {
        $currentHostName = hostname
        if($storageNodes[$i].Name.Split(".")[0] -ne $currentHostName)
        {
            Write-Verbose -Message "$functionName Updating Storage Cache on $($storageNodes[$i].Name)." -Verbose
            Invoke-Command -ComputerName $storageNodes[$i].Name -Verbose -ErrorAction Stop -ScriptBlock {hostname; Update-StorageProviderCache -DiscoveryLevel Full; Update-StorageProviderCache -DiscoveryLevel Full}
        }
    }
}

function Convert-AccessControlType
{
    param 
    (
        [parameter(Mandatory = $true)]
        [string]$AccessControlType
    )

    switch ($AccessControlType)
    {
        0 {return "Allow"}
        1 {return "Deny"}
        Allow {return "Allow"}
        Deny {return "Deny"}
    }
}

function Convert-AccessRight
{
    param 
    (
        [parameter(Mandatory = $true)]
        [string]$AccessRight
    )

    switch ($AccessRight)
    {
        0 {return "Full"}
        1 {return "Change"}
        2 {return "Read"}
        Full {return "Full"}
        Change {return "Change"}
        Read {return "Read"}
    }
}

function New-PSSessionWithRetry
{
    param 
    (
        [parameter(Mandatory = $true)]
        [string]$ComputerName,

        [PSCredential]$Credential
    )

    $retryCount = 1
    $maxRetryCount = 6
    $sleepSeconds = 10
    while (($retryCount -le $maxRetryCount))
    {
        try
        {
            if ($Credential)
            {
                $psSession = New-PSSession -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop
            }
            else
            {
                $psSession = New-PSSession -ComputerName $ComputerName -ErrorAction Stop
            }
            $retryCount = $maxRetryCount   
        }
        catch [Exception]
        {
            if( $retryCount -ge $maxRetryCount)
            {
                Write-Verbose -Message "Connection attempt $retryCount (of $maxRetryCount) to $ComputerName failed! $($_.Exception)" -Verbose
                Write-Error -Exception $_.Exception
                throw $_
            }
            else
            {
                Write-Verbose -Message "Connection attempt $retryCount (of $maxRetryCount) to $ComputerName failed! Going to try again." -Verbose
            }
        }
        $retryCount = $retryCount + 1
        Start-Sleep -Seconds $sleepSeconds
    } 

    return $psSession
}

function Convert-MPClaimLoadBalancingPolicy
{
    param 
    (
        [parameter(Mandatory = $true)]
        [string]$PolicyName
    )

    switch ($PolicyName)
    {
        ClearPolicy {return 0}
        LeastBlocks {return 6}
    }
}

