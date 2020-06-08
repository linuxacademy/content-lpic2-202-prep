#!/bin/bash

sed -ibak -e '0,/#myhostname/ s/#myhostname.*/myhostname = server1.example.com/' /etc/postfix/main.cf

sed -ibak -e '0,/#mydomain/ s/#mydomain.*/mydomain = example.com/' /etc/postfix/main.cf

sed -ibak -e '0,/#myorigin/ s/#myorigin.*/myorigin = $mydomain/' /etc/postfix/main.cf
sed -ibak 's/inet_interfaces = localhost/inet_interfaces = all/' /etc/postfix/main.cf
sed -ibak -e 's/inet_protocols.*/inet_protocols = all/' /etc/postfix/main.cf
sed -ibak -e 's;#mynetworks = 168.100.189.0/28, 127.0.0.0/8;mynetworks = 10.0.0.0/8, 127.0.0.0/8;' /etc/postfix/main.cf
sed -ibak -e 's;#home_mailbox = Maildir/;home_mailbox = Maildir/;' /etc/postfix/main.cf
sed -ibak -e 's;mydestination = $myhostname, localhost.$mydomain, localhost;mydestination = $myhostname, localhost.$mydomain, localhost, $mydomain;' /etc/postfix/main.cf
restorecon /etc/postfix/main.cf
