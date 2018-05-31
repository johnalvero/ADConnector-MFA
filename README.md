# ADConnector-MFA

## NTP
```
yum install -y ntp

cat <<'EOF' /etc/ntp.conf
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
```
yum install policycoreutils-python -y
semanage fcontext -a -t httpd_sys_content_t "/etc/linotp2(/.*)?"
semanage fcontext -a -t httpd_sys_rw_content_t "/etc/linotp2/data(/.*)?"
semanage fcontext -a -t httpd_sys_rw_content_t "/var/log/linotp(/.*)?"
setsebool -P httpd_can_network_connect_db on
setsebool -P httpd_can_connect_ldap on
```


## Installing LinOTP
```
yum install git -y
git clone https://github.com/johnalvero/ADConnector-MFA.git /usr/local/ADConnector-MFA
yum localinstall http://linotp.org/rpm/el7/linotp/x86_64/Packages/LinOTP_repos-1.1-1.el7.x86_64.rpm
yum install -y epel-release

yum install mariadb-server -y
systemctl enable mariadb
systemctl start mariadb
mysql_secure_installation

yum install -y LinOTP LinOTP_mariadb 

restorecon -Rv /etc/linotp2/
restorecon -Rv /var/log/linotp

linotp-create-mariadb

yum install yum-plugin-versionlock
yum versionlock python-repoze-who

# install apache and config
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
firewall-cmd --reload

# change the admin password
htdigest /etc/linotp2/admins "LinOTP2 admin area" admin

# Fix LinOTP bug @ https://github.com/LinOTP/LinOTP/issues/85

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
Go to the Policies tab to import policy.cfg. The policy allow for the following:
1. TOTP enrollment in the selfservice portal
2. Reset Token
3. Resync Token
4. Set OTP Pin
5. Disable Token
6. Limit to one token per user
7. Use token to authenticate

Adjust the policies as per business need.

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

# Successful authentication should yielf the following
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

## Installing Freeradius
```
yum  install -t yum install freeradius freeradius-perl freeradius-utils
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

yum install -y git perl-App-cpanminus perl-LWP-Protocol-https
git clone https://github.com/LinOTP/linotp-auth-freeradius-perl.git /usr/share/linotp/linotp-auth-freeradius-perl
cpanm Config::File

cat << 'EOF' > /etc/raddb/mods-available/perl
perl {
	filename = /usr/share/linotp/linotp-auth-freeradius-perl/radius_linotp.pm
}
EOF
ln -s /etc/raddb/mods-available/perl /etc/raddb/mods-enabled/perl

cat << 'EOF > /etc/linotp2/rlm_perl.ini
URL=https://localhost/validate/simplecheck
REALM=<your-realm>
Debug=True
SSL_CHECK=False
EOF

rm /etc/raddb/sites-enabled/inner-tunnel 

cp /usr/local/ADConnector-MFA/linotp /etc/raddb/sites-available/
ln -s /etc/raddb/sites-available/linotp /etc/raddb/sites-enabled/linotp
rm /etc/raddb/mods-enabled/eap 

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
