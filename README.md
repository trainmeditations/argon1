# argon1

Argon1 Raspberry Pi Case support scripts installer

Script sourced from
[https://download.argon40.com/argon1.sh](https://download.argon40.com/argon1.sh)

I don't like the idea of piping shell scripts to bash for execution, especially
with embedded sudos. Downloaded the script to have a look before executing it
and found some things I want to change so figured I'd play around with it a bit.

My modifications are released as openly as the original script. The creators are
free to include any of my changes as they see fit, although if they do a bit of
acknowledgement would be nice. As there is no copyright or license notice with the
original script I will not add one here. I did try to contact the developers but
have had no response. By using my version of the script I offer no warranty of fitness
or accept liability for any damage caused.

## Plans

1. Commenting existing source
2. Add functions around blocks of code
3. Change file outputs from echos to heredocs
4. Change required package logic
    - check for packages installed before testing they are installed
5. Fix Uninstall
6. Debian packaging
7. Update Repository
8. Possibly Automate updates

## Configuration

I have added some environment variables to choose where scripts will be installed,
rather than having the paths hardcoded to the /usr paths, and the default is now
/usr/local. This should be the only functional change from the original script
at this point.

I have removed embedded sudos so the script itself will need to
be called with sudo. This avoids admin commands running in a terminal with
previous sudo elevation unexpectedly.

Desktop shortcut files have been moved to the applications menu and call sudo for
config and uninstall scripts

### Environment Variables

- $PREFIX for all files in bin, lib, share. Defaults to /usr/local
- $CONF_PREFIX for path to configuration files. Defaults to empty so files end up in /etc
- $SHORTCUT_PREFIX for where to place .desktop files. Defaults to /usr/local/share/applications
- $NOPKG if set will skip package installation, debugging purposes
- $NOBUS if set will skip enableing busses, debugging purposes
- $NOSVC if set will skip systemd service reloading and starting, debug purpooses
- $NOIR do not download and install IR control script
