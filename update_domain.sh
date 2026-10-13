#! /bin/bash

saved="$(getent hosts lukasz.ftp.sh | egrep -o '([0-9]+\.?){4}')" 
actual="$(curl ifconfig.me)"

echo -e "\nsaved: $saved \nactual: $actual"

filepath=$(realpath "$0"| xargs dirname)

if [ $saved != $actual ]; then 
	wget --no-check-certificate -O - https://freedns.afraid.org/dynamic/update.php?OGI5cmdyMWRBOUJYcE1ZU0sxMXZkZkVzOjI0NTg0MTU0 >> $filepath/freedns_lukasz_ftp_sh.log 2>&1
        wget --no-check-certificate -O - https://freedns.afraid.org/dynamic/update.php?OGI5cmdyMWRBOUJYcE1ZU0sxMXZkZkVzOjIzOTc3NDM3 >> $filepath/freedns_lukasz_my_to.log 2>&1
        echo "domains updated"
else 
        echo "nothing to update"
fi 

