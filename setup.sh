#!/bin/bash
sudo amazon-linux-extras install nginx1 -y
sudo yum install java-17-amazon-corretto-devel git -y
sudo mv /tmp/nginx.conf /etc/nginx/conf.d/
sudo systemctl enable nginx
sudo systemctl start nginx
sudo git clone https://github.com/piyushmanolkar/FlexMoney-Frontend.git /var/www/html
cd /var/www/html && git checkout ${var.backend_branch}
sudo git clone https://github.com/piyushmanolkar/FlexMoney-Java-Backend.git /var/www/backend
cd /var/www/backend && git checkout ${var.frontend_branch}
cd /var/www/backend
sudo chmod +x ./gradlew
sudo ./gradlew build
sudo mv /tmp/backend.service /usr/lib/systemd/system/ && systemctl enable backend && systemctl start backend