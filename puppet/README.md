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
3. Create a keypair for audit signing
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
