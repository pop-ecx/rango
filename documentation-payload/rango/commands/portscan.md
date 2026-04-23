## Description
Perform a port scan on the target host.

### Parameters
`hosts`
* Comma-separated list of hosts to scan. For example: `192.168.2.1, 192.168.2.2`
* You can also provide a single host. For example: `192.168.2.1`
* It is also possible to specify a CIDR range. For example: `192.168.2.1/24`

`ports`
 * Comma-separated list of ports to scan. For example: `80,443,8080`
 * There is already a default list of ports if the parameter is not provided.

`timeout`
 * Timeout in seconds for each port scan. Default is 500 milliseconds.

## Usage

```
portscan -[hosts] [hosts] -[ports] [ports] -[timeout] [timeout]
```

### Examples

```
portscan -hosts 192.168.1.0/24 -ports 22,80,443 -timeout 500
```

> Caution: This is still experimental. Considering other concurrency options to make it more efficient.
