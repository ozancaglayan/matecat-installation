#!/bin/bash
source ./vars.sh

# Checkout specific commits to ensure reproducibility
MATECAT_COMMIT="0f3f3ecaa45"
MATECAT_FILTERS_COMMIT="82f8210448"
RUNROOT="sudo -i -u root -- "

# Clone MateCat
if [[ ! -d "MateCat" ]]; then
  git clone https://github.com/matecat/MateCat.git ${WWWDIR}
  git checkout $MATECAT_COMMIT
fi

if [[ ! -d "MateCat-Filters" ]]; then
  git clone https://github.com/matecat/MateCat-Filters.git
  git checkout $MATECAT_FILTERS_COMMIT
fi
popd

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
  SQLFILE="${WWWDIR}/INSTALL/matecat.sql"
  sed "s/matecat01/${DBPASS}/g" < $SQLFILE > /tmp/matecat.sql
  echo '(You will be prompted root password for mysql root account)'
  mysql -uroot -p < /tmp/matecat.sql
  rm /tmp/matecat.sql
fi

# Prepare node & php stuff
if [[ ! -d ${WWWDIR}/nodejs/node_modules ]]; then
  pushd ${WWWDIR}/nodejs
  npm install
  cp config.ini.sample config.ini
  # Change log file name to reflect that its nodejs server  
  # NOTE: Local log file in the conf!
  # NOTE: log level is debug!   
  sed -i 's/server\.log/nodejs_server.log/' config.ini

fi

if [[ ! -d ${WWWDIR}/support_scripts/grunt/node_modules ]]; then
  pushd ${WWWDIR}/support_scripts/grunt
  npm install
  grunt deploy
fi

# Install PHP stuff
if [[ ! -f ${WWWDIR}/composer.phar ]]; then
  pushd $WWWDIR
  curl -L https://getcomposer.org/installer | php
  php composer.phar install
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
fi

# Give MateCat to www-data
sudo -u root -- chown -R www-data: `realpath ${WWWDIR}`
sudo -u root -- chmod 755 ${WWWDIR}

echo "Restarting services"
$RUNROOT service rc.local restart
$RUNROOT service apache2 restart
$RUNROOT systemctl restart mysql.service
$RUNROOT `realpath ./clear-logs.sh`
