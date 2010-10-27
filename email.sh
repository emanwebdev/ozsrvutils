#!/bin/bash

###
# OpenZula server utilities
# --- Handles adding, deleting and passwords for email addresses
#
# @author Alex Cartwright <alex@openzula.org>
# @copyright Copyright (C) 2010 OpenZula
# @license http://www.gnu.org/licenses/old-licenses/gpl-2.0.html GNU/GPL 2
###

if (( $(which postfix postmap dovecotpw &> /dev/null; echo $?) > 0 )); then
	echo "One or more of the following commands can not be found: postfix, postmap, dovecotpw" >&2
	exit 2
fi

case "$2" in
	--add)
		action=add
		;;
	--chpasswd)
		action=chpasswd
		;;
	--delete)
		action=delete
		;;
	-h)
		echo "OpenZula server utilities"
		echo "Usage:"
		echo -e "\t$scriptName email --add -a foo@example.org"
		echo -e "\t$scriptName email --delete -a foo@example.org"
		echo -e "\t$scriptName email --chpasswd -a foo@example.org -p password\n"
		echo "Report bugs to <alex@openzula.org>"
		exit 0
		;;
	*)
		echo "Invalid action '$2'. Use '--add', '--chpasswd' or '--delete'" >&2
		exit 1
		;;
esac

shift 2
while getopts ":a:p:h" OPTION
do
	case "$OPTION" in
		a)
			optEmail=$OPTARG
			;;
		p)
			optPwd="$OPTARG"
			;;
		h)
			echo "OpenZula server utilities"
			echo "Usage:"
			if [[ $action = add ]]; then
				echo -e "\t$scriptName email --add -a foo@example.org\n"
			elif [[ $action = delete ]]; then
				echo -e "\t$scriptName email --delete -a foo@example.org\n"
			elif [[ $action = chpasswd ]]; then
				echo -e "\t$scriptName email --chpasswd -a foo@example.org -p password\n"
			fi
			echo "Options:"
			echo -e "\t-a\tEmail address\n"
			echo "Report bugs to <alex@openzula.org>"
			exit 0
			;;
		*)
			echo "Invalid argument (or value of) '-$OPTARG'. See '-h' for help text." >&2
			exit 1
			;;
	esac
done

if [[ -z $optEmail ]]; then
	echo "Invalid arguments; expecting at least '-a'. See -'h' for help text." >&2
	exit 1
fi

if [[ ! -d $cfgVarStateDir/emails ]]; then
	mkdir $cfgVarStateDir/emails
fi

# Get the different parts of the email (domain and user)
partUser=$(echo $optEmail | cut -d@ -f1)
partDomain=$(echo $optEmail | cut -d@ -f2)

if [[ $partUser = $partDomain || -z $partUser || -z $partDomain ]]; then
	echo "Please provide a valid email address." >&2
	exit 2
fi

##
## Handle the 'add 'action
##
actionAdd()
{
	grep "$optEmail" /etc/postfix/virtual/mb-maps > /dev/null
	if (( $? == 0 )); then
		echo "Email address already exists." >&2
		exit 2
	fi

	## Let postfix know it's the final destination for this domain
	grep $partDomain /etc/postfix/virtual/mb-domains > /dev/null
	if (( $? == 1 )); then
		echo $partDomain >> /etc/postfix/virtual/mb-domains
		if (( $? == 1 )); then
			echo "Failed to add domain to /etc/postfix/virtual/mb-domains" >&2
			exit 2
		fi
	fi

	## Add the map in for this email address, grouping all emails together
	lastEntryLn=$(grep -n "@$partDomain" /etc/postfix/virtual/mb-maps | tail -1 | cut -d: -f1)
	if [[ -z $lastEntryLn ]]; then
		echo -e "\n## $partDomain\n$optEmail\t\t\t$partDomain/$partUser/" >> /etc/postfix/virtual/mb-maps
	else
		sed -i "${lastEntryLn}a$optEmail\t\t\t$partDomain/$partUser/" /etc/postfix/virtual/mb-maps
	fi

	## Add in the username/password entry
	password=$(apg -d -n1 -m10 -x14 -M LCNS)
	echo $optEmail:$(dovecotpw -s SSHA -p $password) >> /etc/dovecot/passwd

	maildirmake.dovecot /var/mail/virtual/$partDomain/$partUser vmail
	chown -R vmail:vmail /var/mail/virtual/$partDomain

	## All done!
	postmap /etc/postfix/virtual/mb-maps
	postfix reload 2> /dev/null

	credentialsFile=$cfgVarStateDir/emails/$optEmail
	touch $credentialsFile
	chown root:adm $credentialsFile
	chmod 0640 $credentialsFile

	echo -e "address = $optEmail\n" \
			"username = $optEmail\n" \
			"password = $password\n" \
			"server = $(cat /etc/mailname)" > $credentialsFile
	sed -i -e "s#^ ##g" $credentialsFile

	## Display the newly created file to the user
	echo -e "New email address created:\n"
	cat $credentialsFile | sed -e "s#^#\t#g"
}

##
## Handle the 'delete' action
##
actionDelete()
{
	grep $optEmail /etc/postfix/virtual/mb-maps > /dev/null
	if (( $? == 1 )); then
		echo "Email address does not exist" >&2
		exit 2
	fi

	sed -i "/^$optEmail/d" /etc/postfix/virtual/mb-maps /etc/dovecot/passwd
	rm -rf /var/mail/virtual/$partDomain/$partUser

	## See if there are any more emails addresses for this domain
	emailsForDomain=$(grep "@$partDomain" /etc/postfix/virtual/mb-maps | wc -l)
	if (( $emailsForDomain == 0 )); then
		sed -i "/^## $partDomain/d" /etc/postfix/virtual/mb-maps
		sed -i "/^$partDomain/d" /etc/postfix/virtual/mb-domains
		rm -rf /var/mail/virtual/$partDomain
	fi

	unlink $cfgVarStateDir/emails/$optEmail 2> /dev/null
	postmap /etc/postfix/virtual/mb-maps
	postfix reload 2> /dev/null

	echo "Deleted email address '$optEmail'"
}

##
## Handle the 'chpasswd' action
##
actionChpasswd()
{
	stateFilePath=$cfgVarStateDir/emails/$optEmail
	if [[ ! -f $stateFilePath ]]; then
		echo "Unable to find '$stateFilePath'" >&2
		exit 2
	elif (( $(grep ^$optEmail: /etc/dovecot/passwd > /dev/null; echo $?) == 1 )); then
		echo "No login exists for this email address" >&2
		exit 2
	elif [[ -z $optPwd || ${#optPwd} -lt 6 ]]; then
		echo "Password must be >= 6 characters long" >&2
		exit 2
	fi

	sed -i "/^$optEmail:/d" /etc/dovecot/passwd
	echo $optEmail:$(dovecotpw -s SSHA -p $optPwd) >> /etc/dovecot/passwd

	sed -i "s/^password = .*/password = $optPwd/" $stateFilePath

	echo "Updated email password"
}

if [[ $action = add ]]; then
	actionAdd
elif [[ $action = delete ]]; then
	actionDelete
elif [[ $action = chpasswd ]]; then
	actionChpasswd
fi

exit 0