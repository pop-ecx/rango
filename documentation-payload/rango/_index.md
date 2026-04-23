
![logo](../../rango-2.png)

## Summary
Rango is an educational Mythic C2 agent that is designed to be used as a
learning tool for those who want to understand how Mythic C2 agents work. It is
a simple agent that is easy to understand and modify, making it a great starting point for those who want to learn about Mythic C2 agents.
It is written in Zig and targets Linux and Windows systems.


## Notable Features
 - Works on Linux and Windows targets
 - Upload and download files
 - Execute commands
 - list directories
 - delete files and directories
 - Port scanning


### Output Format
The output format supported is ELF (on Linux) and EXE (Windows), which is statically linked and stripped.


### Encryption
Encryption is not yet supported as the Zig standard library does not have
CBC mode for aes encryption. Encyption might be implemented at a later date.


## Authors
- @pop-ecx
