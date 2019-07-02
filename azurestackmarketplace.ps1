### Original Author: John Savill - savilltech.com
### Contributing Author: Chris Mahon - blueflashylights.com

# Get ARM Admin Endpoint URI and AAD Tenant Name
Write-Host "Getting ARM Admin Endpoint" -ForegroundColor Green
$armEndpoint = Read-Host "Please enter your ARM Admin Endpoint URI (ex: https://adminmanagement.region.contoso.com)"
Write-Host ""
Write-Host "Getting AAD Tenant Name" -ForegroundColor Green
$AADTenantName = Read-Host "Please enter your AAD Tenant Name (ex: contoso.onmicrosoft.com)"
Write-Host ""

# Authenticate to the Azure Stack Environment with an account that has access to the Default Provider Subscription
Add-AzureRMEnvironment -Name "AzureStackAdmin" -ArmEndpoint $armEndpoint -ErrorAction Stop
$AuthEndpoint = (Get-AzureRmEnvironment -Name "AzureStackAdmin").ActiveDirectoryAuthority.TrimEnd('/')
$TenantId = (invoke-restmethod "$($AuthEndpoint)/$($AADTenantName)/.well-known/openid-configuration").issuer.TrimEnd('/').Split('/')[-1]
Add-AzureRmAccount -EnvironmentName "AzureStackAdmin" -TenantId $TenantId

# Verify Azure Stack is registered and activation resource group exists
$activationRG = "azurestack-activation"
$bridgeActivation = Get-AzsAzureBridgeActivation -ResourceGroupName $activationRG
$activationName = $bridgeActivation.Name

# Get available Microsoft extensions and compare with extensions already downloaded to Azure Stack marketplace
Write-Host "Comparing installed extensions with available extensions from the Marketplace"
$availableExtensions = ((Get-AzsAzureBridgeProduct -ActivationName $activationName -ResourceGroupName $activationRG -ErrorAction SilentlyContinue | Where-Object {($_.ProductKind -eq "virtualMachineExtension") -and ($_.Name -like "*microsoft*")}).Name) -replace "default/", ""
$myExtensions = ((Get-AzsAzureBridgeDownloadedProduct -ActivationName $activationName -ResourceGroupName $activationRG -ErrorAction SilentlyContinue | Where-Object {($_.ProductKind -eq "virtualMachineExtension") -and ($_.Name -like "*microsoft*")}).Name) -replace "default/", ""
$diffExtensions = Compare-Object $myExtensions $availableExtensions 
$missingExtensions = $diffExtensions | Where-Object {$_.SideIndicator -eq "=>"}
$missingExtensions = $missingExtensions.InputObject

if($missingExtensions)
    {
        # Print all missing Microsoft extensions in window
        Write-Host "The following Microsoft extensions have newer versions:"
        $missingExtensions | Write-Host -ForegroundColor Red
        Write-Host ""
        
        # Allow user to choose whether or not to download the missing Microsoft extensions
        $prompt = Read-Host "Do you want to download the missing extensions to the marketplace? (y/n)"
        Switch ($prompt)
        {
            Y
            {
                foreach ($missingExtension in $missingExtensions)
                {
                    Write-Host "Downloading $missingExtension to the Azure Stack Marketplace" -ForegroundColor Green
                    #Start-Sleep -Seconds 5
                    Invoke-AzsAzureBridgeProductDownload -ActivationName $activationName -Name $missingExtension -ResourceGroupName $activationRG -Force -Confirm:$false
                }
            }
            N
            {
                Write-Host "No extensions were downloaded!" -ForegroundColor Red
                Write-Host ""
            }
            Default
            {
                Write-Host "No extensions were downloaded!" -ForegroundColor Red
                Write-Host ""
            }
        }
    }
else
    {
        Write-Host "There are no missing extensions to download!" -ForegroundColor Green
        Write-Host ""
    }
        
#Get what is installed
Write-Host "Checking for older versions of Microsoft extensions"
$installedExtensions = Get-AzsAzureBridgeDownloadedProduct -ActivationName $activationName -ResourceGroupName $activationRG | Where-Object {($_.ProductKind -eq "virtualMachineExtension") -and ($_.Name -like "*microsoft*")}
$installedExtensions = $installedExtensions | Sort-Object -Property DisplayName, ProductProperties -Descending #want newest first as we'll look for matching and remove the second

$prevDisplayName = "Not going to match"
$prevEntry = $null
foreach($installed in $installedExtensions)
    {
        #see if name matches the previous, i.e. same extension
        if($installed.DisplayName -eq $prevDisplayName)
        {
            #Lets remove it 
            Write-Host "** Found an older version of $($installed.DisplayName) **"
            Write-Host "Previous version is $($installed.ProductProperties.Version) - $($installed.Name)" -ForegroundColor Red
            Write-Host "Current version is $($prevEntry.ProductProperties.Version) - $($prevEntry.Name)" -ForegroundColor Green
            Write-Host ""
            $Readhost = Read-Host "Do you want to delete previous version ($($installed.ProductProperties.Version)) (y/n)?"
            Switch ($ReadHost) 
            { 
                Y 
                {
                    Write-host "Yes, removing older extension version"; Remove-AzsAzureBridgeDownloadedProduct -Name $installed.Name -ActivationName $activationName -ResourceGroupName $activationRG -Force -Confirm:$false -ErrorAction Continue
                } 
                N 
                {
                    Write-Host "No, not removing older extension version"
                } 
                Default
                {
                    Write-Host "No, not removing older extension version"
                } 
            }
        
            Write-Host ""
        }
        $prevDisplayName = $installed.DisplayName
        $prevEntry = $installed
    }
Write-Host ""
Write-Host "Script complete!" -ForegroundColor Green