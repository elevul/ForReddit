#This script assumes you have already installed and connected to the MSOnline Services and ActiveDirectory modules.
#Written by spartan, optimized by elevul
#Importing necessary modules
Import-Module ActiveDirectory
Import-module MSOnline

#Informing user
Write-Warning "THIS SCRIPT WILL COMPLETELY TERMINATE AND DISABLE THE USER ENTERED BELOW. YOU WILL BE PROMPTED TO CONFIRM EACH ACTION."

# Identify all the directories/paths
$RootDir = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)

#Starting logging
$date = Get-Date -Format "dd-MM-yyyy-HH-mm"
Start-Transcript -path "$RootDir\DisableAccount-$date.log" -append
$ProgressPreference = 'SilentlyContinue' 

#Getting script executor:
$CU = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

#Asking for username and validating with some regex
$regexuser = "([a-zA-Z]*)(\.)([a-zA-Z]*)"
do {
  $User = Read-Host -Prompt "Enter AD username (usually first.last) of user being terminated"
} while ($user -notmatch $regexuser)

#Asking for UPN and validating
$regexupn = "(" + [regex]::escape($User) + ")" + "(\@)([a-zA-Z]*)(\.)([a-zA-Z]{1,3})"
do {
  $UPN = Read-Host -Prompt "Enter UPN of user being terminated"
} while ($UPN -notmatch $regexupn)

#Starting a Try-Catch loop to ensure errors stop the execution of the script
try {
  #Starting execution
  Disable-ADAccount -Identity $User -Confirm
  Get-ADUser -Identity $User -Properties MemberOf | ForEach-Object {
    $_.MemberOf | Remove-ADGroupMember -Members $_.DistinguishedName -Confirm:$false
  }
  Set-ADUser -Identity $User -Description "Account $User disabled on $date by $CU"
  Set-ADAccountPassword -Identity $User -Reset -Confirm

  #Checking everything went correctly and reporting on current status
  $Userresult = Get-ADUser -Identity $User -Properties * | Select-Object Canonicalname, Name, SamAccountName, DisplayName, UserPrincipalName, DistinguishedName, Enabled, LastLogonDate, PasswordLastSet, Memberof, PrimaryGroup, Description
  if ($Userresult.Enabled -eq $false) {
    Write-Output "Account is successfully disabled. Current status:"
    $Userresult
  }
  else {
    throw "Something went wrong. Status: $Userresult"
  }

  #Starting online execution
  Set-MsolUser -UserPrincipalName $UPN -BlockCredential $true
  (Get-MsolUser -UserPrincipalName $UPN).licenses.AccountSkuId |
  ForEach-Object -Process {
    Set-MsolUserLicense -UserPrincipalName $UPN -RemoveLicenses $_
  }

  #Checking everything went correctly and reporting on current status
  $UPNresult = Get-MsolUser -UserPrincipalName $UPN | Select-Object -property UserPrincipalName, DisplayName, IsLicensed, Licenses, BlockCredential
  if ((-not $UPNresult.IsLicensed) -and ($UPNresult.BlockCredential -eq $true)) {
    Write-Output "Termination Complete. Current Status:"
    $UPNresult
  }
  else {
    throw "Something went wrong. Status: $UPNresult"    
  }
  
}
catch {
  $_
}

#Stop logging
Stop-Transcript
