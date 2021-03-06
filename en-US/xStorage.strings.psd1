ConvertFrom-StringData @'
###PSLOC 
# Common
NoKeyFound = No Localization key found for ErrorType: {0}
AbsentNotImplemented = Ensure = Absent is not implemented!
ModuleNotFound = Module '{0}' not found in list of available modules.
TestFailedAfterSet = Test-TargetResource returned false after calling set.
RemoteConnectionFailed = Remote PowerShell connection to Server '{0}' failed.
TODO = ToDo. Work not implemented at this time. 
UnexpectedEnsureValue = Unexpected value for the variable Ensure was specified.

# Storage
PoolClusteredError = Pool found to be clustered when shouldn't be. Couldn't clear persistent reservation for disks in pool {0}, since it's still marked as clustered.
MultipleVirtualDiskWithSameFriendlyName = Found multiple {0} virtual disk with friendly name {1} in pool {2}. If you are creating the virtual disk then change the friendly name.
UnableToSetPoolPropertyError = Found virtual disk with friendly name {0} in pool {1} with property {2}: {3} (Expected: {4}). This property is not settable on a virtual disk. If you are creating a virtual disk then create a different one by changing the friendly name.
UnableToQueryClusterDisk = Virtual disk name: {0}, Unable to query the name of the Cluster Disk!
UnableToAddTheVirtualDiskToCSV = Virtual disk name: {0}, ClusterDiskName: {1}, Unable to add the disk to CSV {2}!
ScaleOutFileServerRoleAddedButNotOnline = Scale-out file server role {0} was unsuccessfully added. It's state is {1} on cluster {2}.
ScaleOutFileServerRoleNotOnline = Scale-out file server role {0} is present but it's state is {1} on cluster {2}.
FailedToCreateStoragePool = Failed to create the storage pool {0}!

# Helper
ModuleNotInstalled = Please ensure that the PowerShell module '{0}' is installed!
InitializeVDErrorUnableToMoveClusterGroup = Unable to move the Available Storage Group to current node '{0}'!
NewVDErrorUnableToGetDisk = VDName: '{0}', UniqueId: '{1}', Unable to retrieve the disk object!
NewVDErrorUnableToGetClusterResource = VDName: '{0}', Unable to retrieve the disk Cluster Resource!
NewVDErrorUnableToSetMaintenanceMode = VDName: '{0}', Unable to put the cluster disk in maintenance mode!
NewVDErrorUnableToFormatVolume = VDName: {0}, Unable to format the volume!
NewVDErrorUnableToResumeClusterResource = VDName: {0}, Unable to put the cluster disk out of maintenance mode!
FailedToCreateSSDTierForPool = Failed to create the SSD Tier on Pool '{0}'!
FailedToCreateHDDTierForPool = Failed to create the HDD Tier on Pool '{0}'!
InputTierSizesAreZero = Both input tier sizes are zero. Failed to create a new tiered virtual disk with name '{0}' in pool '{1}'!
FailedToCreateVirtualDisk = Failed to create a new Virtual Disk with name '{0}' in pool '{1}'!
NotAllDisksConnectedToEachStorageNode = Not all disks are connected to node '{0}'.
ClusterSharedVolumeNotFound = Couldn't find a cluster shared volume matching name '{0}'.
PhysicalDisksLessThenMinimumRequired = Found {0} but was expecting at-least '{1}' '{2}' disks.
'@

