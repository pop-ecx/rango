## Description
Creates a new logon session with supplied credentials and impersonates it on the
current thread. network auth will use the new identity. default logon type 9 (logon32_logon_new_credentials).

### Parameters
`username`
 * the user you want to impersonate.

 `domain`
 * the domain of the user you want to impersonate. Use `.` for local accounts.

`password`
* the password of the user you want to impersonate. If it is a local account, make sure the password is correct.

`logon_type`
* the logon type to use. Default is 9 (logon32_logon_new_credentials). For more info on logon types, see https://learn.microsoft.com/en-us/windows-server/identity/securing-privileged-access/reference-tools-logon-types


## Usage

To best use this just run the command `maketoken` with no params. A popup will ask you for the parameters.

### Examples

```
maketoken test . P@ssw0rd 9
```

> Caution: maketoken submits plaintext credentials via LogonUserW. Generates Event ID 4624 + 4648 on the authenticating DC. Ensure operational need justifies credential exposure. May be OPSEC sensitive.
 
