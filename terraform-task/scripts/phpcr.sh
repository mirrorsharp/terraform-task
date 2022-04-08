#!/bin/bash

sudo su

yum update -y

amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2

yum install -y httpd
systemctl start httpd
systemctl enable httpd

usermod -a -G apache ec2-user

systemctl restart httpd

chown -R ec2-user:apache /var/www
sudo chmod 2775 /var/www
find /var/www -type d -exec sudo chmod 2775 {} \;
find /var/www -type f -exec sudo chmod 0664 {} \;

cd /var/www
mkdir inc
cd inc

cat <<'EOF' > script.sql
CREATE DATABASE php_mysql_crud;
use php_mysql_crud;
CREATE TABLE task(
  id INT(11) PRIMARY KEY AUTO_INCREMENT,
  title VARCHAR(255) NOT NULL,
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF
export ENDPOINT=`aws rds --output=text --region us-east-1 describe-db-instances --query "DBInstances[*].Endpoint.Address"`
export MYSQL_PWD=pas12345
mysql -h $ENDPOINT -u root < script.sql

cat <<EOF > dbinfo.inc
<?php

define('DB_SERVER', "$ENDPOINT");
define('DB_USERNAME', 'root');
define('DB_PASSWORD', 'pas12345');
define('DB_DATABASE', 'php_mysql_crud');

?>
EOF

cd /var/www/html
export BUCKET=`aws s3api --output=text --region us-east-1 list-buckets --query "Buckets[].Name"`
aws s3 sync s3://"$BUCKET" . 

sed -i 's/db.php/..\/inc\/dbinfo.inc/g' index.php
sed -i '/header.php/a \
<?php \
$conn = mysqli_connect(DB_SERVER, DB_USERNAME, DB_PASSWORD); \
if (mysqli_connect_errno()) echo "Failed to connect to MySQL: " . mysqli_connect_error(); \
mysqli_select_db($conn, DB_DATABASE); \
?>' index.php

sed -i 's/db.php/..\/inc\/dbinfo.inc/g' save_task.php
sed -i '/dbinfo.inc/a \
$conn = mysqli_connect(DB_SERVER, DB_USERNAME, DB_PASSWORD); \
if (mysqli_connect_errno()) echo "Failed to connect to MySQL: " . mysqli_connect_error(); \
mysqli_select_db($conn, DB_DATABASE);' save_task.php

sed -i 's/db.php/..\/inc\/dbinfo.inc/g' edit.php
sed -i '/dbinfo.inc/a \
$conn = mysqli_connect(DB_SERVER, DB_USERNAME, DB_PASSWORD); \
if (mysqli_connect_errno()) echo "Failed to connect to MySQL: " . mysqli_connect_error(); \
mysqli_select_db($conn, DB_DATABASE);' edit.php

sed -i 's/db.php/..\/inc\/dbinfo.inc/g' delete_task.php
sed -i '/dbinfo.inc/a \
$conn = mysqli_connect(DB_SERVER, DB_USERNAME, DB_PASSWORD); \
if (mysqli_connect_errno()) echo "Failed to connect to MySQL: " . mysqli_connect_error(); \
mysqli_select_db($conn, DB_DATABASE);' delete_task.php

cd /etc/httpd/conf/

sed -i '/# Supplemental configuration/i \
<VirtualHost *:80> \
RewriteEngine On \
RewriteCond %{HTTP:X-Forwarded-Proto} =http \
RewriteRule .* https://%{HTTP:Host}%{REQUEST_URI} [L,R=permanent] \
</VirtualHost>' httpd.conf

yum install -y mod_ssl
cd /etc/pki/tls/certs
./make-dummy-cert localhost.crt
cd /etc/httpd/conf.d/
sed -i 's/SSLCertificateKeyFile/#SSLCertificateKeyFile/g' ssl.conf
systemctl restart httpd