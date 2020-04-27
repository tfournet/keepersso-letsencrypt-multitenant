#!/bin/sh

yum -y install epel-release
yum -y install certbot nginx python2-certbot-nginx



echo """
rsa-key-size = 4096
text = True
non-interactive = True
agree-tos = True
authenticator = nginx
http-01-port = 49090
domains = mydomain.com
""" > /etc/letsencrypt/cli.ini

certbot --nginx

echo "certbot renew" > /etc/cron.weekly/certbot.sh

local_ip=$(ifconfig eth0 | grep "inet " | awk {'print $2'})
rm -f /etc/nginx/conf.d/client_*
for clientid in `seq 1 500`; do
	private_port=$(expr 8000 + $clientid)
	public_port=$(expr 10000 + $clientid)
	echo """
server {
	listen $public_port ssl;
	listen [::]:$public_port;
	server_name keeper.rader365.com;
	ssl_certificate /etc/letsencrypt/live/mydomain.com/fullchain.pem;
	ssl_certificate_key /etc/letsencrypt/live/mydomain.com/privkey.pem;

	location / {
		proxy_pass https://$local_ip:$private_port;
		proxy_buffering off;
		proxy_ssl_verify off;
		proxy_set_header X-Real-IP \$remote_addr;
	}
} """ > /etc/nginx/conf.d/client_$clientid.conf
	
done

# Do SeLinux modifications so things work
semanage port -a -t http_port_t -p tcp 10000-10500
semanage port -a -t http_port_t -p tcp 8000-8500
semanage port -a -t http_port_t -p tcp 20000-20500
setsebool -P httpd_can_network_connect on


systemctl enable nginx
systemctl start nginx


