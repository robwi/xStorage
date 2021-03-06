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
		$VolumeFriendlyName
	)

    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    Assert-Module -ModuleName Storage
    Assert-Module -ModuleName FailoverClusters
 
    $csvVolume = Get-ClusterSharedVolume | ? {$_.Name -match $FriendlyName}
    if ($csvVolume -eq $null)
    {
        $Ensure = "Absent"
        Write-Verbose -Message "$functionName CSV with friendly name containing $FriendlyName does not exists."
    }
    else
    {
        $csvMountPath = $csvVolume.SharedVolumeInfo.FriendlyVolumeName
        $Ensure = "Present"
        Write-Verbose -Message "$functionName CSV with friendly name containing $FriendlyName exists."
    }

	$returnValue = @{
		FriendlyName = $FriendlyName
        VolumeFriendlyName = $VolumeFriendlyName
        Ensure = $Ensure
        MountPath = $csvMountPath
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
		$VolumeFriendlyName,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present"
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
		$VolumeFriendlyName,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present"
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
		$VolumeFriendlyName,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

        [Switch]$Apply
	) 
    
    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    try
    {
        $resourceProperties = Get-TargetResource -FriendlyName $FriendlyName -VolumeFriendlyName $VolumeFriendlyName
        if ($Ensure -eq "Present")
        {
            if( $resourceProperties['Ensure'] -eq "Absent")
            {
                if($Apply) 
                {
                    # Retrieve the name of the Cluster Disk that corresponds to the Virtual Disk
                    # This is the name we use to add it to CSV
                    $ClusterDiskName = (Get-ClusterResource | Where-Object {($_.ResourceType -match "Physical Disk")} | Get-ClusterParameter VirtualDiskName | Where-Object {$_.Value -match $VolumeFriendlyName}).ClusterObject.Name
                    if (!($ClusterDiskName))
                    {
                        throw New-TerminatingError -ErrorType UnableToQueryClusterDisk -FormatArgs @($VolumeFriendlyName)
                    }

                    Write-Verbose -Message "$functionName Virtual disk name: $VolumeFriendlyName, Add the disk to CSV."
                    $csVolume = Add-ClusterSharedVolume -Name $ClusterDiskName
                    if (!($csVolume))
                    {
                        throw New-TerminatingError -ErrorType UnableToAddTheVirtualDiskToCSV -FormatArgs @($VolumeFriendlyName, $ClusterDiskName, $ClusterDiskName)
                    }
                }
                else
                {
                    Write-Verbose -Message "$functionName Cluster shared volume with friendly name $FriendlyName does not exists."
                    return $false
                }
            }
            else
            {
                Write-Verbose -Message "$functionName Volume with friendly name $FriendlyName already exists."
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

