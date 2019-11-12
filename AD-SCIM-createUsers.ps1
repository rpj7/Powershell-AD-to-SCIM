#R Johnson 2019
#Active Directory to ProxyClick directory via SCIM API
#default SSL connections to TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-module ActiveDirectory

$logfile = "logfile.txt"
Function LogWrite
{
   Param ([string]$logstring)
   $a = Get-Date
   $writetoLog = "$($a.ToShortDateString())	$($a.ToShortTimeString())	$logstring"
   Write-Host -ForegroundColor Green $writetoLog
   Add-content .\$Logfile -value $writetoLog
}

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Authorization", 'Bearer <Put your bearer token here>')
$URI = " https://api.proxyclick.com/scim/v1/Users"


function getProxyClickUsers ($start, $count){
    $PCUsers=Invoke-RestMethod "$($URI)?startindex=$start&count=$count" -Method Get  -Headers $headers
    $PCUarr=@()
    foreach ($PCUser in $PCUsers.Resources) {
        $PCUarr+=$PCUser.emails.value
    }
    return $PCUarr
}

#if you have over 5000 users you cant fetch them all at once!
function getAllProxyClickUsers {
    $st=1 # start at record 1
    $page=500 # records to return with each query
    $lastuser=$false
    $allu=@()
    do {
        $tmpu=getProxyClickUsers $st $page
        if ($tmpu -eq $null) {
            $lastuser=$true
        } else {
            $allu+=$tmpu
            $st+=$page
        }


    } until ($lastuser-eq $true)
    return $allu
}

function getADusers{
    #Large groups are not handled very well with GET-ADGroupMember - GET-ADUser with a filter hapily returns over 10,000 records...
    $ADU= Get-ADUser -LDAPFilter "(&(memberof=CN=SomeGroupName,OU=Groups,DC=domain,DC=local)(givenname=*)(mail=*))" -Properties mail
    return $ADU.mail
}

function CreateProxyClickUser ($mail) {
$createJSON = CreateUserJSON $mail
$PCUsers=Invoke-RestMethod $URI -Method Post -Headers $headers -Body $createJSON -ContentType "application/json"

}

function CreateUserJSON ($mail){
    #mail is the primary key for proxyclick and the script functions
    try {
    $Cre8Usr = Get-ADUser -LDAPFilter "(mail=$mail)" -Properties displayname,title,mobile,telephoneNumber
    $givenname=$Cre8Usr.givenname
    $sn=$Cre8Usr.surname
    $displayname = $Cre8Usr.displayname
    $title=$Cre8Usr.title
    }
    catch { return $false }
    
    # Rather crude check that the telephone numbers match the UK e.164 format for mobile numbers (start with a 7)
    # and telphone numbers that start with any number other than zero after the country code.
    if ($Cre8Usr.mobile -ne $null) {
        if ($Cre8Usr.mobile.replace(" ","") -match "^\+447\d{9}$") {$mobile=$Cre8Usr.mobile.replace(" ","")}
    } else {$mobile = ""}

    if ($Cre8Usr.telephoneNumber -ne $null) {
        if ($Cre8Usr.telephoneNumber.replace(" ","") -match "^\+44[1-9]\d{9}$") {$telephone=$Cre8Usr.telephoneNumber.replace(" ","")}
    } else {$telephone = ""}

    $payload =[pscustomobject]@{
        schemas=@("urn:scim:schemas:core:1.0")
        username="$mail"
        name=@{
            formatted= "$displayname"
            familyName= "$sn"
            givenName= "$givenname"
            }
        emails=@(@{
            value="$mail"
            type="work"
            primary="true"
            })
        phoneNumbers = @(
            @{
            type="work"
            value="$telephone"
            },@{
            type="mobile"
            value="$mobile"
            }
            )
        title="$title"
        active="true"
    }
return $payload|ConvertTo-Json
}

$ADUsers = getADusers
$Pusers = getallProxyClickUsers

#identify users in AD that need to be created
$Addusers = Compare-Object $ADUsers $Pusers |where {$_.SideIndicator -eq "<="} | % {$_.inputobject}
#identify users no longer in the group that could be removed (not implemented at the moment)
$Remusers = Compare-Object $ADUsers $Pusers |where {$_.SideIndicator -eq "=>"} | % {$_.inputobject}

foreach( $cre8 in $Addusers) {
LogWrite "create: $cre8"
CreateProxyClickUser $cre8
}
