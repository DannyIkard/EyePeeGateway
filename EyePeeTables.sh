#!/bin/bash

LOG="/tmp/EyePeeTables.log"
EKO(){
  echo "$1"
  echo "$1" >>/var/log/EyePeeTables.log
}


EKO "Running EyePeeTables.sh ------"

echo ""
TS="$1"
if [ "$TS" == debug ]; then
    clear
    EKO "--EyePeeTables.sh - Debug Enabled -------"
else
    EKO "--EyePeeTables.sh -----------------"
fi
echo ""

DDWRTPortForwardNATLoopback(){
    PROTO="$1"
    PORT="$2"
    DESTIP="$3"

    # HTTP from Internet to Intranet host
    iptables -A PREROUTING -t nat -p $PROTO -i $WANIF --dport $PORT -j DNAT --to-destination $DESTIP:$PORT
    iptables -A FORWARD -p tcp -i $WANIF --sport $PORT: -o $LANIF -d $DESTIP --dport $PORT -m state --state NEW -j ACCEPT


    # HTTP from intranet to intranet host (using double NAT)
    iptables -A PREROUTING -t nat -p tcp -i $LANIF -s $INTRANET -d $WANIP --dport $PORT -j DNAT --to-destination $DESTIP:$PORT
    iptables -A POSTROUTING -t nat -p tcp -s $INTRANET -o $LANIF -d $DESTIP --dport $PORT -j SNAT --to $WANIP
}

DDWRT2PortForwardNATLoopback(){
    insmod ipt_mark
    insmod xt_mark
    iptables -t mangle -A PREROUTING -i ! $WANIF -d $WANIP -j MARK --set-mark 0xd001
    iptables -t mangle -A PREROUTING -j CONNMARK --save-mark
    iptables -t nat -A POSTROUTING -m mark --mark 0xd001 -j MASQUERADE 
}


PortForwardNATLoopback(){
    PROTO="$1"
    PORT="$2"
    DESTIP="$3"
    iptables -t nat -A PREROUTING -d $WANIP -p $PROTO --dport $PORT -j DNAT --to $DESTIP:$PORT
    iptables -t nat -A POSTROUTING -s $INTRANET -d $DESTIP -p $PROTO --dport $PORT -j MASQUERADE
}


PortForward(){
    PROTO="$1"
    PORT="$2"
    DESTIP="$3"
    A="$IPT -t nat -I PREROUTING -p $PROTO -d $WANIP --dport $PORT -j DNAT --to $DESTIP:$PORT"
    B="$IPT -I FORWARD -p $PROTO -d $DESTIP --dport $PORT -j ACCEPT"
    if [ "$TS" ]; then
        EKO "  Forwarding $PROTO port $PORT to $DESTIP"
        EKO "    $A"; `$A`
        EKO "    $B"; `$B`
    else
        EKO "  Forwarding $PROTO port $PORT to $DESTIP"
        `$A`
        `$B`
    fi
}

PortRangeForward(){
    PROTO="$1"
    STARTPORT="$2"
    ENDPORT="$3"
    DESTIP="$4"
    A="$IPT -t nat -I PREROUTING -d $WANIP -p $PROTO -m $PROTO --match multiport --dports $STARTPORT:$ENDPORT -j DNAT --to $DESTIP"
    B="$IPT -I FORWARD -p $PROTO -m $PROTO -d $DESTIP --dport $STARTPORT:$ENDPORT -j ACCEPT"
    if [ "$TS" ]; then
        EKO "  Forwarding $PROTO ports $STARTPORT-$ENDPORT to $DESTIP"
        EKO "    $A"; `$A`
        EKO "    $B"; `$B`
    else
        EKO "  Forwarding $PROTO ports $STARTPORT-$ENDPORT to $DESTIP"
        `$A`
        `$B`
    fi
}


GatewayAccept(){
    PROTO="$1"
    PORT="$2"
    A="$IPT -I INPUT -p $PROTO --destination-port $PORT -j ACCEPT"
    if [ "$TS" ]; then
        EKO "  Accepting $PROTO port $PORT at the gateway"
        EKO "    $A"; `$A`
    else
        EKO "  Accepting $PROTO port $PORT at the gateway"
        `$A`
    fi
}







EKO "Analyzing network..."
LANIF="br0"
WANIF="`cat /etc/EyePeeNetworking/WANIFs | head -1`"

WANIP1=$(ifconfig $WANIF | grep 'inet '| grep -v '127.0.0.1' | xargs | cut -d " " -f2)
WANIP2=$(ip -f inet -o addr show $WANIF | cut -d " "  -f 7 | cut -d "/" -f 1)
if [ "$WANIP1" == "$WANIP2" ]; then
    WANIP="$WANIP1"
    EKO "  WAN: $WANIP on $WANIF"
  else
    EKO "Unable to determine WAN IP reliably...  Exiting."
    exit 0
fi
LANIP=$(ifconfig $LANIF | grep 'inet ' | grep -v '127.0.0.1' | xargs | cut -d " " -f2)
if [ ! "$LANIP" ]; then
  EKO "------ Cannot determine LAN IP, exiting... ------"
  exit 1
fi
echo "  Gateway: $LANIP on $LANIF"
INTRANET="`echo $LANIP | cut -d '.' -f-3`.0/24"
echo "  Assuming Class C Intranet: $INTRANET"
IPT=$(which iptables)




echo ""
EKO "Clearing tables..."
$IPT -F
$IPT -X
$IPT -t nat -F
$IPT -t nat -X
$IPT -t mangle -F
$IPT -t mangle -X
$IPT -t raw -F
$IPT -t raw -X
echo ""



EKO "Basic NAT..."
if [ "$TS" ]; then echo "  Default DROP rules (firewall)"; fi
$IPT -P INPUT DROP
$IPT -P FORWARD DROP

if [ "$TS" ]; then echo "  NAT rule to forward across interfaces (SNAT)"; fi
$IPT -t nat -A POSTROUTING -o $WANIF -j SNAT --to-source $WANIP

#----------This is garbage.  Masquerade alternative to SNAT----------------
#if [ "$TS" ]; then echo "  NAT Loopback Masquerade"; fi
#$IPT -t nat -A POSTROUTING -s $INTRANET -o $WANIF -j MASQUERADE

#----------This is phuzi0n's suggestion to fix NAT loopback on certain builds of DDWRT.  I'm applying it here to see if it's feasible here.-------
#iptables -t mangle -A PREROUTING ! -i $WANIF -d $WANIP -j MARK --set-mark 0xd001
#iptables -t mangle -A PREROUTING -j CONNMARK --save-mark
#iptables -t nat -A POSTROUTING -m mark --mark 0xd001 -j MASQUERADE 

if [ "$TS" ]; then echo "  INPUT rules for loopback and established connections from WAN"; fi
$IPT -A INPUT -i lo -j ACCEPT
$IPT -A INPUT -i $LANIF -s $INTRANET -j ACCEPT
$IPT -A INPUT -i $WANIF -m state --state ESTABLISHED,RELATED -j ACCEPT

if [ "$TS" ]; then echo "  Gateway exceptions to accept WAN traffic"; fi
#GatewayAccept tcp 80
GatewayAccept tcp 22
$IPT -A INPUT -p tcp --destination-port 22 -j ACCEPT

if [ "$TS" ]; then echo "  FORWARD rules for loopback and established connections from WAN"; fi
$IPT -A FORWARD -i $LANIF -s $INTRANET -j ACCEPT
$IPT -A FORWARD -i $WANIF -m state --state ESTABLISHED,RELATED -j ACCEPT


echo ""
EKO "WAN to LAN Port Forwarding..."

PortForward tcp 7777 192.168.1.5

#----Lee's Minecraft Server
PortForward tcp 25565 192.168.1.5
PortForward udp 25565 192.168.1.5

#----My Minecraft Server
PortForward tcp 25566 192.168.1.4
PortForward udp 25566 192.168.1.4

#----Lees Garry's Mod
PortRangeForward tcp 27000 27050 192.168.1.7
PortRangeForward udp 27000 27050 192.168.1.7
PortForward tcp 3478 192.168.1.7
PortForward udp 3478 192.168.1.7
PortRangeForward tcp 4379 4380 192.168.1.7
PortRangeForward udp 4379 4380 192.168.1.7

#----Lee's Starbound
PortForward tcp 21025 192.168.1.5

#----Lee's Web Server
PortForward tcp 80 192.168.1.7


#brctl hairpin $WANIF eth1 on
#brctl hairpin $WANIF eth2 on
#brctl hairpin br0 eth1 on
#brctl hairpin br0 eth2 on

echo 1 > /proc/sys/net/ipv4/ip_forward
echo ""
EKO "--Finished Peeing on Tables-----------------Enjoy!"
echo ""

NotSoNice(){
  PID="`ps aux | grep \"$1\" | grep -v grep | xargs | cut -d ' ' -f2`"
  if [[ "$PID" == "" || "$PID" == "0" ]]; then
    EKO "PID for $1 not found!"
  else
    sudo renice -n "$2" -p "$PID"
  fi
}

NotSoNice "dnsmasq" "-5"
NotSoNice "zmdc.pl" "10"


exit 0