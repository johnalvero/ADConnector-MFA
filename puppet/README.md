## Assumptions
  - SELinux is disabled
  - OS IPtables is disabled
  

## Puppet Instructions
1. Create the database (RDS MySQL/Stand Alone EC2)
2. Create the token encryption key and upload to S3
```
dd if=/dev/urandom of=encKey bs=1 count=96
aws s3 cp encKey s3://<bucket/<path>/encKey
```
3. Create the admin digest authentication
```
USERNAME=<username> && REALM="LinOTP2 admin area" && PASSWORD=<password>
PWDIGEST=`echo -n "$USERNAME:$REALM:$PASSWORD" | md5sum | cut -f1 -d ' '`
echo "$USERNAME:$REALM:$PWDIGEST"
```
4. Open the file init.pp and setup the configurable parameters
5. Apply the puppet script
6. Make sure that the instance has a role or credentials to pull the encKey from the bucket
```
puppet apply init.pp --parser future
```
