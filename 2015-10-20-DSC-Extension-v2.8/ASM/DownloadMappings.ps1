# Create a Json to send the the DSC VM Extension
function New-XAzureVmDscExtensionJson
{
[CmdletBinding()]
    param(

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $moduleName,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [string]
        $modulesUrl,

        [AllowNull()]
        [HashTable]
        $properties,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $configurationName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('4.0','latest','5.0PP')]
        [string]
        $WmfVersion,

        [AllowNull()]
        [hashtable]
        $DownloadMappings

    )

    $publicSettingsTable = @{
        Properties = $properties
        WmfVersion = $WmfVersion
    }

    if($null -ne $modulesUrl)
    {
      $publicSettingsTable.Add('ModulesUrl',$modulesUrl)
    }
    if($null -ne $DownloadMappings)
    {
      $advancedOptions = @{DownloadMappings=$DownloadMappings}

      $publicSettingsTable.Add('advancedOptions',$advancedOptions)
    }

    $publicSettingsTable.Add('ConfigurationFunction' , "${ModuleName}\${configurationName}")

    return ConvertTo-Json -Depth 8 $publicSettingsTable
}

# Publish a DSC configuration, Create a SasToken, and return the full URI with the SASToken
function Get-XAzureDscPublishedModulesUrl
{

  [CmdletBinding()]
  param
  (
    [Parameter(HelpMessage='The storage container to publish the configuration to')]
    [ValidateNotNullOrEmpty()]
    [String]
    $StorageContainer  = 'windows-powershell-dsc',
    
    [Parameter(Mandatory=$true, Position=0, HelpMessage='The name of the blob.')]
    [ValidateNotNullOrEmpty()]
    [String]
    $blobName,
    
    [Parameter(Mandatory=$true, Position=1, HelpMessage='The path to the configuration to publish')]
    [ValidateNotNullOrEmpty()]
    [String]
    $configurationPath,

    [Parameter(Mandatory=$true, Position=2, HelpMessage='The name of the storage account to publish to')]
    [ValidateNotNullOrEmpty()]
    [String]
    $storageAccountName
  )

  # Get the Storage Account Context
  function Get-AzureDscStorageAccountContext
  {
      param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $storageAccountName
      )
      $azureStorageAccount = Get-AzureStorageAccount -StorageAccountName $storageAccountName
      if(!$azureStorageAccount)
      {
        throw 'storage account not found'
      }

      $storageAccessKey      = (Get-AzureStorageKey –StorageAccountName $StorageAccountName).Primary
      $storageContext = New-AzureStorageContext -StorageAccountName $StorageAccountName `
            -StorageAccountKey $storageAccessKey

      return $storageContext
  }  

  $expiryTime = [DateTime]::UtcNow.AddMinutes(60)
  
  #Publish the configuration
  Publish-AzureVMDscConfiguration -ConfigurationPath $configurationPath -Verbose -Force `
      -storageContext (Get-AzureDscStorageAccountContext -storageAccountName $storageAccountName) `
      -ContainerName $StorageContainer
  
  # Create a SasToken for the Configuration
  return New-AzureStorageBlobSASToken -Container $StorageContainer -Blob $blobName -Permission r `
      -ExpiryTime $expiryTime -Context (Get-AzureDscStorageAccountContext -storageAccountName $storageAccountName) -FullUri
}

$storageAccountName = 'storageaccountname'
$publisher          = 'Microsoft.Powershell'
$dscVersion         = '2.8'
$serviceName        = 'servicename'
$vmName             = 'vmName'
$moduleName         = 'configuration.ps1'
$blobName           = "$moduleName.zip"
$configurationPath  = "$PSScriptRoot\$moduleName"
$ConfigurationName  = 'ConfigurationName'

$modulesUrl = Get-XAzureDscPublishedModulesUrl -blobName $blobName -configurationPath $configurationPath `
   -storageAccountName $storageAccountName
Write-Verbose -Message "ModulesUrl: $modulesUrl" -Verbose

$PublicConfigurationJson = New-XAzureVmDscExtensionJson -moduleName $moduleName -modulesUrl $modulesUrl `
    -configurationName $ConfigurationName -DownloadMappings @{'WMF_4.0-Windows_6.1-x64' = 'https://mystorage.blob.core.windows.net/mypubliccontainer/Windows6.1-KB2819745-x64-MultiPkg.msu'}
Write-Verbose -Message "PublicConfigurationJson: $PublicConfigurationJson" -Verbose

$vm = get-azurevm -ServiceName $serviceName -Name $vmName
$vm = Set-AzureVMExtension `
        -VM $vm `
        -Publisher $publisher `
        -ExtensionName 'DSC' `
        -Version $dscVersion `
        -PublicConfiguration $PublicConfigurationJson `
        -ForceUpdate
        
$vm | Update-AzureVM

