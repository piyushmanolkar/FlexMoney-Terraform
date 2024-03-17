#!/bin/bash -ex

sudo amazon-linux-extras install nginx1 -y

sudo yum install java-17-amazon-corretto-devel git -y

sudo touch /etc/nginx/conf.d/nginx.conf

sudo cat <<CONF_APPEND >> /etc/nginx/conf.d/nginx.conf

# Nginx configuration file for reverse proxy to Spring Boot server

# Default server configuration
server {
    listen 80;

    server_name localhost;

    # Frontend static files
    location / {
      # Frontend root directory
      root /var/www/html;

      # Index file
      index index.html;
    }

    # Reverse proxy to Spring Boot backend
    location /api/ {
        proxy_pass http://127.0.0.1:8080/;
    }
}

CONF_APPEND

sudo systemctl enable nginx
sudo systemctl start nginx
sudo git clone https://github.com/piyushmanolkar/FlexMoney-Frontend.git /var/www/html
sudo git clone https://github.com/piyushmanolkar/FlexMoney-Java-Backend.git /var/www/backend
cd /var/www/backend 
sudo chmod +x ./gradlew
sudo ./gradlew build
sudo nohup java -jar build/libs/backend.jar &