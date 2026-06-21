#!/bin/bash
dnf update -y
dnf install -y httpd

systemctl enable httpd
systemctl start httpd

echo "<h1>Frontend Server - Apache HTTPD</h1>" > /var/www/html/index.html
