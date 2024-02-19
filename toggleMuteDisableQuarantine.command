#!/bin/bash
#title          : toggleMuteDisableQuarantine.command
#description    : This script will remove the quarantine from toggleMute.app
#author         : sascha.petrik@cgm.com
#date           : 20240219
#version        : 1.1
#usage          : double click to execute or via a terminal
#============================================================================
APPNAME="toggleMute"
APPEXTENSTION=".app" 
APPPATH="/Applications/"
APP="$APPPATH$APPNAME$APPEXTENSTION"

if [[ -d "$APP" ]]
then
    xattr -cr $APP  
    echo " "
    echo "==="
    echo "$APPNAME should work now. Remeber to open it the first time by 'Right Click > Open' and 'Trust me' :)"
    echo "==="
    echo " "
else 
    echo " "
    echo "==="
    echo "$APPNAME in $APPPATH not found. Make sure to unzip the app and move it in the $APPPATH folder before running this command again"
    echo "==="
    echo " "
fi

exit 0