## Puppet Instructions
1. Create the token encryption key and upload to S3
```
dd if=/dev/urandom of=encKey bs=1 count=96
aws s3 cp encKey s3://<bucket/<path>/encKey
```
2. Create the admin digest authentication
```
USERNAME=<username> && REALM="LinOTP2 admin area" && PASSWORD=<password>
PWDIGEST=`echo -n "$USERNAME:$REALM:$PASSWORD" | md5sum | cut -f1 -d ' '`
echo "$USERNAME:$REALM:$PWDIGEST"
```
3. Open the file init.pp and setup the configurable parameters
3. Apply the puppet script
```
puppet apply init.pp --parser future
```
