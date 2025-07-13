
![logo](../../rango-2.png)

## Summary
Rango is an educational Mythic C2 agent that is designed to be used as a
learning tool for those who want to understand how Mythic C2 agents work. It is
a simple agent that is easy to understand and modify, making it a great starting point for those who want to learn about Mythic C2 agents.
It is written in Zig and targets Linux systems.


## Notable Features
 - Works on Linux targets
 - Upload and download files
 - Execute commands
 - list directories


### Output Format
The output format supported is ELF, which is statically linked and stripped.


### Encryption
Encryption is not yet supported as the zig standard library does not have
CBC mode for aes encryption. Encyption might be implemented at a later date.


## Authors
- @pop-ecx
