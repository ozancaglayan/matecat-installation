#!/bin/bash
source ./vars.sh

DUMP_DBPASS=

# Checkout specific commits to ensure reproducibility
MATECAT_COMMIT="0f3f3ecaa45"
MATECAT_FILTERS_COMMIT="82f8210448"
RUNROOT="sudo -i -u root -- "

# Clone MateCat
if [[ ! -d ${WWWDIR} ]]; then
  git clone https://github.com/matecat/MateCat.git ${WWWDIR}
  pushd ${WWWDIR}
  git checkout $MATECAT_COMMIT
  popd
fi

# Clone Filters
if [[ ! -d "${WWWDIR}/Filters" ]]; then
  git clone https://github.com/matecat/MateCat-Filters.git "${WWWDIR}/Filters"
  pushd "${WWWDIR}/Filters"
  git checkout $MATECAT_FILTERS_COMMIT
  popd
fi

if [[ ! -d "${WWWDIR}/Filters/okapi" ]]; then
  pushd "${WWWDIR}/Filters"
  # Clone okapi
  git clone https://bitbucket.org/okapiframework/okapi.git
  pushd okapi
  COMMIT=$(grep 'okapi.commit' pom.xml | sed -r 's/.*<.*>(.*)<.*>/\1/')
  git checkout $COMMIT
  # Build OKAPI
  mvn clean install -DskipTests=true
  popd
  # Build filters
  pushd filters
  mvn clean package -DskipTests=true
  cp src/main/resources/config.sample.properties target/config.properties
  popd
  popd
fi

# Create global log folder
if [[ ! -d /var/log/matecat ]]; then
  echo "Preparing /var/log/matecat"
  $RUNROOT mkdir /var/log/matecat
  $RUNROOT chown www-data: /var/log/matecat
  # Change default log repository
  sed -i '/INIT.*LOG_REPOSITORY/s/=.*$/= \"\/var\/log\/matecat\";/' ${WWWDIR}/inc/Bootstrap.php
  # Change Apache php error log
  sed -i 's/^php_value error_log.*$/php_value error_log \/var\/log\/matecat\/php_errors.log/' ${WWWDIR}/.htaccess
fi

# Install packages
which htop &> /dev/null
if [[ $? == "1" ]]; then
  echo "Installing packages"
  $RUNROOT `realpath install-pkgs.sh` 
fi

# Check PHP version
PHPVER=`php --version | grep "^PHP" | awk '{ print $2 }'`
if [[ ! $PHPVER =~ ^5.6.* ]]; then
  echo 'You need to set default PHP to php5.6'
  exit 1
fi

# Install ActiveMQ
which activemq &> /dev/null
if [[ $? == "1" ]]; then
  echo "Installing ActiveMQ"
  $RUNROOT `realpath activemq.sh` 
fi

# Configure services
grep "www-data.*${UNIXUSER}" /etc/group &> /dev/null
if [[ $? == "1" ]]; then
  echo "Configuring services"
  $RUNROOT `realpath configure.sh` 


  # set DB password for matecat and import SQL
  DUMP_DBPASS=1
  SQLFILE="${WWWDIR}/INSTALL/matecat.sql"
  sed "s/matecat01/${DBPASS}/g" < $SQLFILE > /tmp/matecat.sql
  echo '(You will be prompted root password for mysql root account)'
  mysql -uroot -p < /tmp/matecat.sql
  rm /tmp/matecat.sql
fi

# Prepare node & php stuff
if [[ ! -f ${WWWDIR}/nodejs/config.ini ]]; then
  pushd ${WWWDIR}/nodejs
  npm install
  cp config.ini.sample config.ini
  # Change log file name to reflect that its nodejs server  
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

# Install PHP stuff
if [[ ! -f ${WWWDIR}/composer.phar ]]; then
  pushd $WWWDIR
  curl -L https://getcomposer.org/installer | php
  php composer.phar install
  popd
fi

# Add to rc.local
# NOTE: need systemd service
grep nodejs /etc/rc.local &> /dev/null
if [[ $? == "1" ]]; then
  echo "Adding nodejs server to rc.local"
  STR="echo screen -d -m -S \'node\' node ${WWWDIR}/nodejs/server.js >> /etc/rc.local"
  sudo -u root sh -c "$STR"
fi

grep restartAnalysis /etc/rc.local &> /dev/null
if [[ $? == "1" ]]; then
  STR1="echo /bin/bash ${WWWDIR}/daemons/restartAnalysis.sh >> /etc/rc.local"
  STR2="echo exit 0 >> /etc/rc.local"
  sudo -u root sh -c "$STR1"
  sudo -u root sh -c "$STR2"
fi

if [[ ! -f /etc/apache2/sites-available/matecat.conf ]]; then
  sed "s#@@@path@@@#${WWWDIR}#" < ./matecat-vhost.conf > /tmp/matecat.conf
  sudo -u root sh -c "mv /tmp/matecat.conf /etc/apache2/sites-available"
  $RUNROOT a2dissite 000-default
  $RUNROOT a2ensite matecat.conf
  $RUNROOT service apache2 restart
fi

if [[ ! -f ${WWWDIR}/inc/config.ini ]]; then
  pushd ${WWWDIR}/inc
  cp task_manager_config.ini.sample task_manager_config.ini
  cp config.ini.sample config.ini
  sed -i "s/^DB_PASS.*$/DB_PASS = \"${DBPASS}\"/" config.ini
  sed -i "s:^STORAGE_DIR.*$:STORAGE_DIR = \"${STORAGEDIR}\":" config.ini
  sed -i "s:^FILTERS_ADDRESS.*$:FILTERS_ADDRESS = \"http\://localhost\:8732\":" config.ini
  popd
fi

# Give MateCat to www-data
sudo -u root -- chown -R www-data: `realpath ${WWWDIR}`
sudo -u root -- chmod 755 ${WWWDIR}

echo "Restarting services"
$RUNROOT service rc.local restart
$RUNROOT service apache2 restart
$RUNROOT systemctl restart mysql.service
$RUNROOT `realpath ./clear-logs.sh`

if [[ ! -z $DUMP_DBPASS ]]; then
  echo "Your database password for user ${DBUSER} is: ${DBPASS}"
fi
