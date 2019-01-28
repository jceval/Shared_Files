######################################################################################################################################################################################################
#Name: VM Creation from Snapshots for MANAGED disks
#Last Modified Date: 8 May 2018
#Disclaimer: 
##    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
##    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
##    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
##    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
##    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
##    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
##    SOFTWARE
#Purpose: This script captures a snapshot of the source virtual machine, exports it to the target storage account and creates a new vm, resets the password,sets the tags and attaches the data disks.
#Created By: jaceval@microsoft.com
#Keywords:
#SA=Storage Account
#RG= Resource Group
#Dest= Destination
#VM=Virtual Machine
#NSG= Network Security Group
#####################################################################################################################################################################################################

param(
 [Parameter(Mandatory=$True, HelpMessage = 'Enter source subscription ID')]
 [string]
 $sourceSubscriptionId,
   
 [Parameter(Mandatory=$True, HelpMessage = 'Enter source virtual machine name')]
 [string]
 $sourceVmName,

 [Parameter(Mandatory=$True, HelpMessage = 'Enter target subscription ID')]
 [string]
 $destSubscriptionId,

 [Parameter(Mandatory=$True, HelpMessage = 'Enter target resource group name')]
 [string]
 $destRGName,

 [Parameter(Mandatory=$True, HelpMessage = 'Enter target virtual network name')]
 [string]
 $destVirtualNetworkName,

 [Parameter(Mandatory=$True, HelpMessage = 'Enter new virtual machine name')]
 [string]
 $myNewVMName,

 [Parameter(Mandatory=$True, HelpMessage = 'Enter target storage account name')]
 [string]
 $destSAName,

 [Parameter(Mandatory=$True, HelpMessage = 'Enter target subnet name')]
 [string]
 $destSubnetName,
 
 [Parameter(Mandatory=$True, HelpMessage = 'Enter custom script URL')]
 [string]
 $customScriptURL,

 [Parameter(Mandatory=$True, HelpMessage = 'Enter virtual machine size for the new vm')]
 [string]
 $virtualMachineSize,

 [Parameter(Mandatory=$True, HelpMessage = 'Enter diagnostic storage account name for the new vm')]
 [string]
 $diagnosticSAName,
  
 [Parameter(Mandatory=$True, HelpMessage = 'Enter NSG name for the new vm')]
 [string]
 $nsgName,

 [Parameter(Mandatory=$True, HelpMessage = 'Enter username and password for the new VM')]
 [System.Management.Automation.CredentialAttribute()] 
 $Cred=(Get-Credential)
 )

Write-Host "Logging in..." -f Green
Connect-AzureRmAccount

$tags=@{}
$tags=@{ SBG=""; Environment=""; AppTier="";AppName="" }

Function GetTags()
{
     foreach($key in $($tags.keys))
     {
         $tagValue= Read-Host "Enter Tag value for $key"
         $tags[$key]=$tagValue
     }
 }
Write-Host "Enter Tags information for the new VM $myNewVMName" -f Green
GetTags
Write-Host "Entered Tag information is" -f Green
Write-Host ($tags|Out-String) -ForegroundColor Green

#Variables for Snapshot creation
$storageType = 'StandardLRS'
$sasExpiryDuration = "36000"

##Target VM Configuration
$nicName=$myNewVMName+'-nic01'
$osDiskName=$myNewVMName+'-OSDisk'
$destStorageContainerName = "vhds"

Write-Host "Selecting Source Subscription $sourceSubscriptionId" -f Green
Select-AzureRmSubscription -SubscriptionId $sourceSubscriptionId

##Source VM Varibales
$VMRG= (Find-AzureRmResource -ResourceNameEquals $sourceVmName -ResourceType 'Microsoft.Compute/virtualMachines').ResourceGroupName
$sourceVM=(Get-AzureRmVM -ResourceGroupName $VMRG -Name $sourceVmName)
$VMLocation=$sourceVM.Location

<#
##Source OS Disk
$osDiskURI = $SourceVM.StorageProfile.OsDisk.ManagedDisk.Id
$osDiskSnapshotName = $osDiskURI.Split('/')[8]+'.vhd'
##Take a snapshot and grant the access
try{  
        $osSnapshotConfig = New-AzureRmSnapshotConfig  -SourceUri $osDiskURI -Location $SourceVM.Location -CreateOption copy 
        $osSnapshot   = New-AzureRmSnapshot -Snapshot $osSnapshotConfig   -ResourceGroupName $VMRG -SnapshotName $osDiskSnapshotName
        if($osSnapshot.ProvisioningState -eq 'Succeeded')
            {
                 Write-Host "Successfully created snapshot of OS Disk $osDiskSnapshotName !" -f Green
                 $OSSAS=(Grant-AzureRmSnapshotAccess -ResourceGroupName $VMRG -SnapshotName $osDiskSnapshotName -Access Read -DurationInSecond $sasExpiryDuration).AccessSAS
                 if($OSSAS){Write-Host "Successfully granted access to the snapshot!" -f Green}
            }

}
catch{ Write-Host "Failed during OS Disk Snapshot : Exception message:$_" -f Red }


###Source DATA DISKs
$URIs = ""
$URIs   =($SourceVM.StorageProfile.DataDisks.ManagedDisk.Id)
if($URIs.Count -gt 0)
{
Write-Host "Source VM $sourceVmName has $($URIs.Count) data disks" -f Green
$DataSAS=@{}
$SAS=""
        foreach($uri in $URIs)
        {

                $SnapshotName = $uri.Split('/')[8]+'.vhd'
                try{
                        $SnapshotConfig =  New-AzureRmSnapshotConfig  -SourceUri $uri -Location $SourceVM.Location -CreateOption copy 
                        $Snap=New-AzureRmSnapshot -Snapshot $SnapshotConfig -ResourceGroupName $VMRG -SnapshotName $SnapshotName 
                        if ($Snap.ProvisioningState -eq "Succeeded")
                        {
                                Write-Host "Successfully created Snapshot of $SnapshotName in the Subscription $sourceSubscriptionId" -f Green
                                $SAS=(Grant-AzureRmSnapshotAccess -ResourceGroupName $VMRG -SnapshotName $SnapshotName -Access Read -DurationInSecond $sasExpiryDuration).AccessSAS
                                if($SAS){Write-Host "Successfully granted access to the snapshot $SnapshotName!" -f Green}
                        }
                        $DataSAS.Add($SnapshotName,$SAS)
                    }catch{Write-Host "Failed during data disk Snapshot Creation : Exception message:$_" -f Red}
        }
}else{Write-Host "$sourceVmName VM does not have any data disks"-f Green}

#>

#################################################################################################################################################################################

Write-Host "Selecting destination Subscription $destSubscriptionId" -f Green
Select-AzureRmSubscription -SubscriptionId $destSubscriptionId 
$destLocationName = (Get-AzureRmResourceGroup -Name $destRGName).Location
$destVirtualNetworkRG= (Find-AzureRmResource -ResourceNameEquals $destVirtualNetworkName -ResourceType 'Microsoft.Network/virtualNetworks').ResourceGroupName

try{
            ##Check if SA is existing, if not create the new it
            $destSA=(Find-AzureRmResource -ResourceNameEquals $destSAName -ResourceType 'Microsoft.Storage/storageAccounts' )
            if($destSA)
            {
                Write-Host "Storage Account $destSAName is existing in the target subscription"-f Green
                $destSARG=$destSA.ResourceGroupName
            }
            else 
            {
                $available=(Get-AzureRmStorageAccountNameAvailability -Name $destSAName)
                if($available.NameAvailable -eq 'True')
                {
                    Write-Host "Creating new Storage Account $destSAName"-f Green
                    $newSA=(New-AzureRmStorageAccount -ResourceGroupName $destRGName -Name $destSAName -Location $destLocationName -SkuName Standard_LRS -Kind StorageV2)
                    if($newSA.ProvisioningState -eq "Succeeded"){Write-Host "Successfully created new storage account" -f Green}
                    $destSARG=$destRGName
                 }
                else{Write-Host "Storage Account Name is not available. Please try again with unique name"-f Red -ErrorAction Stop}
            }
             $destSAKey=(Get-AzureRmStorageAccountKey -ResourceGroupName $destSARG -Name $destSAName).Value[0]
             $destinationContext = New-AzureStorageContext –StorageAccountName $destSAName -StorageAccountKey $destSAKey 
             ##Check if the destination container is existing, if not create it
             $newContainer=Get-AzureStorageContainer -Context $destinationContext |where{$_.Name -like "$destStorageContainerName"} -ErrorAction SilentlyContinue
            if($newContainer)
            {
                Write-Host "The Container $destStorageContainerName is already existing" -ForegroundColor Green

            }
            else
            {
                $newContainer=New-AzureStorageContainer -Name $destStorageContainerName -Context $destinationContext
                Write-Host "Successfully created new container $destStorageContainerName" -f Green
            }
}catch{Write-Host "$_" -f Red}


try{
    ## Copying OS blob
    $OSblobCopy =   Start-AzureStorageBlobCopy -AbsoluteUri $OSSAS -DestContainer $destStorageContainerName -DestContext $destinationContext -DestBlob $osDiskSnapshotName
    ##Printing OS blob Copy Status
    $OSTotalBytes = ($OSblobCopy | Get-AzureStorageBlobCopyState).TotalBytes
    while(($OSblobCopy | Get-AzureStorageBlobCopyState).Status -eq "Pending")
    {
        Start-Sleep 10
        $BytesCopied = ($OSblobCopy | Get-AzureStorageBlobCopyState).BytesCopied
        $PercentCopied = [math]::Round($BytesCopied/$OSTotalBytes * 100,2)
        Write-Progress -Activity "OS Disk Blob Copy in Progress" -Status "$PercentCopied% Complete:" -PercentComplete $PercentCopied -CurrentOperation "OS Disk $($osDiskSnapshotName) Copy"
    }
    $OScopyStatus= ($OSblobCopy | Get-AzureStorageBlobCopyState).Status
    if($OScopyStatus -eq "Success"){Write-Host "Successfully Copied OS disk VHD $($osDiskSnapshotName) to the Target Storage Account" -f Green} else{Write-Host "OS VHD $($osDiskSnapshotName) Copy Failed" -f Red}

    ##data disk blob copy
   if($($URIs.Count) -gt 0)
   {
        foreach($item in $DataSAS.GetEnumerator())
	    {
            $dataDiskVHDName=$item.key
            $aburi=$item.Value
            $DatablobCopy=""
            $DatablobCopy=(Start-AzureStorageBlobCopy -AbsoluteUri $DDSAS -DestContainer $destStorageContainerName -DestContext $destinationContext -DestBlob $dataDiskVHDName)
            $DataTotalBytes = ($DatablobCopy | Get-AzureStorageBlobCopyState).TotalBytes
            while(($DatablobCopy | Get-AzureStorageBlobCopyState).Status -eq "Pending")
            {
               Start-Sleep 10
               $BytesCopied = ($DatablobCopy | Get-AzureStorageBlobCopyState).BytesCopied
               $PercentCopied = [math]::Round($BytesCopied/$DataTotalBytes * 100,2)
               Write-Progress -Activity "Blob $($dataDiskVHDName) Copy in Progress" -Status "$PercentCopied% Complete:" -PercentComplete $PercentCopied -CurrentOperation "Data Disk $($dataDiskVHDName) Copy"
            }
            $dataCopyStatus= ($DatablobCopy | Get-AzureStorageBlobCopyState).Status
            if($dataCopyStatus -eq "Success"){Write-Host "Successfully Copied Data disk VHD $($dataDiskVHDName) to the Target Storage Account"-f Green} else{Write-Host "Data VHD $($dataDiskVHDName) Copy Failed" -f Red}
	    }
   }
}catch{Write-Host "Failed during blob copy. Error Message: $_" -f Red}

 
#################################################################################################################################################################################
Write-Host "Creating New Virtual Machine $myNewVMName in subscription $destSubscriptionId" -f Green
##Setting up the configuration for the New VM 
try{
    $destVirtualNetwork = (Get-AzureRmVirtualNetwork -ResourceGroupName $destVirtualNetworkRG -Name $destVirtualNetworkName)
    $subnetId='/subscriptions/'+$($destSubscriptionId)+'/resourceGroups/'+$($destVirtualNetworkRG)+'/providers/Microsoft.Network/virtualNetworks/'+$($destVirtualNetworkName)+'/subnets/'+$($destSubnetName)
    $networkInterface = New-AzureRmNetworkInterface -ResourceGroupName $destRGName  -Name $nicName -Location $destLocationName -SubnetId $subnetId 
    ##make the private IP static
    $nic = Get-AzureRmNetworkInterface -ResourceGroupName $destRGName -Name $nicName
    $nic.IpConfigurations[0].PrivateIpAllocationMethod = 'Static'
    
    ##Attch NSG to the NIC
    $nsg=(Find-AzureRmResource -ResourceNameEquals $nsgName -ResourceType "Microsoft.Network/networkSecurityGroups")
    $nsg =Get-AzureRmNetworkSecurityGroup -ResourceGroupName $nsg.ResourceGroupName -Name $nsgName
    $nic.NetworkSecurityGroup = $nsg
    $nicState=($nic | Set-AzureRmNetworkInterface)
    if($nicState.ProvisioningState -eq "Succeeded")
    {
        $IP = $nic.IpConfigurations[0].PrivateIpAddress
        Write-Host "The allocation method is now set to $($nic.IpConfigurations[0].PrivateIpAllocationMethod) for the IP address $IP`n Suucessfully attached the NSG $nsgName to the nic $nicName" -f Green
    }
    
    $destVMOSVhd = 'https://'+$destSAName+'.blob.core.windows.net/'+$destStorageContainerName+'/'+$osDiskSnapshotName
    $destVmConfig = New-AzureRmVMConfig -VMName $myNewVMName -VMSize $virtualMachineSize 
    $destVmConfig = Set-AzureRmVMOSDisk -VM $destVmConfig -Name $osDiskName -VhdUri $destVMOSVhd -CreateOption Attach -Windows
    $destVmConfig = Add-AzureRmVMNetworkInterface -VM $destVmConfig -Id $networkInterface.Id
    $newVm = New-AzureRmVM -VM $destVMConfig -Location $destLocationName -ResourceGroupName $destRGName
}
catch{Write-Host "Failed during VM Creation : Exception message:$_" -f Red}


if($newVm.IsSuccessStatusCode -eq "True")
{
        $virtualMachine = Get-AzureRmVM -ResourceGroupName $destRGName -Name $myNewVMName
        Write-Host "New VM $myNewVMName created successfully!" -f Green

        ##Reset the username and password
        (Set-AzureRmVMAccessExtension -ResourceGroupName $destRGName -Location $destLocationName -VMName $virtualMachine.Name -Name VMAccessAgent -Credential $Cred) | Out-Null
        if((Get-AzureRmVM -ResourceGroupName $destRGName -Name $myNewVMName).Extensions.VirtualMachineExtensionType -contains 'VMAccessAgent'){Write-Host "Successfully reseted the Username and Password for the VM"-f Green}
        
        ## Set the tags
        (Set-AzureRmResource -Tag $tags -ResourceName $myNewVMName -ResourceType 'Microsoft.Compute/virtualMachines' -ResourceGroupName $destRGName -Force) |Out-Null
        if(!(Get-AzureRmResource -ResourceName $myNewVMName -ResourceGroupName $destRGName).Tags -eq ""){Write-Host "Successfully added Tags to the VM"-f Green}

        ##Set the diagnostic storage account
        try{
        $diagnosticSA=(Find-AzureRmResource -ResourceNameEquals $diagnosticSAName -ResourceType 'Microsoft.Storage/storageAccounts' )
        if($diagnosticSA)
        {
            Write-Host "Using existing storage account for diagnostic" -f Green
            $diagnosticSARG=$diagnosticSA.ResourceGroupName
            $diagnostic= (Set-AzureRmVMBootDiagnostics -VM $virtualMachine -Enable -ResourceGroupName $diagnosticSARG -StorageAccountName $diagnosticSAName)
            if ($diagnostic.ProvisioningState -eq "Succeeded"){Write-Host "Successfully set the diagnostic storage account for the new VM"-f Green} else {Write-Host "Failed setting storage account for Diagnostic Account"-f Red}
        }
                else
                {
                $available=(Get-AzureRmStorageAccountNameAvailability -Name $diagnosticSAName)
                 if($available.NameAvailable -eq 'True')
                 {
                    Write-Host "Creating new Storage Account $diagnosticSAName"-f Green
                    $newdiaSA=(New-AzureRmStorageAccount -ResourceGroupName $destRGName -Name $diagnosticSAName -Location $destLocationName -SkuName Standard_LRS -Kind StorageV2)
                    if($newSA.ProvisioningState -eq "Succeeded")
                    {
                    Write-Host "Successfully created new storage account" -f Green
                    $diagnostic= (Set-AzureRmVMBootDiagnostics -VM $virtualMachine -Enable -ResourceGroupName $destRGName -StorageAccountName $diagnosticSAName)
                    if ($diagnostic.ProvisioningState -eq "Succeeded"){Write-Host "Successfully set the diagnostic storage account for the new VM"-f Green} else {Write-Host "Failed setting storage account for Diagnostic Account"-f Red}
                    }
                 }
                 else{Write-Host "Storage Account Name is not available. Please try again with unique name"-f Red -ErrorAction Stop}
            }

           }catch{Write-Host "Failed during setting diagnostic SA $_."}
 
##Attaching the Data Disks to the VM 
if($URIs.Count -gt 0)
 {
           
            Write-Host "Attaching Data Disks to the VM $myNewVMName" -f Green
            [Int] $diskCount=1
            try
            {
                foreach($uri in $URIs)
                {
                    $dataDiskVHDName=$myNewVMName+'-DataDisk'+$diskCount+'-'+(-join ((48..50) + (97..100) | Get-Random -Count 32 | % {[char]$_}))
                    $datasnapshotname=$uri.Split('/')[8]+'.vhd'
                    $datadiskuri= 'https://'+$destSAName+'.blob.core.windows.net/'+$destStorageContainerName+'/'+$datasnapshotname
                    $addDisk=Add-AzureRmVMDataDisk -VM $virtualMachine -Name $dataDiskVHDName -VhdUri $datadiskuri  -CreateOption Attach -Lun $diskCount 
                    if($($addDisk.StorageProfile.DataDisks.Name) -contains $($dataDiskVHDName)){Write-Host "Successfully added data disk $dataDiskVHDName to the VM $myNewVMName"-f Green}
                    $diskCount++
                }

                $update=(Update-AzureRmVM -ResourceGroupName $destRGName -VM $virtualMachine)
                if ($update.IsSuccessStatusCode -eq "True"){Write-Host "Successfully updated the VM $myNewVMName"-f Green}
                

                    $runName = $customScriptURL.Split('/')[4]
                    Write-Host "Initialising the newly added Data Disk" -f Green
                    $scriptExtention=Set-AzureRmVMCustomScriptExtension -VMName $myNewVMName -ResourceGroupName $destRGName -Location $destLocationName -FileUri $customScriptURL -Run $runName -Name CustomExtesionScript 
                    $removeExtention=Remove-AzureRmVMCustomScriptExtension -VMName $myNewVMName -ResourceGroupName $destRGName  -Name CustomExtesionScript -Force 
            }catch{Write-Host "Exception message:$_"}
        }

}
else {Write-Host "VM creation failed" -f Red}   