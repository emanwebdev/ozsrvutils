#!/bin/bash

###
# OpenZula server utilities
# --- Backup various things such as domain files and emails
#
# @author Alex Cartwright <alex@openzula.org>
# @copyright Copyright (C) 2010 OpenZula
# @license http://www.gnu.org/licenses/old-licenses/gpl-2.0.html GNU/GPL 2
###

## arguments used for all actions
optVerbose=false
optAll=false

## arguments used for 'domain'
optDomain=
optDumpMysql=false
optPurgeOld=false

case "$2" in
	--domains)
		action=domains
		;;
	--email)
		action=emails
		echo "Sorry, this action has not yet been coded!"
		exit 0
		;;
	-h)
		echo "OpenZula server utilities"
		echo "Usage:"
		echo -e "\t$scriptName backup --domains [-d domain] [-ahmpv]\n"
		echo "Report bugs to <alex@openzula.org>"
		exit 0
		;;
	*)
		echo "Invalid action '$2'. Use '--domains' or '--emails'" >&2
		exit 1
		;;
esac

shift 2
while getopts ":ad:mpvh" OPTION
do
	case "$OPTION" in
		a)
			optAll=true
			;;
		d)
			if [[ $OPTARG =~ ^www\. ]]; then
				optDomain="${OPTARG:4}"
			else
				optDomain="$OPTARG"
			fi
			;;
		m)
			optDumpMysql=true
			;;
		p)
			optPurgeOld=true
			;;
		v)
			optVerbose=true
			;;
		h)
			echo "OpenZula server utilities"
			echo "Usage:"
			if [[ $action = domains ]]; then
				echo -e "\t$scriptName backup --domains [-d domain] [-ahmpv]\n"
				echo -e "Options:"
				echo -e "\t-a\tBackup all available domains ('-d' is ignored if this is provided)."
				echo -e "\t-d\tDomain name of the website to backup (ignored and optional if '-a' is provided)."
				echo -e "\t-m\t(optional) Backup MySQL database (if available)."
				echo -e "\t-p\t(optional) Purge backups older than 30 days before creating new backup."
			fi
			echo -e "\t-v\tProduce verbose output."
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

##
## Handle the 'domains' action
##
actionDomains() {
	if [[ $optAll = true ]]; then
		domainList=$($scriptDir/$scriptName list --domains)
	else
		domainList[0]="${optDomain}"
	fi

	if [[ -z $domainList ]]; then
		echo "No domains specified. Are you sure you specified '-d' or '-a' argument?" >&2
		exit 2
	fi

	## Loop over all (or 1, could be) domains to backup
	for domain in $domainList
	do
		## Check we have needed arguments and they are of good value
		stateFilePath=$cfgVarStateDir/domains/$domain
		if [[ ! -f $stateFilePath ]]; then
			echo "Unable to find '$stateFilePath'" >&2
			continue
		fi
		domainPath=$(grep path $stateFilePath | cut -d" " -f3)
		if [[ ! -d $domainPath ]]; then
			echo "Domain path '$domainPath' does not exist" >&2
			continue
		fi

		owner=$(stat -c %U $domainPath)
		backupDir=$domainPath/backups/$(date +%Y-%m-%d)

		if [[ ! -d $domainPath/backups ]]; then
			mkdir $domainPath/backups
		elif [[ $optPurgeOld = true ]]; then
			## Remove backups older than 30 days
			find $domainPath/backups/ -mtime +30 -type d -exec rm -rf {} \; > /dev/null
		fi

		## Archive domains document root, only if files are newer than the previous backup
		lastBackupDate=$(ls -1 -v $domainPath/backups | tail -1)
		lastBackupPath=$domainPath/backups/$lastBackupDate

		mkdir $backupDir 2> /dev/null
		if [[ -z $lastBackupDate || ! -d $lastBackupPath || $(find $domainPath/public/ -cnewer $lastBackupPath -prune | wc -l) -gt 0 ]]; then
			if [[ -f $backupDir/$domain.tar.bz2 ]]; then
				unlink $backupDir/$domain.tar.bz2
			fi
			tar -cjf $backupDir/$domain.tar.bz2 -C $domainPath public &> /dev/null
		elif [[ $lastBackupPath/$domain.tar.bz2 != $backupDir/$domain.tar.bz2 ]]; then
			cp -f $lastBackupPath/$domain.tar.bz2 $backupDir 2> /dev/null
		fi

		## Backup the MySQL Database
		if [[ $optDumpMysql = true && -f $domainPath/.ozsrvutils-mysql ]]; then
			dbUser=$(head -1 $domainPath/.ozsrvutils-mysql)
			dbName=$(tail -1 $domainPath/.ozsrvutils-mysql)
			mysqldump --opt -u $cfgMysqlUser -p$cfgMysqlPass -h $cfgMysqlHost $dbName | bzip2 > $backupDir/$dbName.sql.bz2
			dumpedMysql=true
		else
			dumpedMysql=false
		fi

		## All done!
		chown -R $owner:$owner $domainPath/backups
		if [[ $optVerbose = true ]]; then
			echo -e "Backed up existing domain:"
			echo -e "\tDomain path: $domainPath"
			echo -e "\tBackup path: $backupDir"
			echo -e "\tDumped MySQL database? $dumpedMysql\n"
		fi
	done
}

if [[ $action = domains ]]; then
	actionDomains
fi

exit 0