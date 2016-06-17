#!/bin/bash

echo ""
TS="$1"
if [ "$TS" ]; then
    clear
    echo "--EyePeeTableGateway.sh - Debug Enabled -------"
else
    echo "--EyePeeTablesGateway.sh-----------------------"
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
        echo "  Forwarding $PROTO port $PORT to $DESTIP"
        echo "    $A"; `$A`
        echo "    $B"; `$B`
    else
        echo "  Forwarding $PROTO port $PORT to $DESTIP"
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
        echo "  Forwarding $PROTO ports $STARTPORT-$ENDPORT to $DESTIP"
        echo "    $A"; `$A`
        echo "    $B"; `$B`
    else
        echo "  Forwarding $PROTO ports $STARTPORT-$ENDPORT to $DESTIP"
        `$A`
        `$B`
    fi
}


GatewayAccept(){
    PROTO="$1"
    PORT="$2"
    A="$IPT -I INPUT -p $PROTO --destination-port $PORT -j ACCEPT"
    if [ "$TS" ]; then
        echo "  Accepting $PROTO port $PORT at the gateway"
        echo "    $A"; `$A`
    else
        echo "  Accepting $PROTO port $PORT at the gateway"
        `$A`
    fi
}



echo "Analyzing network..."
LANIF="br0"
WANIF="eth0"
WANIP1=$(ifconfig eth0 | grep 'inet addr:'| grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1}')
WANIP2=$(ip -f inet -o addr show eth0|cut -d\  -f 7 | cut -d/ -f 1)
if [ "$WANIP1" == "$WANIP2" ]; then
    WANIP="$WANIP1"
    echo "  WAN: $WANIP on $WANIF"
  else
    echo "Unable to determine WAN IP reliably...  Exiting."
    exit 0
fi
LANIP=$(ifconfig br0 | grep 'inet addr:'| grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1}')
echo "  Gateway: $LANIP on $LANIF"
INTRANET="`echo $LANIP | cut -d '.' -f-3`.0/24"
echo "  Assuming Class C Intranet: $INTRANET"
IPT=/sbin/iptables
extip="$WANIP"
lan="$INTRANET"




echo ""
echo "Clearing tables..."
$IPT -F
$IPT -X
$IPT -t nat -F
$IPT -t nat -X
$IPT -t mangle -F
$IPT -t mangle -X
$IPT -t raw -F
$IPT -t raw -X
echo ""



echo "Basic NAT..."
if [ "$TS" ]; then echo "  Default DROP rules (firewall)"; fi
$IPT -P INPUT DROP
$IPT -P FORWARD DROP

if [ "$TS" ]; then echo "  NAT rule to forward across interfaces (SNAT)"; fi
#$IPT -t nat -A POSTROUTING -o eth0 -j SNAT --to-source $extip

if [ "$TS" ]; then echo "  NAT Loopback Masquerade"; fi
$IPT -t nat -A POSTROUTING -s $INTRANET -o $WANIF -j MASQUERADE

if [ "$TS" ]; then echo "  INPUT rules for loopback and established connections from WAN"; fi
$IPT -A INPUT -i lo -j ACCEPT
$IPT -A INPUT -i $LANIF -s $lan -j ACCEPT
$IPT -A INPUT -i $WANIF -m state --state ESTABLISHED,RELATED -j ACCEPT

if [ "$TS" ]; then echo "  Gateway exceptions to accept WAN traffic"; fi
GatewayAccept tcp 80
GatewayAccept tcp 22
$IPT -A INPUT -p tcp --destination-port 22 -j ACCEPT

if [ "$TS" ]; then echo "  FORWARD rules for loopback and established connections from WAN"; fi
$IPT -A FORWARD -i $LANIF -s $lan -j ACCEPT
$IPT -A FORWARD -i $WANIF -m state --state ESTABLISHED,RELATED -j ACCEPT


echo ""
echo "WAN to LAN Port Forwarding..."


#----Lee's Minecraft Server
PortForward tcp 25565 192.168.1.5
PortForward udp 25565 192.168.1.5

#----My Minecraft Server
PortForwardNATLoopback tcp 25566 192.168.1.4
PortForwardNATLoopback udp 25566 192.168.1.4

#----Lee's Garry's Mod
PortRangeForward tcp 27000 27050 192.168.1.7
PortRangeForward udp 27000 27050 192.168.1.7
PortForward tcp 3478 192.168.1.7
PortForward udp 3478 192.168.1.7
PortRangeForward tcp 4379 4380 192.168.1.7
PortRangeForward udp 4379 4380 192.168.1.7




echo 1 > /proc/sys/net/ipv4/ip_forward
echo ""
echo "--Finished Peeing on Tables-----------------Enjoy!"
echo ""
exit 0
