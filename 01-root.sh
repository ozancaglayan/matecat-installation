#!/bin/bash
DBPASS="dbmatecat1234"

# Add PPA for php5.6
apt-add-repository -y ppa:ondrej/php

apt -y update
apt install -y build-essential monit git curl wget net-tools \
	apache2 mysql-client mysql-server psmisc htop screen openjdk-8-jre-headless \
	redis-server php5.6 php5.6-xdebug php5.6-mysql libapache2-mod-php5.6 \
	php5.6-curl php5.6-json php5.6-xml php5.6-xml \
	nodejs npm unzip

ln -sf `which nodejs` /usr/bin/node

# Add matecat user
adduser --disabled-password --gecos "" matecat

# Configure apache
# TODO: ServerName??
a2enmod rewrite filter deflate headers expires proxy_http.load
service apache2 restart

# Configure MySQL
# See: https://github.com/matecat/MateCat/issues/768
echo -e '[mysqld]\nsql-mode="NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION"' >> /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl restart mysql.service

# Configure Redis
sed -i 's/bind 127.0.0.1/bind 0.0.0.0/g' /etc/redis/redis.conf
systemctl restart redis-server.service

# Import SQL
# Get matecat .sql schema from 201705
curl -L https://github.com/matecat/MateCat/files/984512/matecat_schema.sql.zip | funzip > /tmp/matecat.sql

# set DB password for matecat and import SQL
sed -i "s/matecat01/${DBPASS}/g" /tmp/matecat.sql
echo '(You will be prompted root password for mysql root account)'
mysql -uroot -p < /tmp/matecat.sql
rm /tmp/matecat.sql

# Install grunt
npm install -g grunt-cli
