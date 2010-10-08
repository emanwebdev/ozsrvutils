#!/bin/bash

###
# OpenZula server utilities
# --- Provides an eaasy way to add and delete domains for hosting
#
# @author Alex Cartwright <alex@openzula.org>
# @copyright Copyright (C) 2010 OpenZula
# @license http://www.gnu.org/licenses/old-licenses/gpl-2.0.html GNU/GPL 2
###

## arguments used for all 'actions'
optDomain=

## arguments used for 'add'
optUser=
optPass=
optCreateMysql=true
optDbName=
optDbUser=

## arguments used for 'delete'
optRemoveMysql=true

case "$2" in
	--add)
		action=add
		;;
	--delete)
		action=delete
		;;
	-h)
		echo "OpenZula server utilities"
		echo "Usage:"
		echo -e "\t$scriptName domain --add -d domain -u user [-p password] [-m dbname] [-j dbuser] [-hn]"
		echo -e "\t$scriptName domain --delete -d domain [-mh]\n"
		echo "Report bugs to <alex@openzula.org>"
		exit 0
		;;
	*)
		echo "Invalid action '$2'. Use '--add' or '--delete'" >&2
		exit 1
		;;
esac

shift 2
while getopts ":d:j:nm:p:u:h" OPTION
do
	case "$OPTION" in
		d)
			if [[ $OPTARG =~ ^www\. ]]; then
				optDomain="${OPTARG:4}"
			else
				optDomain="$OPTARG"
			fi
			;;
		j)
			optDbUser="$OPTARG"
			;;
		n)
			if [[ $action = add ]]; then
				optCreateMysql=false
			else
				optRemoveMysql=false
			fi
			;;
		m)
			optDbName="$OPTARG"
			;;
		p)
			optPass="$OPTARG"
			;;
		u)
			optUser="$OPTARG"
			;;
		h)
			echo "OpenZula server utilities"
			echo "Usage:"
			if [[ $action = add ]]; then
				echo -e "\t$scriptName domain --add -d domain -u user [-p password] [-m dbname] [-j dbuser] [-hn]\n"
				echo "Options:"
				echo -e "\t-d\tDomain name of the website to be setup."
				echo -e "\t-j\t(optional) MySQL username. Defaults to 'domain-user' if omitted."
				echo -e "\t-n\t(optional) Do not create MySQL database (-j and -m will be ignored)."
				echo -e "\t-m\t(optional) MySQL database name. Defaults to 'user_domain' if omitted."
				echo -e "\t-p\t(optional) Password for the new user, auto generated if omitted."
				echo -e "\t-u\tUsername this domain will belong to. If it does not exist it shall be\n" \
						"\t\tcreated for you. This value is trimmed to have a max length of 12 chars."
			elif [[ $action = delete ]]; then
				echo -e "\t$scriptName domain --delete -d domain [-nh]\n"
				echo "Options:"
				echo -e "\t-d\tDomain name of the website to be deleted."
				echo -e "\t-n\t(optional) Do *not* remove associated MySQL database (if available)."
			fi
			echo -e "\t-h\tDisplays this help text.\n"
			echo "Report bugs to <alex@openzula.org>"
			exit 0
			;;
		*)
			echo "Invalid argument (or value of) '-$OPTARG'. See '-h' for help text." >&2
			exit 1
			;;
	esac
done

if [[ ! -d $cfgVarStateDir/domains ]]; then
	mkdir $cfgVarStateDir/domains
fi

##
## Handle the 'add' action
##
actionAdd()
{
	if [[ -z $optUser || -z $optDomain ]]; then
		echo "Invalid arguments, expects at least '-u' and '-d'. See '-h' for help text." >&2
		exit 1
	elif [[ -f $cfgVarStateDir/domains/$optDomain ]]; then
		echo "Domain '$optDomain' already exists." >&2
		exit 2
	fi

	## Get the ID of the user, create it if needed
	optUser=${optUser:0:12}
	userId=$(id -u $optUser 2> /dev/null)
	if (( $? == 0 )); then
		## Find another domain this user has and use the password from that
		existingStateFile=$(grep -H -m 1 "^username = $optUser$" $cfgVarStateDir/domains/* 2> /dev/null | head -1 | cut -d: -f1)
		if [[ -n $existingStateFile ]]; then
			optPass=$(grep "^password =" $existingStateFile | cut -d" " -f3)
		else
			optPass="[no change]"
		fi
	else
		## Ensure the 'www-users' group exists
		if (( $(getent group www-users > /dev/null; echo $?) == 2 )); then
			addgroup www-users
		fi
		optUser=$(echo $optUser | sed -e 's/-//g')
		if [[ -z $optPass ]]; then
			optPass=$(apg -d -n1 -m10 -x14 -M LCNS -E \/\'\\\")
		fi
		## Create the new user
		adduser --disabled-password --gecos "Created by ozsrvutils" $optUser > /dev/null
		if (( $? > 0 )); then
			echo "Failed to add new user, exiting..." >&2
			exit 2
		fi
		adduser $optUser www-users > /dev/null
		echo $optUser:$optPass | chpasswd
	fi

	## Setup the document root
	domainPath=/home/$optUser/domains/$optDomain
	sudo -u $optUser mkdir -p $domainPath/public
	chown :www-data /home/$optUser

	## Calculate the database credentials to use
	if [[ $optCreateMysql = true ]]; then
		sitename=$(echo $optDomain | cut -d. -f1 | sed -e 's/-//g')
		dbPass=$(apg -d -n1 -m10 -x14 -M LCNS -E \/\'\\\")
		if [[ -z $optDbName ]]; then
			dbName=${optUser:0:12}_${sitename:0:19}
		else
			dbName=$optDbName
		fi
		if [[ -z $optDbUser ]]; then
			## Work out the max length of the name part of the DB User. Use 8 chars max from the account username
			tmpDbUser=${optUser:0:8}
			snMaxLength=$(( 16-(${#tmpDbUser}+1) ))
			dbUser=${sitename: 0 : $snMaxLength}-$tmpDbUser
		else
			dbUser=$optDbUser
		fi
		dbName=$(echo $dbName | sed -e 's/-//g')

		# Create the actual database and user
		mysql -u $cfgMysqlUser -p$cfgMysqlPass -h $cfgMysqlHost \
			  -e "CREATE DATABASE $dbName; GRANT $cfgMysqlGrantPrivs ON $dbName.* TO '$dbUser'@'$cfgMysqlGrantHost' IDENTIFIED BY '$dbPass'"
		if (( $? == 0 )); then
			# Store details in a file so we can get them later
			sudo -u $optUser touch $domainPath/.ozsrvutils-mysql
			echo -e "$dbUser\n$dbName" > $domainPath/.ozsrvutils-mysql
		else
			echo "Failed to create MySQL database '$dbName' with user '$dbUser'" >&2
			# Empty the values since they are no longer correct and not needed
			dbUser=
			dbPass=
			dbName=
		fi
	fi

	## Run any additional files needed
	export OZ_USER=$optUser OZ_DOMAIN_NAME=$optDomain OZ_DOMAIN_PATH=$domainPath
	for postFile in $configPath/post-domain-add.d/*.sh; do
		if [[ -x $postFile ]]; then
			(cd $configPath/post-domain-add.d && ./$(basename $postFile))
		fi
	done

	## All done!
	sudo -u $optUser touch $domainPath/.ozsrvutils
	credentialsFile=$cfgVarStateDir/domains/$optDomain

	touch $credentialsFile
	chown root:adm $credentialsFile
	chmod 0640 $credentialsFile

	echo -e "domain = $optDomain\n" \
			"username = $optUser\n" \
			"password = $optPass\n" \
			"path = $domainPath" > $credentialsFile
	if [[ $optCreateMysql = true ]]; then
		echo -e "mysql_username = $dbUser\n" \
				"mysql_password = $dbPass\n" \
				"mysql_database = $dbName" >> $credentialsFile
	fi

	sed -i -e "s#^ ##g" $credentialsFile

	## Display the newly created file to the user
	echo -e "Created new domain for web hosting:\n"
	cat $credentialsFile | sed -e "s#^#\t#g"
	echo -e "\nPlease restart your webserver (e.g. 'apache2ctl graceful') for the website to go live."
}

##
## Handle the 'delete' action
##
actionDelete() {
	if [[ -z $optDomain ]]; then
		echo "Invalid arguments, expects at least '-d'. See -'h' for help text." >&2
		exit 1
	fi

	stateFilePath=$cfgVarStateDir/domains/$optDomain
	if [[ ! -f $stateFilePath ]]; then
		echo "Unable to find '$stateFilePath'" >&2
		exit 2
	fi
	domainPath=$(grep "^path =" $stateFilePath | cut -d" " -f3)
	user=$(grep "^user =" $stateFilePath | cut -d" " -f3)

	## Remove MySQL Database if needed (and the user)
	if [[ $optRemoveMysql = true && -f $domainPath/.ozsrvutils-mysql ]]; then
		dbUser=$(head -1 $domainPath/.ozsrvutils-mysql)
		dbName=$(tail -1 $domainPath/.ozsrvutils-mysql)
		mysql -u $cfgMysqlUser -p$cfgMysqlPass -h $cfgMysqlHost \
			  -e "DROP DATABASE $dbName; DROP USER '$dbUser'@'$cfgMysqlGrantHost';"
		if (( $? == 0 )); then
			dbRemoved=true
		else
			dbRemoved=false
			echo "Failed to remove MySQL database '$dbName' and/or user '$dbUser'@'$cfgMysqlGrantHost'" >&2
		fi
	else
		dbRemoved=false
	fi

	## Remove physical files
	rm -rf $domainPath
	unlink $cfgVarStateDir/domains/$optDomain

	## Run any additional files needed
	export OZ_USER=$user OZ_DOMAIN_NAME=$optDomain OZ_DOMAIN_PATH=$domainPath
	for postFile in $configPath/post-domain-delete.d/*.sh; do
		if [[ -x $postFile ]]; then
			(cd $configPath/post-domain-delete.d && ./$(basename $postFile))
		fi
	done

	## All done!
	echo -e "Deleted domain for web hosting:\n"
	echo -e "\tDomain: $optDomain"
	echo -e "\tPath removed: $domainPath"
	echo -e "\tRemoved MySQL database? $dbRemoved"
	echo -e "\nPlease restart your webserver (e.g. 'apache2ctl graceful')."
}

if [[ $action = add ]]; then
	actionAdd
elif [[ $action = delete ]]; then
	actionDelete
fi

exit 0