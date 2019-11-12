# Powershell-AD-to-SCIM

Not the cleanest code - but due to security constraints I needed to create users in a SCIM enabled application (Proxyclick)
from an Active directory group membership.

Get-ADUser with an LDAP filter allows for large groups to be returned (over 10,000 users )
Get-ADGroupMember <groupname> generates errors when you get over a few thousand users in a group
