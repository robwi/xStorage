$currentPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Debug -Message "CurrentPath: $currentPath"
Import-Module $currentPath\..\..\StorageHelper.psm1 -Verbose:$false

function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$StorageClusterName,

        [parameter(Mandatory = $true)]
		[System.String]
		$RegisteryKeyIfCleanupStorageSpaces
	)

    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    Assert-Module -ModuleName Storage
    Assert-Module -ModuleName FailoverClusters

    #$Key = "HKLM:\SOFTWARE\Microsoft\Cloud Solutions"
    $KeyName = "IfCleanupStorageSpaces"
    $IfCleanupStorageSpaces = Get-RegistryKeyValue -Key $RegisteryKeyIfCleanupStorageSpaces -KeyName $KeyName

	$returnValue = @{
		StorageClusterName = $StorageClusterName
        RegisteryKeyIfCleanupStorageSpaces = $RegisteryKeyIfCleanupStorageSpaces
		IfCleanupStorageSpaces = $IfCleanupStorageSpaces
	}

	$returnValue
}


function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$StorageClusterName,

        [parameter(Mandatory = $true)]
		[System.String]
		$RegisteryKeyIfCleanupStorageSpaces,

		[System.Boolean]
		$RemoveClusterQuorum,

		[System.Boolean]
		$RemoveAllStorageClusterResources,

		[System.Boolean]
		$ClearClusterDiskReservation,

		[System.Boolean]
		$DeletePoolsAndVirtualDisks,

		[System.Boolean]
		$ResetAndClearPhysicalDisks,

		[System.Boolean]
		$VerifyPhysicalDisksHealth

	)

	ValidateOrApply-Resource @PSBoundParameters -Apply

}


function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$StorageClusterName,

        [parameter(Mandatory = $true)]
		[System.String]
		$RegisteryKeyIfCleanupStorageSpaces,

		[System.Boolean]
		$RemoveClusterQuorum,

		[System.Boolean]
		$RemoveAllStorageClusterResources,

		[System.Boolean]
		$ClearClusterDiskReservation,

		[System.Boolean]
		$DeletePoolsAndVirtualDisks,

		[System.Boolean]
		$ResetAndClearPhysicalDisks,

		[System.Boolean]
		$VerifyPhysicalDisksHealth
	)

    $isDesiredState = ValidateOrApply-Resource @PSBoundParameters

    return $isDesiredState
}


# This is an internal function that is either used by Test or Set for the resource based on the Apply flag.
#
function ValidateOrApply-Resource 
{ 
	[CmdletBinding()]
	param
	(
        [parameter(Mandatory = $true)]
		[System.String]
		$StorageClusterName,

        [parameter(Mandatory = $true)]
		[System.String]
		$RegisteryKeyIfCleanupStorageSpaces,

		[System.Boolean]
		$RemoveClusterQuorum,

		[System.Boolean]
		$RemoveAllStorageClusterResources,

		[System.Boolean]
		$ClearClusterDiskReservation,

		[System.Boolean]
		$DeletePoolsAndVirtualDisks,

		[System.Boolean]
		$ResetAndClearPhysicalDisks,

		[System.Boolean]
		$VerifyPhysicalDisksHealth,		

        [Switch]$Apply
	) 
    
    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    try
    {
        $resourceProperties = Get-TargetResource -StorageClusterName $StorageClusterName -RegisteryKeyIfCleanupStorageSpaces $RegisteryKeyIfCleanupStorageSpaces

        if( $resourceProperties['IfCleanupStorageSpaces'] -eq $true)
        {
            if ($Apply)
            {
                Delete-AllStorage -RemoveClusterQuorum $RemoveClusterQuorum -RemoveAllStorageClusterResources $RemoveAllStorageClusterResources -ClearClusterDiskReservation $ClearClusterDiskReservation -DeletePoolsAndVirtualDisks $DeletePoolsAndVirtualDisks -ResetAndClearPhysicalDisks $ResetAndClearPhysicalDisks -VerifyPhysicalDisksHealth $VerifyPhysicalDisksHealth
            }
            else
            {
                return $false
            }
        }
        else
        {
            if (!($Apply))
            {
                return $true
            }
        }

    }
    catch
    {
        Write-Verbose -Message "$functionName has failed! Message: $_ ."
        throw $_
    }
}


function Delete-AllStorage
{     
    param 
    (
        [Boolean]$RemoveClusterQuorum,

        [Boolean]$RemoveAllStorageClusterResources,

        [Boolean]$ClearClusterDiskReservation,

        [Boolean]$DeletePoolsAndVirtualDisks,

        [Boolean]$ResetAndClearPhysicalDisks,

        [Boolean]$VerifyPhysicalDisksHealth
    )

    $functionName = $($MyInvocation.MyCommand.Name) + ":"
    $startTime = Get-Date 

    # Cleaning up Cluster resources
    #
    if ($RemoveClusterQuorum)
    {
        Write-Verbose -Message "$functionName Removing witness disk from Quorum setting so it can be removed." -Verbose
        Set-ClusterQuorum -NodeMajority > $null
    }

    if ($RemoveAllStorageClusterResources)
    {
        Write-Verbose -Message "$functionName Removing disks from cluster shared volumes so they can be removed." -Verbose
        Get-ClusterSharedVolume | Remove-ClusterSharedVolume > $null

        Write-Verbose -Message "$functionName Removing cluster disks resources." -Verbose
        Get-ClusterResource | where {$_.ResourceType -eq 'Physical Disk'} | Remove-ClusterResource -Confirm:$false -Force

        Write-Verbose -Message "$functionName Removing cluster pool resources." -Verbose
        Get-ClusterResource | where {$_.ResourceType -eq 'Storage Pool'} | Remove-ClusterResource  -Confirm:$false -Force
    }

    Update-StorageCache

    $storageNodeNames = @()
    $storageNodes = Get-StorageNode
    Write-Verbose -Message "$functionName Count of storage nodes: $($($storageNodes.Count) - 1)." -Verbose
    foreach ($i in 1..($storageNodes.count-1)) 
    {
        $storageNodeNames += $storageNodes[$i].Name
    }

    $storageSubSystem = Get-StorageSubSystem -FriendlyName *Clustered*Spaces*
                    
    # Cleaning up physical resources
    #
    #
    # Cleaning up the persistent reservation for physical disks.
    #
    # Cleaning up the persistent reservation for physical disks. 
    # In normal scenario (where the cluster still exists) this operation is supposed to be call after pool removal from the cluster 
    # but in the current scenario, we have already removed the cluster using OSD. The pools were simply left behind from the old cluster. 
    # Keeping this in mind we need to clean-up the disks of any PR data before proceeding futher with the pool deletion, 
    # otherwise the pools are not writable.
    if ($ClearClusterDiskReservation)
    {
        $physicalDisks = $storageSubSystem | Get-PhysicalDisk
        if ($physicalDisks)
        {
            Write-Verbose -Message "$functionName Clearing persistent reservation for physical disks (Count: $($physicalDisks.Count)) in storage subsystem '$($storageSubSystem.FriendlyName)'." -Verbose
            foreach ($physicalDisk in $physicalDisks)
            {
                if ($physicalDisk.DeviceId)
                {
                    # Write-Verbose -Message "$functionName Clearing PR for $($physicalDisk.FriendlyName) and $($physicalDisk.DeviceId)" -Verbose
                    Clear-ClusterDiskReservation -Node $storageNodeNames -Disk $physicalDisk.DeviceId -Force -Confirm:$false -ErrorAction SilentlyContinue
                }
            }
        }
    }

    # Deleting Pool and Virtual Disks
    if ($DeletePoolsAndVirtualDisks)
    {
        $storagePools = $storageSubSystem | Get-StoragePool | ? {$_.IsPrimordial -eq $false}
        foreach ($storagePool in $storagePools)
        {
            Write-Verbose -Message "$functionName Start cleaning pool: $($storagePool.FriendlyName)." -Verbose
            if (!($storagePool.IsClustered))
            {
                # Attach the pool
                if ($storagePool.IsReadOnly -eq $true)
                {
                    $storagePool | Set-StoragePool -IsReadOnly:$false -ErrorAction Stop
                }
                $storagePool = Get-StoragePool -FriendlyName $storagePool.FriendlyName

                Write-Verbose -Message "$functionName Storage Pool info after setting IsReadOnly flag: FriendlyName: $($storagePool.FriendlyName), IsReadOnly: $($storagePool.IsReadOnly)." -Verbose

                Write-Verbose -Message "$functionName Getting virtual disks in Storage Pool $($storagePool.FriendlyName)." -Verbose
                $virtualDisks = $storagePool | Get-VirtualDisk
                if ($virtualDisks)
                {
                    Write-Verbose -Message "$functionName Connecting virtual disks in Storage Pool $($storagePool.FriendlyName)." -Verbose
                    $virtualDisks | ForEach-Object { Connect-VirtualDisk -UniqueId $_.UniqueId -ErrorAction SilentlyContinue -Verbose}

                    Write-Verbose -Message "$functionName Removing virtual disks in Storage Pool $($storagePool.FriendlyName)." -Verbose
                    $virtualDisks | Remove-VirtualDisk -Confirm:$false -ErrorAction SilentlyContinue
                }

                Write-Verbose -Message "$functionName Removing Storage Pool $($storagePool.FriendlyName)." -Verbose
                $storagePool | Remove-StoragePool -Confirm:$false -ErrorAction Stop
            }
            else
            {
                throw New-TerminatingError -ErrorType PoolClusteredError -FormatArgs @($($storagePool.FriendlyName))
            }
        }
    }
     
    # Clean-up of Physical Disks 
    # Cleans up any residual pool state. As a word of caution this should only be done for cases when we are running full clean-up. All drives in the cluster subsystem will be wiped clean.
    #
    if ($ResetAndClearPhysicalDisks)
    {
        $physicalDisks = $storageSubSystem | Get-PhysicalDisk
        if ($physicalDisks)
        {
            Write-Verbose -Message "$functionName Resetting physical disks (Count: $($physicalDisks.Count)) to cleanup any residual pool state." -Verbose
            Reset-PhysicalDisk -InputObject $physicalDisks -Confirm:$false -ErrorAction Stop
        } 
                
        # Clear all the information from the disks. As a word of caution this should only be done for cases when we are running full clean-up. All drives in the cluster subsystem will be wiped clean.
        #
        $physicalDisks = $storageSubSystem | Get-PhysicalDisk             
        $diskUniqueIds = @()
        Write-Verbose -Message "$functionName Setting IsOffline:false and IsReadOnly:false for all the disks (Count: $($physicalDisks.Count))." -Verbose
        foreach ($physicalDisk in $physicalDisks)
        {
            $diskUniqueIds += $physicalDisk.UniqueId
        }
        $disks = Get-Disk -UniqueId $diskUniqueIds

        if ($disks -and $disks.Count -gt 0)
        {
            Write-Verbose -Message "$functionName Setting IsOffline:false for disks (Count: $($disks.Count))." -Verbose   
            Set-Disk -InputObject $disks -IsOffline $false

            Write-Verbose -Message "$functionName Setting IsReadOnly:false for disks (Count: $($disks.Count))." -Verbose
            Set-Disk -InputObject $disks -IsReadOnly $false

            Write-Verbose -Message "$functionName Clearing disks (Count: $($disks.Count))." -Verbose
            Clear-Disk -Number $disks.Number -RemoveData:$true -Confirm:$false -RemoveOEM:$true -ErrorAction SilentlyContinue
        }   
    }
                
    Update-StorageCache

    $endTime = Get-Date
    Write-Verbose -Message "$functionName Total time for clean-up $($endTime-$startTime) ." -Verbose

    if ($VerifyPhysicalDisksHealth)
    {
        Test-PhysicalDisksHealth
    }

    Start-Sleep -Seconds 60
}
Export-ModuleMember -Function *-TargetResource

