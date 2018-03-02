#!/bin/bash

if [[ $UID == "0" ]]; then
  echo "You need to run this script as root."
  exit 1
fi

#######
# NOTES
#######
# If on proxy and building okapi & filters, you need to set maven's settings.xml

###############################
# Some configuration parameters
###############################
set -x
BASEDIR=$(dirname `realpath $0`)
SERVER="liumcat.univ-lemans.fr"
UNIXUSER="matecat"
DBUSER=${UNIXUSER}
WWWDIR="/home/${UNIXUSER}/www-data"
LOGDIR="/var/log/matecat"
STORAGEDIR="${WWWDIR}/storage"
ACTIVEMQ_VER="5.13.2"

# Checkout specific commits to ensure reproducibility
MATECAT_COMMIT="0f3f3ecaa45"
MATECAT_FILTERS_COMMIT="82f8210448"
FILTERS_DIR="/home/${UNIXUSER}/MateCat-Filters/filters/target"
FILTERS_JAR="filters-1.2.3.jar"
DUMP_DBPASS=
set +x

exit
##################
# Install packages
##################
if [[ ! -f /usr/bin/node ]]; then
  echo "Installing packages"

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
  if [[ ! -d "/opt/apache-activemq-${ACTIVEMQ_VER}" ]]; then
    adduser -system activemq
    sed -i "s#activemq:/bin/false#activemq:/bin/bash#g" /etc/passwd

    DIR="apache-activemq-${ACTIVEMQ_VER}"

    pushd /opt
    wget http://archive.apache.org/dist/activemq/${ACTIVEMQ_VER}/${DIR}-bin.tar.gz
    tar xzf ${DIR}-bin.tar.gz && rm ${DIR}-bin.tar.gz

    ln -sf /opt/${DIR}/ /opt/activemq
    chown -R activemq: /opt/${DIR}/
    ln -sf /opt/activemq/bin/activemq /etc/init.d/

    /etc/init.d/activemq create /etc/default/activemq
    chown root:nogroup /etc/default/activemq
    chmod 600 /etc/default/activemq
    sed -i 's/managementContext createConnector="false"/managementContext createConnector="true"/g' /etc/default/activemq/conf/activemq.xml
    ln -s /etc/init.d/activemq /usr/bin/activemq

    # Increase memory limits
    sed -i 's/^#ACTIVEMQ_OPTS_MEMORY.*$/ACTIVEMQ_OPTS_MEMORY=\"-Xms2G -Xmx4G\"/' /opt/activemq/bin/env
  fi
fi

##########################
# Create global log folder
##########################
if [[ ! -d $LOGDIR ]]; then
  echo "Preparing $LOGDIR"
  mkdir $LOGDIR
  chown www-data: $LOGDIR
fi

###############
# Clone MateCat
###############
if [[ ! -d ${WWWDIR} ]]; then
  git clone https://github.com/matecat/MateCat.git ${WWWDIR}
  pushd ${WWWDIR}
  git checkout $MATECAT_COMMIT
  popd
fi

###############
# Clone Filters
###############
if [[ ! -d "/home/${UNIXUSER}/MateCat-Filters" ]]; then
  git clone https://github.com/matecat/MateCat-Filters.git "/home/${UNIXUSER}/MateCat-Filters"
  pushd "/home/${UNIXUSER}/MateCat-Filters"
  git checkout $MATECAT_FILTERS_COMMIT
  dos2unix pom.xml
  popd
fi

OKAPI_COMMIT=$(grep 'okapi.commit' /home/${UNIXUSER}/MateCat-Filters/pom.xml | sed -r 's/.*<.*>(.*)<.*>/\1/')

#############
# Clone OKAPI
#############
if [[ ! -d "/home/${UNIXUSER}/okapi" ]]; then
  # Clone okapi
  git clone https://bitbucket.org/okapiframework/okapi.git /home/${UNIXUSER}/okapi
  pushd /home/${UNIXUSER}/okapi
  echo $OKAPI_COMMIT
  git checkout "$OKAPI_COMMIT"
  # Build OKAPI
  mvn clean install -DskipTests=true
  popd
fi

###############
# Build Filters
###############
if [[ ! -f "${FILTERS_DIR}/${FILTERS_JAR}" ]]; then
  # Build filters
  pushd /home/${UNIXUSER}/MateCat-Filters/filters
  mvn clean package -DskipTests=true
  cp src/main/resources/config.sample.properties target/config.properties
fi

###################
# Configure MateCat
###################
if [[ ! -f ${WWWDIR}/inc/task_manager_config.ini ]]; then
  pushd ${WWWDIR}/inc
  cp task_manager_config.ini.sample task_manager_config.ini
  popd
fi

if [[ ! -f ${WWWDIR}/inc/config.ini ]]; then
  pushd ${WWWDIR}/inc
  cp config.ini.sample config.ini
  sed -i "s:^CLI_HTTP_HOST.*$:CLI_HTTP_HOST = \"http\://${SERVER}\":" config.ini
  sed -i "s:^STORAGE_DIR.*$:STORAGE_DIR = \"${STORAGEDIR}\":" config.ini
  sed -i "s:^FILTERS_ADDRESS.*$:FILTERS_ADDRESS = \"http\://localhost\:8732\":" config.ini
  sed -i "/FILTERS_MASHAPE_KEY/d" config.ini

  # Configure mail
  sed -i "s:matecat\.loc:${SERVER}:" config.ini

  # Add additional stuff
  echo "MAILER_FROM = 'cattool@${SERVER}'" >> config.ini
  echo "MAILER_RETURN_PATH = 'no-reply@${SERVER}'" >> config.ini
  echo "FAST_ANALYSIS_MEMORY_LIMIT = '4096M'" >> config.ini

  cd ..
  echo 'Patching MateCat configuration files.'
  patch -p1 < "${BASEDIR}/data/matecat.patch"
  popd
fi

####################
# Configure services
####################
grep "www-data.*${UNIXUSER}" /etc/group &> /dev/null
if [[ $? == "1" ]]; then
  echo "Configuring services"

  # Add user if not
  grep $UNIXUSER /etc/passwd &> /dev/null
  if [[ $? == "1" ]]; then
    echo "Adding user $UNIXUSER"
    adduser --gecos "" ${UNIXUSER}
  fi

  # Add the user to www-data group
  usermod -a -G www-data ${UNIXUSER}

  # Configure apache & PHP
  echo "short_open_tag = On" >> /etc/php/5.6/cli/php.ini
  echo "memory_limit = 4096M" >> /etc/php/5.6/cli/php.ini
  a2enmod rewrite filter deflate headers expires proxy_http.load

  # Make apache proxy aware
  grep -i 'proxy.*=' /etc/environment | sed -r 's/(.*)/export \1/g' >> /etc/apache2/envvars

  # Configure Redis
  sed -i 's/bind 127.0.0.1/bind 0.0.0.0/g' /etc/redis/redis.conf

  # Configure MySQL
  # See: https://github.com/matecat/MateCat/issues/768
  echo -e '[mysqld]\nsql-mode="NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION"' >> /etc/mysql/mysql.conf.d/mysqld.cnf
  systemctl restart mysql.service

  # Create MySQL scheme
  DUMP_DBPASS=1

  # Generate DBPASS
  DBPASS=`cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w ${1:-10} | head -n 1`

  # set DB password for matecat and import SQL
  sed -i "s/^DB_PASS.*$/DB_PASS = \"${DBPASS}\"/" ${WWWDIR}/inc/config.ini

  SQLFILE="${WWWDIR}/INSTALL/matecat.sql"
  sed "s/matecat01/${DBPASS}/g" < $SQLFILE > /tmp/matecat.sql
  echo '(You will be prompted root password for mysql root account)'
  mysql -uroot -p < /tmp/matecat.sql
  rm /tmp/matecat.sql
  echo "Your database password for user ${DBUSER} is: ${DBPASS}"
fi

#######################
# Install Node packages
#######################
if [[ ! -f ${WWWDIR}/nodejs/config.ini ]]; then
  pushd ${WWWDIR}/nodejs
  npm install
  cp config.ini.sample config.ini
  sed -i "s#log/server\.log#${LOGDIR}/nodejs_server.log#" config.ini
  popd
fi

if [[ ! -d ${WWWDIR}/support_scripts/grunt/node_modules ]]; then
  pushd ${WWWDIR}/support_scripts/grunt
  npm install
  grunt deploy
  popd
fi

###################
# Install PHP stuff
###################
if [[ ! -f ${WWWDIR}/composer.phar ]]; then
  pushd $WWWDIR
  curl -L https://getcomposer.org/installer | php
  php composer.phar install
  popd
fi

#######################
# Install systemd files
#######################
for SYSTEMD in ${BASEDIR}/data/*.service; do
  ETCPATH="/etc/systemd/system/`basename $SYSTEMD`"
  echo "Adding/updating $ETCPATH service"
  sed "s#@WWWDIR@#${WWWDIR}#g; s#@FILTERS_DIR@#${FILTERS_DIR}#g" < $SYSTEMD > ${ETCPATH}
  chmod 664 $ETCPATH
  systemctl enable `basename $SYSTEMD`
  systemctl start `basename $SYSTEMD`
done
systemctl daemon-reload

#####################
# Enable apache2 site
#####################
if [[ ! -f /etc/apache2/sites-available/matecat.conf ]]; then
  sed "s#@WWWDIR@#${WWWDIR}#" < data/matecat-vhost.conf > /tmp/matecat.conf
  mv /tmp/matecat.conf /etc/apache2/sites-available
  a2dissite 000-default
  a2ensite matecat.conf
  service apache2 restart
fi

#########################
# Configure proxy for PHP
#########################
PHP_PROXY="/etc/php/5.6/cli/proxy_setup.php"
if [[ ! -z ${HTTP_PROXY} ]] && [[ ! -f ${PHP_PROXY} ]]; then
    echo "Found proxy ${HTTP_PROXY}"
    PROXY_STR=`echo ${HTTP_PROXY} | sed 's#https#tcp#; s#http#tcp#'`
    sed "s#HTTP_PROXY_STR#${PROXY_STR}#; s#HTTPS_PROXY_STR#${PROXY_STR}#" < ${BASEDIR}/data/proxy.php > ${PHP_PROXY}
    echo auto_prepend_file = \"/etc/php/5.6/cli/proxy_setup.php\" >> /etc/php/5.6/cli/php.ini
fi

# Give MateCat to www-data
chown -R www-data: `realpath ${WWWDIR}`
chmod 755 ${WWWDIR}

echo "Clearing previous logs"
rm -rf ${LOGDIR}/*
rm -rf /var/log/apache2/matecat*

echo "Restarting services"
systemctl restart --all apache2* matecat* mysql* redis-server.service

if [[ ! -z $DUMP_DBPASS ]]; then
  echo "Your database password for user ${DBUSER} is: ${DBPASS}"
fi
