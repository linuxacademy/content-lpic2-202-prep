cat  <<EOF > /var/named/named.conf
\$TTL    86400
@       IN      SOA     nameserver.mylabserver.com. root.mylabserver.com. (
                          10030         ; Serial
                           3600         ; Refresh
                           1800         ; Retry
                         604800         ; Expiry
                          86400         ; Minimum TTL
)
; Name Server
@        IN      NS       nameserver.mylabserver.com.
; A Record Definitions
nameserver  IN      A       
EOF
truncate -s -1 /var/named/named.conf
ifconfig eth0 | grep "inet " | awk -F ' ' '{ print $2 }' >> /var/named/named.conf
cat <<EOF >> /var/named/named.conf
test1       IN      A       
EOF
truncate -s -1 /var/named/named.conf
ifconfig eth0 | grep "inet " | awk -F ' ' '{ print $2 }' | cut -f1-3 -d'.' | tr -d '\n' >> /var/named/named.conf
cat <<EOF >> /var/named/named.conf
.30
test2       IN      A       
EOF
truncate -s -1 /var/named/named.conf
ifconfig eth0 | grep "inet " | awk -F ' ' '{ print $2 }' | cut -f1-3 -d'.' | tr -d '\n' >> /var/named/named.conf
cat <<EOF >> /var/named/named.conf
.72
EOF

