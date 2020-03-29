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

## Configuration

I have added some environment variables to choose where scripts will be installed,
rather than having the paths hardcoded to the /usr paths, and the default is now
/usr/local. I have started removing embedded sudos so the script itself will need to
be called with sudo. This avoids admin commands running in a terminal with
previous sudo elevation unexpectedly.

### Environment Variables

- $PREFIX for all files in bin, lib, share. Defaults to /usr/local
- $CONF_PREFIX for path to configuration files. Defaults to empty so files end up in /etc
- $SHORTCUT_PREFIX for where to place .desktop files. Defaults to /home/pi/desktop
- $NOPKG if set will skip package installation, debugging purposes
- $NOBUS if set will skip enableing busses, debugging purposes
- $NOSVC if set will skip systemd service reloading and starting, debug purpooses
