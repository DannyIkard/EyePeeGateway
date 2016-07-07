#!/bin/sh
cp /EyePeeTables.conf /etc/EyePeeTables.conf
cp /EyePeeTables.sh /etc/EyePeeTables.sh
cp /EyePeeWatchdog.sh /etc/EyePeeWatchdog.sh
cp /init.d/EyePeeNetworking /etc/init.d/EyePeeNetworking
chmod 755 /etc/init.d/EyePeeNetworking
update-rc.d EyePeeNetworking defaults
chmod 755 /etc/EyePeeTables.sh
chmod 755 /etc/EyePeeWatchdog.sh
exit 0