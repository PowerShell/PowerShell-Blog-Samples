Configuration Main
{

Param ( [string] $nodeName )

Import-DscResource –ModuleName PSDesiredStateConfiguration

Node $nodeName
  {  
    Script GetWmfVersion
    {
      TestScript = {
                      Write-Verbose "WmfVersion : $($PSVersionTable.PSVersion.Major)" -Verbose
                      $true
                   }
      SetScript = { Write-verbose 'no-op'}
      GetScript = { return @{} }
    }
  }
}