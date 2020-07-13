﻿#Requires -Version 5.0
param (
	[string]$pkgXML = (Join-Path (Split-Path -parent $MyInvocation.MyCommand.Definition) 'packages.xml') ,
	[string]$personalPkgXML,
	[switch]$thoroughList,
	[switch]$skipRepoCheck,
	[switch]$skipRepoMove
)
$ErrorActionPreference = 'Stop'

#needed for accessing dotnet zip functions
Add-Type -AssemblyName System.IO.Compression.FileSystem

#needed to use [Microsoft.PowerShell.Commands.PSUserAgent] when running in pwsh
Import-Module Microsoft.PowerShell.Utility

#default dot source for needed functions
. (Join-Path (Split-Path -parent $MyInvocation.MyCommand.Definition) 'PkgFunctions-normal.ps1')
. (Join-Path (Split-Path -parent $MyInvocation.MyCommand.Definition) 'PkgFunctions-special.ps1')
. (Join-Path (Split-Path -parent $MyInvocation.MyCommand.Definition) 'OtherFunctions.ps1')

#Install nuget package provider if not already installed
$null = Get-PackageProvider -Name nuget -Force

#Check for personal-packages.xml in user profile
#todo, add more options for filenames
if (!($IsWindows) -or ($IsWindows -eq $true)) {
	$profileXMLPath = [IO.Path]::Combine($env:APPDATA, "choco-remixer", "personal-packages.xml" )
} elseif ($IsLinux -eq $true) {
	$profileXMLPath = [IO.Path]::Combine( $env:HOME, ".config" , "choco-remixer", "personal-packages.xml" )
} elseif ($IsMacOS -eq $true) {
	Throw "MacOS not supported"
} else {
	Throw "Something went wrong detecting OS"
}

if ((Get-Command "choco" -ea 0) -eq $null) {
	Write-Error "Did not find Choco, please make sure it is installed and on path"
	Throw
}

if ([Environment]::GetEnvironmentVariable("ChocolateyInstall") -eq $null)  {
	Write-Error "Did not find ChocolateyInstall environment variable, please make sure it exists"
	Throw
}



#select which personal-packages.xml to use
if (!($PSBoundParameters.ContainsKey('personalPkgXML'))) {

	$gitXMLPath = (Join-Path (Split-Path -parent $MyInvocation.MyCommand.Definition) 'personal-packages.xml')
	if (Test-Path $profileXMLPath) {
		$personalPkgXML = $profileXMLPath
	} elseif (Test-Path $gitXMLPath) {
		$personalPkgXML = $gitXMLPath
	} else {
		Throw "Cannot find personal-packages.xml, please specify path to it"
	}
	
} elseif (!(Test-Path $personalPkgXML)) {
	throw "personal-packages.xml not found, please specify valid path"
}

$personalPkgXMLPath = (Resolve-Path $personalPkgXML).path

if (!(Test-Path $pkgXML)) {
	throw "packages.xml not found, please specify valid path"
}




#changeme?
[XML]$packagesXMLcontent = Get-Content $pkgXML
[XML]$personalpackagesXMLcontent = Get-Content $personalPkgXMLPath

$options = $personalpackagesXMLcontent.mypackages.options
#add these to parameters?
$searchDir        = $options.searchDir.tostring()
$workDir          = $options.workDir.tostring()
$dropPath         = $options.DropPath.tostring()
$useDropPath      = $options.useDropPath.tostring()
$writePerPkgs     = $options.writePerPkgs.tostring()
$pushURL          = $options.pushURL.tostring()
$pushPkgs         = $options.pushPkgs.tostring()
$repoCheck        = $options.repoCheck.tostring()
$publicRepoURL    = $options.publicRepoURL.tostring()
$privateRepoURL   = $options.privateRepoURL.tostring()
$privateRepoCreds = $options.privateRepoCreds.tostring()
$repoMove         = $options.repoMove.tostring()
$proxyRepoURL     = $options.proxyRepoURL.tostring()
$proxyRepoCreds   = $options.proxyRepoCreds.tostring()
$moveToRepoURL    = $options.moveToRepoURL.tostring()


if (!(Test-Path $searchDir)) {
	throw "$searchDir not found, please specify valid searchDir"
}
if (!(Test-Path $workDir)) {
	throw "$workDir not found, please specify valid workDir"
}
if ($workDir.ToLower().StartsWith($searchDir.ToLower())) {
	throw "workDir cannot be a sub directory of the searchDir"
}

if ($useDropPath -eq "yes") {
	if (!(Test-Path $dropPath)) {
		throw "Drop path not found, please specify valid path"
	}
	
	for (($i= 0); ($i -le 12) -and ($null -ne $(Get-ChildItem -Path $dropPath -Filter "*.nupkg")) ; $i++ ) {
		Write-Output "Found files in the drop path, waiting 15 seconds for them to clear"
		Start-Sleep -Seconds 15
	}
	
	if ($null -ne $(Get-ChildItem -Path $dropPath -Filter "*.nupkg")) {
		Write-Warning "There are still files in the drop path"
	}
} elseif ($useDropPath -eq "no") { 
} else {
	Throw "bad useDropPath value in personal-packages.xml, must be yes or no"
}

if ("no","yes" -notcontains $writePerPkgs) {
	Throw "bad writePerPkgs value in personal-packages.xml, must be yes or no"
}

if ($pushPkgs -eq "yes") {
	if ($null -eq $pushURL) {
		Throw "no pushURL in personal-packages.xml"
	}
	try { $page = Invoke-WebRequest -UseBasicParsing -Uri $pushURL -method head } 
	catch { $page = $_.Exception.Response }

	if ($null -eq $page.StatusCode) {
		Throw "bad pushURL in personal-packages.xml"
	} elseif ($page.StatusCode  -eq  200) { 
	} else {
		Write-Verbose "pushURL exists, but did not return ok. This is expected if it requires authentication"
	}
	
	$apiKeySources = Get-ChocoApiKeysUrls
	
	if ($apiKeySources -notcontains $pushURL) {
		Write-Verbose "Did not find a API key for $pushURL"
	}
	
} elseif ($pushPkgs -eq "no") { } else {
	Throw "bad pushPkgs value in personal-packages.xml, must be yes or no"
}



if (($repomove -eq "yes") -and (!($skipRepoMove))) {
	
	
	if ($null -eq $moveToRepoURL) {
		Throw "no moveToRepoURL in personal-packages.xml"
	}
	try { $page = Invoke-WebRequest -UseBasicParsing -Uri $moveToRepoURL -method head } 
	catch { $page = $_.Exception.Response }

	if ($null -eq $page.StatusCode) {
		Throw "bad moveToRepoURL in personal-packages.xml"
	} elseif ($page.StatusCode  -eq  200) { 
		Write-Verbose "moveToRepoURL valid"
	} else {
		Write-Verbose "moveToRepoURL exists, but did not return ok. This is expected if it requires authentication"
	}

	if (!($pushPkgs)) {
		$apiKeySources = Get-ChocoApiKeysUrls
	}
	
	if ($apiKeySources -inotcontains $moveToRepoURL) {
		Write-Warning "Did not find a API key for $moveToRepoURL"
	}
	
	
	if ($null -eq $proxyRepoCreds) {
		Throw "proxyRepoCreds cannot be empty, please change to an explicit no, yes, or give the creds"
	} elseif ($proxyRepoCreds -eq "no") { 
		$proxyRepoHeaderCreds = @{ }
		#todo, fix later things that want creds
		Throw "not implemented yet, you could remove this line and see how it goes"
	} elseif ($proxyRepoCreds -eq "yes") {
		#todo, implement me
		Throw "not implemented yes, later will give option to give creds here"
	} else {
		$proxyRepoCredsBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($proxyRepoCreds))
		$proxyRepoHeaderCreds = @{ 
			Authorization = "Basic $proxyRepoCredsBase64"
		}
		$credArray = $proxyRepoCreds -split ":"
		$passwd = $credArray[1] | ConvertTo-SecureString -Force -AsPlainText
		$proxyRepoPSCreds = New-Object -TypeName System.Management.Automation.PSCredential -argumentlist $credArray[0],$passwd
		
		$credArray = $null
		$passwd = $null
	}

	if ($null -eq $proxyRepoURL) {
		Throw "no proxyRepoURL in personal-packages.xml"
	}
	
	try { 
		$page = Invoke-WebRequest -UseBasicParsing -Uri $proxyRepoURL -method head -Headers $proxyRepoHeaderCreds
	} catch { 
		$page = $_.Exception.Response
	}
	
	if ($null -eq $page.StatusCode) {
		Throw "bad proxyRepoURL in personal-packages.xml"
	} elseif ($page.StatusCode  -eq  200) {
		Write-Verbose "proxyRepoURL valid"
	} else {
		Write-Warning "proxyRepoURL exists, but did not return ok. If it requires credentials, please check that they are correct"
	}
	
	
	
	
	
	
	
<# 	$systemTempDir = [System.IO.Path]::GetTempPath()
	$tempConfigFile = Join-Path $systemTempDir "deleteme-$($(New-Guid)).config"
	if (Test-Path $tempConfigFile) {
		Remove-Item $tempConfigFile -Force -ea 0 
	}
	Set-Content -Path $tempConfigFile -Value "<configuration>`n</configuration>"
	
	$packageSources = get-packagesource -ProviderName nuget
	
	if ($packageSources.Name -contains "remixerProxyRepo") {
		Unregister-PackageSource -Name remixerProxyRepo
	}
	
	$null = Register-PackageSource -Name remixerProxyRepo -Location $publicRepoURL -Trusted -Force -ConfigFile $tempConfigFile -ProviderName nuget -Credential $proxyRepoPSCreds 
	
	Find-Package -Source remixerProxyRepo -IncludeDependencies -Credential $proxyRepoPSCreds

	Unregister-PackageSource -Name remixerProxyRepo
	Remove-Item $tempConfigFile -Force -ea 0 #>
	
} elseif ($repoMove -eq "no") { 
} else {
	if (!($skipRepoMove)) {
		Throw "bad repoMove value in personal-packages.xml, must be yes or no"
	}
}


if (($repocheck -eq "yes") -and (!($skipRepoCheck))) {

	if ($null -eq $publicRepoURL) {
		Throw "no publicRepoURL in personal-packages.xml"
	}
	try { $page = Invoke-WebRequest -UseBasicParsing -Uri $publicRepoURL -method head } 
	catch { $page = $_.Exception.Response }

	if ($null -eq $page.StatusCode) {
		Throw "bad publicRepoURL in personal-packages.xml"
	} elseif ($page.StatusCode  -eq  200) { 
	} else {
		Write-Warning "publicRepoURL exists, but did not return ok. This is expected if it requires authentication"
	}

	if ($null -eq $privateRepoCreds) {
		Throw "privateRepoCreds cannot be empty, please change to an explicit no, yes, or give the creds"
	} elseif ($privateRepoCreds -eq "no") { 
		$privateRepoHeaderCreds = @{ }
		#todo, fix later things that want creds
		Throw "not implemented yet, you could remove this line and see how it goes"
	} elseif ($privateRepoCreds -eq "yes") {
		#todo, implement me
		Throw "not implemented yes, later will give option to give creds here"
	} else {
		$privateRepoCredsBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($privateRepoCreds))
		$privateRepoHeaderCreds = @{ 
			Authorization = "Basic $privateRepoCredsBase64"
		}
		$credArray = $privateRepoCreds -split ":"
		$passwd = $credArray[1] | ConvertTo-SecureString -Force -AsPlainText
		$privateRepoPSCreds = New-Object -TypeName System.Management.Automation.PSCredential -argumentlist $credArray[0],$passwd
		
		$credArray = $null
		$passwd = $null
	}

	if ($null -eq $privateRepoURL) {
		Throw "no privateRepoURL in personal-packages.xml"
	}
	try { 
		$page = Invoke-WebRequest -UseBasicParsing -Uri $privateRepoURL -method head -Headers $privateRepoHeaderCreds
	} catch { $page = $_.Exception.Response }
	
	if ($null -eq $page.StatusCode) {
		Throw "bad privateRepoURL in personal-packages.xml"
	} elseif ($page.StatusCode  -eq  200) { 
	} else {
		Write-Warning "privateRepoURL exists, but did not return ok. If it reques credentials, please check that they are correct"
	}
	
	$toSearchToInternalize = $personalpackagesXMLcontent.mypackages.toInternalize.id
	$toInternalizeCompare = Compare-Object -ReferenceObject $packagesXMLcontent.packages.custom.pkg.id -DifferenceObject $toSearchToInternalize.innertext | Where-Object SideIndicator -eq "=>"
	
	
	if ($toInternalizeCompare.inputObject) {
		Throw "$($toInternalizeCompare.InputObject) not found in packages.xml"; 
	}
	
	$systemTempDir = [System.IO.Path]::GetTempPath()
	$tempConfigFile = Join-Path $systemTempDir "deleteme-$($(New-Guid)).config"
	if (Test-Path $tempConfigFile) {
		Remove-Item $tempConfigFile -Force -ea 0 
	}
	Set-Content -Path $tempConfigFile -Value "<configuration>`n</configuration>"
	
	$packageSources = get-packagesource -ProviderName nuget
	
	if ($packageSources.Name -contains "remixerpublicRepo") {
		Unregister-PackageSource -Name remixerPublicRepo 
	}
	 
	if ($packageSources.Name -contains "remixerPrivateRepo") {
		Unregister-PackageSource -Name remixerPrivateRepo 
	}
	
	$null = Register-PackageSource -Name remixerPublicRepo -Location $publicRepoURL -Trusted -Force -ConfigFile $tempConfigFile -ProviderName nuget
	$null = Register-PackageSource -Name remixerPrivateRepo -Location $privateRepoURL -Trusted -Force -ConfigFile $tempConfigFile -ProviderName nuget -Credential $privateRepoPSCreds

	
	$toSearchToInternalize | ForEach-Object {
		Write-Verbose "Comparing repo versions of $($_.InnerText)"
		if ($_.prerelease -eq "true") {
			$privateRepoPkgInfo = Find-Package -ConfigFile $tempConfigFile -Source remixerPrivateRepo -Name $_.InnerText -AllowPrereleaseVersions -Credential $privateRepoPSCreds -AllVersions
			$publicRepoPkgInfo  = Find-Package -ConfigFile $tempConfigFile -Source remixerPublicRepo  -Name $_.InnerText -AllowPrereleaseVersions  
		} else {
			$privateRepoPkgInfo = Find-Package -ConfigFile $tempConfigFile -Source remixerPrivateRepo -Name $_.InnerText -Credential $privateRepoPSCreds -AllVersions
			$publicRepoPkgInfo  = Find-Package -ConfigFile $tempConfigFile -Source remixerPublicRepo  -Name $_.InnerText 
		}
		
		if ($privateRepoPkgInfo.Version -notcontains $publicRepoPkgInfo.Version) {
			Write-Host "$($_.InnerText) out of date on private repo, found version $($publicRepoPkgInfo.Version)"
			
			$saveDir = Join-Path $searchDir $_.innertext
			if (!(Test-Path $saveDir)) {
				$null = mkdir $saveDir
			}
			
			$null = Save-Package -ConfigFile $tempConfigFile -Path $saveDir -InputObject $publicRepoPkgInfo -AllowPrereleaseVersions
			
		}
	}
		
	Remove-Item $tempConfigFile -Force -ea 0
	
	Unregister-PackageSource -Name remixerPublicRepo 
	Unregister-PackageSource -Name remixerPrivateRepo 
	
} elseif ($repoCheck -eq "no") { 
} else {
	if (!($skipRepoCheck)) {
		Throw "bad repoCheck value in personal-packages.xml, must be yes or no"
	}
}

#need this as normal PWSH arrays are slow to add an element, this can add them quickly
[System.Collections.ArrayList]$nupkgObjArray = @()

#todo, make able to do multiple search dirs
#add switch here to select from other options to get list of nupkgs
if ($thoroughList) {
	#Get-ChildItem $searchDir -File -Filter "*adopt*.nupkg" -Recurse
	$nupkgArray = Get-ChildItem -File $searchDir -Filter "*.nupkg" -Recurse
} else {
	#filters based on folder name, therefore less files to open later and therefore faster, but may not be useful in all circumstances. 
	$nupkgArray = (Get-ChildItem -File $searchDir  -Filter "*.nupkg" -Recurse) | Where-Object { 
		($_.directory.name -notin $packagesXMLcontent.packages.internal.id) `
		-and ($_.directory.Parent.name -notin $packagesXMLcontent.packages.internal.id) `
		-and ($_.directory.name -notin $personalpackagesXMLcontent.mypackages.personal.id) `
		-and ($_.directory.Parent.name -notin $personalpackagesXMLcontent.mypackages.personal.id) `
		}
}


#unique needed to workaround a bug if accessing searchDir from a samba share where things show up twice if there are directories with the same name but different case.
$nupkgArray | select -Unique | ForEach-Object {
	$nuspecDetails = Get-NuspecVersion -NupkgPath $_.fullname
	$nuspecVersion = $nuspecDetails[0]
	$nuspecID = $nuspecDetails[1]
	$internalizedVersions = ($personalpackagesXMLcontent.mypackages.internalized.pkg | Where-Object {$_.id -ieq "$nuspecID" }).version

	if ($internalizedVersions -icontains $nuspecVersion) {
		#package is internalized by user
		#add something here? verbose logging?
		
	} elseif ($packagesXMLcontent.packages.notImplemented.id -icontains $nuspecID) {
		Write-Output "$nuspecID $nuspecVersion  not implemented, requires manual internalization" #$nuspecVersion
		#package is not supported, due to bad choco install script that is hard to internalize
		#add something here? verbose logging?

	} elseif ($personalpackagesXMLcontent.mypackages.personal.id -icontains $nuspecID) {
		#package is personal custom package and is internal
		#add something here? verbose logging?

	} elseif ($packagesXMLcontent.packages.internal.id -icontains $nuspecID) {
		#package from chocolatey.org is internal by default
		#add something here? verbose logging?

 	} elseif ($packagesXMLcontent.packages.custom.pkg.id -icontains $nuspecID) {

		 $installScriptDetails = Get-ZippedInstallScript -NupkgPath $_.fullname
		 $status = $installScriptDetails[0]
		 $installScript = $installScriptDetails[1]

		if ($installScriptDetails[0] -eq "noscript") {
			Write-Output "You may want to add $nuspecID $nuspecVersion to the internal list"
			#Write-Output '<id>'$nuspecID'</id>'

		} else {

			$idDir      = (Join-Path $workDir $nuspecID)
			$versionDir = (Join-Path $idDir $nuspecVersion)
			$newpath    = (Join-Path $versionDir $_.name)
			$customXml  = $packagesXMLcontent.packages.custom.pkg | where-object id -eq $nuspecID
			$toolsDir   = (Join-Path $versionDir "tools")

			if (($null -eq $customXml.functionName) -or ($customXml.functionName -eq "")) {
				Throw "Could not find function for $nuspecID"
			}
			
			$obj = [PSCustomObject]@{
				nupkgName     = $_.name
				origPath      = $_.fullname
				version       = $nuspecVersion
				nuspecID      = $nuspecID
				status        = $status
				idDir         = $idDir
				versionDir    = $versionDir
				toolsDir      = $toolsDir
				newPath       = $newpath
				needsToolsDir = $customXml.needsToolsDir
				functionName   = $customXml.functionName
				needsStopAction   = $customXml.needsStopAction
				installScriptOrig = $installScript
				installScriptMod  = $installScript

			}

			$nupkgObjArray.add($obj) | Out-Null

			Write-Output "Found $nuspecID $nuspecVersion to internalize"
			#Write-Output $_.fullname
		}
		
	} else {
		
		Write-Output "$nuspecID $nuspecVersion is new, id unknown"
	}
}

#don't need the list anymore, use nupkgObjArray
$nupkgArray = $null

#Setup the directories for internalizing
Foreach ($obj in $nupkgObjArray) {
	try {
	
		if (!(Test-Path $obj.idDir)) {
			$null = mkdir $obj.idDir
		}

		if (Test-Path $obj.versionDir) {
			$null = New-Item -Path $obj.versionDir -Name "temp.txt" -ItemType file -ea 0
			Remove-Item -ea 0 -Force -Recurse -Path (Get-ChildItem -Path $obj.versionDir -Exclude "tools","*.exe","*.msi","*.msu","*.zip")
		} else {
			$null = mkdir $obj.versionDir
		}

		if (Test-Path $obj.toolsDir) {
			$null = New-Item -Path $obj.toolsDir -Name "temp.txt" -ItemType file -ea 0
			Remove-Item -ea 0 -Force -Recurse -Path (Get-ChildItem -Path $obj.toolsDir -Exclude "*.exe","*.msi","*.msu","*.zip")
		} else {
			$null = mkdir $obj.toolsDir
		}

		#Copy-Item $obj.OrigPath $obj.versionDir 
		$obj.status = "setup"
	} catch {
		$obj.status = "not-setup"
		Write-Host "failed to setup" $obj.nuspecID $obj.version
		Remove-Item -ea 0 -Force -Recurse -Path $obj.versionDir
	}
	
}

Foreach ($obj in $nupkgObjArray) {
	if ($obj.status -eq "setup") {
		#Try { 
			Write-Host "Starting " $obj.nuspecID
			Extract-Nupkg -obj $obj  

			#Write-Output $obj.functionName
			$tempFuncName = $obj.functionName
			$tempFuncName = $tempFuncName + ' -obj $obj'
			Invoke-Expression $tempFuncName
			$tempFuncName = $null

			Write-UnzippedInstallScript -obj $obj

			#start choco pack in the correct directory
			$packcode = Start-Process -FilePath "choco" -ArgumentList 'pack -r' -WorkingDirectory $obj.versionDir -NoNewWindow -Wait -PassThru
			
			if ($packcode.exitcode -ne "0") {
				$obj.status = "pack failed"
			} else {
				$obj.status = "internalized"
			}
		#} Catch {
		#	$obj.status = "internalization failed"
		#}
	}
}



Foreach ($obj in $nupkgObjArray) {
	if ($obj.status -eq "internalized") {
		#Try {
			if ($useDropPath -eq "yes") {
				Write-Verbose "coping $($obj.nuspecID) to drop path"
				Copy-Item (Get-ChildItem $obj.versionDir -Filter "*.nupkg").fullname $dropPath
			}
			if ($writePerPkgs -eq "yes") {
				Write-Verbose "writing $($obj.nuspecID) to personal packages as internalized"
				Write-PerPkg -personalPkgXMLPath $personalPkgXMLPath -Version $obj.version -nuspecID $obj.nuspecID
			}
			if ($pushPkgs -eq "yes") {
				Write-Output "pushing $($obj.nuspecID)"
				$pushArgs = 'push -f -r -s ' + $pushURL
				$pushcode = Start-Process -FilePath "choco" -ArgumentList $pushArgs -WorkingDirectory $obj.versionDir -NoNewWindow -Wait -PassThru
			}
			
			if (($pushPkgs -eq "yes") -and ($pushcode.exitcode -ne "0")) {
				$obj.status = "push failed"
			} else {
				$obj.status = "done"
			}
		#} Catch {
		#	$obj.status = "failed copy or write"
		#} 
	} else {
		
	}
}



$nupkgObjArray | ForEach-Object {
	Write-Host $_.nuspecID $_.Version $_.status
}
#Write-Output "completed"

# Get-ChildItem -Recurse -Path '..\.nugetv2\F1' -Filter "*.nupkg" | % { Copy-Item $_.fullname . }

#needs log4net 2.0.3, load net40-full dll
#add-type -Path ".\chocolatey.dll"
#add-type -Path ".\net40-full\log4net.dll"
#[chocolatey.StringExtensions]::to_lower("ASDF")
