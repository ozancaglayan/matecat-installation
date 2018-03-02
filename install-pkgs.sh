#!/bin/bash

# Add PPA for php5.6
if [[ ! -f /etc/apt/sources.list.d/ondrej-ubuntu-php-xenial.list ]]; then
  apt-add-repository -y ppa:ondrej/php
fi

apt -y update
apt -y dist-upgrade
apt install -y git curl wget net-tools dos2unix \
	apache2 mysql-client mysql-server psmisc htop screen openjdk-8-jre-headless openjdk-8-jdk \
	redis-server php5.6 php5.6-xdebug php5.6-mysql libapache2-mod-php5.6 \
	php5.6-curl php5.6-json php5.6-xml php5.6-xml php5.6-zip php5.6-mbstring php5.6-gd \
	nodejs npm unzip maven tree

# Make php5.6 the default
update-alternatives --set php /usr/bin/php5.6

# Create compatibility link
ln -sf `which nodejs` /usr/bin/node

# Install grunt-cli globally
npm install -g grunt-cli

# Install ActiveMQ
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

# Increase memory limits
sed -i 's/^#ACTIVEMQ_OPTS_MEMORY.*$/ACTIVEMQ_OPTS_MEMORY=\"-Xms2G -Xmx4G\"/' /opt/activemq/bin/env
