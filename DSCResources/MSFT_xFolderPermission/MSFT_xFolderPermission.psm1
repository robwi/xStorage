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
        [ValidateNotNullOrEmpty()]
		[System.String]
		$Path,

        [ValidateSet("Folder","CSV")]
		[System.String]
		$PathType = "Folder",

		[parameter(Mandatory = $true)]
		[ValidateSet("AppendData", "ChangePermissions", "CreateDirectories", "CreateFiles", "Delete",  
                    "DeleteSubdirectoriesAndFiles", "ExecuteFile", "FullControl", "ListDirectory",  
                    "Modify", "Read", "ReadAndExecute", "ReadAttributes", "ReadData", "ReadExtendedAttributes",  
                    "ReadPermissions", "Synchronize", "TakeOwnership", "Traverse", "Write", "WriteAttributes",  
                    "WriteData", "WriteExtendedAttributes")] 
		[System.String[]]
		$FileSystemRights,

		[parameter(Mandatory = $true)]
		[ValidateSet("Allow","Deny")]
		[System.String]
		$AccessControlType,

		[ValidateSet("ContainerInherit","ObjectInherit","None")]  
		[System.String[]]
		$InheritanceFlags = ("ContainerInherit","ObjectInherit"),

		[ValidateSet("InheritOnly","NoPropagateInherit","None")] 
		[System.String[]]
		$PropagationFlags = "None",
        
		[parameter(Mandatory = $true)]
		[System.String]
		$AccountName
	)

    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    $Path = Get-FolderPathForPathType -Path $Path -PathType $PathType -Verbose

    $acl = Get-Acl $Path
    $accessRules = $acl.Access

    $expectedAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($AccountName, $FileSystemRights, $InheritanceFlags, $PropagationFlags, $AccessControlType)

    $accountHasPermissions = $false
    foreach($rule in $accessRules)
    {   
        if( ($rule.IdentityReference -eq $expectedAccessRule.IdentityReference) -and 
            ($rule.FileSystemRights -eq $expectedAccessRule.FileSystemRights) -and
            ($rule.AccessControlType -eq $expectedAccessRule.AccessControlType) -and
            ($rule.InheritanceFlags -eq $expectedAccessRule.InheritanceFlags) -and
            ($rule.PropagationFlags -eq $expectedAccessRule.PropagationFlags))
        {
            $accountHasPermissions = $true
            $FoundFileSystemRights = $rule.FileSystemRights
            $FoundAccessControlType = $rule.AccessControlType
            $FoundInheritanceFlags = $rule.InheritanceFlags
            $FoundPropagationFlags = $rule.PropagationFlags
        }
    }

    if ($accountHasPermissions)
    {
        $Ensure = "Present"
    }
    else
    {
        $Ensure = "Absent"
    }

	$returnValue = @{
		Path = $Path
		PathType = $PathType
        Ensure = $Ensure
		FileSystemRights = $FoundFileSystemRights
		AccessControlType = $FoundAccessControlType
        InheritanceFlags = $FoundInheritanceFlags
        PropagationFlags = $FoundPropagationFlags
		AccountName = $AccountName
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
		$Path,

		[ValidateSet("Folder","CSV")]
		[System.String]
		$PathType = "Folder",

        [ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

		[parameter(Mandatory = $true)]
		[ValidateSet("AppendData", "ChangePermissions", "CreateDirectories", "CreateFiles", "Delete",  
                    "DeleteSubdirectoriesAndFiles", "ExecuteFile", "FullControl", "ListDirectory",  
                    "Modify", "Read", "ReadAndExecute", "ReadAttributes", "ReadData", "ReadExtendedAttributes",  
                    "ReadPermissions", "Synchronize", "TakeOwnership", "Traverse", "Write", "WriteAttributes",  
                    "WriteData", "WriteExtendedAttributes")] 
		[System.String[]]
		$FileSystemRights,

		[parameter(Mandatory = $true)]
		[ValidateSet("Allow","Deny")]
		[System.String]
		$AccessControlType,

		[ValidateSet("ContainerInherit","ObjectInherit","None")]  
		[System.String[]]
		$InheritanceFlags,

		[ValidateSet("InheritOnly","NoPropagateInherit","None")] 
		[System.String[]]
		$PropagationFlags = "None",

		[parameter(Mandatory = $true)]
		[System.String]
		$AccountName
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
		$Path,

		[ValidateSet("Folder","CSV")]
		[System.String]
		$PathType = "Folder",

        [ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

		[parameter(Mandatory = $true)]
		[ValidateSet("AppendData", "ChangePermissions", "CreateDirectories", "CreateFiles", "Delete",  
                    "DeleteSubdirectoriesAndFiles", "ExecuteFile", "FullControl", "ListDirectory",  
                    "Modify", "Read", "ReadAndExecute", "ReadAttributes", "ReadData", "ReadExtendedAttributes",  
                    "ReadPermissions", "Synchronize", "TakeOwnership", "Traverse", "Write", "WriteAttributes",  
                    "WriteData", "WriteExtendedAttributes")] 
		[System.String[]]
		$FileSystemRights,

		[parameter(Mandatory = $true)]
		[ValidateSet("Allow","Deny")]
		[System.String]
		$AccessControlType,

		[ValidateSet("ContainerInherit","ObjectInherit","None")]  
		[System.String[]]
		$InheritanceFlags,

		[ValidateSet("InheritOnly","NoPropagateInherit","None")] 
		[System.String[]]
		$PropagationFlags = "None",

		[parameter(Mandatory = $true)]
		[System.String]
		$AccountName
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
		$Path,

		[ValidateSet("Folder","CSV")]
		[System.String]
		$PathType = "Folder",

        [ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

		[parameter(Mandatory = $true)]
		[ValidateSet("AppendData", "ChangePermissions", "CreateDirectories", "CreateFiles", "Delete",  
                    "DeleteSubdirectoriesAndFiles", "ExecuteFile", "FullControl", "ListDirectory",  
                    "Modify", "Read", "ReadAndExecute", "ReadAttributes", "ReadData", "ReadExtendedAttributes",  
                    "ReadPermissions", "Synchronize", "TakeOwnership", "Traverse", "Write", "WriteAttributes",  
                    "WriteData", "WriteExtendedAttributes")] 
		[System.String[]]
		$FileSystemRights,

		[parameter(Mandatory = $true)]
		[ValidateSet("Allow","Deny")]
		[System.String]
		$AccessControlType,

		[ValidateSet("ContainerInherit","ObjectInherit","None")]  
		[System.String[]]
		$InheritanceFlags,

		[ValidateSet("InheritOnly","NoPropagateInherit","None")] 
		[System.String[]]
		$PropagationFlags = "None",

		[parameter(Mandatory = $true)]
		[System.String]
		$AccountName,

        [Switch]$Apply
	) 
    
    $functionName = $($MyInvocation.MyCommand.Name) + ":"

    try
    {
        $resourceProperties = Get-TargetResource -Path $Path -PathType $PathType -FileSystemRights $FileSystemRights -AccessControlType $AccessControlType -InheritanceFlags $InheritanceFlags -PropagationFlags $PropagationFlags -AccountName $AccountName 

        if ($Ensure -eq "Present")
        {
            if( $resourceProperties['Ensure'] -eq "Absent")
            {
                if($Apply) 
                {
                    Write-Verbose -Message "$functionName Adding access rule for path $Path and account name $AccountName."

                    $expectedAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($AccountName, $FileSystemRights, $InheritanceFlags, $PropagationFlags, $AccessControlType)

                    $acl = Get-Acl $resourceProperties['Path']
                    $acl.AddAccessRule($expectedAccessRule)
                    Set-Acl -Path $resourceProperties['Path'] -AclObject $acl -ErrorAction Stop
                }
                else
                {
                    return $false
                }
            }
            else
            {
                Write-Verbose -Message "$functionName Appropriate access rule already exists for path $Path and account name $AccountName." 
                if (!$Apply)
                {
                    return $true
                }
            }
        }
        elseif( $Ensure -eq "Absent")
        {
            if( $resourceProperties['Ensure'] -eq "Present")
            {
                if($Apply) 
                {
                    Write-Verbose -Message "$functionName Removing access rule for path $Path and account name $AccountName."

                    $expectedAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($AccountName, $FileSystemRights, $InheritanceFlags, $PropagationFlags, $AccessControlType)

                    $acl = Get-Acl $resourceProperties['Path']
                    $acl.RemoveAccessRule($expectedAccessRule)
                    Set-Acl -Path $resourceProperties['Path'] -AclObject $acl -ErrorAction Stop
                }
                else
                {
                    return $false
                }
            }
            else
            {
                Write-Verbose -Message "$functionName Appropriate access rule already exists for path $Path and account name $AccountName."
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
        Write-Verbose -Message "$functionName has failed! Message: $_ ."
        throw $_
    }
}

Export-ModuleMember -Function *-TargetResource

