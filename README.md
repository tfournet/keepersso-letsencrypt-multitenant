# Setting up KeeperSSO for MultiTenancy with LetsEncrypt SSL Certs using NGINX

This is a rough guide of how I set up a single Linux host to enable Single-Sign-On capabilities for [Keeper Security](https://www.keepersecurity.com)
for multiple companies. We used CentOS 7 on MS Azure but any linux distro should work with some modifications.

We have our own scripts for setting this up in a nearly fully-automated fashion, but these are specific to our environment and wouldn't be of use to anyone else

## Components

* Linux server with the ability to receive incoming connections on selected ports
* KeeperSSO install file 
* LetsEncrypt Certbot
* Apache NGINX
* SAML Platform - We use Azure Active Directory

## Planning

* TCP Ports. There will be 3 for each tenant that gets set up:
  * Private Port - 
    * This will be where the KeeperSSO java listens for SAML requests
    * We will refer to this as `$private_port`
  * Public Port
    * NGINX will listen on this port, provide a valid SSL cert, and forward connections to the private port
    * We will refer to this as `$public_port`
  * Admin Port
    * We won't bother forwarding this, but we will configure it in case of future troubleshooting or configuration is required
    * We will refer to this as `$admin_port`
   
In our case, we used ranges beginning with port `8000` for `$private_port`, `10000` for `$public_port`, and `20000` for `$admin_port`. In our examples we will assume this, but feel free to change it at your own discretion.


## Initial Setup

First off, SELinux needs to allow connections on these ports. Default configurations may limit the ports that daemons are allowed to open.

### SELinux Rules:
```
# Do SeLinux modifications so things work
sudo semanage port -a -t http_port_t -p tcp 10000-10500
sudo semanage port -a -t http_port_t -p tcp 8000-8500
sudo semanage port -a -t http_port_t -p tcp 20000-20500
sudo setsebool -P httpd_can_network_connect on
```

### Install LetsEncrypt CertBot, Apache NGINX, and the NGINX Module for CertBot:

```
sudo yum -y install epel-release
sudo yum -y install certbot nginx python2-certbot-nginx
```
