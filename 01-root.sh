#!/bin/bash
source ./vars.sh

# Add PPA for php5.6
apt-add-repository -y ppa:ondrej/php

apt -y update
apt install -y build-essential monit git curl wget net-tools \
	apache2 mysql-client mysql-server psmisc htop screen openjdk-8-jre-headless \
	redis-server php5.6 php5.6-xdebug php5.6-mysql libapache2-mod-php5.6 \
	php5.6-curl php5.6-json php5.6-xml php5.6-xml \
	nodejs npm unzip maven

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

# Download activemq
pushd /tmp
wget http://archive.apache.org/dist/activemq/5.13.2/apache-activemq-5.13.2-bin.tar.gz
tar xzf apache-activemq-5.13.2-bin.tar.gz && rm apache-activemq-5.13.2-bin.tar.gz
mv apache-activemq-5.13.2 /opt
ln -sf /opt/apache-activemq-5.13.2/ /opt/activemq
adduser -system activemq
sed -i "s#activemq:/bin/false#activemq:/bin/bash#g" /etc/passwd
chown -R activemq: /opt/apache-activemq-5.13.2/
ln -sf /opt/activemq/bin/activemq /etc/init.d/

/etc/init.d/activemq create /etc/default/activemq
chown root:nogroup /etc/default/activemq
chmod 600 /etc/default/activemq
sed -i 's/managementContext createConnector="false"/managementContext createConnector="true"/g' /etc/default/activemq/conf/activemq.xml
ln -s /etc/init.d/activemq /usr/bin/activemq
/etc/init.d/activemq start

# Setup rc.local
sed -i 's#exit 0##g' /etc/rc.local
echo "screen -d -m -S 'node' node ${WWWDIR}/nodejs/server.js" >> /etc/rc.local
echo "/usr/bin/activemq start" >> /etc/rc.local
echo "/bin/bash ${WWWDIR}/daemons/restartAnalysis.sh" >> /etc/rc.local
echo "exit 0" >> /etc/rc.local
