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
		$VendorId,

		[parameter(Mandatory = $true)]
		[System.String]
		$ProductId
	)

    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    Assert-Module -ModuleName Storage

    $hardwareIdOnSystemList = Get-MSDSMSupportedHW -ErrorAction Stop

    $Ensure = "Absent"
    foreach ($hardwareIdOnSystem in $hardwareIdOnSystemList)
    {
        if (($hardwareIdOnSystem.ProductId -eq $ProductId) -and ($hardwareIdOnSystem.VendorId -eq $VendorId))
        {
            $Ensure = "Present"
            Write-Verbose -Message "$functionName Found VendorId: $VendorId, ProductId: $ProductId"
            break;
        }
    }

	$returnValue = @{
		VendorId = $VendorId
        ProductId = $ProductId
        Ensure = $Ensure
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
		$VendorId,

		[parameter(Mandatory = $true)]
		[System.String]
		$ProductId,

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
		$VendorId,

		[parameter(Mandatory = $true)]
		[System.String]
		$ProductId,

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
		$VendorId,

		[parameter(Mandatory = $true)]
		[System.String]
		$ProductId,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

        [Switch]$Apply
	) 
    
    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    try
    {
        $resourceProperties = Get-TargetResource -VendorId $VendorId -ProductId $ProductId

        if ($Ensure -eq "Present")
        {
            if ($resourceProperties['Ensure'] -eq "Absent")
            {
                if ($Apply)
                {
                    Write-Verbose -Message "$functionName Adding VendorId: $VendorId, ProductId: $ProductId"
                    New-MSDSMSupportedHW -VendorId $VendorId -ProductId $ProductId -ErrorAction Stop
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

