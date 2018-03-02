#!/bin/bash
source ./vars.sh

#######
# NOTES
#######
# Proxy
# You need to set maven settings.xml file for proxy

# Checkout specific commits to ensure reproducibility
MATECAT_COMMIT="0f3f3ecaa45"
MATECAT_FILTERS_COMMIT="82f8210448"
FILTERS_DIR="/home/${UNIXUSER}/MateCat-Filters/filters/target"
FILTERS_JAR="filters-1.2.3.jar"
RUNROOT="sudo -i -u root -- "
DUMP_DBPASS=

##################
# Install packages
##################
if [[ ! -f /usr/bin/node ]]; then
  echo "Installing packages"
  $RUNROOT `realpath install-pkgs.sh`
fi

###################
# Check PHP version
###################
PHPVER=`php --version | grep "^PHP" | awk '{ print $2 }'`
if [[ ! $PHPVER =~ ^5.6.* ]]; then
  echo 'You need to set default PHP to php5.6'
  exit 1
fi

##########################
# Create global log folder
##########################
if [[ ! -d /var/log/matecat ]]; then
  echo "Preparing /var/log/matecat"
  $RUNROOT mkdir /var/log/matecat
  $RUNROOT chown www-data: /var/log/matecat
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
  PATCHFILE=`realpath data/matecat.patch`
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
  patch -p1 < $PATCHFILE
  popd
fi

####################
# Configure services
####################
grep "www-data.*${UNIXUSER}" /etc/group &> /dev/null
if [[ $? == "1" ]]; then
  echo "Configuring services"
  $RUNROOT `realpath configure.sh`

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
  # NOTE: log level is debug!
  sed -i 's/log\/server\.log/\/var\/log\/matecat\/nodejs_server.log/' config.ini
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
for SYSTEMD in data/*.service; do
  ETCPATH="/etc/systemd/system/`basename $SYSTEMD`"
  echo "Adding/updating $ETCPATH service"
  sudo -u root sh -c "sed \"s#@WWWDIR@#${WWWDIR}#g; s#@FILTERS_DIR@#${FILTERS_DIR}#g\" < $SYSTEMD > ${ETCPATH}"
  $RUNROOT chmod 664 $ETCPATH
  $RUNROOT systemctl enable `basename $SYSTEMD`
  $RUNROOT systemctl start `basename $SYSTEMD`
done
$RUNROOT systemctl daemon-reload

#####################
# Enable apache2 site
#####################
if [[ ! -f /etc/apache2/sites-available/matecat.conf ]]; then
  sed "s#@@@path@@@#${WWWDIR}#" < data/matecat-vhost.conf > /tmp/matecat.conf
  sudo -u root sh -c "mv /tmp/matecat.conf /etc/apache2/sites-available"
  $RUNROOT a2dissite 000-default
  $RUNROOT a2ensite matecat.conf
  $RUNROOT service apache2 restart
fi

#########################
# Configure proxy for PHP
#########################
PHP_PROXY="/etc/php/5.6/cli/proxy_setup.php"
if [[ ! -z ${HTTP_PROXY} ]] && [[ ! -f ${PHP_PROXY} ]]; then
    echo "Found proxy ${HTTP_PROXY}"
    PROXY_STR=`echo ${HTTP_PROXY} | sed 's#https#tcp#; s#http#tcp#'`
    sudo -u root sh -c "sed \"s#HTTP_PROXY_STR#${PROXY_STR}#; s#HTTPS_PROXY_STR#${PROXY_STR}#\" < data/proxy.php > ${PHP_PROXY}"
    sudo -u root sh -c 'echo auto_prepend_file = \"/etc/php/5.6/cli/proxy_setup.php\" >> /etc/php/5.6/cli/php.ini'
fi

# Give MateCat to www-data
sudo -u root -- chown -R www-data: `realpath ${WWWDIR}`
sudo -u root -- chmod 755 ${WWWDIR}

echo "Clearing previous logs"
$RUNROOT rm -rf /var/log/matecat/*
$RUNROOT rm -rf /var/log/apache2/matecat*

echo "Restarting services"
$RUNROOT systemctl restart --all apache2* matecat* mysql* redis-server.service

if [[ ! -z $DUMP_DBPASS ]]; then
  echo "Your database password for user ${DBUSER} is: ${DBPASS}"
fi
