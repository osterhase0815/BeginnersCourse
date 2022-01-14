#!/bin/bash
# ********************************************************************************************************************************************
# configure_myphpadmin
# ********************************************************************************************************************************************

export NGINX_FQDN="${nginx_fqdn}"
export DB_FQDN="${db_fqdn}"
export DB_USER="${db_user}"
export DB_PWD="${db_pwd}"

echo "NGINX_FQDN='$NGINX_FQDN'"
echo "DB_FQDN='$DB_FQDN'"
echo "DB_USER='$DB_USER'"
echo "DB_PWD='$DB_PWD'"

# ************************************************************************
configure_myphpadmin() {

sudo tee /etc/dbconfig-common/phpmyadmin.conf <<EOT
  # automatically generated by the maintainer scripts of phpmyadmin
  # any changes you make will be preserved, though your comments
  # will be lost!  to change your settings you should edit this
  # file and then run "dpkg-reconfigure phpmyadmin"
  
  # dbc_install: configure database with dbconfig-common?
  #              set to anything but "false" to opt out of assistance
  dbc_install='false'
  
  # dbc_upgrade: upgrade database with dbconfig-common?
  #              set to anything but "false" to opt out of assistance
  dbc_upgrade='false'
  
  # dbc_remove: deconfigure database with dbconfig-common?
  #             set to anything but "false" to opt out of assistance
  dbc_remove='false'
EOT
  
sudo tee /etc/phpmyadmin/config-db.php <<EOT
<?php
  # !!! dbname is mandatory or login won't work!!!
  #
  \$dbuser='$DB_USER';
  \$dbpass='$DB_PWD';
  \$basepath='';
  \$dbname='phpmyadmin';
  \$dbserver='$DB_FQDN';
  \$dbport='3306';
  \$dbtype='mysql';
?>
EOT
}

# ********************************************************************************************************************************************
# create_nginx_conf
# ********************************************************************************************************************************************
#
create_nginx_conf () {
# with php
sudo tee -a /etc/nginx/fastcgi_params <<EOT
  fastcgi_param  SCRIPT_FILENAME    \$document_root\$fastcgi_script_name; 
EOT

sudo tee /etc/nginx/fastcgi.conf <<EOT 
  # 404
  try_files \$fastcgi_script_name =404;

  # default fastcgi_params
  include fastcgi_params;

  # fastcgi settings
# fastcgi_pass			unix:/run/php/php7.2-fpm.sock;
  fastcgi_index			index.php;
  fastcgi_buffers			8 16k;
  fastcgi_buffer_size		32k;
  fastcgi_hide_header             X-Powered-By;
  fastcgi_hide_header             X-CF-Powered-By;
EOT

sudo tee /etc/nginx/nginx.conf <<EOT 
  user www-data;
  worker_processes auto;
  pid /run/nginx.pid;
  include /etc/nginx/modules-enabled/*.conf;

  events  {
    worker_connections 768;
    # multi_accept on;
  }
  
  http {
    ##
    # Basic Settings
    ##
  
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    # server_tokens off;
    # server_names_hash_bucket_size 64;
    # server_name_in_redirect off;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    ##
    # SSL Settings
    ##
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2; # Dropping SSLv3, ref: POODLE
    ssl_prefer_server_ciphers on;
  
    ##
    # Logging Settings
    ##
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    ##
    # Gzip Settings
    ##
    gzip on;
    # gzip_vary on;
    # gzip_proxied any;
    # gzip_comp_level 6;
    # gzip_buffers 16 8k;
    # gzip_http_version 1.1;
    # gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    ##
    # Virtual Host Configs
    ##
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
  }
EOT

sudo rm -f /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/$NGINX_FQDN
sudo mkdir /var/www/$NGINX_FQDN
sudo tee /etc/nginx/sites-available/$NGINX_FQDN <<EOT 
  # Virtual Host configuration for 
  #
  # You can move that to a different file under sites-available/ and symlink that
  # to sites-enabled/ to enable it.
  #
  server {

    server_name $NGINX_FQDN;

    root /var/www/$NGINX_FQDN;
    index index.php;

    location / {
#         try_files $uri $uri/ =404;
    }
  
    location ~ \.php$ {
      try_files \$uri =404;
      fastcgi_pass unix:/run/php/php7.2-fpm.sock;
      fastcgi_index index.php;
      fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
      include fastcgi_params;
      }   
  }
EOT
sudo ln -s /etc/nginx/sites-available/$NGINX_FQDN /etc/nginx/sites-enabled/$NGINX_FQDN
}

# ********************************************************************************************************************************************
# main
# ********************************************************************************************************************************************
#
# ============ set local time  =============================
# 
sudo rm -f /etc/localtime 
sudo ln -s /usr/share/zoneinfo/Europe/Berlin /etc/localtime
#
# ============ nginx =============================
#
sudo apt-get update
sudo apt install nginx -y

# ============ php w.o. apache =============================
# the sequence of packets does the trick somehow
#
sudo apt install php7.2-fpm php-cgi -y
sudo apt install php php-cli -y
sudo apt install php-json php-mysql php-zip php-gd  php-mbstring php-curl php-xml php-pear php-bcmath -y
create_nginx_conf
sudo systemctl restart nginx
#
# ============ certbot =============================
#
sudo snap install core && sudo snap refresh core
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
#sudo /bin/sh -v -c "/usr/bin/certbot --test-cert --agree-tos --email <your_email>@somewhere -n --nginx --domains $NGINX_FQDN"
 sudo /bin/sh -v -c "/usr/bin/certbot --agree-tos --email hans.volpe@gmx.de -n --nginx --domains $NGINX_FQDN"
sudo systemctl restart nginx
#
# ============ phpMyAdmin =============================
#
sudo sh -c "DEBIAN_FRONTEND=noninteractive apt-get -y install phpmyadmin"
ln -s /usr/share/phpmyadmin /var/www/$NGINX_FQDN/phpmyadmin
configure_myphpadmin
#
# ugly patch to avoid error message for empty array with count()
# echo sudo sed -i \"s/|\s*\((count(\$analyzed_sql_results\['select_expr'\]\)/| (\1)/g\" /usr/share/phpmyadmin/libraries/sql.lib.php
sudo sed -i "s/|\s*\((count(\$analyzed_sql_results\['select_expr'\]\)/| (\1)/g" /usr/share/phpmyadmin/libraries/sql.lib.php
#
sudo mysql -h "$DB_FQDN" -u "$DB_USER" -p "$DB_PWD" < /usr/share/phpmyadmin/sql/create_tables.sql 
sudo systemctl restart nginx