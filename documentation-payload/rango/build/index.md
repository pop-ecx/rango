## Summary
Rango comes with a couple of options to choose from when building the agent.

## Build Options
### Initial Build Options
- `Operating System`: This just chooses the target operating system for the agent. The options are `linux` and `windows`.
- `Payload type`: This is just the name of the agent that will be displayed in the Mythic C2 interface. The option is `rango`.

### Payload Build Options
- `In mem or disk`: This option chooses whether the agent will be loaded in memory or written to disk upon unpacking/execution. The options are `in-mem`, `disk` or `None`.
- `OS`: Operating system for the agent. Options are `linux` and `windows`.
- `Out`: This chooses the output format for the agent. The option right now is `exe` which just means an executable file. The idea is to extend to other output formats like `so` and `dll` in the future.
- `Pack with ZYRA`: This option chooses whether to pack the agent with ZYRA, currently only supported for Linux agents. The options are `true` and `false`, default is `false`.
- `Packing_key`: This is the key used for packing the agent with ZYRA. Default is `ff`.
- `Release_type`: This option chooses the optimization level for the agent. The options are `debug`, `safe`, `fast` and `false`. default is `small`. The idea is to use debug for development and testing, safe for release candidates, and fast or small for actual engagements depending on use case.

### Command Build Options
Rango uses compile time flags to determine which commands are available to the agent. To add a command to the agent, 
you need to add it to the `commands in payload` list in the build UI. You select commands from the `commands available` list.

### profile parameters
Rango uses the http profile. The build parameters supported by Rango are:

- `AESPSK`: uses `aes256_hmac` or`none` for encryption. If you want to use encryption, you need to set this to `aes256_hmac` else it will be `none`.
- `callback_host`: callback host for the agent for example `https://mythic.local`
- `callback_interval`: callback interval for the agent in seconds.
- `callback_jitter`: callback jitter for the agent in percentage.
- `callback_port`: callback port for the agent.
- `killdate`: kill date for the agent in format `DD-MM-YYYY`.
