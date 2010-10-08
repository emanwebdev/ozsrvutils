#!/bin/bash

###
# OpenZula server utilities
#
# @author Alex Cartwright <alex@openzula.org>
# @copyright Copyright (C) 2010 OpenZula
# @license http://www.gnu.org/licenses/old-licenses/gpl-2.0.html GNU/GPL 2
###

scriptName=$(basename $0)
scriptDir=$(dirname $0)
configPath=./config
configFile=$configPath/config.cfg

showHelp()
{
	echo "OpenZula server utilities"
	echo -e "Usage:\n\t$scriptName [backup|domain|email|list]\n"
	echo "Options:"
	echo -e "\t-v\tVersion information"
	echo -e "\t-h\tDisplays this help text, or help for each action e.g. $scriptName domain -h\n"
	echo "Report bugs to <alex@openzula.org>"
}

if (( $(id -u) > 0 )); then
	echo "Please run this script as root." >&2
	exit 2
fi

if [[ -f $configFile ]]; then
	source $configFile
	## Ensure the var state directory exists
	if [[ ! -d $cfgVarStateDir ]]; then
		mkdir -p $cfgVarStateDir
	fi
else
	echo "Unable to find config file '$configFile'" >&2
	exit 2
fi

if (( $# == 0 )); then
	showHelp
	exit 0
fi

case "$1" in
	backup)
		source $scriptDir/backup.sh
		;;
	domain)
		source $scriptDir/domain.sh
		;;
	email)
		source $scriptDir/email.sh
		;;
	list)
		source $scriptDir/list.sh
		;;
	-v)
		echo "0.9.62"
		;;
	-h)
		showHelp
		exit 1
		;;
	*)
		echo "Invalid argument '$1'. See '-h' for help text." >&2
		exit 1
		;;
esac

exit 0