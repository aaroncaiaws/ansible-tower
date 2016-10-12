#!/bin/bash
APACHE_CONF=/etc/apache2/conf-enabled/awx-httpd-443.conf
# bash setup
set -e # fail fast
set -x # echo everything
trap "kill -15 -1 && echo all proc killed" TERM KILL INT

#Correcting Apache Config, must occur here since Apache Config is transient
#if [[ ${SERVER_NAME} ]]; then
#   echo "add ServerName to $SERVER_NAME"
#   head -n 1 ${APACHE_CONF} | grep -q "^ServerName" \
#   && sed -i -e "s/^ServerName.*/ServerName $SERVER_NAME/" ${APACHE_CONF} \
#   || sed -i -e "1s/^/ServerName $SERVER_NAME\n/" ${APACHE_CONF}
#fi
#
#Check if Log Data exists, exiting if not
#if [  ! -d "/var/log" ] ; then
#    echo "Mount for log /var/log not existing, please mount in container"
#    exit 101
#else
#    cp -pRn /var/log.bak/. /var/log
#    setfacl -Rm o:r-X,d:o:r-X /var/log
#fi
##Fail Fast, Settings not existing, exiting because of missing clone
#if [ ! -d "/etc/tower" ]; then
#   echo "Settings /etc/tower not existing"
#   echo "Please clone a repository with a valid \"input\"-folder and related settings."
#   exit 101
#fi
##Check if DB-Mount exists, exiting if not
#if [  ! -d "/var/lib/postgresql/9.4" ]; then
#    echo "DB-mount /var/lib/postgresql/9.4 not existing, please mount in container"
#    exit 101
#fi
##Check if AWX-Data exists, exiting if not
#if [  ! -d "/var/lib/awx" ]; then
#    echo "AWX-Data Mount /var/lib/awx not existing, please mount in container"
#    exit 101
#fi
##Check if Secret Data exists, exiting if not
#if [  ! -d "/secret" ]; then
#    echo "Mount for secret-data /secret not existing, please mount in container"
#    exit 101
#fi

# remove stale pid file when restarting the same container
rm -f /run/apache2/apache2.pid

if [ "$1" = 'initialize' ]; then
    #Fixing Apache Config
    echo "Setting apache ServerName to $SERVER_NAME"
    head -n 1 ${APACHE_CONF} | grep -q "^ServerName" \
    && sed -i -e "s/^ServerName.*/ServerName $SERVER_NAME/" ${APACHE_CONF} \
    || sed -i -e "1s/^/ServerName $SERVER_NAME\n/" ${APACHE_CONF}
    #Fail if Data is existing
    if [ "$(ls -A /var/lib/postgresql/9.4)" ] || [ "$(ls -A /var/lib/awx)" ]; then
        echo "DB (/var/lib/postgresql/9.4) and/or Data (/var/lib/awx) existing. Remove on Host first and try again. Exiting..."
        exit 102
    fi
    #Bootstrapping postgres from container
    cp -pR /var/lib/postgresql/9.4.bak/main /var/lib/postgresql/9.4/main
    #Ugly hack to ensure that key stored in ha.py is in sync to the one stored in the db.
    #Otherwise, we are facing server errors
    cp -pR /etc/tower.bak/conf.d/ha.py /etc/tower/conf.d/ha.py
    #Bootstrapping AWX-Data from container
    cp -pR /var/lib/awx.bak/. /var/lib/awx/
    #Fixing Websocketport: https://issues.sbb.ch/browse/CDP-64
    echo "{\"websocket_port\": 11230}" > /var/lib/awx/public/static/local_settings.json && cat /var/lib/awx/public/static/local_settings.json
    #Fixing SSL-Access: https://issues.sbb.ch/browse/CDP-68
    echo -e "[http]\n\tsslVerify = false"> /var/lib/awx/.gitconfig && cat /var/lib/awx/.gitconfig
    #Setting permissions to settings
    chmod 666 /etc/tower/* /etc/tower/conf.d/* && chmod 777 /etc/tower /etc/tower/conf.d
    #Success Message
    echo -e "----------------------------------------"
    echo -e "Done Bootstrapping..."
    echo -e "----------------------------------------"
elif [ "$1" = 'start' ]; then
    if [ ! "$(ls -A /var/lib/postgresql/9.4)" ] || [ ! "$(ls -A /var/lib/awx)" ] || [ ! "$(ls -A /etc/tower)" ]; then
        echo "DB and/or Data and/or Settings not existing. Clone and/or bootstrap first."
        exit 102
    fi
    source /secret/*
    #Starting the tower
    ansible-tower-service start
    echo -e "----------------------------------------"
    echo -e "Tower started, Process idles......."
    echo -e "----------------------------------------"
    sleep inf & wait
else
    exec "$@"
fi
