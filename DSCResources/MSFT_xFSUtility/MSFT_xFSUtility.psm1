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

		[System.Boolean]
		$BehaviorDisableDeleteNotify
	)

    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    Assert-Module -ModuleName Storage
 
    # BehaviorDisableDeleteNotify
    $queryValue = fsutil behavior query disabledeletenotify
    if ($queryValue -eq "DisableDeleteNotify = 1")
    {
        Write-Verbose -Message "$functionName Found DisableDeleteNotify = 1"
        $BehaviorDisableDeleteNotify = $true
    }
    elseif($queryValue -eq "DisableDeleteNotify = 0")
    {
        Write-Verbose -Message "$functionName Found DisableDeleteNotify = 0"   
        $BehaviorDisableDeleteNotify = $false
    }

	$returnValue = @{
		Name = $Name
        BehaviorDisableDeleteNotify = $BehaviorDisableDeleteNotify
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

		[System.Boolean]
		$BehaviorDisableDeleteNotify
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

		[System.Boolean]
		$BehaviorDisableDeleteNotify
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

		[System.Boolean]
		$BehaviorDisableDeleteNotify,

        [Switch]$Apply
	) 
    
    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    try
    {
        $resourceProperties = Get-TargetResource -Name $Name -BehaviorDisableDeleteNotify $BehaviorDisableDeleteNotify
        if ($PSBoundParameters.ContainsKey("BehaviorDisableDeleteNotify"))
        {
            if( $resourceProperties['BehaviorDisableDeleteNotify'] -ne $BehaviorDisableDeleteNotify)
            {
                if ($Apply)
                {
                    if($BehaviorDisableDeleteNotify)
                    {
                        Write-Verbose -Message "$functionName Setting fsutil behavior set disabledeletenotify 1"
                        fsutil behavior set disabledeletenotify 1
                    }
                    else
                    {
                        Write-Verbose -Message "$functionName Setting fsutil behavior set disabledeletenotify 0"
                        fsutil behavior set disabledeletenotify 0
                    }
                }
                else
                {
                    return $false
                }
            }
            else
            {
                Write-Verbose -Message "$functionName Desired value is already set for BehaviorDisableDeleteNotify to $BehaviorDisableDeleteNotify"
            }
        }
        else
        {
            Write-Verbose -Message "$functionName No value specified for BehaviorDisableDeleteNotify in the input of the resource."
        }

        if (!($Apply))
        {
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

