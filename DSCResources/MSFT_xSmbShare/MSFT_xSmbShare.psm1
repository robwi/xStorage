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
        $Name,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Path,

        [ValidateSet("Folder","CSV")]
        [System.String]
        $PathType = "Folder",
  
        [System.String]
        $StorageNodeName,

        [System.String[]]
        $ChangeAccess,

        [System.String[]]
        $FullAccess,

        [System.String[]]
        $NoAccess,

        [System.String[]]
        $ReadAccess
    )

    if([string]::IsNullOrEmpty($StorageNodeName))
    {
        $StorageNodeName = "localhost"
    }

    $fileServerSession = New-PSSessionWithRetry -ComputerName $StorageNodeName
    $smbShare = Invoke-Command -Session $fileServerSession -ScriptBlock { Get-SmbShare -Name $using:Name -ErrorAction SilentlyContinue }

    $changeAccessValue = @()
    $readAccessValue = @()
    $fullAccessValue = @()
    $noAccessValue = @()
    if ($smbShare -ne $null)
    {
        # Full:0, Change:1, Read: 2 
        # Deny: 1, Allow: 0

        $smbShareAccess = Invoke-Command -Session $fileServerSession -ScriptBlock { Get-SmbShareAccess -Name $using:Name} -Verbose
        foreach ($access in $smbShareAccess)
        {
            $accessRight = Convert-AccessRight($access.AccessRight)
            $accessControlType = Convert-AccessControlType($access.AccessControlType)
            if (($accessRight -eq "Change") -and ($accessControlType -eq "Allow"))
            {
                if (($ChangeAccess -ne $null) -and ($ChangeAccess -contains $access.AccountName))
                {
                    $changeAccessValue += $access.AccountName
                }
            }
            elseif (($accessRight -eq "Read") -and ($accessControlType -eq "Allow"))
            {
                if (($ReadAccess -ne $null) -and ($ReadAccess -contains $access.AccountName))
                {
                    $readAccessValue += $access.AccountName
                }
            }            
            elseif (($accessRight -eq "Full") -and ($accessControlType -eq "Allow"))
            {
                if (($FullAccess -ne $null) -and ($FullAccess -contains $access.AccountName))
                {
                    $fullAccessValue += $access.AccountName
                }
            }
            elseif (($accessRight-eq "Full") -and ($accessControlType-eq "Deny"))
            {
                if (($NoAccess -ne $null) -and ($NoAccess -contains $access.AccountName))
                {
                    $noAccessValue += $access.AccountName
                }
            }
        }    
    }
    else
    {
        Write-Verbose "Share with name $Name does not exist"
    } 

    Remove-PSSession -Session $fileServerSession

    $returnValue = @{
        Name = $smbShare.Name
        Path = $smbShare.Path
        PathType = $PathType
        StorageNodeName = $StorageNodeName
        Description = $smbShare.Description
        ConcurrentUserLimit = $smbShare.ConcurrentUserLimit
        EncryptData = $smbShare.EncryptData
        FolderEnumerationMode = $smbShare.FolderEnumerationMode                
        ShareState = $smbShare.ShareState
        ShareType = $smbShare.ShareType
        ShadowCopy = $smbShare.ShadowCopy
        Special = $smbShare.Special
        ChangeAccess = $changeAccessValue
        ReadAccess = $readAccessValue
        FullAccess = $fullAccessValue
        NoAccess = $noAccessValue     
        Ensure = if($smbShare) {"Present"} else {"Absent"}
    }

    $returnValue
}

function Set-AccessPermission
{
    [CmdletBinding()]
    Param
    (           
        $ShareName,

        [string[]]
        $UserName,

        [string]
        [ValidateSet("Change","Full","Read","No")]
        $AccessPermission,

        [System.Management.Automation.Runspaces.PSSession]
        $ServerSession
    )
    $formattedString = '{0}{1}' -f $AccessPermission,"Access"
    Write-Verbose -Message "Setting $formattedString for $UserName"

    if ($AccessPermission -eq "Change" -or $AccessPermission -eq "Read" -or $AccessPermission -eq "Full")
    {
        Invoke-Command -Session $ServerSession -ScriptBlock { Grant-SmbShareAccess -Name $using:Name -AccountName $using:UserName -AccessRight $using:AccessPermission -Force } -Verbose
    }
    else
    {
        Invoke-Command -Session $ServerSession -ScriptBlock { Block-SmbShareAccess -Name $using:Name -AccountName $using:UserName -Force } -Verbose
    }
}

function Remove-AccessPermission
{
    [CmdletBinding()]
    Param
    (           
        $ShareName,

        [string[]]
        $UserName,

        [string]
        [ValidateSet("Change","Full","Read","No")]
        $AccessPermission,

        [System.Management.Automation.Runspaces.PSSession]
        $ServerSession
    )
    $formattedString = '{0}{1}' -f $AccessPermission,"Access"
    Write-Debug -Message "Removing $formattedString for $UserName"

    if ($AccessPermission -eq "Change" -or $AccessPermission -eq "Read" -or $AccessPermission -eq "Full")
    {
        Invoke-Command -Session $ServerSession -ScriptBlock { Revoke-SmbShareAccess -Name $using:Name -AccountName $using:UserName -Force } -Verbose
    }
    else
    {
        Invoke-Command -Session $ServerSession -ScriptBlock { UnBlock-SmbShareAccess -Name $using:Name -AccountName $using:UserName -Force } -Verbose
    }
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
        $Path,

        [ValidateSet("Folder","CSV")]
        [System.String]
        $PathType = "Folder",

        [System.String]
        $StorageNodeName,

        [System.String]
        $Description,

        [System.String[]]
        $ChangeAccess,

        [System.UInt32]
        $ConcurrentUserLimit,

        [System.Boolean]
        $EncryptData,

        [ValidateSet("AccessBased","Unrestricted")]
        [System.String]
        $FolderEnumerationMode,

        [System.String[]]
        $FullAccess,

        [System.String[]]
        $NoAccess,

        [System.String[]]
        $ReadAccess,

        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure
    )

    if([string]::IsNullOrEmpty($StorageNodeName))
    {
        $StorageNodeName = "localhost"
    }

    $fileServerSession = New-PSSessionWithRetry -ComputerName $StorageNodeName

    $psboundparameters.Remove("Debug")
    $psboundparameters.Remove("PathType")
    $psboundparameters.Remove("StorageNodeName")

    $shareExists = $false
    $smbShare = Invoke-Command -Session $fileServerSession -ScriptBlock { Get-SmbShare -Name $using:Name -ErrorAction SilentlyContinue } -Verbose
    if($smbShare -ne $null)
    {
        Write-Verbose -Message "Share with name $Name exists"
        $shareExists = $true
    }

    if ($Ensure -eq "Present")
    {
        if ($shareExists -eq $false)
        {
            $psboundparameters.Remove("Ensure")
            

            $sPath = Get-FolderPathForPathType -Path $Path -PathType $PathType -ServerSession $fileServerSession -Verbose
            $psboundparameters["Path"] = $sPath + "\" + $Name

            Write-Verbose "Creating share $Name to ensure it is Present with path $($psboundparameters["Path"])"
            
            Invoke-Command -Session $fileServerSession -ScriptBlock { New-Item -Path $using:psboundparameters["Path"] -Type Directory; New-SmbShare @using:psboundparameters } -Verbose
        }
        else
        {
            # Need to call either Set-SmbShare or *ShareAccess cmdlets
            if ($psboundparameters.ContainsKey("ChangeAccess"))
            {
                $changeAccessValue = $psboundparameters["ChangeAccess"]
                $psboundparameters.Remove("ChangeAccess")
            }
            if ($psboundparameters.ContainsKey("ReadAccess"))
            {
                $readAccessValue = $psboundparameters["ReadAccess"]
                $psboundparameters.Remove("ReadAccess")
            }
            if ($psboundparameters.ContainsKey("FullAccess"))
            {
                $fullAccessValue = $psboundparameters["FullAccess"]
                $psboundparameters.Remove("FullAccess")
            }
            if ($psboundparameters.ContainsKey("NoAccess"))
            {
                $noAccessValue = $psboundparameters["NoAccess"]
                $psboundparameters.Remove("NoAccess")
            }
            
            # Use Set-SmbShare for performing operations other than changing access
            $psboundparameters.Remove("Ensure")
            $psboundparameters.Remove("Path")
            Invoke-Command -Session $fileServerSession -ScriptBlock { Set-SmbShare @using:psboundparameters -Force } -Verbose

            # Use *SmbShareAccess cmdlets to change access
            if ($ChangeAccess -ne $null)
            {         
                # We add the current account to the existing permissions                         
                $changeAccessValue | % { Set-AccessPermission -ShareName $Name -AccessPermission "Change" -Username $_ -ServerSession $fileServerSession}
            }

            if ($ReadAccess -ne $null)
            {
                # We add the current account to the existing permissions
                $readAccessValue | % { Set-AccessPermission -ShareName $Name -AccessPermission "Read" -Username $_ -ServerSession $fileServerSession}
            }

            if ($FullAccess -ne $null)
            {
                # We add the current account to the existing permissions
                $fullAccessValue | % { Set-AccessPermission -ShareName $Name -AccessPermission "Full" -Username $_ -ServerSession $fileServerSession}
            }

            if ($NoAccess -ne $null)
            {
                # We add the current account to the existing permissions
                $noAccessValue | % { Set-AccessPermission -ShareName $Name -AccessPermission "No" -Username $_ -ServerSession $fileServerSession}
            }
        }
    }
    elseif( $Ensure -eq "Absent")
    {
        Write-Verbose "Removing share $Name to ensure it is Absent" 
        Invoke-Command -Session $fileServerSession -ScriptBlock { Remove-SmbShare -Name $using:Name -Force } -Verbose
    
    }

    Remove-PSSession -Session $fileServerSession
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
        $Path,

        [ValidateSet("Folder","CSV")]
        [System.String]
        $PathType = "Folder",

        [System.String]
        $StorageNodeName,

        [System.String]
        $Description,

        [System.String[]]
        $ChangeAccess,

        [System.UInt32]
        $ConcurrentUserLimit,

        [System.Boolean]
        $EncryptData,

        [ValidateSet("AccessBased","Unrestricted")]
        [System.String]
        $FolderEnumerationMode,

        [System.String[]]
        $FullAccess,

        [System.String[]]
        $NoAccess,

        [System.String[]]
        $ReadAccess,

        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure
    )

    if([string]::IsNullOrEmpty($StorageNodeName))
    {
        $StorageNodeName = "localhost"
    }

    $testResult = $false;
    $share = Get-TargetResource -Name $Name -Path $Path -PathType $PathType -StorageNodeName $StorageNodeName -ChangeAccess $ChangeAccess -FullAccess $FullAccess -NoAccess $NoAccess -ReadAccess $ReadAccess -ErrorAction SilentlyContinue -ErrorVariable ev

    # Getting the acutal Share local path from the path type.
    $fileServerSession = New-PSSessionWithRetry -ComputerName $StorageNodeName
    $sPath = Get-FolderPathForPathType -Path $Path -PathType $PathType -ServerSession $fileServerSession -Verbose
    $PSBoundParameters['Path'] = $sPath + "\" + $Name

    if ($Ensure -eq "Present")
    {
        if ($share.Ensure -eq "Absent")
        {
            $testResult = $false
        }
        elseif ($share.Ensure -eq "Present")
        {
            Write-Verbose "Share with name $Name is present"
            $Params = 'Name', 'Path', 'StorageNodeName', 'Description', 'ChangeAccess', 'ConcurrentUserLimit', 'EncryptData', 'FolderEnumerationMode', 'FullAccess', 'NoAccess', 'ReadAccess', 'Ensure'
            
            $testresult = $true
            foreach($Param in $Params)
            {
                if($PSBoundParameters.ContainsKey($Param))
                {
                    if((Compare-Object -ReferenceObject $PSBoundParameters[$Param] -DifferenceObject $Share.$Param) -ne $null)
                    {
                        Write-Verbose "Property $Param is $($PSBoundParameters[$Param]) and should be $($Share.$Param)"
                        $testresult = $false
                    }
                }
            }
        }
    }
    else
    {
        if ($share.Ensure -eq "Absent")
        {
            $testResult = $true
        }
        else
        {
            $testResult = $false
        }
    }

    Remove-PSSession -Session $fileServerSession

    $testResult
}

Export-ModuleMember -Function *-TargetResource

