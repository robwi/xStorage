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
		$FriendlyName,

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
		$HDDStorageTierSize
	)

    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    Assert-Module -ModuleName Storage
    Assert-Module -ModuleName FailoverClusters

    try
    {
        $volume = Get-Volume -FileSystemLabel $FriendlyName -ErrorAction Stop
    }
    catch [Exception]
    {
        New-ExceptCategory -ErrorRecord $_ -SuppressCategory ObjectNotFound
    }

    if ($volume -eq $null)
    {
        $Ensure = "Absent"
        Write-Verbose -Message "$functionName Volume with friendly name (FileSystemLabel) $FriendlyName does not exists."
    }
    else
    {
        $Ensure = "Present"
        Write-Verbose -Message "$functionName Volume with friendly name (FileSystemLabel) $FriendlyName exists."

        if ($volume.Count -ne $null)
        {
            # If we found a volume with the same friendly name 
            $msg = "$functionName Found multiple ($($volume.Count)) volumes with friendly name $FriendlyName. If you are creating the volume then change the friendly name."
            New-TerminatingError -ErrorMessage $msg
        }
    }

    $FoundStorageTiers = @(0, 0)
    $virtualDisk = Get-StoragePool -FriendlyName $StoragePoolFriendlyName -ErrorAction Stop | Get-VirtualDisk | Where-Object {$_.FriendlyName -eq $VirtualDiskFriendlyName} -ErrorAction stop
    if ($virtualDisk -eq $null)
    {
        Write-Verbose -Message "$functionName Virtual disk with friendly name $VirtualDiskFriendlyName does not exists."  
    }
    else
    {
        Write-Verbose -Message "$functionName Virtual disk with friendly name $VirtualDiskFriendlyName exists."

        if ($virtualDisk.Count -ne $null)
        {
            # If we found a virtual disk with the same friendly name     
            $msg = "$functionName Found multiple ($($virtualDisk.Count)) virtual disk with friendly name $VirtualDiskFriendlyName in pool $StoragePoolFriendlyName. If you are creating the virtual disk then change the friendly name."
            New-TerminatingError -ErrorMessage $msg
        }

        $FoundStorageTiers = Get-StorageTiersByVirtualDisk -VirtualDisk $virtualDisk -Verbose
    }
    $FoundSSDStorageTierSize = $FoundStorageTiers[0]
    $FoundHDDStorageTierSize = $FoundStorageTiers[1]

    Write-Verbose -Message "$functionName For Virtual disk with friendly name $VirtualDiskFriendlyName we found SSDTierSize: $($FoundSSDStorageTierSize/1MB) (User Specified: $($FoundSSDStorageTierSize/1MB))."
    Write-Verbose -Message "$functionName For Virtual disk with friendly name $VirtualDiskFriendlyName we found HDDTierSize: $($FoundHDDStorageTierSize/1MB) (User Specified: $($FoundHDDStorageTierSize/1MB))."

	$returnValue = @{
		FriendlyName = $FriendlyName
        VirtualDiskFriendlyName = $VirtualDiskFriendlyName
		StoragePoolFriendlyName = $StoragePoolFriendlyName
        Ensure = $Ensure
        FileSystem = $volume.FileSystem
		SSDStorageTierSize = $FoundSSDStorageTierSize
		HDDStorageTierSize = $FoundHDDStorageTierSize
        ResiliencySettingName = $virtualDisk.ResiliencySettingName
		NumberOfDataCopies = $virtualDisk.NumberOfDataCopies
		NumberOfColumns = $virtualDisk.NumberOfColumns
        VolumeGuidPath = $volume.Path
        Size = $virtualDisk.Size
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

		[parameter(Mandatory = $true)]
		[System.String]
		$VirtualDiskFriendlyName,

		[parameter(Mandatory = $true)]
		[System.String]
		$StoragePoolFriendlyName,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure,

		[ValidateSet("NTFS","ReFS")]
		[System.String]
		$FileSystem = "NTFS",

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

		[parameter(Mandatory = $true)]
		[System.String]
		$VirtualDiskFriendlyName,

		[parameter(Mandatory = $true)]
		[System.String]
		$StoragePoolFriendlyName,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

        [ValidateSet("NTFS","ReFS")]
		[System.String]
		$FileSystem = "NTFS",
        
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

		[parameter(Mandatory = $true)]
		[System.String]
		$VirtualDiskFriendlyName,

		[parameter(Mandatory = $true)]
		[System.String]
		$StoragePoolFriendlyName,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

        [ValidateSet("NTFS","ReFS")]
		[System.String]
		$FileSystem = "NTFS",

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
		$NumberOfColumns,

        [Switch]$Apply
	) 
    
    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    try
    {
        if ($NumberOfDataCopies -eq 'Auto')
        {
            $NumberOfDataCopies = Get-NumberOfDataCopiesBasedOnEnclosures -StoragePoolFriendlyName $StoragePoolFriendlyName
        }

        $resourceProperties = Get-TargetResource -FriendlyName $FriendlyName -VirtualDiskFriendlyName $VirtualDiskFriendlyName -StoragePoolFriendlyName $StoragePoolFriendlyName -SSDStorageTierSize $SSDStorageTierSize -HDDStorageTierSize $HDDStorageTierSize
        if ($Ensure -eq "Present")
        {
            if( $resourceProperties['Ensure'] -eq "Absent")
            {
                if($Apply) 
                {
                    $virtualDisk = Get-StoragePool -FriendlyName $StoragePoolFriendlyName -ErrorAction Stop | Get-VirtualDisk | Where-Object {$_.FriendlyName -eq $VirtualDiskFriendlyName} -ErrorAction stop
                    if ($virtualDisk -eq $null)
                    {
                        $virtualDisk = New-xVirtualDisk -VirtualDiskFriendlyName $VirtualDiskFriendlyName -StoragePoolFriendlyName $StoragePoolFriendlyName -SSDStorageTierSize $SSDStorageTierSize -HDDStorageTierSize $HDDStorageTierSize -ResiliencySettingName $ResiliencySettingName -NumberOfDataCopies $NumberOfDataCopies -NumberOfColumns $NumberOfColumns
                    }
                    else
                    {
                        Write-Verbose -Message "$functionName Virtual disk with friendly name $VirtualDiskFriendlyName already exist. Going to initialize it and create a volume."
                    }

                    if(!($virtualDisk))
                    {
                        throw New-TerminatingError -ErrorType FailedToCreateVirtualDisk -FormatArgs @($VirtualDiskFriendlyName,$StoragePoolFriendlyName)
                    }
                    else
                    {
                        Initialize-xVirtualDisk -VDUniqueId $virtualDisk.UniqueId -VDName $VirtualDiskFriendlyName
                    }
                }
                else
                {
                    Write-Verbose -Message "$functionName Volume with friendly name $FriendlyName does not exists."
                    return $false
                }
            }
            else
            {
                $areSSDsPresent = (Get-DisksByMediaType -DiskMediaType "SSD" -StoragePoolFriendlyName $StoragePoolFriendlyName).Count -gt 0
                $areHDDsPresent = (Get-DisksByMediaType -DiskMediaType "HDD" -StoragePoolFriendlyName $StoragePoolFriendlyName).Count -gt 0

                if ($areSSDsPresent -and $areHDDsPresent)
                {
                    if (($SSDStorageTierSize -ne 0) -and ($HDDStorageTierSize -ne 0))
                    { 
                        if ($resourceProperties['SSDStorageTierSize'] -ne $SSDStorageTierSize)
                        {
                            throw New-TerminatingError -ErrorType UnableToSetPoolPropertyError -FormatArgs @($VirtualDiskFriendlyName,$StoragePoolFriendlyName,'SSDStorageTierSize',$resourceProperties['SSDStorageTierSize'],$SSDStorageTierSize)
                        }

                        if ($resourceProperties['HDDStorageTierSize'] -ne $HDDStorageTierSize)
                        {
                            throw New-TerminatingError -ErrorType UnableToSetPoolPropertyError -FormatArgs @($VirtualDiskFriendlyName,$StoragePoolFriendlyName,'HDDStorageTierSize',$resourceProperties['HDDStorageTierSize'],$HDDStorageTierSize)     
                        }
                    }
                }

                $Size = $SSDStorageTierSize + $HDDStorageTierSize
                if ($Size -ne $resourceProperties['Size'])
                {
                    throw New-TerminatingError -ErrorType UnableToSetPoolPropertyError -FormatArgs @($VirtualDiskFriendlyName,$StoragePoolFriendlyName,'Size',$resourceProperties['Size'],$Size)
                }

                if ($resourceProperties['ResiliencySettingName'] -ne $ResiliencySettingName)
                {
                    throw New-TerminatingError -ErrorType UnableToSetPoolPropertyError -FormatArgs @($VirtualDiskFriendlyName,$StoragePoolFriendlyName,'ResiliencySettingName',$resourceProperties['ResiliencySettingName'],$ResiliencySettingName)
                }

                if ($resourceProperties['NumberOfDataCopies'] -ne $NumberOfDataCopies)
                {
                    throw New-TerminatingError -ErrorType UnableToSetPoolPropertyError -FormatArgs @($VirtualDiskFriendlyName,$StoragePoolFriendlyName,'NumberOfDataCopies',$resourceProperties['NumberOfDataCopies'],$NumberOfDataCopies)
                }

                if ($resourceProperties['NumberOfColumns'] -ne $NumberOfColumns)
                {
                    throw New-TerminatingError -ErrorType UnableToSetPoolPropertyError -FormatArgs @($VirtualDiskFriendlyName,$StoragePoolFriendlyName,'NumberOfColumns',$resourceProperties['NumberOfColumns'],$NumberOfColumns)
                }
                
                # Found all the properties were matching. We are all good. Returning true
                return $true
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
    }
    catch
    {
        Write-Verbose -Message "$functionName has failed! Message: $_ ."
        throw $_
    }
}

Export-ModuleMember -Function *-TargetResource

