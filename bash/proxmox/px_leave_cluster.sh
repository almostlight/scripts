#! /bin/bash

systemctl stop pve-cluster corosync
pmxcfs -l
rm -rf /etc/corosync/*
rm -rf /etc/pve/corosync.conf
killall pmxcfs
systemctl start pve-cluster

