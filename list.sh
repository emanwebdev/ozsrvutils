#!/bin/bash

###
# OpenZula server utilities
# --- Lists various things that have been created with ozsrvutils
#
# @author Alex Cartwright <alex@openzula.org>
# @copyright Copyright (C) 2010 OpenZula
# @license http://www.gnu.org/licenses/old-licenses/gpl-2.0.html GNU/GPL 2
###

case "$2" in
	--domains)
		ls -1 $cfgVarStateDir/domains/ 2> /dev/null
		;;
	--emails)
		ls -1 $cfgVarStateDir/emails/ 2> /dev/null
		;;
	-h)
		echo "OpenZula server utilities"
		echo "Usage:"
		echo -e "\t$scriptName list --domains"
		echo -e "\t$scriptName list --emails\n"
		echo "Report bugs to <alex@openzula.org>"
		exit 0
		;;
	*)
		echo "Invalid action '$2'. Use '--domains' or '--emails'" >&2
		exit 1
		;;
esac

exit 0