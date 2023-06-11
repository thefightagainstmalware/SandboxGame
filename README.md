# SandboxGame
The fractureiser incident has shone a light on malware targeting Minecraft servers. This repository hosts software designed to sandbox Minecraft servers. 

# Setup
Simply run main.sh from the root of the repository
```sh
wget https://raw.githubusercontent.com/thefightagainstmalware/SandboxGame/main/main.sh
# cat main.sh - remember to audit your shell scripts!
chmod +x main.sh
./main.sh
```
The setup is simple and easy; set it and forget it.

Supported:
- AppArmor

Planned:
- bwrap
- SELinux
- docker
