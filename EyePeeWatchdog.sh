#!/bin/bash
trap Interrupt SIGINT SIGTERM


#------------------------------------Initialize----------------------------------------------
MYPID="`cat /var/lock/EyePeeWatchdog.sh 2>/dev/null | tail -1 `"

Delay=300
Verbose=0
Troubleshooting=0
NetDownCount=0

#------------------------------------Functions----------------------------------------------
Eko(){
  echo "`date` - $1" >>/var/log/EyePeeWatchdog.log
  echo "$1"
}

Exit(){
  rm /var/lock/EyePeeWatchdog.lock 2>/dev/null
  Eko "Exiting code $1"
  exit $1
}

Interrupt(){
  echo ""
  Eko "Interrupt signal...  Exiting"
  Exit 0
}

NetworkDown(){
  Eko "--Net Down!!!"
  if [ "$NetDownCount" == "1" ]; then
    Eko "OK, well that didn't work.  Time to burn this bitch down..."
    reboot >>/var/log/EyePeeWatchdog.log
  else
    Eko "--Oh fuck.  Well, ain't that some shit.  Here's some info:"
    echo "`dmesg`" >/var/log/EyePeeWatchdog.log
    echo "`systemctl status dnsmasq`" >>/var/log/EyePeeWatchdog.log
    echo "`systemctl status networking`" >>/var/log/EyePeeWatchdog.log
    echo "`systemctl status thunar`" >>/var/log/EyePeeWatchdog.log
    Eko "--Let's try restarting this shitshow!"
    systemctl restart networking >>/var/log/EyePeeWatchdog.log
    systemctl restart dnsmasq >>/var/log/EyePeeWatchdog.log
    systemctl restart thunar >>/var/log/EyePeeWatchdog.log
    NetDownCount="1"
  fi
}

while getopts ":h:v:t:d:" opt; do
    case $opt in
    h)
        show_help
        exit 0
        ;;
    v)
        Verbose=1
        ;;
    t)
        Troubleshooting=1
        ;;
    d)
        Delay=$OPTARG
        ;;
    :)
        echo "Option -$OPTARG requires an argument."
        ;;
    esac
done
shift $((OPTIND-1))

[ "$1" = "--" ] && shift

if [[ $2 = "-d" || $2 = "-t" || $2 = "-v" || $1 = "-d" || $1 = "-t" || $1 = "-v" ]]; then
  Eko "Optional arguments must come first!"
  Exit 1
fi
if [ $1 ]; then
  MainPing="$1"
else
  MainPing="google.com"
  SecondaryPing="yahoo.com"
fi
if [ $2 ]; then
  SecondaryPing="$2"
  Eko "Using $MainPing as main ping and $SecondaryPing as backup"
else
  SecondaryPing="$MainPing"
  Eko "Using $MainPing for ping"
fi


if [ -f /var/lock/EyePeeWatchdog.lock ]; then
  if [ "`ps aux | grep \"$MYPID\" | grep -v grep | xargs | cut -d ' ' -f11-12`" = "bash EyePeeWatchdog.sh" ]; then
    Eko "EyePeeWatchdog is already running as PID $MYPID"
    Exit 1
  else
    Eko "Lock file is stale"
    Eko "$$" >/var/lock/EyePeeWatchdog.lock
  fi
else
  Eko "$$" >/var/lock/EyePeeWatchdog.lock
fi


#------------------------------------Run Loop----------------------------------------------
Eko "Starting EyePeeWatchdog"
while sleep $Delay; do
  MainPingFail=0
  SecondaryPingFail=0
  Eko "--Pinging $MainPing..."
  sleep 1
  PingResult="`ping -c1 $MainPing 2>&1`"
  echo "$PingResult"
  if [ "`echo "$PingResult" | grep \"1 packets transmitted, 1 received,\"`" ]; then
    MainPingFail=1
  fi
  if [ ! "$MainPingFail" == "1" ]; then
    Eko "--Pinging $MainPing failed, trying $SecondaryPing..."
    sleep 1
    PingResult="`ping -c1 $SecondaryPing 2>&1`"
    echo "$PingResult"
    if [ ! "`echo "$PingResult" | grep \"1 packets transmitted, 1 received,\"`" ]; then
      SecondaryPingFail=1
      Eko "--Pinging $SecondaryPing failed"
      NetworkDown
    fi
#    if [ "$SecondaryPing" == "1" ]; then
#      sleep 1
#      Eko "--Pinging $SecondaryPing failed"
#      NetworkDown
#    fi
  else
    sleep 1
    Eko "--Pinging $MainPing successful"
  fi
done
echo "Critical error...  Exiting"
Exit 1