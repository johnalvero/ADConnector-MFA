## Puppet Instructions
1. Create the token encryption key and upload to S3
```
dd if=/dev/urandom of=encKey bs=1 count=96
aws s3 cp encKey s3://<bucket/<path>/encKey
```
2. xx
