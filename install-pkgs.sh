#!/bin/bash

# Add PPA for php5.6
if [[ ! -f /etc/apt/sources.list.d/ondrej-ubuntu-php-xenial.list ]]; then
  apt-add-repository -y ppa:ondrej/php
fi

apt -y update
apt -y dist-upgrade
apt install -y monit git curl wget net-tools \
	apache2 mysql-client mysql-server psmisc htop screen openjdk-8-jre-headless openjdk-8-jdk \
	redis-server php5.6 php5.6-xdebug php5.6-mysql libapache2-mod-php5.6 \
	php5.6-curl php5.6-json php5.6-xml php5.6-xml php5.6-zip php5.6-mbstring php5.6-gd \
	nodejs npm unzip maven tree

ln -sf `which nodejs` /usr/bin/node

npm install -g grunt-cli
