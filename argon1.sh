#!/bin/bash

# checks if file exists, deletes if it does then creates
# it with user write permissions
argon_create_file() {
	mkdir -p `dirname $1`
	if [ -f $1 ]; then
		rm $1
	fi
	touch $1
	chmod 644 $1
}

# checks if a package is installed with dpkg
argon_check_pkg() {
	RESULT=$(dpkg-query -W -f='${Status}\n' "$1" 2> /dev/null | grep "installed")

	if [ "$RESULT" == "" ]; then
		echo "NG"
	else
		echo "OK"
	fi
}

argon_get_platform() {
	CHECKPLATFORM="Others"
	# Check if Raspbian, otherwise Ubuntu
	if (grep -q -F 'Raspbian' /etc/os-release &> /dev/null); then
		CHECKPLATFORM="Raspbian"
	fi
}

argon_get_pkglist() {
	if [ "$CHECKPLATFORM" = "Raspbian" ]; then
		pkglist=(raspi-gpio python3-rpi.gpio python3-smbus i2c-tools)
	else
		# Ubuntu has serial and i2c enabled
		pkglist=(python3-rpi.gpio python3-smbus i2c-tools)
	fi
}

# installs necessary packages
argon_install_required_pkgs() {
		install_list=()
		for curpkg in ${pkglist[@]}; do
				RESULT=$(argon_check_pkg $curpkg)
				if [ "$RESULT" == "NG" ]; then
						install_list+=( $curpkg )
				fi
		done
		if [ "${#install_list[@]}" -gt 0 ]; then
				echo "The following packages need to be installed: ${install_list[@]}"
				read -p "Press y to install these packages now? " -n 1 -r
				echo
				if [[ $REPLY =~ ^[yY] ]]; then
						if ! apt install -y ${install_list[@]}; then
							echo "**********************************************************************"
							echo "Package installation failed. Please ensure internet is connected, your"
							echo "repository caches are up to date and you have installation privileges."
							echo "**********************************************************************"
							exit 1
						fi
				else
						echo "********************************************************************************"
						echo "The required packages must be installed. Please run this script again when ready"
						echo "********************************************************************************"
						exit 1
				fi
		fi
}

#instalation prefix
if [ -z "$PREFIX" ]
then
	PREFIX="/usr/local"
fi

#application shortcut location
if [ -z "$SHORTCUT_PREFIX" ]
then
	SHORTCUT_PREFIX="${PREFIX}/share/applications/"
fi

#filenames and locations
daemonname="argononed"
powerbuttonscript="${PREFIX}/bin/${daemonname}.py"
shutdownscript="${TEST_PREFIX}/lib/systemd/system-shutdown/${daemonname}-poweroff.py"
daemonconfigfile="${CONF_PREFIX}/etc/${daemonname}.conf"
configscript="${PREFIX}/bin/argonone-config"
removescript="${PREFIX}/bin/argonone-uninstall"
daemonfanservice="${PREFIX}/lib/systemd/system/${daemonname}.service"
irscript="${PREFIX}/bin/argonone-ir"

#enables i2c and serial busses
argon_enable_busses() {
	# Ubuntu Mate for RPi has raspi-config too, so test for it
	command -v raspi-config &> /dev/null
	if [ $? -eq 0 ]
	then
		raspi-config nonint do_i2c 0
		raspi-config nonint do_serial 0
	fi
}	

#creates config file, only if file doesn't already exist
argon_create_daemonconfigfile() {
	if [ ! -f $daemonconfigfile ]; then
		# Generate config file for fan speed
		mkdir -p `dirname $daemonconfigfile`
		touch $daemonconfigfile
		chmod 664 $daemonconfigfile

		cat > $daemonconfigfile <<- EOF
		#
		# Argon One Fan Configuration
		#
		# List below the temperature (Celsius) and fan speed (in percent) pairs
		# Use the following form:
		# min.temperature=speed
		#
		# Example:
		# 55=10
		# 60=55
		# 65=100
		#
		# Above example sets the fan speed to
		#
		# NOTE: Lines begining with # are ignored
		#
		# Type the following at the command line for changes to take effect:
		# systemctl restart $daemonname.service
		#
		# Start below:
		55=10
		60=55
		65=100
		EOF
	fi
}

# Generate script that runs every shutdown event
argon_create_shutdownscript() {
	argon_create_file $shutdownscript

	cat > $shutdownscript <<- EOF
	#!/usr/bin/python3
	import sys
	import smbus
	import RPi.GPIO as GPIO
	rev = GPIO.RPI_REVISION
	if rev == 2 or rev == 3:
	    bus = smbus.SMBus(1)
	else:
	    bus = smbus.SMBus(0)

	if len(sys.argv)>1:
	    bus.write_byte(0x1a,0)
	    #powercut signal
	    if sys.argv[1] == "poweroff" or sys.argv[1] == "halt":
	        try:
	            bus.write_byte(0x1a,0xFF)
	        except:
	            rev=0
	EOF

	chmod 755 $shutdownscript
}


# Generate script to monitor shutdown button
argon_create_powerbuttonscript() {
	argon_create_file $powerbuttonscript

	cat > $powerbuttonscript <<- EOF
	#!/usr/bin/python3
	import smbus
	import RPi.GPIO as GPIO
	import os
	import time
	from threading import Thread
	rev = GPIO.RPI_REVISION
	if rev == 2 or rev == 3:
	    bus = smbus.SMBus(1)
	else:
	    bus = smbus.SMBus(0)

	GPIO.setwarnings(False)
	GPIO.setmode(GPIO.BCM)
	shutdown_pin=4
	GPIO.setup(shutdown_pin, GPIO.IN,  pull_up_down=GPIO.PUD_DOWN)

	def shutdown_check():
	    while True:
	        pulsetime = 1
	        GPIO.wait_for_edge(shutdown_pin, GPIO.RISING)
	        time.sleep(0.01)
	        while GPIO.input(shutdown_pin) == GPIO.HIGH:
	            time.sleep(0.01)
	            pulsetime += 1
	        if pulsetime >=2 and pulsetime <=3:
	            os.system("reboot")
	        elif pulsetime >=4 and pulsetime <=5:
	            os.system("shutdown now -h")

	def get_fanspeed(tempval, configlist):
	    for curconfig in configlist:
	        curpair = curconfig.split("=")
	        tempcfg = float(curpair[0])
	        fancfg = int(float(curpair[1]))
	        if tempval >= tempcfg:
	            return fancfg
	    return 0
	
	def load_config(fname):
	    newconfig = []
	    try:
	        with open(fname, "r") as fp:
	            for curline in fp:
	                if not curline:
	                    continue
	                tmpline = curline.strip()
	                if not tmpline:
	                    continue
	                if tmpline[0] == "#":
	                    continue
	                tmppair = tmpline.split("=")
	                if len(tmppair) != 2:
	                    continue
	                tempval = 0
	                fanval = 0
	                try:
	                    tempval = float(tmppair[0])
	                    if tempval < 0 or tempval > 100:
	                        continue
	                except:
	                    continue
	                try:
	                    fanval = int(float(tmppair[1]))
	                    if fanval < 0 or fanval > 100:
	                        continue
	                except:
	                    continue
	                newconfig.append( "{:5.1f}={}".format(tempval,fanval))
	        if len(newconfig) > 0:
	            newconfig.sort(reverse=True)
	    except:
	        return []
	    return newconfig

	def temp_check():
	    fanconfig = ["65=100", "60=55", "55=10"]
	    tmpconfig = load_config("$daemonconfigfile")
	    if len(tmpconfig) > 0:
	        fanconfig = tmpconfig
	    address=0x1a
	    prevblock=0
	    while True:

	        try:
	            tempfp = open("/sys/class/thermal/thermal_zone0/temp", "r")
	            temp = tempfp.readline()
	            tempfp.close()
	            val = float(int(temp)/1000)
	        except IOError:
	            val = 0
	
	        block = get_fanspeed(val, fanconfig)
	        if block < prevblock:
	            time.sleep(30)
	        prevblock = block
	        try:
	            bus.write_byte(address,block)
	        except IOError:
	            temp=""
	        time.sleep(30)

	try:
	    t1 = Thread(target = shutdown_check)
	    t2 = Thread(target = temp_check)
	    t1.start()
	    t2.start()
	except:
	    t1.stop()
	    t2.stop()
	    GPIO.cleanup()
	EOF

	chmod 755 $powerbuttonscript
}

# Generate systemd service file for fan daemon
argon_create_daemonfanservice() {
	argon_create_file $daemonfanservice

	# Fan Daemon
	cat > $daemonfanservice <<- EOF
	[Unit]
	Description=Argon One Fan and Button Service
	After=multi-user.target
	[Service]
	Type=simple
	Restart=always
	RemainAfterExit=true
	ExecStart=/usr/bin/python3 $powerbuttonscript
	[Install]
	WantedBy=multi-user.target
	EOF

	chmod 644 $daemonfanservice
}

# Generate uninstall script
argon_create_removescript() {
	argon_create_file $removescript

	# Uninstall Script
	cat > $removescript <<- EOF
	#!/bin/bash
	SHORTCUT_PREFIX=$SHORTCUT_PREFIX
	PREFIX=$PREFIX
	daemonname=$daemonname
	powerbuttonscript=$powerbuttonscript
	shutdownscript=$shutdownscript
	configscript=$configscript
	removescript=$removescript
	daemonfanservice=$daemonfanservice
	daemonconfigfile=$daemonconfigfile
	irscript=$irscript
	install_list=(${install_list[@]})
	EOF
	cat >> $removescript <<- "EOF"
	echo "-------------------------"
	echo "Argon One Uninstall Tool"
	echo "-------------------------"
	read -p "Press Y to continue: " -n 1 -r
	echo
	if ! [[ $REPLY =~ ^[yY] ]]; then
		echo "Cancelled"
		exit 1
	fi
	if [ -d $SHORTCUT_PREFIX ]; then
		rm "${SHORTCUT_PREFIX}argonone-config.desktop"
		rm "${SHORTCUT_PREFIX}argonone-uninstall.desktop"
		rm "${PREFIX}/share/pixmaps/ar1config.png"
		rm "${PREFIX}/share/pixmaps/ar1uninstall.png"
	fi
	if [ -f $powerbuttonscript ]; then
		systemctl stop $daemonname.service
		systemctl disable $daemonname.service
		systemctl daemon-reload
		$shutdownscript uninstall
		rm $powerbuttonscript
		rm $shutdownscript
		rm $configscript
		rm $removescript
		rm $daemonfanservice
		echo "Config file remains at ${daemonconfigfile}"
		read -p "Press Y to delete: " -n 1 -r
		echo
		if [[ $REPLY =~ ^[yY] ]]; then
			rm $daemonconfigfile
		fi
		echo "Removed Argon One Services."
		if [ "${#install_list[@]}" -gt 0 ]; then
			echo
			echo "The following packages were installed by the argonone installer:"
			echo "	${install_list[@]}"
			echo
			echo "If they are no longer needed you can remove them."
		fi
	fi
	if [ -f $irscript ]; then
		rm $irscript
	fi
	EOF

	chmod 755 $removescript
}

#Generate config script
argon_create_configscript() {

	argon_create_file $configscript

	# Config Script
	cat > $configscript <<- EOF
	#!/bin/bash
	daemonconfigfile=$daemonconfigfile
	daemonname=$daemonname
	EOF
	cat >> $configscript <<- "EOF"
	echo "--------------------------------------"
	echo "Argon One Fan Speed Configuration Tool"
	echo "--------------------------------------"
	echo "WARNING: This will remove existing configuration."
	read -p "Press Y to continue: " -n 1 -r
	echo
	if ! [[ $REPLY =~ ^[yY] ]]; then
		echo "Cancelled"
		exit 1
	fi
	echo "Thank you."

	get_number() {
		re="^[0-9]+\$" #function checks if value between 0-100, don't test sign
		read curnumber
		if [ -z "$curnumber" ]
		then
			echo "-2"
			return
		elif [[ $curnumber =~ $re ]]
		then
			if [ $curnumber -lt 0 ]
			then
				echo "-1"
				return
			elif [ $curnumber -gt 100 ]
			then
				echo "-1"
				return
			fi	
			echo $curnumber
			return
		fi
		echo "-1"
		return
	}
	

	loopflag=1
	while [ $loopflag -eq 1 ]
	do
		echo
		echo "Select fan mode:"
		echo "  1. Always on"
		echo "  2. Adjust to temperatures (55C, 60C, and 65C)"
		echo "  3. Customize behavior"
		echo "  4. Cancel"
		echo "NOTE: You can also edit $daemonconfigfile directly"
		echo -n "Enter Number (1-4):"
		newmode=$( get_number )
		if [[ $newmode -ge 1 && $newmode -le 4 ]]
		then
			loopflag=0
		fi
	done

	echo
	if [ $newmode -eq 4 ]
	then
		echo "Cancelled"
		exit
	elif [ $newmode -eq 1 ]
	then
		echo "#" > $daemonconfigfile
		echo "# Argon One Fan Speed Configuration" >> $daemonconfigfile
		echo "#" >> $daemonconfigfile
		echo "# Min Temp=Fan Speed" >> $daemonconfigfile
		echo 1"="100 >> $daemonconfigfile
		systemctl restart $daemonname.service
		echo "Fan always on."
		exit
	elif [ $newmode -eq 2 ]
	then
		echo "Please provide fan speeds for the following temperatures:"
		echo "#" > $daemonconfigfile
		echo "# Argon One Fan Speed Configuration" >> $daemonconfigfile
		echo "#" >> $daemonconfigfile
		echo "# Min Temp=Fan Speed" >> $daemonconfigfile
		curtemp=55
		while [ $curtemp -lt 70 ]
		do
			errorfanflag=1
			while [ $errorfanflag -eq 1 ]
			do
				echo -n ""$curtemp"C (0-100 only):"
				curfan=$( get_number )
				if [ $curfan -ge 0 ]
				then
					errorfanflag=0
				fi
			done
			echo $curtemp"="$curfan >> $daemonconfigfile
			curtemp=$((curtemp+5))
		done

		systemctl restart $daemonname.service
		echo "Configuration updated."
		exit
	fi

	echo "Please provide fan speeds and temperature pairs"
	echo

	loopflag=1
	paircounter=0
	while [ $loopflag -eq 1 ]
	do
		errortempflag=1
		errorfanflag=1
		while [ $errortempflag -eq 1 ]
		do
			echo -n "Provide minimum temperature (in Celsius) then [ENTER]:"
			curtemp=$( get_number )
			if [ $curtemp -ge 0 ]
			then
				errortempflag=0
			elif [ $curtemp -eq -2 ]
			then
				errortempflag=0
				errorfanflag=0
				loopflag=0
			fi
		done
		while [ $errorfanflag -eq 1 ]
		do
			echo -n "Provide fan speed for "$curtemp"C (0-100) then [ENTER]:"
			curfan=$( get_number )
			if [ $curfan -ge 0 ]
			then
				errorfanflag=0
			elif [ $curfan -eq -2 ]
			then
				errortempflag=0
				errorfanflag=0
				loopflag=0
			fi
		done
		if [ $loopflag -eq 1 ]
		then
			if [ $paircounter -eq 0 ]
			then
				echo "#" > $daemonconfigfile
				echo "# Argon One Fan Speed Configuration" >> $daemonconfigfile
				echo "#" >> $daemonconfigfile
				echo "# Min Temp=Fan Speed" >> $daemonconfigfile
			fi
			echo $curtemp"="$curfan >> $daemonconfigfile
			
			paircounter=$((paircounter+1))
			
			echo "* Fan speed will be set to "$curfan" once temperature reaches "$curtemp" C"
			echo
		fi
	done
	
	echo
	if [ $paircounter -gt 0 ]
	then
		echo "Thank you!  We saved "$paircounter" pairs."
		systemctl restart $daemonname.service
		echo "Changes should take effect now."
	else
		echo "Cancelled, no data saved."
	fi
	EOF

	chmod 755 $configscript
}

#Enable new systemd services
argon_enable_services() {
	systemctl daemon-reload
	systemctl enable $daemonname.service

	systemctl start $daemonname.service
}

argon_get_IRscript() {
	wget https://download.argon40.com/argonone-irconfig.sh -O $irscript
	chmod 755 $irscript
}

#Create desktop shortcuts
argon_create_desktopshortcuts() {
	if [ -d $SHORTCUT_PREFIX ]; then
		mkdir -p ${PREFIX}/share/pixmaps
		if [ ! -f "${PREFIX}/share/pixmaps/ar1config.png" ]; then
			wget http://download.argon40.com/ar1config.png -O $PREFIX/share/pixmaps/ar1config.png
		fi
		if [ ! -f "${PREFIX}/share/pixmaps/ar1uninstall.png" ]; then
			wget http://download.argon40.com/ar1uninstall.png -O $PREFIX/share/pixmaps/ar1uninstall.png
		fi
		# Create Shortcuts
		shortcutfile="${SHORTCUT_PREFIX}argonone-config.desktop"

		cat > $shortcutfile <<- EOF
		[Desktop Entry]
		Name=Argon One Configuration
		Comment=Argon One Configuration
		Icon=/usr/share/pixmaps/ar1config.png
		Exec=sudo ${configscript}
		Type=Application
		Encoding=UTF-8
		Terminal=true
		Categories=ConsoleOnly;Settings;
		EOF

		chmod 644 $shortcutfile
		
		shortcutfile="${SHORTCUT_PREFIX}argonone-uninstall.desktop"

		cat > $shortcutfile <<- EOF
		[Desktop Entry]
		Name=Argon One Uninstall
		Comment=Argon One Uninstall
		Icon=/usr/share/pixmaps/ar1uninstall.png
		Exec=sudo ${removescript}
		Type=Application
		Encoding=UTF-8
		Terminal=true
		Categories=ConsoleOnly;System;
		EOF

		chmod 644 $shortcutfile
	fi
}

#Installation Process

argon_get_platform
if [ -z $NOPKG ]
then
	argon_install_required_pkgs
fi
if [ -z $NOBUS ]
then
	argon_enable_busses
fi
argon_create_daemonconfigfile
argon_create_shutdownscript
argon_create_powerbuttonscript
argon_create_daemonfanservice
argon_create_removescript
argon_create_configscript
if [ -z $NOSVC ]
then
	argon_enable_services
fi
if [ -z $NOIR ]
then
	argon_get_IRscript
fi
argon_create_desktopshortcuts

echo "***************************"
echo "Argon One Setup Completed."
echo "***************************"
echo 
if [ -d ${SHORTCUT_PREFIX} ]; then
	echo "Shortcuts created on your desktop or in your application menu."
else
	echo Use 'argonone-config' to configure fan
	echo Use 'argonone-uninstall' to uninstall
fi
echo
