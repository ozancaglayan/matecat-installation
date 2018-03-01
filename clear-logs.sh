#!/bin/bash

cat /dev/null > /var/log/apache2/matecat.error.log
rm -rf /home/ozan/MateCat/storage/log_archive/*.log
rm -rf /home/ozan/MateCat/storage/log_archive/*.txt
rm -rf /home/ozan/MateCat/nodejs/log/*.log
rm -rf /home/ozan/MateCat/storage/log_archive/php_errors.txt
rm -rf /var/log/matecat/*
