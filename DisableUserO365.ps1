<#
    .Synopsis
        Create User Account and Mailbox in Exchange
    .Description
        Copies User Account if specified and creates mailbox and sets attributes such as manager, ProxyAddress etc
     .Example
     .\DisableUser.ps1
#>    

Import-Module ActiveDirectory

#Import VB
Add-Type -AssemblyName Microsoft.VisualBasic
$vb = [Microsoft.VisualBasic.Interaction]

$samaccount_to_disable = $vb::inputbox("Enter SAMAccount Name to Disable")
$Ticket_Number = $vb::inputbox("Enter Ticket Number")
#$Logfiletime = (Get-Date).ToString('dd-MM-yyyy')
#$logpath = "\\c$\Temp\DisabledUsersTest\ "
#$logfile = $logpath + "\$samaccount_to_disable.txt"
$datestamp = ((Get-Date).ToString('dd-MM-yyyy'))
$DisableOU = "OU=Disabled Users,OU=Users,DC=Domain,DC=com,DC=au"

### Check if user exists ###
$User = $(try {Get-ADUser $samaccount_to_disable -Properties SamAccountName,Name,distinguishenName,EmailAddress,Manager} catch {$null})
If ($User -eq $Null) {
    Write-Host "User doesn't Exist in AD, Please run script again"
}
Else {
    Write-Host "User found in AD, Continuing"
}

### Get Manager ###
$Manager = $(try {(Get-ADUser $User.manager).SamAccountName} catch {$null})

If ($Manager -eq $Null) {
    Write-Host "No Manager set,"
    $samaccount_to_forward_email = $vb::inputbox("Enter SAMAccount Name to forward email to")
}
Else {
    Write-Host "Manager set, Continuing"
}

### Check if Account is enabled ###
If ($User.Enabled -eq $True)
{
    Write-Host "Account Disabled, Continuing"
}
Else {
    Write-Host "Disabling Account.."
}

### Disable Account ##
Disable-ADAccount $samaccount_to_disable

### Set Discription ###
Set-ADUser $samaccount_to_disable -Description  "Disabled by IT Person - $Ticket_Number - $datestamp"

### Move User to Disabled Users OU ###
$User | Move-ADObject -TargetPath $DisableOU

### Get Distribution Groups ###
$Group_Memberships = Get-ADPrincipalGroupMembership -Identity $samaccount_to_disable  | Where-Object { $_.Name -notcontains "Domain Users" }

    If ($Group_Memberships -ne $null)

    {

    foreach($group in $Group_Memberships){

    if((Get-ADGroup $group).groupcategory -like "*distribution*")
        {
    
    # Remove each group membership from the user

    Write-Host -ForegroundColor Yellow    "Removing user from $($group.name) "

    $Group_Memberships | Remove-ADGroupMember -Members $samaccount_to_disable

    Write-Host -ForegroundColor Green "$($group.name) Removed"

        }
    }
}
   Else

    {

    Write-Host -ForegroundColor Red "Group Membership still exist please remove manually"

}

Write-Host -ForegroundColor Yellow "Connecting to Exchange Online"

### Connect to Exchange Online ###
$UserCredential = Get-Credential
$ExchangeSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $UserCredential -Authentication Basic -AllowRedirection
Import-PSSession $ExchangeSession
Pause

### Get Mailbox to Disable ###
Get-Mailbox $samaccount_to_disable

#### Convert to shared mailbox ####
Set-Mailbox $samaccount_to_disable -Type shared

### Confirm Mailbox Converted ###
Get-Mailbox -Identity $samaccount_to_disable | Format-List Name, *Type*

### Set eMail Forwarding ###
Set-Mailbox -Identity $samaccount_to_disable -ForwardingSMTPAddress "$samaccount_to_forward_email@domain.com.au"

Exit-PSSession

##### Get Office365 Credentials and Connect to Office365 PowerShell#####
$Office365_Credentials = Get-Credential
Import-Module MsOnline
Connect-MsolService -Credential $Office365_Credentials

##### Connect to  Office365 PowerShell if on another machine
#$O365Session = New-PSSession –ComputerName 
#Invoke-Command –Session $O365Session –ScriptBlock {Start-ADSyncSyncCycle -PolicyType Delta ; Import-Module MsOnline ; Connect-MsolService}
#Import-PSSession –Session $O365Session –allowclobber 

### Check if License Assigned  Office365 License###
Get-MsolUser -UserPrincipalName "$samaccount_to_disable@domain.com.au"

### Remove Office365 License###
Set-MsolUserLicense -UserPrincipalName "$samaccount_to_disable@domain.com.au" -RemoveLicenses "Company:ENTERPRISEPACK"

### Verify License Removed ###
Get-MsolUser -UserPrincipalName "$samaccount_to_disable@domain.com.au"

Exit-PSSession

##### Hide from Global Address List #####
Set-ADUser -Identity $samaccount_to_disable -Add @{msExchHideFromAddressLists = $True}

### Set MailNickname Attribute as SamAccountNamae
$samaccount_to_disable | Set-ADUser -Replace @{MailNickName = $samaccount_to_disable}

