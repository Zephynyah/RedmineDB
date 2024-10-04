<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.241
	 Created on:   	10/4/2024 3:50 AM
	 Created by:   	Jason Hickey
	 Organization: 	House of Powershell
	 Filename:     	New-Credential.ps1
	===========================================================================
	.DESCRIPTION
		A description of the file.
    .NOTES
    https://www.powershellgallery.com/packages/PrtgAPI/0.9.19/Content/Functions%5CNew-Credential.ps1
#>


function New-Credential
{
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "", Scope = "Function")]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingUserNameAndPassWordParams", "", Scope = "Function")]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Scope = "Function")]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "", Scope = "Function")]
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$UserName,
		[string]$Password
	)
	
	if (![string]::IsNullOrEmpty($Password))
	{
		$secureString = ConvertTo-SecureString $Password -AsPlainText -Force
	}
	else
	{
		$secureString = New-Object SecureString
	}
	
	New-Object System.Management.Automation.PSCredential -ArgumentList $UserName, $secureString
}
