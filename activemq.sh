#!/bin/bash

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
