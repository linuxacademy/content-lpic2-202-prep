#!/bin/bash

LDIF="/tmp/users.ldif"
SUFFIX="dc=example,dc=com"
yum -e0 -y -q install compat-openldap openldap-clients openldap-servers nss-pam-ldapd > /dev/null 2>&1

echo "Cleaning up old ldifs"
rm -f /tmp/*.ldif 

if yum list installed openldap-servers  > /dev/null 2>&1
then
    systemctl -q is-active slapd && {
        systemctl stop slapd
        systemctl -q disable slapd
    }
    echo -n "Removing existing LDAP server files ..... "
    rm -rf /var/lib/ldap/*
    yum remove -y -q -e0 compat-openldap openldap-clients openldap-servers
    id -u ldapuser1 > /dev/null && userdel -frZ  ldapuser1 2>/dev/null
    id -u ldapuser2 > /dev/null && userdel -frZ  ldapuser2 2>/dev/null
    echo "Done"
fi

yum -e0 -y -q install compat-openldap openldap-clients openldap-servers nss-pam-ldapd > /dev/null 2>&1

systemctl start slapd.service
systemctl enable slapd.service > /dev/null 2>&1
slappasswd -s 1234 -n > /etc/openldap/passwd

cat << EOF > /tmp/dbinit.ldif
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=example,dc=com

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=ldapadm,dc=example,dc=com

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $(</etc/openldap/passwd)
EOF

echo "Initiating DB"
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/dbinit.ldif > /dev/null 2>&1
echo

cat << EOF > /tmp/monitor.ldif
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external, cn=auth" read by dn.base="cn=ldapadm,dc=example,dc=com" read by * none
EOF

echo "Deploying Monitor changes"
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/monitor.ldif > /dev/null 2>&1
echo
echo "Setting up SSL"
openssl req -new -x509 -nodes -out /etc/openldap/certs/myLA.pem -keyout /etc/openldap/certs/LA.key -days 365 -subj '/C=US/L=Yes/O=Yes/OU=LA/CN=server.example.com' > /dev/null 2>&1
chown -R ldap:ldap /etc/openldap/certs
chmod 600 /etc/openldap/certs/LA.key

cat << EOF > /tmp/pem.ldif
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/certs/myLA.pem
EOF

cat << EOF > /tmp/key.ldif
dn: cn=config
changetype: modify
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/certs/LA.key
EOF

ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/key.ldif > /dev/null 2>&1
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/pem.ldif > /dev/null 2>&1
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/key.ldif > /dev/null 2>&1

echo
slaptest -u

echo "Setting up the OpenLDAP DB"
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown -R ldap:ldap /var/lib/ldap
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif > /dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif > /dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif > /dev/null 2>&1

cat << EOF > /tmp/base.ldif
dn: dc=example,dc=com
dc: example
objectClass: top
objectClass: domain

dn: cn=ldapadm,dc=example,dc=com
objectClass: organizationalRole
cn: ldapadm
description: LDAP Manager

dn: ou=People,dc=example,dc=com
objectClass: organizationalUnit
ou: People

dn: ou=Group,dc=example,dc=com
objectClass: organizationalUnit
ou: Group
EOF

echo "Adding base config"
ldapadd -x -w 1234 -D cn=ldapadm,dc=example,dc=com -f /tmp/base.ldif > /dev/null 2>&1

echo "Creating users"
[ -d /home/ldap ] || mkdir /home/ldap
useradd -d /home/ldap/ldapuser1 ldapuser1  > /dev/null  2>&1
echo "ldapuser1:ldap1234" | chpasswd
useradd -d /home/ldap/ldapuser2 ldapuser2 > /dev/null  2>&1
echo "ldapuser2:ldap1234" | chpasswd

GROUP_IDS=()
echo -n > $LDIF
grep "x:10[0-9][0-9]:" /etc/passwd |
( while IFS=':' read U_NAME U_X U_UID U_GID U_GECOS U_DIR U_SHELL
do
    # U_GECOS="$(echo "$U_GECOS" | cut -d' ' -f1,2)"
    [ ! "$U_GECOS" ] && U_GECOS="$U_NAME"
 
    S_ENT=$(grep "${U_NAME}:" /etc/shadow)
 
    S_AGING=$(passwd -S "$U_NAME")
    S_AGING_ARRAY=($S_AGING)
 
    # build up array of group IDs
    [ ! "$(echo "${GROUP_IDS[@]}" | grep "$U_GID")" ] && GROUP_IDS=("${GROUP_IDS[@]}" "$U_GID")
 
    echo "dn: uid=$U_NAME,ou=People,$SUFFIX" >> $LDIF
    echo "objectClass: account" >> $LDIF
    echo "objectClass: posixAccount" >> $LDIF
    echo "objectClass: shadowAccount" >> $LDIF
    echo "objectClass: top" >> $LDIF
    echo "cn: $(echo "$U_GECOS" | awk -F',' '{print $1}')" >> $LDIF
    echo "uidNumber: $U_UID" >> $LDIF
    echo "gidNumber: $U_GID" >> $LDIF
    echo "userPassword: {crypt}$(echo "$S_ENT" | cut -d':' -f2)" >> $LDIF
    echo "gecos: $U_GECOS" >> $LDIF
    echo "loginShell: $U_SHELL"  >> $LDIF
    echo "homeDirectory: $U_DIR" >> $LDIF
    echo "shadowExpire: ${S_AGING_ARRAY[6]}" >> $LDIF
    echo "shadowWarning: ${S_AGING_ARRAY[5]}" >> $LDIF
    echo "shadowMin: ${S_AGING_ARRAY[3]}" >> $LDIF
    echo "shadowMax: ${S_AGING_ARRAY[4]}" >> $LDIF
    echo >> $LDIF
done

echo "dn: uid=ldapuser3,ou=People,$SUFFIX" >> $LDIF
echo "objectClass: account" >> $LDIF
echo "objectClass: posixAccount" >> $LDIF
echo "objectClass: shadowAccount" >> $LDIF
echo "objectClass: top" >> $LDIF
echo "cn: ldapuser3" >> $LDIF
echo "uidNumber: 5000" >> $LDIF
echo "gidNumber: 5000" >> $LDIF
echo "userPassword: $(</etc/openldap/password)" >> $LDIF
echo "gecos: LinuxAcademy" >> $LDIF
echo "loginShell: /bin/bash"  >> $LDIF
echo "homeDirectory: /home/ldap/ldapuser3" >> $LDIF

echo "dn: cn=ldapuser3,ou=Group,$SUFFIX" >> $LDIF
echo "objectClass: posixGroup" >> $LDIF
echo "objectClass: top" >> $LDIF
echo "cn: ldapuser3" >> $LDIF
echo "gidNumber: 5000" >> $LDIF
echo "" >> $LDIF
 
for G_GID in "${GROUP_IDS[@]}"
do
    L_CN="$(grep ":$G_GID:" /etc/group | cut -d':' -f1)"
    echo "dn: cn=$L_CN,ou=Group,$SUFFIX" >> $LDIF
    echo "objectClass: posixGroup" >> $LDIF
    echo "objectClass: top" >> $LDIF
    echo "cn: $L_CN" >> $LDIF
    echo "gidNumber: $G_GID" >> $LDIF
    echo >> $LDIF
done
)

echo "Adding users to LDAP"
ldapadd -x -w 1234 -D cn=ldapadm,dc=example,dc=com -f $LDIF > /dev/null 2>&1
