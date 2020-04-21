#!/bin/sh
cat <<EOF >> /etc/samba/smb.conf
[LAmount]
	comment = LA's Mount Point
	path = /opt
EOF
