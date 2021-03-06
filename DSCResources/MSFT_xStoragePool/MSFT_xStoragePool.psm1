$currentPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Debug -Message "CurrentPath: $currentPath"
Import-Module $currentPath\..\..\StorageHelper.psm1 -Verbose:$false

<#
 # DSC resouces for handling Storage Pools and it's properties
#>
function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$FriendlyName
	)

    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    Assert-Module -ModuleName Storage
    Assert-Module -ModuleName FailoverClusters

    try
    {
        $storagePool = Get-StoragePool -FriendlyName $FriendlyName -ErrorAction Stop
    }
    catch [Exception]
    {
        New-ExceptCategory -ErrorRecord $_ -SuppressCategory ObjectNotFound
    }

    if ($storagePool -eq $null)
    {
        Write-Verbose -Message "$functionName Storage Pool with friendly name $FriendlyName does not exists."
        $Ensure = "Absent"
    }
    else
    {
        Write-Verbose -Message "$functionName Storage Pool with friendly name $FriendlyName exists."
        $Ensure = "Present"
        $EnclosureAwareDefault = $storagePool.EnclosureAwareDefault

        $allDisks = $storagePool | Get-PhysicalDisk
        if ($allDisks)
        {
            $firstDisk = $allDisks[0]

            $countOfDisksWithFirstDiskUsagePolicy = ($storagePool | Get-PhysicalDisk | Where-Object {$_.Usage -eq $firstDisk.Usage}).Count
            $countOfAllDisks = $allDisks.Count
            if( $countOfDisksWithFirstDiskUsagePolicy -eq $countOfAllDisks)
            {
                # All the physical disks in the pool has same Usage policy.
                $PhysicalDiskPolicyUsage = $firstDisk.Usage
                Write-Verbose -Message "$functionName Storage Pool with friendly name $($storagePool.FriendlyName) has all the physical disks with Usage policy set to $PhysicalDiskPolicyUsage."
            }
            else
            {
                Write-Verbose -Message "$functionName Storage Pool with friendly name $($storagePool.FriendlyName) does not have all the physical disks with same Usage policy."
            }
        }
    }
    
	$returnValue = @{
        FriendlyName = $FriendlyName
		IsReadOnly =  $storagePool.IsReadOnly
		Ensure = $Ensure
	    RetireMissingPhysicalDisks = $storagePool.RetireMissingPhysicalDisks	
		RepairPolicy = $storagePool.RepairPolicy
        PhysicalDiskPolicyUsage = $PhysicalDiskPolicyUsage
        EnclosureAwareDefault = $EnclosureAwareDefault
	}
    
	return $returnValue
}

function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$FriendlyName,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

        [ValidateSet("Auto","Always", "Never")]
		[System.String]
		$RetireMissingPhysicalDisks = "Always",

        [ValidateSet("Sequential","Parallel")]
		[System.String] 
		$RepairPolicy = "Parallel",  
		
        [ValidateSet("Unknown", "AutoSelect", "ManualSelect", "HotSpare", "Retired", "Journal")]
        [System.String]
		$PhysicalDiskPolicyUsage = "AutoSelect",

        [System.Boolean]
        $EnclosureAwareDefault = $false
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
		$FriendlyName,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

        [ValidateSet("Auto","Always", "Never")]
		[System.String]
		$RetireMissingPhysicalDisks = "Always",

        [ValidateSet("Sequential","Parallel")]
		[System.String]
		$RepairPolicy = "Parallel",

        [ValidateSet("Unknown", "AutoSelect", "ManualSelect", "HotSpare", "Retired", "Journal")]
		[System.String]
		$PhysicalDiskPolicyUsage = "AutoSelect",

        [System.Boolean]
        $EnclosureAwareDefault = $false
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
		$FriendlyName,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

        [ValidateSet("Auto","Always", "Never")]
		[System.String]
		$RetireMissingPhysicalDisks = "Always",

        [ValidateSet("Sequential","Parallel")]
		[System.String] 
		$RepairPolicy = "Parallel",  
		
        [ValidateSet("Unknown", "AutoSelect", "ManualSelect", "HotSpare", "Retired", "Journal")]
        [System.String]
		$PhysicalDiskPolicyUsage = "AutoSelect",

        [System.Boolean]
        $EnclosureAwareDefault = $false,

        [Switch]$Apply
	) 
    
    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    try
    {
        $NumberOfEnclosures = (Get-StorageEnclosure).Count
        Write-Verbose -Message "$functionName Found $NumberOfEnclosures enclosures while working on pool, $FriendlyName."
        
        $IsHardwareEnclosureAwarenessCapable = $false
        if ($NumberOfEnclosures -ge 3)
        {
            $IsHardwareEnclosureAwarenessCapable = $true
        }

        $resourceProperties = Get-TargetResource -FriendlyName $FriendlyName
        if ($Ensure -eq "Present")
        {
            if( $resourceProperties['Ensure'] -eq "Absent")
            {
                if($Apply) 
                { 
                    if ($EnclosureAwareDefault -and (-not $IsHardwareEnclosureAwarenessCapable)) 
                    {
                        $EnclosureAwareDefault = $false
                        Write-Verbose -Message "$functionName Unable to make the pool $FriendlyName enclosure aware as we only found $NumberOfEnclosures which is less then required!"
                    }

                    Write-Verbose -Message "$functionName Collecting physical disks for storage pool with friendly name $FriendlyName."
                    $DisksForEachPoolSSDs = $null
                    $DisksForEachPoolSSDs = Get-DisksByMediaType -DiskMediaType "SSD"
                       
                    $DisksForEachPoolHDDs = $null
                    $DisksForEachPoolHDDs = Get-DisksByMediaType -DiskMediaType "HDD"

                    Write-Verbose -Message "$functionName Creating the Storage Pool $FriendlyName with $($DisksForEachPoolSSDs.Count) SSDs and $($DisksForEachPoolHDDs.Count) HDDs."
                
                    # Combining the disks retrieved earlier.
                    $DisksForEachPoolAll = @()
                    $DisksForEachPoolAll += $DisksForEachPoolSSDs
                    $DisksForEachPoolAll += $DisksForEachPoolHDDs

                    Write-Verbose -Message "$functionName Creating the Storage Pool $FriendlyName."          
                    $maxRetryCount = 2
                    $retryCount = 0
                    $storagePool = $null
                    while (($retryCount -le $maxRetryCount))
                    {
                        try
                        { 
                            $storagePool = New-StoragePool -StorageSubSystemFriendlyName *Clustered*Spaces* -FriendlyName $FriendlyName -PhysicalDisks $DisksForEachPoolAll -EnclosureAwareDefault:$EnclosureAwareDefault
                            $retryCount = $maxRetryCount   
                        }
                        catch [Exception]
                        {
                            if( $retryCount -ge $maxRetryCount)
                            {
                                Write-Verbose -Message "$functionName Creating pool $FriendlyName on the stamp has failed after $($retryCount+1) attempts! Message: $_.ErrorDetails.Message" 
                                Write-Error -Exception $_
                                throw $_
                            }
                            else
                            {
                                Write-Verbose -Message "$functionName Creating pool $FriendlyName on the Rack has failed on $retryCount attempt. If less then $($maxRetryCount+1) then going to try again. Message: $_.ErrorDetails.Message" 
                            }
                        }
                        $retryCount = $retryCount + 1
                    }
                }
                else
                {
                    Write-Verbose -Message "$functionName Storage Pool with friendly name $FriendlyName does not exists."
                    return $false
                }
            }
            else
            {
                $storagePool = Get-StoragePool -FriendlyName $FriendlyName -ErrorAction Stop
                Write-Verbose -Message "$functionName Retrieved storage pool with friendly name $FriendlyName." 
            }
        }
        elseif( $Ensure -eq "Absent")
        {
            throw New-TerminatingError -ErrorType AbsentNotImplemented -ErrorCategory NotImplemented 
        }
        else
        { 
            throw New-TerminatingError -ErrorType UnexpectedEnsureValue -ErrorCategory NotImplemented
        }

        if (!($storagePool))
        {
            throw New-TerminatingError -ErrorType FailedToCreateStoragePool -FormatArgs @($FriendlyName)
        }
        else
        {
            Write-Verbose -Message "$functionName Sucessfully created or found a Storage Pool $($storagePool.FriendlyName), OperationalStatus: $($storagePool.OperationalStatus), HealthStatus: $($storagePool.HealthStatus)."
        }

        if($storagePool.IsReadOnly)
        {    
            if($Apply)
            {
                # We need to make the pool writable before we can apply any properties.
                $storagePool | Set-StoragePool -IsReadOnly:$false -ErrorAction Stop
                $storagePool = Get-StoragePool -FriendlyName $FriendlyName -ErrorAction Stop
            }
        }
        Write-Verbose -Message "$functionName Storage Pool with friendly name $FriendlyName has IsReadOnly set to $($storagePool.IsReadOnly)." 
        
        $resourcePropertiesToSet = @{}
        if( $storagePool.RetireMissingPhysicalDisks -ne $RetireMissingPhysicalDisks)
        {    
            if($Apply) 
            {
                $resourcePropertiesToSet['RetireMissingPhysicalDisks'] = $RetireMissingPhysicalDisks
                Write-Verbose -Message "$functionName Storage Pool with friendly name $FriendlyName has RetireMissingPhysicalDisks set to $RetireMissingPhysicalDisks."
            }
            else
            {
                Write-Verbose -Message "$functionName Storage Pool with friendly name $FriendlyName has RetireMissingPhysicalDisks set to $($storagePool.RetireMissingPhysicalDisks)."
                return $false
            }
        }
        else
        {
            Write-Verbose -Message "$functionName Storage Pool with friendly name $FriendlyName has RetireMissingPhysicalDisks already set to $RetireMissingPhysicalDisks."
        }

        if( $storagePool.RepairPolicy -ne $RepairPolicy)
        {    
            if($Apply) 
            {
                $resourcePropertiesToSet['RepairPolicy'] = $RepairPolicy
                Write-Verbose -Message "$functionName Storage Pool with friendly name $($storagePool.FriendlyName) has RepairPolicy set to $RepairPolicy."
            }
            else
            {
                Write-Verbose -Message "$functionName Storage Pool with friendly name $($storagePool.FriendlyName) has RepairPolicy set to $($storagePool.RepairPolicy)."
                return $false
            }
        }
        else
        {
            Write-Verbose -Message "$functionName Storage Pool with friendly name $($storagePool.FriendlyName) has RepairPolicy already set to $RepairPolicy."
        }

        if (($storagePool.EnclosureAwareDefault -ne $EnclosureAwareDefault) -and ($IsHardwareEnclosureAwarenessCapable))
        {    
            if($Apply) 
            {
                $resourcePropertiesToSet['EnclosureAwareDefault'] = $EnclosureAwareDefault
                Write-Verbose -Message "$functionName Storage Pool with friendly name $($storagePool.FriendlyName) has EnclosureAwareDefault set to $EnclosureAwareDefault."
            }
            else
            {
                Write-Verbose -Message "$functionName Storage Pool with friendly name $($storagePool.FriendlyName) has EnclosureAwareDefault set to $($storagePool.EnclosureAwareDefault)."
                return $false  
            }
        }
        else
        {
            Write-Verbose -Message "$functionName Storage Pool with friendly name $($storagePool.FriendlyName) has EnclosureAwareDefault already set to $EnclosureAwareDefault or is not enclosure awareness capable."
        }
        
        if($resourcePropertiesToSet.Keys.Count -gt 0) 
        {
            # We want the storage subsystem to automatically retire missing physical disks in these storage pool and replace them with hot-spares or 
            # other available physical disks (in the storage pool). 
            # Also setting RepairPolicy to 'Parallel' which ensures multiple slabs to rebuild, and this results in faster rebuild times.
		    $storagePool | Set-StoragePool @resourcePropertiesToSet -ErrorAction Stop
            $storagePool = Get-StoragePool -FriendlyName $FriendlyName -ErrorAction Stop
        }
        
        # Applying physical disk policies
        #
        $PhysicalDiskPolicyUsageString = Get-PhysicalDiskPolicyUsageString -PhysicalDiskPolicyUsage $PhysicalDiskPolicyUsage
        if ($resourceProperties['PhysicalDiskPolicyUsage'] -ne $PhysicalDiskPolicyUsageString)
        {
            if($Apply) 
            {
                $disks = $storagePool | Get-PhysicalDisk
                Write-Verbose -Message "$functionName Setting SSD disks 'Usage' setting to $PhysicalDiskPolicyUsage on Pool $FriendlyName."
                Set-PhysicalDisk -InputObject $disks -Usage $PhysicalDiskPolicyUsage
            }
            else
            {
                return $false
            }
        }
        else
        {
            Write-Verbose -Message "$functionName Storage Pool with friendly name $($storagePool.FriendlyName) has all the physical disks with Usage policy already set to '$PhysicalDiskPolicyUsageString'."
        }

        if($Apply)
        {
            Write-Verbose -Message "$functionName Finished setting resource is in desired state for $FriendlyName." 
        }
        else
        {
            Write-Verbose -Message "$functionName Resource is validated to be in desired state for $FriendlyName."
            return $true
        }
    }
    catch
    {
        Write-Verbose -Message "$functionName has failed! Message: $_ ."
        throw $_
    }
}

Export-ModuleMember -Function *-TargetResource

