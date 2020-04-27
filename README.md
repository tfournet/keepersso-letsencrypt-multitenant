# Setting up KeeperSSO for MultiTenancy with LetsEncrypt SSL Certs using NGINX

This is a rough guide of how I set up a single Linux host to enable Single-Sign-On capabilities for [Keeper Security](https://www.keepersecurity.com)
for multiple companies. We used CentOS 7 on MS Azure but any linux distro should work with some modifications.

We have our own scripts for setting this up in a nearly fully-automated fashion, but these are specific to our environment and wouldn't be of use to anyone else

I will refer each company being set up in KeeperSSO as a tenant or client

I maybe missing some steps since I used some trial and error to get it going. If you find anything, please let me know.

## Components

* Linux server you control
  * The Server needs to be reachable on a public fqdn that you plan to use for your configurations
  * It needs to be able to have multiple TCP ports forwarded to it (one for each tenant)
* Java OpenJDK
* KeeperSSO install file 
* LetsEncrypt Certbot
* Apache NGINX
* SAML Platform - We use Azure Active Directory

## Planning

* TCP Ports. There will be 3 for each tenant that gets set up:
  * Private Port 
    * This will be where the KeeperSSO java listens for SAML requests
    * We will refer to this as `$private_port`
  * Public Port
    * NGINX will listen on this port, provide a valid SSL cert, and forward connections to the private port
    * We will refer to this as `$public_port`
  * Admin Port
    * We won't bother forwarding this, but we will configure it in case of future troubleshooting or configuration is required
    * We will refer to this as `$admin_port`
  * Public Hostname 
    * This will be the same for each tenant, only the port numbers will differ
    * We will refer to this as `$public_hostname`
  * Internal IP of the host. 
    * Will refer to this as `$local_ip`. 
    * A simple way to get this programmatically (assuming the interface is `eth0`), is `local_ip=$(ifconfig eth0 | grep "inet " | awk {'print $2'})`
  * Root installation location 
    * Highly recommend putting all your tenant installs underneath a centralized location, but I guess it doesn't have to be that way
   
In our case, we used ranges beginning with port `8000` for `$private_port`, `10000` for `$public_port`, and `20000` for `$admin_port`. In our examples we will assume this, but feel free to change it at your own discretion.


## Initial Setup

First off, SELinux needs to allow connections on these ports. Default configurations may limit the ports that daemons are allowed to open.

### SELinux Rules:
```
# Do SeLinux modifications so things work
sudo semanage port -a -t http_port_t -p tcp 10000-10500 # Allow Public Ports
sudo semanage port -a -t http_port_t -p tcp 8000-8500   # Allow Private Ports
sudo semanage port -a -t http_port_t -p tcp 20000-20500 # Allow Admin Ports
sudo setsebool -P httpd_can_network_connect on # Allow connections for HTTP listeners
```
If you would prefer not to do ranges of ports, you can open them one by one as you add tenants.

### Install LetsEncrypt CertBot, Apache NGINX, and the NGINX Module for CertBot:

```
sudo yum -y install epel-release
sudo yum -y install certbot nginx python2-certbot-nginx
```

### Install the Java 11 JDK as recommended by Keeper
`sudo yum -y install java-11-openjdk`

### Create a Keeper service account 
`sudo useradd keeper`

### Make sure the server is reachable on its public hostname at port 80 (for LetsEncrypt Certs)

### Test the certbot install with a dry run
```
certbot certonly \
    --standalone \
    --preferred-challenges http \
    --http-01-port 80 \
    -d $public_hostname \
    -m $my_email_address \
    --dry-run --test-cert 
```
If this test does not pass, You will need to work out why and get it working before continuing.

### Write the following to /etc/letsencrypt/cli.ini:
```
rsa-key-size = 4096
email = $my_email_address
text = True
non-interactive = True
agree-tos = True
authenticator = nginx
http-01-port = 49090
domains = $public_hostname
```

### Install the inital LetsEncrypt Cert into NGINX
`sudo certbot --nginx`

This will write files into `/etc/letencrypt/live/$public_hostname/`. These will be referred to by each tenant configuration in nginx.

### Set up a crontab entry to check for whether the cert needs to be renewed.
I run it weekly to give us time to troubleshoot any issues:
`sudo echo "certbot renew" > /etc/cron.weekly/certbot.sh`

### Enable and start the NGINX daemon
```
sudo systemctl enable nginx
sudo systemctl start nginx
```

# Tenant Setup

## Preparation
Keep track of the following for the tenant setup phase
* Tenant's primary domain name
  * Keep note of this. I will refer to it as `$domain`
* Chosen ports for the tenant - The three ports referenced above
* Tenant Unique identification - I use an integer (actually our Connectwise Automate ClientID), and base my port numbers and other settings off of these
* Directory to install the tenant's Keeper application into. Will refer to this as `$install_dir`


## Keeper Admin Console
* Create A **Keeper Administrator** user account. You will need to authenticate Keeper against htis account. An account with MFA enabled works. It should be a unique account in the root node for the tenant that will not ever be enabled for SSO. I (and Keeper) recommend keeping this account dedicated for Admin and SSO and not used for anything else.
* Add a node called `SSO` to the root structure
  * You can name this whatever you want, but I like `SSO`
  * Enter that node, and choose the Provisioning tab
  * Add Method and choose Single Sign-On (SAML 2.0)
  * Enter the customer's primary domain, noted earlier
  * Leave Enable Just-In-Time Provisioning checked

## NGINX
First off, we create an nginx config for the tenant. You can simply write a unique file into `/etc/nginx/conf.d` for each tenant being set up. We go by a tenant ID number which corresponds to the TCP ports we're going to use. Make sure you replace the variables below with your actual information. The exception is `$remote_addr` which is picked up by nginx.
```
server {
	listen $public_port ssl;
	listen [::]:$public_port;
	server_name keeper.rader365.com;
	ssl_certificate /etc/letsencrypt/live/$public_hostname/fullchain.pem;
	ssl_certificate_key /etc/letsencrypt/live/$public_hostname/privkey.pem;

	location / {
		proxy_pass https://$local_ip:$private_port;
		proxy_buffering off;
		proxy_ssl_verify off;
		proxy_set_header X-Real-IP $remote_addr;
	}
}
```

## SAML Setup (Azure)
* Follow Keeper's instructions for your Identity Provider. I've only done [Azure](https://docs.keeper.io/sso-connect-guide/identity-provider-setup/azure-configuration) so those are the only instructions I can provide. 
* For Azure, I copy the **Federation Data XML** file to the system as vault-$domain.xml


## Download KeeperSSO Java Application
```
wget "https://keepersecurity.com/sso_connect/KeeperSso_java.zip" -O /tmp/KeeperSso_java.zip
sudo mkdir -p $install_dir
cd $install_dir
unzip /tmp/KeeperSso_java.zip 
sudo mv </path/to>/vault-$domain.xml $install_dir
sudo chown -R keeper.keeper $install_dir
```

## Generate a self-signed cert for the Java daemon
This does not need to be "valid" since we'll use nginx in front of it. We use a random password here (`$sslpass`)
```
openssl genrsa 2048 > private-$domain.pem
openssl req -x509 -new -key private-$domain.pem -out public-$domain.pem  \
    -nodes \
    -days 3650 \
    -subj "/C=US/ST=<mystate>/L=<mycity>/O=KeeperSSO/CN=$domain"
openssl pkcs12 -export -in public-$domain.pem -inkey private-$domain.pem -out cert-$domain.pfx -passout pass:$sslpass
```

## Run KeeperSSO Initial Configuration
```
cd $install_dir
parameters="-initialize $domain \
            -private_ip $local_ip \
            -sso_connect_host $public_hostname \
            -private_port $private_port \
            -sso_ssl_port $public_port \
            -idp_type 5 \
            -key_store_type p12 \
            -saml_file $saml_file \
            -ssl_file cert-$domain.pfx \
            -key_password $sslpass \
            -key_store_password $sslpass \
            -admin_port $admin_port "
sudo su keeper -c "java -jar SSOConnect.jar $parameters"
```
There *should* be no errors here. If there are, then you'll need to troubleshoot and resolve them before continuing.

## Set up the daemon to run KeeperSSO for this tenant on every startup. 
I name the files with that unique client identifier. 
Write this file (replacing variables as appropriate) to /etc/systemd/system/ssoconnect-$clientid.service
```
[Unit]
Description=SSO Connect Java Daemon Client $clientid

[Service]
WorkingDirectory=$install_dir
User=keeper
ExecStart=/usr/bin/java -jar $install_dir/SSOConnect.jar $install_dir

[Install]
WantedBy=multi-user.target
```

Then set it up to run:
```
sudo chmod 644 /etc/systemd/system/ssoconnect-$clientid.service
sudo systemctl enable ssoconnect-$clientid
sudo systemctl start ssoconnect-$clientid
```

And that's it! (hopefully)




