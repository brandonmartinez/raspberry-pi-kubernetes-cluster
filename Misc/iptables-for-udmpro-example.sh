#!/bin/sh

# This is just a sample of what the IP Tables script in the UDM Pro may look like
# Replace "192.168.52.110" with the address of your cluster
# via: https://scotthelme.co.uk/catching-and-dealing-with-naughty-devices-on-my-home-network-v2/

iptables -t nat -A PREROUTING ! -s 192.168.52.110 -p tcp --dport 53 -j DNAT --to 192.168.52.110
iptables -t nat -A PREROUTING ! -s 192.168.52.110 -p udp --dport 53 -j DNAT --to 192.168.52.110

# Replace the network range with your local network range
iptables -t nat -A POSTROUTING -m iprange --src-range 192.168.16.1-192.168.31.254 -j MASQUERADE

# If you have multiple networks, add them as well
# (the next example also excludes our cluster since it's in that network)
iptables -t nat -A POSTROUTING ! -s 192.168.52.110 -m iprange --src-range 192.168.52.1-192.168.55.254 -j MASQUERADE
iptables -t nat -A POSTROUTING -m iprange --src-range 192.168.100.1-192.168.100.254 -j MASQUERADE
iptables -t nat -A POSTROUTING -m iprange --src-range 192.168.2.1-192.168.2.254 -j MASQUERADE