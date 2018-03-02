#!/bin/bash
source "`dirname $0`/vars.sh"

# Add user if not
grep $UNIXUSER /etc/passwd &> /dev/null
if [[ $? == "1" ]]; then
  echo "Adding user."
  adduser --gecos "" ${UNIXUSER}
fi
# Add the user to www-data group
usermod -a -G www-data ${UNIXUSER}

# Configure apache & PHP
echo "short_open_tag = On" >> /etc/php/5.6/cli/php.ini
echo "memory_limit = 4096M" >> /etc/php/5.6/cli/php.ini
a2enmod rewrite filter deflate headers expires proxy_http.load

grep -i 'proxy.*=' /etc/environment | sed -r 's/(.*)/export \1/g' >> /etc/apache2/envvars

# Configure Redis
sed -i 's/bind 127.0.0.1/bind 0.0.0.0/g' /etc/redis/redis.conf

# Configure MySQL
# See: https://github.com/matecat/MateCat/issues/768
echo -e '[mysqld]\nsql-mode="NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION"' >> /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl restart mysql.service
