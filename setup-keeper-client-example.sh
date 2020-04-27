#!/bin/sh

# SCP the file in: scp .\Downloads\vault-<domain.com>.xml <desthost>

if [[ "$(whoami)" != "root" ]]; then 
    echo "Please run this command with sudo!"
    exit 1
fi

public_hostname="" # needs a hostname here


local_ip=$(ifconfig eth0 | grep "inet " | awk {'print $2'})

rpm -q java-11-openjdk >/dev/null ||  yum -qy install java-11-openjdk vim-enhanced curl openssl

app_download_url="https://keepersecurity.com/sso_connect/KeeperSso_java.zip"
app_download_file="/mnt/resource/KeeperSso_java.zip"
rm -f $app_download_file
wget -q $app_download_url -O $app_download_file 



clientid=0
while ! [[ $clientid =~ ^[1-9]+[0-9]*$  ]]; do
    echo -n "Enter this client's ConnectWise Automate (Labtech) Client ID: "
    read clientid
done
echo "Entered ClientID $clientid"

echo -n "Enter the Enterprise Domain Name for this client: "
read domain

saml_file="/home/rader/vault-$domain.xml"
if [ ! -f $saml_file ]; then
    echo "ERROR: Missing Federation Metadata XML file from MS Azure. Please upload it to /home/rader"
    exit 1
fi

private_port=$(expr 8000 + $clientid)
public_port=$(expr 10000 + $clientid)
admin_port=$(expr 20000 + $clientid)
install_dir="/opt/keeper/sso_$clientid"

adminuser=0
while ! [[ $adminuser =~ ^([a-zA-Z0-9_\-\.]+)@([a-zA-Z0-9_\-\.]+)\.([a-zA-Z]{2,5})$  ]]; do
    echo -n "Enter the Keeper Admin Account Username for this client: "
    read adminuser
done


rm -rf $install_dir
mkdir -p $install_dir
cd $install_dir
unzip -q $app_download_file 
mv $saml_file $install_dir
saml_file=$install_dir/vault-$domain.xml
chown -R keeper.keeper $install_dir


# Generate SSL Keys
openssl genrsa 2048 > private-$domain.pem
openssl req -x509 -new -key private-$domain.pem -out public-$domain.pem  \
    -nodes \
    -days 3650 \
    -subj "/C=US/ST=XX/L=wherever/O=KeeperSSO/CN=$domain"
openssl pkcs12 -export -in public-$domain.pem -inkey private-$domain.pem -out cert-$domain.pfx -passout pass:nuggies

tmpfile=`mktemp`
dd if=/dev/urandom of=$tmpfile bs=512 count=1
randpass=$(cat $tmpfile | md5sum | cut -c2-20)
rm -f $tmpfile
parameters="-initialize $domain \
            -private_ip $local_ip \
            -username $adminuser \
            -sso_connect_host $public_hostname \
            -private_port $private_port \
            -sso_ssl_port $public_port \
            -idp_type 5 \
            -key_store_type p12 \
            -saml_file $saml_file \
            -ssl_file cert-$domain.pfx \
            -key_password "$randpass" \
            -key_store_password "$randpass" \
            -admin_port $admin_port "

echo $parameters



keepercmd="cd $install_dir; java -jar SSOConnect.jar $parameters"
su keeper -c "$keepercmd"


echo """
[Unit]
Description=SSO Connect Java Daemon Client $clientid

[Service]
WorkingDirectory=$install_dir
User=keeper
ExecStart=/usr/bin/java -jar $install_dir/SSOConnect.jar $install_dir

[Install]
WantedBy=multi-user.target
""" > /tmp/ssoconnect-$clientid.service
mv /tmp/ssoconnect-$clientid.service /etc/systemd/system/
chmod 644 /etc/systemd/system/ssoconnect-$clientid.service

systemctl enable ssoconnect-$clientid
echo "Starting SSOConnect Daemon for $domain"
sleep 3
systemctl start ssoconnect-$clientid

echo "Setup Complete"
