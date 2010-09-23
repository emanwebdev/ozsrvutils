#!/bin/bash

##
## post-domain-add
## Creates the Apache2 vhost template and enables the website
##

if [[ -f apache2-vhost-template ]]; then
	cat apache2-vhost-template | sed -e "s/{USER}/$OZ_USER/g" \
									 -e "s/{DOMAIN}/$OZ_DOMAIN_NAME/g" > /etc/apache2/sites-available/$OZ_DOMAIN_NAME
	a2ensite $OZ_DOMAIN_NAME > /dev/null
	exit 0
else
	echo "'apache2-vhost-template' does not exist, unable to create vhost config" >&2
	exit 2
fi