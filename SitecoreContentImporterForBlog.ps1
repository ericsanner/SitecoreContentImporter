<#
    .SYNOPSIS
       Sitecore Content Importer
        
    .DESCRIPTION
        Includes helper functions to write custom content importers for Sitecore
        
    .NOTES	
        Eric Sanner | Perficient | eric.sanner@perficient.com | https://www.linkedin.com/in/ericsanner/
		
	.TODO
		Buckets
#>

#BEGIN Config
$database = "master"
$masterIndex = "sitecore_master_index"
$webIndex = "sitecore_web_index"
$allowDelete = $false
#END Config

#BEGIN Helper Functions

function Write-LogExtended {
	param(
		[string]$Message,
		[System.ConsoleColor]$ForegroundColor = $host.UI.RawUI.ForegroundColor,
		[System.ConsoleColor]$BackgroundColor = $host.UI.RawUI.BackgroundColor
	)

	Write-Log -Object $message
	Write-Host -Object $message -ForegroundColor $ForegroundColor -BackgroundColor $backgroundColor
}

function Strip-Html {
	#https://www.regular-expressions.info/lookaround.html#lookahead Replaces multiple spaces with a single space
	param (
		[string]$text
	)
	
	$text = $text -replace '<[^>]+>',' '
	$text = $text -replace " (?= )", "$1"
	$text = $text.Trim()
	
	return $text
}

function Truncate-Output {
	param (
		$obj,
		$maxLeng
	)
	
	$ret = "";
	
	if($obj -ne $null)
	{
		$str = $obj.ToString().Trim()
		$leng = [System.Math]::Min($str.Length, $maxLeng)
		$truncated = ($str.Length -gt $maxLeng)
		
		$ret = $str.Substring(0, $leng)
		if($truncated -eq $true)
		{
			$ret = $ret + "..."
		}
	}

	return $ret
}

function Get-SourceDataFromFile {
	param(
		[string]$path,
		[string]$encoding = "utf8"
	)
	
	return Get-Content -Path $path -Encoding $encoding -Raw
}

function Get-SourceDataFromUrl {
	param(
		[string]$uri
	)
	
	#TODO: Include authorization
		
	Invoke-WebRequest -Uri $uri -UseBasicParsing
}

function Convert-DataToJson {
	param(
		[string]$data
	)
	
	return ConvertFrom-Json $data
}

#END Helper Functions

#BEGIN Sitecore Functions

function Get-SitecoreItemById {
	#Returned Item uses item.ID
	#https://doc.sitecorepowershell.com/working-with-items#get-item-by-id
	param(
		[string]$id
	)

	return Get-Item -Path $database -ID $id -ErrorAction SilentlyContinue
}

function Get-SitecoreItemByPath {
	#Returned Item uses item.ID
	#https://doc.sitecorepowershell.com/working-with-items#get-item-by-path
	param(
		[string]$path
	)

	return Get-Item -Path "${database}:${path}" -ErrorAction SilentlyContinue
}

function Get-SitecoreItemsByQuery {	
	#Returned Item uses item.ID
	#https://doc.sitecorepowershell.com/working-with-items#get-item-sitecore-query
	param(
		[string]$path,
		[string]$query
	)
		
	return Get-Item -Path "${database}:${path}" -Query $query -ErrorAction SilentlyContinue
}

function Index-SitecoreItems {
	#https://doc.sitecorepowershell.com/appendix/indexing/initialize-searchindexitem
	param (
		[Sitecore.Data.Items.Item]$itemRoot,
		[string]$index = "master"
	)
	
	if($index -eq "web")
	{
		$index = $webIndex
	}
	else
	{
		$index = $masterIndex
	}
		
	Write-LogExtended "[I] Updating $($index) for $($itemRoot.ID) - $($itemRoot.Paths.Path)"
	
	Initialize-SearchIndexItem -Item $itemRoot -Name $index
}

function Find-SitecoreItems {	
	#Find-Item uses content search api.  
	#Search service must be running and indexes must to be up to date.  
	#Will only search for fields that are indexed.
	#Could miss items that are recently added (In this case use Get-Item)
	#Returned Items use item.ID (because of "| Initialize-Item", otherwise returned items use item.ItemId).
	#https://doc.sitecorepowershell.com/appendix/indexing/find-item
	#https://doc.sitecorepowershell.com/appendix/indexing/initialize-item
	param(
		[array]$criteria
	)	
	
	return Find-Item -Index $masterIndex -Criteria $criteria | Initialize-Item
}

function Get-ValidSitecoreItemName {
	#https://sitecore.stackexchange.com/questions/27307/creating-a-new-item-with-in-itemname Removes any invalid characters based on InvalidItemNameChars in the config
	#https://www.regular-expressions.info/lookaround.html#lookahead Replaces multiple -- with a single -
	param (
		[string]$itemName
	)	
	
	#TODO: ProposeValidItemName cannot accept an empty string
	
	if($itemName -ne $null -or $itemName -ne "")
	{		
		$itemName = [Sitecore.Data.Items.ItemUtil]::ProposeValidItemName($itemName)
		$itemName = $itemName -replace " ", "-"
		$itemName = $itemName -replace "-(?=-)", "$1"
		$itemName = $itemName.ToLower()
	}
	
	return $itemName 
}

function Get-NewOrExistingSitecoreItem {
	#https://doc.sitecorepowershell.com/working-with-items#new-item
	param (
		[Sitecore.Data.Items.Item]$itemRoot,
		[string]$itemTemplateId,
		[string]$itemName,
		[string]$lang = "en"
	)
	
	$item = $null
	$itemName = Get-ValidSitecoreItemName $itemName
	$itemPath = "$($itemRoot.Paths.Path)/$($itemName)"
		
	if(Test-Path -Path $itemPath)
	{
		$item = Get-SitecoreItemByPath $itemPath
		Write-LogExtended "[I] Found existing item $($item.ID) - $($item.Name)"
	}
	else
	{		
		$item = New-Item -Parent $itemRoot -ItemType $itemTemplateId -Name $itemName -Language $lang
		Write-LogExtended "[A] Created new item $($item.ID) - $($item.Name)"
	}	
		
	return $item
}

function Update-SitecoreItem {
	#Reads key/value pairs in hashtable to update item
	#Any keys in the hashtable that are not available on the item are skipped
	#Item is only updated if at least one value was updated
	#https://learn.microsoft.com/en-us/powershell/scripting/lang-spec/chapter-10?view=powershell-7.3
	param(
		[Sitecore.Data.Items.Item]$item,
		[System.Collections.Hashtable]$updates
	)
	
	if($item -eq $null)
	{
		Write-LogExtended "[E] Error updating item $($item) - Item is null" Red
	    return
	}
	
	if($updates -eq $null)
	{
		Write-LogExtended "[E] Error updating item $($item) - Update hashtable is null" Red
		return
	}
		
	$changeDetected = $false
	$foregroundColor = "Green"
	
	Write-LogExtended "[I] Updating Item $($item.ID) - $($item.Name)"
	$item.Editing.BeginEdit()
	
	foreach($key in $updates.GetEnumerator())
	{
	    if($item.($key.Name) -ne $null)
	    {
	        $output = "Field Name '$($key.Name)' Current Value: '$(Truncate-Output $item.($key.Name) 40)' New Value: '$(Truncate-Output $key.Value 40)'"			
	        
	        if($item.($key.Name) -ne $key.Value)
	        {
	            Write-LogExtended "[U] $($output)"
	            $item.($key.Name) = $key.Value
	            $changeDetected = $true
	        }
	        else
	        {
	            Write-LogExtended "[-] $($output)"
	        }
	    }
	}
	
	$itemModified = $item.Editing.EndEdit()
	
	if($changeDetected -ne $itemModified)
	{
	    $foregroundColor = "Red"
	}
	
	Write-LogExtended "[I] Change Detected: $($changeDetected) Item modified $($itemModified)" $foregroundColor
}

function Remove-SitecoreItem {
	param(
		[Sitecore.Data.Items.Item]$item,
		[boolean]$delete = $false
	)
	
	if($item -eq $null)
	{
		Write-LogExtended "[E] Error removing item $($item) - Item is null" Red
	    return
	}
	
	$itemRemoved = $null
	
	if($allowDelete -and $delete)
	{
		$itemRemoved = ($item.Delete() -or $true)
		
		if($itemRemoved -ne $null)
		{
			Write-LogExtended "[D] Item $($item.ID) deleted"    
		}
	}
	else
	{		
		$itemRemoved = $item.Recycle()		
	
		if($itemRemoved -ne $null)
		{
			Write-LogExtended "[R] Item $($item.ID) moved to recycle bin"    
		}
	}
	
	if($itemRemoved -eq $null)
	{
	    Write-LogExtended "[E] Error removing item $($item.ID)" Red
	}
}

function Publish-SitecoreItem {
	#https://doc.sitecorepowershell.com/appendix/common/publish-item
	param (
		[Sitecore.Data.Items.Item]$item,
		[string]$lang = "en"
	)
	
	Write-LogExtended "[I] Publishing $($item.ID) - $($item.Paths.Path)"
	
	Publish-Item -Item $item -PublishMode Smart -Language $lang
}

function Publish-SitecoreItemAndChildren {
	#https://doc.sitecorepowershell.com/appendix/common/publish-item
	param (
		[Sitecore.Data.Items.Item]$item,
		[string]$lang = "en"
	)
	
	Write-LogExtended "[I] Publishing $($item.ID) - $($item.Paths.Path) and children"
	
	Publish-Item -Item $item -PublishMode Smart -Language $lang -Recurse
}

#END Sitecore Functions

function Examples {

	$item = Get-SitecoreItemById "{9453CE15-E682-4613-ADE7-6C0F33DB8741}"

	Write-Host $item.ID
	Write-Host $item.Name
	Write-Host $item.Title
	
	$updates = @{}
	$updates.Add("Title", "Import Test")
	$updates.Add("NonExistantField", "Import Test")

	Update-SitecoreItem $item $updates

	#Remove-SitecoreItem $item

	$criteria = @(
		@{Filter = "Equals"; Field = "_templatename"; Value = "Job Page";},
		@{Filter = "Contains"; Field = "_fullpath"; Value = "/home/jobs";}	
	)

	$items = Find-SitecoreItems -criteria $criteria
	Write-Host $items.Count

	Foreach($itm in $items)
	{
		Write-Host $itm.ID
		Write-Host $itm.Name
		Write-Host $itm.Title
		#Update-SitecoreItem $itm $updates
	}
}

#BEGIN Import Functions

function ResetImportField {
	#Reset ImportedOnLastRun field on existing items
	
	Write-LogExtended "[I] Resetting import field"
	
	$updates = @{}
	$updates.Add("ImportedOnLastRun", "")

	$criteria = @(
		@{Filter = "Equals"; Field = "_templatename"; Value = "Job Page";},
		@{Filter = "Contains"; Field = "_fullpath"; Value = "/home/jobs";}	
	)

	$items = Find-SitecoreItems -criteria $criteria
	Write-LogExtended "[I] Found $($items.Count) items to reset"

	Foreach($item in $items)
	{
		Update-SitecoreItem $item $updates
	}
}

function ReadSourceData {
	$data = Get-SourceDataFromFile "c:\inetpub\wwwroot\your_file.json"
		
	return Convert-DataToJson $data
}

function IsValidJob {
	param (
		[Object]$job
	)
	
	$valid = $true
	
	if($job.eId -eq $null -or $job.eId -eq "" -or $job.requisitionId -eq $null -or $job.requisitionId -eq "" -or $job.category -eq $null -or $job.category -eq "" -or $job.company -eq $null -or $job.company -eq "" -or $job.jobLocations.Count -eq 0)
	{
		Write-LogExtended "[E] Error importing job $($job.eId) - Not a valid job" Red
		$valid = $false
	}
	
	return $valid
}

function IterateSourceData {
	
	Write-LogExtended "[I] Iterating Source Data"
	
	Foreach($job in $data.requisitions)
	{
		$item = $null
		
		$validJob = IsValidJob $job
		
		if($validJob -eq $false)
		{
			continue
		}
		
		Write-LogExtended "[I] Importing job $($job.eId)"
		
		$itemName = "$($job.title)-$($job.eId)"
		$item = Get-NewOrExistingSitecoreItem $itemRoot $itemTemplateId $itemName
		
		if($item -ne $null)
		{
			$locations = ProcessLocations $job.jobLocations
			
			$category = Get-SitecoreItemByPath "/sitecore/content/YourTenant/Shared/Data/Tags/Careers Categories/$($job.company)"
			if($category -eq $null)
			{
				Write-LogExtended "[E] Error finding category $($job.company)" Red
			}
			
			$jobFamily = Get-SitecoreItemByPath "/sitecore/content/YourTenant/Shared/Data/Tags/Job Families/$($job.category)"
			if($jobFamily -eq $null)
			{
				Write-LogExtended "[E] Error finding job family $($job.category)" Red
			}
			
			$briefDescription = Strip-Html $job.briefDescription
			
			$updates = @{}
			$updates.Add("Careers Category", $category.ID)
			$updates.Add("Description", $job.description)
			$updates.Add("__Display name", $job.title)
			$updates.Add("ImportedOnLastRun", "1")
			$updates.Add("JobID", $job.eId)
			$updates.Add("Job Family", $jobFamily.ID)
			$updates.Add("JobListingTitle", $job.title)
			$updates.Add("MetaDescription", $briefDescription)
			$updates.Add("NavigationTitle", $job.title)
			$updates.Add("OpenGraphDescription", $briefDescription)
			$updates.Add("OpenGraphTitle", $job.title)
			$updates.Add("Content", $job.description)
			$updates.Add("Title", $job.title)			
			$updates.Add("Addresses", $locations)

			Update-SitecoreItem $item $updates
		}			
	}	
}

function ProcessLocations {
	param (
		[Object]$locationData
	)	
	
	Write-LogExtended "[I] Processing Locations"
	
	$locations = @()
	
	Foreach($location in $locationData)
	{
		
		$country = Get-NewOrExistingSitecoreItem $countriesRoot $countriesTemplateId $location.country		
		
		$countryUpdates = @{}
		$countryUpdates.Add("CountryName", $location.country)
		$countryUpdates.Add("__Display name", $location.country)
		
		Update-SitecoreItem $country $countryUpdates
		
		$state = Get-NewOrExistingSitecoreItem $statesRoot $statesTemplateId $location.state
		
		$stateUpdates = @{}
		$stateUpdates.Add("StateName", $location.state)
		$stateUpdates.Add("__Display name", $location.state)
		
		Update-SitecoreItem $state $stateUpdates
		
		$poi = Get-NewOrExistingSitecoreItem $poiRoot $poiTemplateId $location.name
		
		$poiUpdates = @{}
		$poiUpdates.Add("StreetAddress1", $location.address)
		$poiUpdates.Add("StreetAddress2", $location.address2)
		$poiUpdates.Add("City", $location.city)
		$poiUpdates.Add("StateName", $state.ID)
		$poiUpdates.Add("CountryName", $country.ID)
		$poiUpdates.Add("ZipCode", $location.postalCode)
		$poiUpdates.Add("__Display name", $location.name)

		Update-SitecoreItem $poi $poiUpdates
		
		$locations += $poi.ID
	}
	
	return $locations -join "|"
}

function DeleteItemsNotImported {
	#Delete items not imported this run
	
	Write-LogExtended "[I] Removing items not imported"
	
	$criteria = @(
		@{Filter = "Equals"; Field = "_templatename"; Value = "Job Page";},
		@{Filter = "Contains"; Field = "_fullpath"; Value = "/home/jobs";},
		@{Filter = "Equals"; Field = "importedonlastrun_b"; Value = "false";}
	)

	$items = Find-SitecoreItems -criteria $criteria
	Write-LogExtended "[I] Found $($items.Count) items to remove"
	
	Foreach($item in $items)
	{
		Remove-SitecoreItem $item
	}
}

#END Import Functions

#BEGIN Main

	#/sitecore/content/YourTenant/Home/Jobs
	$itemTemplateId = "{125764E1-2EFA-4C8B-B880-4D212403DBD6}"	
	$itemRootId = "{FF36ABF4-A94E-4AB1-A3AC-F698F35AB5A4}"
	$itemRoot = Get-SitecoreItemById $itemRootId
	
	#/sitecore/content/YourTenant/Shared/Data/Country 
	$countriesTemplateId = "{05E9CEBB-1245-4EDD-AA61-0DA470A518B8}"
	$countriesRootId = "{EB972B0E-86E3-4FDC-8BE6-30DA7725345B}"
	$countriesRoot = Get-SitecoreItemById $countriesRootId
	
	#/sitecore/content/YourTenant/Shared/Data/States 
	$statesTemplateId = "{D46E443F-DEC3-4CAA-9241-44920F7362F0}"
	$statesRootId = "{5BD53A36-D492-4A5B-A73D-341353FB1627}"
	$statesRoot = Get-SitecoreItemById $statesRootId
	
	#/sitecore/content/YourTenant/Shared/Data/POIs 
	$poiTemplateId = "{8A1251F1-2E42-4567-888A-CD527DD61099}"
	$poiRootId = "{9B2F8D66-66FC-45E0-8E4F-6DA3D4175918}"
	$poiRoot = Get-SitecoreItemById $poiRootId

	Index-SitecoreItems $itemRoot "master"	
	ResetImportField
	
	$data = ReadSourceData	
	IterateSourceData
	
	Index-SitecoreItems $itemRoot "master"
	DeleteItemsNotImported
	
	Index-SitecoreItems $itemRoot "master"
	Index-SitecoreItems $countriesRoot "master"
	Index-SitecoreItems $statesRoot "master"
	Index-SitecoreItems $poiRoot "master"
	
	Publish-SitecoreItemAndChildren $itemRoot
	Publish-SitecoreItemAndChildren $countriesRoot
	Publish-SitecoreItemAndChildren $statesRoot
	Publish-SitecoreItemAndChildren $poiRoot
	
	Index-SitecoreItems $itemRoot "web"
	Index-SitecoreItems $countriesRoot "web"
	Index-SitecoreItems $statesRoot "web"
	Index-SitecoreItems $poiRoot "web"
	
#END Main