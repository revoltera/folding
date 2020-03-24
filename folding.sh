#!/bin/bash
# ----------------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 42):
# Martin@Revoltera.com wrote this file.  As long as you retain this notice you
# can do whatever you want with this stuff. If we meet some day, and you think
# this stuff is worth it, you can buy me a beer in return.
# ----------------------------------------------------------------------------
# About: This is a simple script that makes silent deployment of Folding@Home
# possible. All you need to do is to fill out the configurations down below.
# Note that some parts of this script will requier super-user privileges. If
# Folding@Home is already setup and running, this script will instead act as
# a progress monitor. Enjoy, and good luck.
# Version: 0.1, https://github.com/revoltera
# ----------------------------------------------------------------------------
#
#
# Change these to your own values, if you don't have a username or passkey,
# get one from here: https://apps.foldingathome.org/getpasskey
FOLDING_USER=Anonymous # Folding@home User Name. Default: Anonymous
FOLDING_TEAM=0 # Folding@home Team Number. Default: 0
FOLDING_PASSKEY='' # Passkey is optional. Default: 
FOLDING_POWER=medium # System resources to be used initially: light, medium, full. Default: medium
FOLDING_GPU=false # Find and use GPU automatically. Default: false
FOLDING_AUTOSTART=true # Should FAHClient be automatically started? Default: true
FOLDING_ANONYMOUS=false # Set to true if you do not want to fold as a user. Default: true
FOLDING_SLOTS=0 # Set the number of slots, i.e., simultaneous assignment capacity (0 = automatic). Default: 0
#
#
# Change these if there are more recent releases.
CLIENT_DOWNLOAD_URL=https://download.foldingathome.org/releases/public/release/fahclient/debian-stable-64bit/v7.5/latest.deb
CONTROLLER_DOWNLOAD_URL=https://download.foldingathome.org/releases/public/release/fahcontrol/debian-stable-64bit/v7.5/latest.deb
#
#
# Uninstall:
# PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin dpkg -P fahclient
#
#
##########################################################################
# Change blow if you must.
##########################################################################
CLIENT_PACKAGE_NAME=fahclient.deb
CONTROL_PACKAGE_NAME=fahcontrol.deb
CLIENT_CONFIG_FILE=/etc/fahclient/config.xml
# Check first if the service exist, if not, download and install.
CLIENT_IS_ACTIVE=$(systemctl show -p ActiveState FAHClient | sed 's/ActiveState=//g')
if [ "$CLIENT_IS_ACTIVE" == "active" ] ; then
	# Start the service, if not running.
	CLIENT_IS_RUNNING=$(systemctl show -p SubState FAHClient | sed 's/SubState=//g')
	if [ "$CLIENT_IS_RUNNING" != "running" ] ; then
		/etc/init.d/FAHClient start
	fi
else
	# Donwload the packages.
	echo "Downloading client..."
	wget -O $CLIENT_PACKAGE_NAME $CLIENT_DOWNLOAD_URL -q --show-progress
	echo
	echo "Downloading controller..."
	wget -O $CONTROL_PACKAGE_NAME $CONTROLLER_DOWNLOAD_URL -q --show-progress
	echo

	# Set the number of slots.
	if  [ $FOLDING_SLOTS -gt 0 ] ; then
		for (( i = 0; i < FOLDING_SLOTS; i++ )); do
			FOLDING_SLOTS_CONFIG+="<slot id=\"$i\" type=\"CPU\"/>  \n"
		done
	fi

	# Elevate privileges, create the configuration file,
	# and continue with the silent installation.
	sudo -- sh -c "mkdir -p ${CLIENT_CONFIG_FILE%/*};
	[ ! -e $CLIENT_CONFIG_FILE ] || rm $CLIENT_CONFIG_FILE;
	echo '<config>
		<user value=\"$FOLDING_USER\"/>
		<team value=\"$FOLDING_TEAM\"/>
		<passkey value=\"$FOLDING_PASSKEY\"/>
		$FOLDING_SLOTS_CONFIG
		<power value=\"$FOLDING_POWER\"/>
		<gpu value=\"$FOLDING_GPU\"/>
		<fold-anon value=\"$FOLDING_ANONYMOUS\"/>
	</config>' >> $CLIENT_CONFIG_FILE;
	echo '------------------';
	echo 'Installing client and controller...';
	DEBIAN_FRONTEND=noninteractive dpkg -i --force-depends $CLIENT_PACKAGE_NAME;
	dpkg -i --force-depends $CONTROL_PACKAGE_NAME;
	echo '------------------'"

	# Remove the downloaded packgages.
	rm $CLIENT_PACKAGE_NAME
	rm $CONTROL_PACKAGE_NAME

        # Install init.d script.
        if [ "$FOLDING_AUTOSTART" == "true" ]; then
		if [ -x insserv ]; then
			# Start the service.
			sudo -- sh -c "insserv -d FAHClient; 
			/usr/sbin/service FAHClient start || true"

		else
			# Start the service.
			sudo -- sh -c "/usr/sbin/update-rc.d FAHClient defaults; 
			/usr/sbin/update-rc.d FAHClient enable; 
			/usr/sbin/invoke-rc.d FAHClient start || true"
		fi
        else
		if [ -x insserv ]; then
			sudo insserv -r FAHClient
		else
			sudo usr/sbin/update-rc.d FAHClient disable
		fi
        fi

	# The installation ends by starting the service, so check if it exist.
	CLIENT_IS_RUNNING=$(systemctl show -p SubState FAHClient | sed 's/SubState=//g')

	# Check if the service is running, otherwise start it.
	if [ "$CLIENT_IS_RUNNING" != "running" ] ; then
		echo
		read -n 1 -s -r -p "Unable to install, press any key to continue."
		echo
		exit 1
	fi
fi

print_logo() {
	logo="\n"
	logo+="  ___ ___  _    ___ ___ _  _  ___  ____  _  _  ___  __  __ ___ \n"
	logo+=" | __/ _ \\| |  |   \\_ _| \\| |/ __|/ __ \\| || |/ _ \\|  \\/  | __|\n"
	logo+=" | _| (_) | |__| |) | || .\` | (_ / / _\` | __ | (_) | |\/| | _| \n"
	logo+=" |_| \\___/|____|___/___|_|\\_|\\___\\ \\__,_|_||_|\\___/|_|  |_|___|\n"
	logo+=" -------------------------------- \\____/ -----Fighting disease!\n"
	logo+="\n"
	echo -e "$logo"
}

loading_symbol() {
	ROTATE_POSITION=$(($1 % 4))
	if [ "$ROTATE_POSITION" == "0" ] ; then echo "|" 
	elif [ "$ROTATE_POSITION" == "1" ] ; then echo "/"
	elif [ "$ROTATE_POSITION" == "2" ] ; then echo "—"
	elif [ "$ROTATE_POSITION" == "3" ] ; then echo "\\"
	fi
}

folding_overview() {
	# Delcare the array that holds the assignment progress.
	declare -A ASSIGNMENT_SLOT

	while :; do 

		# Once every hour, check if there are more completed assignments in older log files.
		OLD_ASSIGNMENTS_COMPLETED=0

		# Check active slots, user, and team once an hour too.
		ASSIGNMENT_SLOTS=$(grep -c "Enabled folding slot" /var/lib/fahclient/log.txt)
		FOLDING_USER=$(tac /var/lib/fahclient/log.txt | grep -oP -m 1 "(?<=<user\sv=[\"']).*(?='|\")")
		FOLDING_TEAM=$(tac /var/lib/fahclient/log.txt | grep -oP -m 1 "(?<=<team\sv=[\"']).*(?='|\")")

		if [ -d "/var/lib/fahclient/logs" ] ; then
			for i in /var/lib/fahclient/logs/*.txt; do
				[ -f "$i" ] || break
				OLD_ASSIGNMENTS_COMPLETED=$(($OLD_ASSIGNMENTS_COMPLETED+$(grep -c "(100%)" "$i")))
			done
		fi

		# Keep on checking progress for another hour.
		for i in {1..60} ; do 

			# Check completed assignments and active slots.
			ASSIGNMENTS_COMPLETED=$(grep -c "(100%)" /var/lib/fahclient/log.txt)
			ASSIGNMENTS_COMPLETED=$(($ASSIGNMENTS_COMPLETED+$OLD_ASSIGNMENTS_COMPLETED))
			ASSIGNMENT_SLOTS_ACTIVE=0

			# Loop through our slots and see if there are any progress.
			for (( j = 0; j < $ASSIGNMENT_SLOTS; j++ )) do
				SLOT_NAME=$j
				if  [ $j -lt 10 ] ; then
					SLOT_NAME="0$j"
				fi

				# Grep the latest row that matches work in progress.
				SLOT_PROGRESS_ROW=$(tac /var/lib/fahclient/log.txt | grep -oP -m 1 "(FS$SLOT_NAME:.*:Completed.*)" | cut -f3 -d':')
				SLOT_PROGRESS_PERCENT=$(echo "$SLOT_PROGRESS_ROW" | cut -d "(" -f2 | cut -d ")" -f1)

				# Check if we found anything or if it was already finnished.
				if  [ "$SLOT_PROGRESS_PERCENT" != "100%" ] && [ "$SLOT_PROGRESS_PERCENT" != "" ] ; then
					# Get som metadata about the project of the slot.
					SLOT_ASSIGNMENT_INFO=$(tac /var/lib/fahclient/log.txt | grep -oP -m 1 "(FS$SLOT_NAME:.*:Project.*)" | cut -f3,4 -d':')
					SLOT_ASSIGNMENT_STEPS=$(tac /var/lib/fahclient/log.txt | grep -oP -m 1 "(FS$SLOT_NAME:.*:Steps.*)" | cut -f3,4 -d':')
					SLOT_STATUS="$SLOT_ASSIGNMENT_INFO \n"
					SLOT_STATUS+=" \t$SLOT_ASSIGNMENT_STEPS \n"
					SLOT_STATUS+=" \tSlot: $(($j+1)) $SLOT_PROGRESS_ROW"
					ASSIGNMENT_SLOT[$j]=$SLOT_STATUS
					ASSIGNMENT_SLOTS_ACTIVE=$((ASSIGNMENT_SLOTS_ACTIVE+1))
				else
					ASSIGNMENT_SLOT[$j]=""
				fi
			done

			# Refresh only once every 60 seconds, but let loading indicators refresh more often.
			for j in {1..60} ; do 
				if [ $ASSIGNMENT_SLOTS_ACTIVE -gt 0 ] ; then
					# System details.
					CPU_WORKLOAD=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' | cut -c 1-4)
					RAM_USAGE=$(free | grep Mem | awk '{print $3/$2 * 100}' | cut -c 1-4)

					# ... it bothered me.
					if [ $ASSIGNMENT_SLOTS_ACTIVE -gt 1 ]; then ASSIGNMENT_STRING="assignments"; else ASSIGNMENT_STRING="assignment"; fi

					# Progress of the current assignment.
					STATUS_SCREEN=" Working on $ASSIGNMENT_SLOTS_ACTIVE $ASSIGNMENT_STRING \n"
					STATUS_SCREEN+=" - Folding as $FOLDING_USER for team $FOLDING_TEAM \n"
					STATUS_SCREEN+=" - Completed assignments on this unit: $ASSIGNMENTS_COMPLETED \n"
					STATUS_SCREEN+=" - Number of slots enabled on this unit: $ASSIGNMENT_SLOTS \n\n"
					STATUS_SCREEN+=" --------------------------------------------------------------\n"
					for (( k = 0; k < $ASSIGNMENT_SLOTS; k++ )) do
						if [ "${ASSIGNMENT_SLOT[$k]}" != "" ] ; then
							STATUS_SCREEN+=" [$(loading_symbol $j)]\t${ASSIGNMENT_SLOT[$k]} \n"
							STATUS_SCREEN+=" --------------------------------------------------------------\n"
						fi
					done
					STATUS_SCREEN+="\n CPU: $CPU_WORKLOAD% \tRAM: $RAM_USAGE%\n\n"
				else
					# Loading screen, waiting for assignments.
					STATUS_SCREEN=" Searching for an assignment $(loading_symbol $j) \n"
					STATUS_SCREEN+=" - Folding as $FOLDING_USER for team $FOLDING_TEAM \n"
					STATUS_SCREEN+=" - Completed assignments on this unit: $ASSIGNMENTS_COMPLETED \n"
					STATUS_SCREEN+=" - Number of slots enabled on this unit: $ASSIGNMENT_SLOTS \n"
					STATUS_SCREEN+="\n"
					STATUS_SCREEN+="\n"
					STATUS_SCREEN+=" Five latest log entries: \n"
					STATUS_SCREEN+=" $(tail -n 5 /var/lib/fahclient/log.txt)"
					STATUS_SCREEN+="\n"
					STATUS_SCREEN+="\n"
					STATUS_SCREEN+=" $(date)\n\n"
				fi

				clear
				print_logo
				echo -e "$STATUS_SCREEN"
				sleep 1;
			done

		done

	done
}

# Call the overview monitoring.
folding_overview

