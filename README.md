# argon1

Argon1 Raspberry Pi Case support scripts installer

Script sourced from
[https://download.argon40.com/argon1.sh](https://download.argon40.com/argon1.sh)

I don't like the idea of piping shell scripts to bash for execution, especially
with embedded sudos. Downloaded the script to have a look before executing it
and found some things I want to change so figured I'd play around with it a bit.

## Plans

1. Commenting existing source
2. Add functions around blocks of code
3. Change required package logic
    - check for packages installed before testing they are installed
4. Change file outputs from echos to heredoc
5. Debian packaging
6. Update Repository
7. Possibly Automate updates
