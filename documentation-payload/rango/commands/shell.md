## Description

Run a shell command using `/bin/sh -c` on Linux
the output. This will not block the agent.

### Parameters

`command`
 * Shell command to run

## Usage
```
shell [command]
```
```
shell -command [command]
```

### Examples
```
shell id
```
```
shell uname -a
```


## OPSEC Considerations
{{% notice info %}}
This will spawn a child process which is visible in a process browser.
{{% /notice %}}
