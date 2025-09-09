## Rango 

<p align="center">
  <img src="https://github.com/pop-ecx/rango/blob/main/rango-2.png" />
</p>

Rango is a simple and basic Mythic C2 agent written in zig for GNU/Linux systems. 

It is designed as a proof of concept for testing zig as a language for writing C2 agents.

> I couldn't find a famous iguana character in pop culture to name my agent after so I went with rango.

## Features

- Basic C2 functionality
- Zig implementation
- Simple and easy to understand codebase
- No external dependencies
- Supports basic command execution

## Capabilities
- Execute ls on the target
- Execute basic commands

## Installation
To install go to your mythic directory and run:

```bash
sudo ./mythic-cli install github https://github.com/pop-ecx/rango.git
```


## Coming Features
- ~[ ]File upload and download~
- ~[ ] encryption~

> :warning: Rango is still not mature yet. Expect some bugs.


> Since the agent nor translator doesn't support encryption at the moment, you can achieve this using ssl in http profile. Make sure the ssl is from a trusted CA as zig's http client can be bitchy if it isn't.

> If you want some sort of packer/obfuscation you can try 3rd party tools like ZYRA.

If you want to use the agent pre-[writergate](https://ziglang.org/download/0.15.1/release-notes.html#Writergate), go to the 0.14.0 branch
