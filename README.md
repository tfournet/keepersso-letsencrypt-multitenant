# Setting up KeeperSSO for MultiTenancy with LetsEncrypt SSL Certs using NGINX

This is a rough guide of how I set up a single Linux host to enable Single-Sign-On capabilities for [Keeper Security](https://www.keepersecurity.com)
for multiple companies. We used CentOS 7 but any linux distro should work with some modifications
Keeper 


## hi
stuff

```
# Do SeLinux modifications so things work
semanage port -a -t http_port_t -p tcp 10000-10500
semanage port -a -t http_port_t -p tcp 8000-8500
semanage port -a -t http_port_t -p tcp 20000-20500
setsebool -P httpd_can_network_connect on
```
