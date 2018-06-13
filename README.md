# ADConnector MFA

## Connectivity Diagram

![diagram](https://github.com/johnalvero/ADConnector-MFA/blob/master/diagram.jpeg)

## Note
Guide done in CentOS 7. Adjust guide for your own environment as necessary.

## NTP
If you are dealing with TOTP, time syncronization is important. This is specially more important if you are working with virtualized environment.
```
# Install the NTP package
yum install -y ntp

cat <<'EOF'> /etc/ntp.conf
# by default act only as a basic NTP client
restrict -4 default nomodify nopeer noquery notrap
restrict -6 default nomodify nopeer noquery notrap
 
# allow NTP messages from the loopback address, useful for debugging
restrict 127.0.0.1
restrict ::1
 
# server(s) we time sync to
server 0.asia.pool.ntp.org
server 1.asia.pool.ntp.org
server 2.asia.pool.ntp.org
server 3.asia.pool.ntp.org
EOF

systemctl start ntpd
```

## SELinux
LinOTP can support SELinux. No need to disable SELinux, just do the following:
```
yum install policycoreutils-python -y
semanage fcontext -a -t httpd_sys_content_t "/etc/linotp2(/.*)?"
semanage fcontext -a -t httpd_sys_rw_content_t "/etc/linotp2/data(/.*)?"
semanage fcontext -a -t httpd_sys_rw_content_t "/var/log/linotp(/.*)?"
```


## Installing LinOTP
```
yum install git epel-release -y
yum localinstall http://linotp.org/rpm/el7/linotp/x86_64/Packages/LinOTP_repos-1.1-1.el7.x86_64.rpm
git clone https://github.com/johnalvero/ADConnector-MFA.git /usr/local/ADConnector-MFA

# MariaDB (can also work with MySQL)
yum install mariadb-server -y
systemctl enable mariadb
systemctl start mariadb
mysql_secure_installation

# LinOTP
yum install -y LinOTP LinOTP_mariadb 
restorecon -Rv /etc/linotp2/
restorecon -Rv /var/log/linotp

# Setup the dababase and credentials
linotp-create-mariadb

# Lock python-repoze-who version
yum install yum-plugin-versionlock
yum versionlock python-repoze-who

# install apache and vhost config
yum install LinOTP_apache
setsebool -P httpd_can_network_connect_db on
setsebool -P httpd_can_connect_ldap on

mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.back
mv /etc/httpd/conf.d/ssl_linotp.conf.template /etc/httpd/conf.d/ssl_linotp.conf

systemctl enable httpd
systemctl start httpd

# openfirewall
firewall-cmd --zone=public --add-port=443/tcp --permanent
firewall-cmd --zone=public --add-port=80/tcp --permanent
firewall-cmd --zone=public --add-port=1812/udp --permanent
firewall-cmd --zone=public --add-port=1813/udp --permanent
firewall-cmd --reload

# change the admin password
htdigest /etc/linotp2/admins "LinOTP2 admin area" admin

# Fix LinOTP bug @ https://github.com/LinOTP/LinOTP/issues/85
# Fixes the bug where a session expired error is encountered everywhere in the admin portal

vi /usr/lib/python2.7/site-packages/linotp/lib/userservice.py

#try to get (local) selfservice
#if none is present fall back to possible
#userauthcookie (cookie for remote self service)

cookie = request.cookies.get(
    'user_selfservice', request.cookies.get(
        'userauthcookie', 'no_auth_cookie'))

session = request.params.get('session', 'no_session')

#fix
session = session.replace("\\075", "=")
#fix

# navigate to admin portal
https://<ip>/manage
Username: admin
```

## Configuring LinOTP

### Users
1. Setup your AD/LDAP UserIdResolver
2. The previous step will automatically prompt you to create the default realm
You should now be able to see your users from the User View

### Policies
Go to the Policies tab to import *policy.cfg*. The policy will setup the following:
1. TOTP enrollment in the selfservice portal
2. Reset Token
3. Resync Token
4. Set OTP Pin
5. Disable Token
6. Limit to one token per user
7. Use token to authenticate

Adjust the policies as needed. But for testing purposes, the applied policy is enough.

### Assign a token to test user

 1. Navigate to `https://<ip>/`
 2. Use your AD username & password to authenticate
 3. In the Enroll TOTP token tab, choose the following
```
Generate Random Seed
Google Authenticator compliant
```
 4. Click enroll TOTP token
 5. Scan the QR code using Google Authenticator in your mobile phone

You now have a TOTP token to be used for MFA.

### Test the token
```
curl -k 'https://localhost/validate/check?user=<username>&pass=<Token-From-Google-Authenticator>'

# Successful authentication should yield the following
{
   "version": "LinOTP 2.10.0.3", 
   "jsonrpc": "2.0802", 
   "result": {
      "status": true, 
      "value": true
   }, 
   "id": 0
}

If this is not the output you see, go back and review the installation steps.
```

## Installing Freeradius and packages
```
yum  install -y yum install freeradius freeradius-perl freeradius-utils perl-App-cpanminus perl-LWP-Protocol-https perl-Try-Tiny
cpanm Config::File
```

## Configuring FreeRadius
```
mv /etc/raddb/clients.conf /etc/raddb/clients.conf.back
mv /etc/raddb/users /etc/raddb/users.back

cat << 'EOF' > /etc/raddb/clients.conf
client localhost {
        ipaddr  = 127.0.0.1
        netmask = 32            
        secret  = 'SECRET' 
}

client adconnector {
        ipaddr  = <ip-range-of-ad-connector>
        netmask = <netmask-bit>            
        secret  = 'SECRET' 
}
EOF

# Download the freeradius linotp perl module
git clone https://github.com/LinOTP/linotp-auth-freeradius-perl.git /usr/share/linotp/linotp-auth-freeradius-perl

# Setup the linotp perl module
cat << 'EOF' > /etc/raddb/mods-available/perl
perl {
     filename = /usr/share/linotp/linotp-auth-freeradius-perl/radius_linotp.pm
}
EOF

# Activate it
ln -s /etc/raddb/mods-available/perl /etc/raddb/mods-enabled/perl

# freeradius linotp perl config
cat << 'EOF' > /etc/linotp2/rlm_perl.ini
URL=https://localhost/validate/simplecheck
REALM=<your-realm>
Debug=True
SSL_CHECK=False
EOF

# Remove unnecessary config
rm /etc/raddb/sites-enabled/inner-tunnel
rm /etc/raddb/sites-enabled/default
rm /etc/raddb/mods-enabled/eap 

# Activate the freeradius linotp virtual host
cp /usr/local/ADConnector-MFA/linotp /etc/raddb/sites-available/
ln -s /etc/raddb/sites-available/linotp /etc/raddb/sites-enabled/linotp


# Temporarily start radius
radiusd -X
```
## Testing Radius Authentication (OTP)
```
radtest <username> <token-from-google-authenticator> localhost 0 SECRET

# Success result
Sent Access-Request Id 19 from 0.0.0.0:50410 to 127.0.0.1:1812 length 81
	User-Name = "<username>"
	User-Password = "375937"
	NAS-IP-Address = 127.0.0.1
	NAS-Port = 0
	Message-Authenticator = 0x00
	Cleartext-Password = "375937"
Received Access-Accept Id 19 from 127.0.0.1:1812 to 0.0.0.0:0 length 43
	Reply-Message = "LinOTP access granted"
	
systemctl enable radiusd
systemctl start radiusd
```
## Enable radius-based MFA in AD Connector
In your AD Connector directory, go to the __Multi-Factor authentication__ tab. Apply the following settings
```
Enable Multi-Factor Authentication: Tick
RADIUS server IP address(es): <IP address of the radius server>
Shared secret code: <radius shared secret>
Protocol: PAP
```
### Login to the AWS Console
Moment of truth. It's time to login to your AWS console `https://<xxx>.awsapps.com/console/`
