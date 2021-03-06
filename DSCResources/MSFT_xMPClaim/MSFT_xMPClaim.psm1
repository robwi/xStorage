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
		$Name
	)

    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    Assert-Module -ModuleName Storage

    $queryValue = mpclaim.exe -s -d
    if( $queryValue -contains "No MPIO disks are present.")
    {
        $Ensure = "Absent"
        Write-Verbose -Message "$functionName No MPIO disks are present on $Name."
    }
    else
    {
        $Ensure = "Present"
        $totalDisks = Get-PhysicalDisk | Where-Object {(($_.MediaType -eq "HDD") -or ($_.MediaType -eq "SSD")) -and ($_.BusType -eq "SAS")}

        Write-Verbose -Message "$functionName MPIO is already enabled. Checking loadbalancing policy on $($totalDisks.Count) disks on $Name."

        # Note: If more load balancing policies are implemented this check needs to change
        $queryValue = $queryValue | ? {$_.contains('LB')} 
        if ($queryValue.Count -eq ($totalDisks.Count+1))
        {
            $LoadBalancingPolicy = "LeastBlocks"
            Write-Verbose -Message "$functionName Found load balancing policy $LoadBalancingPolicy on $Name."
        }
        else
        {
            $LoadBalancingPolicy = $null 
        }
    }

	$returnValue = @{
		Name = $Name
        Ensure = $Ensure
        LoadBalancingPolicy = $LoadBalancingPolicy
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
		$Name,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

        [ValidateSet("ClearPolicy", "LeastBlocks")]
		[System.String]
		$LoadBalancingPolicy,

		[System.String]
		$DeviceHardwareId,

		[System.Boolean]
		$SuppressReboot
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

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

        [ValidateSet("ClearPolicy", "LeastBlocks")]
		[System.String]
		$LoadBalancingPolicy,

		[System.String]
		$DeviceHardwareId,

        [System.Boolean]
		$SuppressReboot
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
		$Name,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

        [ValidateSet("ClearPolicy", "LeastBlocks")]
		[System.String]
		$LoadBalancingPolicy,

		[System.String]
		$DeviceHardwareId,

        [System.Boolean]
		$SuppressReboot,

        [Switch]$Apply
	) 
    
    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    try
    {
        $resourceProperties = Get-TargetResource -Name $Name

        if ($Ensure -eq "Present")
        {
            if( $resourceProperties['Ensure'] -eq "Absent")
            {
                if($Apply) 
                {
                    Write-Verbose -Message "$functionName Enabling MPIO on $Name."
                    mpclaim.exe -n -i -d $DeviceHardwareId

                    if ( !([String]::IsNullOrEmpty($LoadBalancingPolicy)) )
                    {
                        $policyNumber = Convert-MPClaimLoadBalancingPolicy -PolicyName $LoadBalancingPolicy
                        Write-Verbose -Message "$functionName Enabling load balancing policy number $policyNumber ($LoadBalancingPolicy) on $Name."
                        mpclaim.exe -l -m $policyNumber
                    }
                }
                else
                {
                    return $false
                }
            }
            else
            {
                Write-Verbose -Message "$functionName MPIO already enabled on $Name. Checking other properties."

                if ( !([String]::IsNullOrEmpty($LoadBalancingPolicy)) )
                {
                    if ($resourceProperties['LoadBalancingPolicy'] -ne $LoadBalancingPolicy)
                    {
                        if ($Apply)
                        {
                            $policyNumber = Convert-MPClaimLoadBalancingPolicy -PolicyName $LoadBalancingPolicy
                            Write-Verbose -Message "$functionName Enabling load balancing policy number $policyNumber ($LoadBalancingPolicy) on $Name."
                            mpclaim.exe -l -m $policyNumber
                        }
                        else
                        {
                            return $false
                        }
                    }
                    else
                    {
                        Write-Verbose -Message "$functionName Load balancing policy Expected: $LoadBalancingPolicy, Found: $($resourceProperties['LoadBalancingPolicy']) on $Name."
                    }
                }

                if (!$Apply)
                {
                    return $true
                }
            }

            if ($Apply)
            {
                if(!($SuppressReboot))
                {
                    $global:DSCMachineStatus = 1
                    Write-Verbose "$functionName Setting machine to reboot on $Name"
                }
                else
                {
                    Write-Verbose "$functionName Suppressing reboot while setting MPIO on $Name"
                }
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

