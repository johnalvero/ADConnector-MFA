## ADConnector-MFA

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
```


### Installing LinOTP

- asfasdf
- sdfsadf

### Configuring LinOTP

### Installing Freeradius

### Configuring FreeRadius

### Testing Radius Authentication (OTP)
