y#!/bin/bash
# OpenVPN road warrior installer for Debian-based distros

# This script will only work on Debian-based systems. It isn't bulletproof but
# it will probably work if you simply want to setup a VPN on your Debian/Ubuntu
# VPS. It has been designed to be as unobtrusive and universal as possible.


if [[ "$USER" != 'root' ]]; then
	echo "Sorry, you need to run this as root"
	exit
fi


if [[ ! -e /dev/net/tun ]]; then
	echo "TUN/TAP is not available"
	exit
fi


if [[ ! -e /etc/debian_version ]]; then
	echo "Looks like you aren't running this installer on a Debian-based system"
	exit
fi

newclient () {
	# Generates the client.ovpn
	cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf ~/$1.ovpn
	sed -i "/ca ca.crt/d" ~/$1.ovpn
	sed -i "/cert client.crt/d" ~/$1.ovpn
	sed -i "/key client.key/d" ~/$1.ovpn
	echo "<ca>" >> ~/$1.ovpn
	cat /usr/share/easy-rsa/keys/ca.crt >> ~/$1.ovpn
	echo "</ca>" >> ~/$1.ovpn
	echo "<cert>" >> ~/$1.ovpn
	cat /usr/share/easy-rsa/keys/$1.crt >> ~/$1.ovpn
	echo "</cert>" >> ~/$1.ovpn
	echo "<key>" >> ~/$1.ovpn
	cat /usr/share/easy-rsa/keys/$1.key >> ~/$1.ovpn
	echo "</key>" >> ~/$1.ovpn
}


# Try to get our IP from the system and fallback to the Internet.
# I do this to make the script compatible with NATed servers (lowendspirit.com)
# and to avoid getting an IPv6.
IP=$(ifconfig | grep 'inet addr:' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | cut -d: -f2 | awk '{ print $1}' | head -1)
if [[ "$IP" = "" ]]; then
		IP=$(wget -qO- ipv4.icanhazip.com)
fi


if [[ -e /etc/openvpn/server.conf ]]; then
	while :
	do
	clear
		echo "Looks like OpenVPN is already installed"
		echo "What do you want to do?"
		echo ""
		echo "1) Add a cert for a new user"
		echo "2) Revoke existing user cert"
		echo "3) Remove OpenVPN"
		echo "4) Exit"
		echo ""
		read -p "Select an option [1-4]: " option
		case $option in
			1) 
			echo ""
			echo "Tell me a name for the client cert"
			echo "Please, use one word only, no special characters"
			read -p "Client name: " -e -i client CLIENT
			cd /usr/share/easy-rsa/
			source ./vars
			# build-key for the client
			export KEY_CN="$CLIENT"
			export EASY_RSA="${EASY_RSA:-.}"
			"$EASY_RSA/pkitool" $CLIENT
			# Generate the client.ovpn
			newclient "$CLIENT"
			echo ""
			echo "Client $CLIENT added, certs available at ~/$CLIENT.ovpn"
			exit
			;;
			2)
			echo ""
			echo "Tell me the existing client name"
			read -p "Client name: " -e -i client CLIENT
			cd /usr/share/easy-rsa/
			. /usr/share/easy-rsa/vars
			. /usr/share/easy-rsa/revoke-full $CLIENT
			# If it's the first time revoking a cert, we need to add the crl-verify line
			if grep -q "crl-verify" "/etc/openvpn/server.conf"; then
				echo ""
				echo "Certificate for client $CLIENT revoked"
			else
				echo "crl-verify /usr/share/doc/openvpn/examples/sample-keys/crl.pem" >> "/etc/openvpn/server.conf"
				/etc/init.d/openvpn restart
				echo ""
				echo "Certificate for client $CLIENT revoked"
			fi
			exit
			;;
			3) 
			apt-get remove --purge -y openvpn openvpn-blacklist
			rm -rf /etc/openvpn
			rm -rf /usr/share/doc/openvpn
			sed -i '/--dport 53 -j REDIRECT --to-port/d' /etc/rc.local
			sed -i '/iptables -t nat -A POSTROUTING -s 10.8.0.0/d' /etc/rc.local
			echo ""
			echo "OpenVPN removed!"
			exit
			;;
			4) exit;;
		esac
	done
else
	clear
	echo 'Welcome to this quick OpenVPN "road warrior" installer'
	echo ""
	# OpenVPN setup and first user creation
	echo "I need to ask you a few questions before starting the setup"
	echo "You can leave the default options and just press enter if you are ok with them"
	echo ""
	echo "First I need to know the IPv4 address of the network interface you want OpenVPN"
	echo "listening to."
	read -p "IP address: " -e -i $IP IP
	echo ""
	echo "What port do you want for OpenVPN?"
	read -p "Port: " -e -i 1194 PORT
	echo ""
	echo "Do you want OpenVPN to be available at port 53 too?"
	echo "This can be useful to connect under restrictive networks"
	read -p "Listen at port 53 [y/n]: " -e -i n ALTPORT
	echo ""
	echo "Do you want to enable internal networking for the VPN?"
	echo "This can allow VPN clients to communicate between them"
	read -p "Allow internal networking [y/n]: " -e -i n INTERNALNETWORK
	echo ""
	echo "What DNS do you want to use with the VPN?"
	echo "   1) Current system resolvers"
	echo "   2) OpenDNS"
	echo "   3) Level 3"
	echo "   4) NTT"
	echo "   5) Hurricane Electric"
	echo "   6) Yandex"
	read -p "DNS [1-6]: " -e -i 1 DNS
	echo ""
	echo "Finally, tell me your name for the client cert"
	echo "Please, use one word only, no special characters"
	read -p "Client name: " -e -i client CLIENT
	echo ""
	echo "Okay, that was all I needed. We are ready to setup your OpenVPN server now"
	read -n1 -r -p "Press any key to continue..."
	apt-get update
	apt-get install openvpn iptables openssl -y
	cp -R /usr/share/doc/openvpn/examples/easy-rsa/ /etc/openvpn
	# easy-rsa isn't available by default for Debian Jessie and newer
	if [[ ! -d /usr/share/easy-rsa/ ]]; then
		wget --no-check-certificate -O ~/easy-rsa.tar.gz https://github.com/OpenVPN/easy-rsa/archive/2.2.2.tar.gz
		tar xzf ~/easy-rsa.tar.gz -C ~/
		mkdir -p /usr/share/easy-rsa/
		cp ~/easy-rsa-2.2.2/easy-rsa/2.0/* /usr/share/easy-rsa/
		rm -rf ~/easy-rsa-2.2.2
		rm -rf ~/easy-rsa.tar.gz
	fi
	cd /usr/share/easy-rsa/
	# Let's fix one thing first...
	cp -u -p openssl-1.0.0.cnf openssl.cnf
	# Fuck you NSA - 1024 bits was the default for Debian Wheezy and older
	sed -i 's|export KEY_SIZE=1024|export KEY_SIZE=2048|' /usr/share/easy-rsa/vars
	perl -p -i -e 's|^(subjectAltName=)|#$1|;' /usr/share/easy-rsa/openssl-1.0.0.cnf # @todo: update this to sed -i...
	# Create the PKI
	. /usr/share/easy-rsa/vars
	. /usr/share/easy-rsa/clean-all
	# The following lines are from build-ca. I don't use that script directly
	# because it's interactive and we don't want that. Yes, this could break
	# the installation script if build-ca changes in the future.
	export EASY_RSA="${EASY_RSA:-.}"
	"$EASY_RSA/pkitool" --initca $*
	# Same as the last time, we are going to run build-key-server
	export EASY_RSA="${EASY_RSA:-.}"
	"$EASY_RSA/pkitool" --server server
	# Now the client keys. We need to set KEY_CN or the stupid pkitool will cry
	export KEY_CN="$CLIENT"
	export EASY_RSA="${EASY_RSA:-.}"
	"$EASY_RSA/pkitool" $CLIENT
	# DH params
	. /usr/share/easy-rsa/build-dh
	# Let's configure the server
	cd /usr/share/doc/openvpn/examples/sample-config-files
	gunzip -d server.conf.gz
	cp server.conf /etc/openvpn/
	cd /usr/share/easy-rsa/keys
	cp ca.crt ca.key dh2048.pem server.crt server.key /etc/openvpn
	cd /etc/openvpn/
	# Set the server configuration
	sed -i 's|dh dh1024.pem|dh dh2048.pem|' server.conf
	sed -i 's|;push "redirect-gateway def1 bypass-dhcp"|push "redirect-gateway def1 bypass-dhcp"|' server.conf
	sed -i "s|port 1194|port $PORT|" server.conf
	# DNS
	case $DNS in
		1) 
		# Obtain the resolvers from resolv.conf and use them for OpenVPN
		grep -v '#' /etc/resolv.conf | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read line; do
			sed -i "/;push \"dhcp-option DNS 208.67.220.220\"/a\push \"dhcp-option DNS $line\"" server.conf
		done
		;;
		2)
		sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 208.67.222.222"|' server.conf
		sed -i 's|;push "dhcp-option DNS 208.67.220.220"|push "dhcp-option DNS 208.67.220.220"|' server.conf
		;;
		3) 
		sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 4.2.2.2"|' server.conf
		sed -i 's|;push "dhcp-option DNS 208.67.220.220"|push "dhcp-option DNS 4.2.2.4"|' server.conf
		;;
		4) 
		sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 129.250.35.250"|' server.conf
		sed -i 's|;push "dhcp-option DNS 208.67.220.220"|push "dhcp-option DNS 129.250.35.251"|' server.conf
		;;
		5) 
		sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 74.82.42.42"|' server.conf
		;;
		6) 
		sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 77.88.8.8"|' server.conf
		sed -i 's|;push "dhcp-option DNS 208.67.220.220"|push "dhcp-option DNS 77.88.8.1"|' server.conf
		;;
	esac
	# Listen at port 53 too if user wants that
	if [[ "$ALTPORT" = 'y' ]]; then
		iptables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-port $PORT
		sed -i "1 a\iptables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-port $PORT" /etc/rc.local
	fi
	# Enable net.ipv4.ip_forward for the system
	sed -i 's|#net.ipv4.ip_forward=1|net.ipv4.ip_forward=1|' /etc/sysctl.conf
	# Avoid an unneeded reboot
	echo 1 > /proc/sys/net/ipv4/ip_forward
	# Set iptables
	if [[ "$INTERNALNETWORK" = 'y' ]]; then
		iptables -t nat -A POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP
		sed -i "1 a\iptables -t nat -A POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP" /etc/rc.local
	else
		iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP
		sed -i "1 a\iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP" /etc/rc.local
	fi
	# And finally, restart OpenVPN
	/etc/init.d/openvpn restart
	# Try to detect a NATed connection and ask about it to potential LowEndSpirit
	# users
	EXTERNALIP=$(wget -qO- ipv4.icanhazip.com)
	if [[ "$IP" != "$EXTERNALIP" ]]; then
		echo ""
		echo "Looks like your server is behind a NAT!"
		echo ""
		echo "If your server is NATed (LowEndSpirit), I need to know the external IP"
		echo "If that's not the case, just ignore this and leave the next field blank"
		read -p "External IP: " -e USEREXTERNALIP
		if [[ "$USEREXTERNALIP" != "" ]]; then
			IP=$USEREXTERNALIP
		fi
	fi
	# IP/port set on the default client.conf so we can add further users
	# without asking for them
	sed -i "s|remote my-server-1 1194|remote $IP $PORT|" /usr/share/doc/openvpn/examples/sample-config-files/client.conf
	# Generate the client.ovpn
	newclient "$CLIENT"
	echo ""
	echo "Finished!"
	echo ""
	echo "Your client config is available at ~/$CLIENT.ovpn"
	echo "If you want to add more clients, you simply need to run this script another time!"
fi
