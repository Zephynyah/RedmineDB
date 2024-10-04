<#	
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.241
	 Created on:   	10/4/2024 12:23 AM
	 Created by:   	Jason Hickey
	 Organization: 	House of Powershell
	 Filename:     	RedmineDB.psm1
	-------------------------------------------------------------------------
	 Module Name: RedmineDB
	===========================================================================
#>

#Requires -Version 5.0

$DebugPreference = "SilentlyContinue"


#region Class

Class Redmine {
	Hidden [Parameter(Mandatory = $True)][String]$Server
	Hidden [Microsoft.PowerShell.Commands.WebRequestSession]$Session
	Hidden [String]$CSRFToken
	$db
	
	# Constructors
	
	Redmine([String]$Server, [Hashtable]$IWRParams)
	{
		$this.Server = $Server
		If ($Script:APIKey)
		{
			Write-Host "X-Redmine-API-Key Saved"
		}
		Else
		{
			$this.signin($IWRParams)
		}
		$this.db = $this.new('db')
	}
	
	# Methods
	
	Hidden signin($IWRParams)
	{
		$sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
		$IWRParams += @{
			SessionVariable = Get-Variable -name sess -ValueOnly
			Method		    = 'GET'
			Uri			    = "$($this.Server)/login"
		}
		$Response = Invoke-WebRequest @IWRParams
		If ($Response.Forms.Fields)
		{
			$this.CSRFToken = $Response.Forms.Fields['authenticity_token']
		}
		$this.Session = Get-Variable -name $sess -ValueOnly
	}
	
	Hidden signout()
	{
		$IRMParams = @{
			WebSession = $this.Session
			Method	   = 'POST'
			Uri	       = "$($this.Server)/logout"
			Headers    = @{ 'X-CSRF-Token' = $this.CSRFToken }
		}
		Invoke-RestMethod @IRMParams
	}
	
	[PSCustomObject]request($IRMParams)
	{
		$IRMParams += @{
			WebSession = $this.Session
		}
		$Response = Invoke-RestMethod @IRMParams
		Write-Debug $Response
		return $Response
	}
	
	[PSCustomObject]new($type)
	{
		$Object = New-Object 'db'
		$Object.Server = $this.Server
		$Object.Session = $this.Session
		return $Object
	}
	
}

Class DB {
	# db/id.json
	# db.json
	Hidden [Parameter(Mandatory = $True)][String]$Server
	Hidden [Microsoft.PowerShell.Commands.WebRequestSession]$Session
	Hidden [String]$setname = 'db'
	Hidden [String]$include = '?include=memberships,groups'
	[String]$id
	[string]$name
	[String]$description
	[Bool]$is_private
	[PSCustomObject]$project
	[PSCustomObject]$status
	[PSCustomObject]$type
	[PSCustomObject]$author
	[PSCustomObject[]]$tags
	[PSCustomObject[]]$custom_fields
	[PSCustomObject[]]$issues
	[String]$created_on
	[String]$updated_on
	
	# Methods
	
	[Array]to_json()
	{
		$UTF8 = [System.Text.Encoding]::UTF8
		$JSON = @{ db_entry = @{ } }
		foreach ($property in $this.psobject.properties.name)
		{
			If ($this.$property -eq 0 -or $this.$property.Count -eq 0)
			{
				Write-Debug "Null $property"
				continue
			}
			Else
			{
				Switch ($property)
				{
					'project' { $JSON.db_entry.Add('project_id', $this.project.id) }
					'type' { $JSON.db_entry.Add('type_id', $this.type.id) }
					'status' { $JSON.db_entry.Add('status_id', $this.status.id) }
					'parent' { $JSON.db_entry.Add('parent_issue_id', $this.parent.id) }
					'issues' {
						$JSON.db_entry.Add('issues_ids', @())
						$this.issues | ForEach-Object{ $JSON.db_entry.issues_ids += $_.id }
					}
					{ $_ -in 'setname', 'include', 'Server', 'Session' } { }
					default { $JSON.db_entry.Add($property, $this.$property) }
				}
			}
		}
		$JSON = $JSON | ConvertTo-Json -Depth 10 -Compress
		Write-Debug $JSON
		return $JSON
	}
	
	[PSCustomObject]request($Method, $Uri)
	{
		$IRMParams = @{ Method = $Method }
		If ($Script:APIKey)
		{
			$IRMParams += @{ Headers = @{ 'X-Redmine-API-Key' = $Script:APIKey } }
			If ($Uri.Contains('?'))
			{
				$Uri = $Uri + '&key=' + $Script:APIKey
			}
			Else
			{
				$Uri = $Uri + '?key=' + $Script:APIKey
			}
		}
		Else
		{
			$IRMParams += @{
				WebSession = $this.Session
			}
		}
		$IRMParams += @{ Uri = $this.Server + '/' + $Uri }
		If ($Method -Match 'POST|PUT')
		{
			$IRMParams += @{
				ContentType = 'application/json'
				Body	    = $this.to_json()
			}
		}
		$Response = Invoke-RestMethod @IRMParams
		Write-Debug $Response
		return $Response
	}
	
	[PSCustomObject]getByName($name)
	{
		$Object = New-Object 'db'
		$Object.Server = $this.Server
		$Object.Session = $this.Session
		$filter = '&name=' + $name
		
		$Response = $this.request('GET', 'db.json' + $this.include + $filter)
		foreach ($property in $Response.db_entry.psobject.Properties.Name)
		{
			$Object.$property = $Response.db_entry.$property
		}
		return $Object
	}
	
	[PSCustomObject]get($id)
	{
		$Object = New-Object 'db'
		$Object.Server = $this.Server
		$Object.Session = $this.Session
		
		$Response = $this.request('GET', $this.setname + '/' + $id + '.json' + $this.include)
		foreach ($property in $Response.db_entry.psobject.Properties.Name)
		{
			$Object.$property = $Response.db_entry.$property
		}
		return $Object
	}
	
	[Hashtable]allpages($base_url, $filter)
	{
		Write-Debug $filter
		$offset = 0
		$limit = 1000
		
		$Response = $this.request('GET', $base_url + '?offset=' + $offset + '&limit=' + $limit + $this.include + $filter)
		$remain = $Response.total_count
		Write-Debug "$offset + $remain"
		
		$collection = @{ }
		While ($remain -gt 0)
		{
			$Response.db_entries | ForEach-Object {
				$item = $_ -as ('db' -as [type])
				$collection.Add($item.id, $item)
			}
			$remain -= $limit
			$offset += $limit
			Write-Debug "$offset + $remain"
			if ($remain -lt 100) { $limit = $remain }
			
			$Response = $this.request('GET', $base_url + '?offset=' + $offset + '&limit=' + $limit + $this.include + $filter)
		}
		return $collection
	}
	
	[Hashtable]all() { return $this.all('', $null) }
	[Hashtable]all($filter) { return $this.all($filter, $null) }
	[Hashtable]all($filter, $project_id)
	{
		$collection = @{ }
		$collection = $this.allpages($this.setname + '.json', $filter)
		return $collection
	}
	
	clear()
	{
		foreach ($property in $this.psobject.properties.name)
		{
			$this.$property = $Null
		}
	}
	
	[PSCustomObject]create()
	{
		$Response = $this.request('POST', $this.setname + '.json')
		$this.clear()
		
		return ($Response.db_entry)
	}
	
	read()
	{
		$Response = $this.request('GET', $this.setname + '/' + $this.id + '.json')
		foreach ($property in $Response.db_entry.psobject.Properties.Name)
		{
			$this.$property = $Response.db_entry.$property
		}
		
	}
	
	update()
	{
		$this.request('PUT', $this.setname + '/' + $this.id + '.json')
		$this.clear()
	}
	
	delete()
	{
		$this.request('DELETE', $this.setname + '/' + $this.id + '.json')
	}
}


#endregion

#region Function

Function Connect-Redmine
{
	<#
   .SYNOPSIS
    Connect to the Redmine server
   .DESCRIPTION
    Connect to the Redmine server and set the authorization variable in script scope
   .EXAMPLE
    Connect-Redmine https://testredmine
   .EXAMPLE
    Connect-Redmine testredmine
   .LINK
    https://github.com/hamletmun/PSRedmine
	#>
	Param (
		[Parameter(Mandatory = $True)]
		[String]$Server,
		[String]$Key,
		[String]$Username,
		[String]$Password
	)
	
	Remove-Variable -Name Redmine -Scope script -ErrorAction 0
	
	If ($Key)
	{
		$IWRParams = @{ }
		$Script:APIKey = $Key
	}
	Else
	{
		If (!($Username)) { If (!($Username = Read-Host "Enter username or blank for [$env:USERNAME]")) { $Username = $env:USERNAME } }
		If ($Password) { [Security.SecureString]$Password = ConvertTo-SecureString $Password -AsPlainText -Force }
		Else { [Security.SecureString]$Password = Read-Host "Enter password for [$Username]" -AsSecureString }
		$cred = New-Object System.Management.Automation.PSCredential ($Username, $Password)
		$IWRParams = @{
			Credential = $cred
		}
	}
	$Script:Redmine = [Redmine]::new($Server, $IWRParams)
}

Function Disconnect-Redmine
{
	<#
   .SYNOPSIS
    Disconnect from the Redmine server
   .DESCRIPTION
    Disconnect from the Redmine server
   .EXAMPLE
    Disconnect-Redmine
   .EXAMPLE
    Disconnect-Redmine
   .LINK
    https://github.com/hamletmun/PSRedmine
	#>
	
	Remove-Variable -Name Redmine -Scope script
	If ($APIKey) { Remove-Variable -Name APIKey -Scope script }
}

Function Search-RedmineDB
{
	<#
   .SYNOPSIS
    Search Redmine resource by keyword
   .DESCRIPTION
    Search Redmine resource by keyword
   .EXAMPLE
    Search-RedmineDB project demoproj
   .EXAMPLE
    Search-RedmineDB version demover -project_id demoproj
   .LINK
    https://github.com/hamletmun/PSRedmine
	#>
	Param (
		[String]$keyword,
		[String]$project_id,
		[ValidateSet('open', 'closed', '*')]
		[String]$status = 'open'
	)
	
	$filter = ''
	If ($project_id) { $filter += '&project_id=' + $project_id }
	If ($status) { $filter += '&status_id=' + $status }
	
	$collection = Switch ($type)
	{
		{ $_ -in 'membership', 'version' } { $Redmine.db.all($filter, $project_id) }
		default { $Redmine.db.all($filter) }
	}
	
	$filtered = @{ }
	Switch ($type)
	{
		'issue' { $collection.Keys | ForEach-Object { if ($collection[$_].subject -Match $keyword) { $filtered[$_] = $collection[$_] } } }
		'user' { $collection.Keys | ForEach-Object { if ($collection[$_].login -Match $keyword) { $filtered[$_] = $collection[$_] } } }
		'membership' { $collection.Keys | ForEach-Object { if ($collection[$_].user.name -Match $keyword) { $filtered[$_] = $collection[$_] } } }
		default { $collection.Keys | ForEach-Object { if ($collection[$_].name -Match $keyword) { $filtered[$_] = $collection[$_] } } }
	}
	return $filtered
}

Function Set-RedmineDB
{
	Param (
		[String]$name,
		[String]$type,
		[String]$status,
		[bool]$private,
		[String]$description,
		[String[]]$tags,
		[String]$systemMake,
		[String]$systemModel,
		[String]$operatingSystem,
		[String]$serialNumber,
		[String]$assetTag,
		[String]$periodsProcessing,
		[String]$parentHardware,
		[String]$hostname,
		[String[]]$programs,
		[String]$gscStatus,
		[String]$hardDriveSize,
		[String]$memory,
		[String]$memoryValitility,
		[String]$state,
		[String]$building,
		[String]$room,
		[String]$rackSeat,
		[String]$node,
		[String]$safeAndDrawerNumber,
		[string]$refreshDate,
		[String]$macAddress,
		[String]$notes,
		[PSCustomObject[]]$issues
	)
	
	$resource = $Redmine.new('db')
	
	foreach ($boundparam in $PSBoundParameters.GetEnumerator())
	{
		If ($boundparam.Value -eq $null) { continue }
		Switch ($boundparam.Key)
		{
			'private' { $resource.is_private = $boundparam.Value }
			'type' { $resource.type = [PSCustomObject]@{ id = $boundparam.Value } }
			'status' { $resource.status = [PSCustomObject]@{ id = $boundparam.Value } }
			'systemMake' { $resource.custom_fields += [PSCustomObject]@{ id = 101; value = $boundparam.Value } }
			'systemModel' { $resource.custom_fields += [PSCustomObject]@{ id = 102; value = $boundparam.Value } }
			'operatingSystem' { $resource.custom_fields += [PSCustomObject]@{ id = 105; value = $boundparam.Value } }
			'serialNumber' { $resource.custom_fields += [PSCustomObject]@{ id = 106; value = $boundparam.Value } }
			'assetTag' { $resource.custom_fields += [PSCustomObject]@{ id = 107; value = $boundparam.Value } }
			'periodsProcessing' { $resource.custom_fields += [PSCustomObject]@{ id = 113; value = $boundparam.Value } }
			'parentHardware' { $resource.custom_fields += [PSCustomObject]@{ id = 114; value = $boundparam.Value } }
			'hostname' { $resource.custom_fields += [PSCustomObject]@{ id = 115; value = $boundparam.Value } }
			'programs' { $resource.custom_fields += [PSCustomObject]@{ id = 116; value = $boundparam.Value } }
			'gscStatus' { $resource.custom_fields += [PSCustomObject]@{ id = 117; value = $boundparam.Value } }
			
			'memory' { $resource.custom_fields += [PSCustomObject]@{ id = 119; value = $boundparam.Value } }
			'hardDriveSize' { $resource.custom_fields += [PSCustomObject]@{ id = 120; value = $boundparam.Value } }
			'memoryValitility' { $resource.custom_fields += [PSCustomObject]@{ id = 124; value = $boundparam.Value } }
			
			'state' { $resource.custom_fields += [PSCustomObject]@{ id = 109; value = $boundparam.Value } }
			'building' { $resource.custom_fields += [PSCustomObject]@{ id = 126; value = $boundparam.Value } }
			'room' { $resource.custom_fields += [PSCustomObject]@{ id = 127; value = $boundparam.Value } }
			
			'rackSeat' { $resource.custom_fields += [PSCustomObject]@{ id = 112; value = $boundparam.Value } }
			'node' { $resource.custom_fields += [PSCustomObject]@{ id = 125; value = $boundparam.Value } }
			
			'safeAndDrawerNumber' { $resource.custom_fields += [PSCustomObject]@{ id = 128; value = $boundparam.Value } }
			
			'refreshDate' { $resource.custom_fields += [PSCustomObject]@{ id = 108; value = $boundparam.Value } }
			'macAddress' { $resource.custom_fields += [PSCustomObject]@{ id = 150; value = $boundparam.Value } }
			'issues' { $boundparam.Value | ForEach-Object { $resource.issues += [PSCustomObject]@{ id = $_ } } }
			default {
				If ($boundparam.Key -In $resource.PSobject.Properties.Name)
				{
					$resource.$($boundparam.Key) = $boundparam.Value
				}
			}
		}
	}
	
	Write-Debug 'Returned from Set-RedmineDB'
	Write-Debug ($resource | ConvertTo-Json -Depth 4)
	return $resource
}

Function New-RedmineDB
{
	<#
   .SYNOPSIS
    Create a new Redmine resource
   .DESCRIPTION
    Create a new Redmine resource
   .EXAMPLE
    New-RedmineDB project -identifier test13 -name test13
   .EXAMPLE
    New-RedmineDB version -project_id test13 -name testver
   .EXAMPLE
    New-RedmineDB issue -project_id test13 -subject testissue
   .LINK
    https://github.com/hamletmun/PSRedmine
	#>
	Param (
		[String]$name,
		[String]$type,
		[String]$status,
		[bool]$private,
		[String]$description,
		[String[]]$tags,
		[String]$systemMake,
		[String]$systemModel,
		[String]$operatingSystem,
		[String]$serialNumber,
		[String]$assetTag,
		[String]$periodsProcessing,
		[String]$parentHardware,
		[String]$hostname,
		[String[]]$programs,
		[String]$gscStatus,
		[String]$hardDriveSize,
		[String]$memory,
		[String]$memoryValitility,
		[String]$state,
		[String]$building,
		[String]$room,
		[String]$rackSeat,
		[String]$node,
		[String]$safeAndDrawerNumber,
		[string]$refreshDate,
		[String]$macAddress,
		[String]$notes,
		[PSCustomObject[]]$issues
	)
	
	$resource = Set-RedmineDB @PSBoundParameters
	$resource.create()
}

Function Get-RedmineDB
{
	<#
   .SYNOPSIS
    Get Redmine resource item by id
   .DESCRIPTION
    Get Redmine resource item by id
   .EXAMPLE
    Get-RedmineDB id 438
   .EXAMPLE
    Get-RedmineDB 398
   .LINK
    https://github.com/hamletmun/PSRedmine
	#>
	Param (
		[Parameter(Mandatory = $true)]
		[ResourceType]$type,
		[Parameter(Mandatory = $true)]
		[String]$id
	)
	
	$Redmine.db.get($id)
}

Function Edit-RedmineDB
{
	<#
   .SYNOPSIS
    Edit a Redmine resource
   .DESCRIPTION
    Edit a Redmine resource
   .EXAMPLE
    Edit-RedmineDB project -id test13 -description 'change description'
   .EXAMPLE
    Edit-RedmineDB version -id 406 -due_date 2018-09-29
   .EXAMPLE
    Edit-RedmineDB issue -id 29551 -version_id 406
   .LINK
    https://github.com/hamletmun/PSRedmine
	#>
	Param (
		[Parameter(Mandatory = $true)]
		[String]$id,
		[String]$name,
		[String]$type,
		[String]$status,
		[bool]$private,
		[String]$description,
		[String[]]$tags,
		[String]$systemMake,
		[String]$systemModel,
		[String]$operatingSystem,
		[String]$serialNumber,
		[String]$assetTag,
		[String]$periodsProcessing,
		[String]$parentHardware,
		[String]$hostname,
		[String[]]$programs,
		[String]$gscStatus,
		[String]$hardDriveSize,
		[String]$memory,
		[String]$memoryValitility,
		[String]$state,
		[String]$building,
		[String]$room,
		[String]$rackSeat,
		[String]$node,
		[String]$safeAndDrawerNumber,
		[string]$refreshDate,
		[String]$macAddress,
		[String]$notes,
		[PSCustomObject[]]$issues
	)
	
	$resource = Set-RedmineDB @PSBoundParameters
	$resource.id = $id
	$resource.update()
}

Function Remove-RedmineDB
{
	<#
   .SYNOPSIS
    Remove a Redmine resource
   .DESCRIPTION
    Remove a Redmine DB Entry.
   .EXAMPLE
    Remove-RedmineDB id 29551
   .EXAMPLE
    Remove-RedmineDB 29551
   .LINK
    https://github.com/hamletmun/PSRedmine
	#>
	Param (
		[Parameter(Mandatory = $true)]
		[String]$id
	)
	
	$Redmine.db.get($id).delete()
}

Function Decomission-RedmineDB
{
	<#
   .SYNOPSIS
    Decomission a Redmine resource
   .DESCRIPTION
    Decomission a Redmine DB Entry.
   .EXAMPLE
    Decomission-RedmineDB id 29551
   .EXAMPLE
    Decomission-RedmineDB 29551
   .LINK
    https://github.com/hamletmun/PSRedmine
	#>
	Param (
		[Parameter(Mandatory = $true)]
		[String]$id
	)
	
	$Parameters = @{
        building = ""
        room = ""
		programs = 'None'
	}
	
	$resource = Set-RedmineDB @Parameters
	$resource.id = $id
	
	Write-Debug 'Decomission-RedmineDB Parameters'
	Write-Debug @Parameters
#	$resource.update()
}

Function Get-RedmineDBIdByName
{
	Param (
		[String]$project_id
	)
	$Response = Search-RedmineDB membership -project_id (Get-RedmineDB project $project_id).id
	$Response.Keys | ForEach-Object { $Response[$_].user } | Sort-Object name
}

Function Add-RedmineWatcher
{
	Param (
		[Int]$issue_id,
		[Int[]]$watchers
	)
	ForEach ($user_id in $watchers)
	{
		$JSON = '{ "user_id": "' + $user_id + '" }'
		$Response = Invoke-RestMethod -Method POST -ContentType application/json -URI "$($Redmine.Server)/issues/$issue_id/watchers.json?key=$Script:APIKey" -Body $JSON
	}
}

Function Remove-RedmineWatcher
{
	Param (
		[Int]$issue_id,
		[Int[]]$watchers
	)
	ForEach ($user_id in $watchers)
	{
		$Response = Invoke-RestMethod -Method DELETE -URI "$($Redmine.Server)/issues/$issue_id/watchers/$user_id.json?key=$Script:APIKey"
	}
}

#endregion

