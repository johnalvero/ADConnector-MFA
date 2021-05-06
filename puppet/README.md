## Assumptions
  - SELinux is disabled
  - OS IPtables is disabled
  - NTP time is properly setup
  

## Puppet Instructions
1. Create the database (RDS MySQL/Stand Alone EC2). There is no need to create the table schema, LinOTP will create the tables automatically
2. Create the token encryption key and upload to an S3 bucket
```
dd if=/dev/urandom of=encKey bs=1 count=96
aws s3 cp encKey s3://<bucket/<path>/encKey
```
3. Create a keypair for audit log signing
```
openssl genrsa -out private.pem 2048
openssl rsa -in private.pem -pubout -out public.pem

aws s3 cp public.pem s3://<bucket/<path>/public.pem
aws s3 cp private.pem s3://<bucket/<path>/private.pem
```
4. Open the file init.pp and setup the configurable parameters
5. Make sure that the instance has a role or credentials to pull the encKey from the bucket
6. Apply the puppet script
```
puppet apply init.pp --parser future
```


Note: if radius does not start
```
install cpan
cpanm Config::File
check permission for (755) /usr/lib64/perl5/vendor_perl/Config
```
