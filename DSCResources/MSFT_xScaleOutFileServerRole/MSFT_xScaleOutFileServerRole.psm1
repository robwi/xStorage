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
		$Name,

		[parameter(Mandatory = $true)]
		[System.String]
		$ClusterName
	)

    $role = Get-ClusterGroup -Cluster $ClusterName -ErrorAction Stop | Where-Object {($_.GroupType -eq 'ScaleoutFileServer') -and ($_.Name -eq $Name)}

    if ($role)
    {
        $Ensure = "Present" 
        Write-Verbose -Message "$functionName We found scale-out file server role $Name in state $($role.State) on cluster $ClusterName." 
    } 
    else
    {
        $Ensure = "Absent"
        Write-Verbose -Message "$functionName We did not found scale-out file server role $Name on cluster $ClusterName."  
    }

	$returnValue = @{
		Name = $Name
		ClusterName = $ClusterName
        Ensure = $Ensure
        State = $role.State
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
		$Name,

		[parameter(Mandatory = $true)]
		[System.String]
		$ClusterName,

        [ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

		[System.Boolean]
        $RemoveResources = $false
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
		$Name,

		[parameter(Mandatory = $true)]
		[System.String]
		$ClusterName,

        [ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

		[System.Boolean]
        $RemoveResources = $false
	)

    $isDesiredState = ValidateOrApply-Resource @PSBoundParameters

    return $isDesiredState
}

function ValidateOrApply-Resource 
{ 
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

		[parameter(Mandatory = $true)]
		[System.String]
		$ClusterName,

        [ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

        [System.Boolean]
        $RemoveResources = $false,

        [Switch]$Apply
	) 
    
    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    try
    {
        $resourceProperties = Get-TargetResource -Name $Name -ClusterName $ClusterName

        if ($Ensure -eq "Present")
        {
            if( $resourceProperties['Ensure'] -eq "Absent")
            {
                if($Apply) 
                {
                    Write-Verbose -Message "$functionName Adding scale-out file server role $Name and cluster $ClusterName."
                    $role = Add-ClusterScaleOutFileServerRole -Name $Name -Cluster $ClusterName -ErrorAction Stop

                    if($role.State -ne "Online")
                    {
                       throw New-TerminatingError -ErrorType ScaleOutFileServerRoleAddedButNotOnline -FormatArgs @($Name,$role.State,$ClusterName)
                    }
                }
                else
                {
                    return $false
                }
            }
            else
            {
                Write-Verbose -Message "$functionName Scale-out file server role $Name on cluster $ClusterName already exists."

                # If the resource is present but not Online we need to make sure it's Online for it to be usable.
                if ($resourceProperties['State'] -ne "Online")
                {
                    if ($Apply)
                    {
                        Write-Verbose -Message "$functionName Scale-out file server role $Name is present on the cluster $ClusterName but is in $($resourceProperties['State']) state. Trying to bring it Online"

                        Start-ClusterGroup -Name $Name -Cluster $ClusterName -ErrorAction Stop

                        $role = Get-ClusterGroup -Name $Name -Cluster $ClusterName -ErrorAction Stop | Where-Object {$_.GroupType -eq 'ScaleoutFileServer'}

                        if($role.State -ne "Online")
                        {
                           throw New-TerminatingError -ErrorType ScaleOutFileServerRoleNotOnline -FormatArgs @($Name,$role.State,$ClusterName)
                        }
                    }
                    else
                    {
                        return $false
                    }
                }
                else
                {           
                    if (!$Apply)
                    {
                        return $true
                    } 
                }
            }
        }
        elseif( $Ensure -eq "Absent")
        {
            if( $resourceProperties['Ensure'] -eq "Present")
            {
                if($Apply) 
                {
                    Write-Verbose -Message "$functionName Removing scale-out file server role $Name and cluster $ClusterName."
                    $role = Get-ClusterGroup -Name $Name -Cluster $ClusterName -ErrorAction Stop | Where-Object {$_.GroupType -eq 'ScaleoutFileServer'}
                    Remove-ClusterGroup -InputObject $role -RemoveResources:$RemoveResources -ErrorAction Stop
                }
                else
                {
                    return $false
                }
            }
            else
            {
                Write-Verbose -Message "$functionName Scale-out file server role $Name and cluster $ClusterName already absent."
                if (!$Apply)
                {
                    return $true
                }
            }
        }
        else
        { 
            throw New-TerminatingError -ErrorType UnexpectedEnsureValue -ErrorCategory NotImplemented
        }
    }
    catch
    {
        # SOFS is already in use in the Active Directory.
        if ($_.ErrorDetails.Message.Contains("0xc0000022"))
        {
            $additionalMsg = "One of the common reasons for this error is that the cluster $ClusterName might not have Full access over the computer account $Name in Active Directory."
        }
        Write-Verbose -Message "$functionName has failed! Message: $_ . $additionalMsg"
        throw $_
    }
}


Export-ModuleMember -Function *-TargetResource


