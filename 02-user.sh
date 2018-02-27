#!/bin/bash
source ./vars.sh


#npm install -g grunt grunt-cli

### Get Matecat
#mkdir git
#cd git
#git clone https://github.com/matecat/MateCat.git
#git clone https://github.com/matecat/MateCat-Filters.git

# Install php composer
#cd ~/git/MateCat
#curl -L https://getcomposer.org/installer | php
#php composer.phar install
cd ~/git/MateCat/inc
cp config.ini.sample config.ini
sed -i 's/^DB_PASS.*$/DB_PASS = \"dbmatecat1234\"/g' config.ini
sed -i 's#^STORAGE_DIR.*$#STORAGE_DIR = \"/home/matecat/www-data/storage\"#' config.ini
cp task_manager_config.ini.sample task_manager_config.ini


#cd ~/git/MateCat/support_scripts/grunt
#npm -g install
#grunt deploy

