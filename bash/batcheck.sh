#!/bin/bash

[ $(acpi | grep -oE [0-9]+% | sed s/%//) -le 50 ] \
	&& echo "[$(date)] power loss, shutting down" > /var/log/batcheck.log && shutdown now \
	|| echo "[$(date)] power ok" > /var/log/batcheck.log

