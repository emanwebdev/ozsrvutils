#!/bin/bash

##
## post-domain-delete
## Disables and removes the Apache2 vhost
##

a2dissite "$OZ_DOMAIN_NAME" > /dev/null
unlink "/etc/apache2/sites-available/$OZ_DOMAIN_NAME"

exit 0