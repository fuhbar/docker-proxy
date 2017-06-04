#!/bin/bash
set -e
echo -e "Content-type: text/plain\n"
/sbin/ip -o -f inet addr show eth0 | awk '{ sub(/\/.+/,"",$4); print $4 }'
