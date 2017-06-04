#!/bin/bash
#
# Script to maintain ip rules on the host when starting up a transparent
# proxy server for docker.

set -x

if [ "$1" = 'ssl' ]; then
    WITH_SSL=yes
else
    WITH_SSL=no
fi

set -e


start_routing () {
  # Add a new route table that routes everything marked through the new container
  # workaround boot2docker issue #367
  # https://github.com/boot2docker/boot2docker/issues/367
  [ -d /etc/iproute2 ] || sudo mkdir -p /etc/iproute2
  if [ ! -e /etc/iproute2/rt_tables ]; then
    if [ -f /usr/local/etc/rt_tables ]; then
      ln -s /usr/local/etc/rt_tables /etc/iproute2/rt_tables
    elif [ -f /usr/local/etc/iproute2/rt_tables ]; then
      ln -s /usr/local/etc/iproute2/rt_tables /etc/iproute2/rt_tables
    fi
  fi
  ([ -e /etc/iproute2/rt_tables ] && grep -q TRANSPROXY /etc/iproute2/rt_tables) \
    || sh -c "echo '1	TRANSPROXY' >> /etc/iproute2/rt_tables"
  ip rule show | grep -q TRANSPROXY \
    || ip rule add from all fwmark 0x1 lookup TRANSPROXY
  ip route add default via "${IPADDR}" dev ${IF} table TRANSPROXY

  # Mark packets to port 80 and 443 external, so they route through the new
  # route table
  COMMON_RULES="-t mangle -I PREROUTING -p tcp ! -s ${IPADDR} -j MARK --set-mark 1"
  echo "Redirecting HTTP to docker-proxy"
  iptables $COMMON_RULES --dport 80
  if [ "$WITH_SSL" = 'yes' ]; then
      echo "Redirecting HTTPS to docker-proxy"
      iptables $COMMON_RULES --dport 443
  else
      echo "Not redirecting HTTPS. To enable, re-run with the argument 'ssl'"
      echo "CA certificate will be generated anyway, but it won't be used"
  fi

  # Override docker isolation rules for this particular host FIXME narrow it down
  iptables -I FORWARD -o ${IF} -j ACCEPT

  # Exemption rule to stop docker from masquerading traffic routed to the
  # transparent proxy
  #iptables -t nat -I POSTROUTING -o docker0 -s 172.17.0.0/16 -j ACCEPT
  # Prevent masquerading for locally originated traffic targetting the transparent proxy
  iptables -t nat -I POSTROUTING -o ${IF} -s 172.0.0.0/8 -j ACCEPT
}

stop_routing () {
    # Remove iptables rules.
    set +e
    ip route show table TRANSPROXY | grep -q default \
        && ip route del default table TRANSPROXY
    while true; do
        rule_num=$(iptables -t mangle -L PREROUTING -n --line-numbers \
            | grep -E "MARK.*${IPADDR}.*tcp \S+ MARK set 0x1" \
            | awk '{print $1}' \
            | head -n1)
        [ -z "$rule_num" ] && break
        iptables -t mangle -D PREROUTING "$rule_num"
    done
    iptables -D FORWARD -o ${IF} -j ACCEPT
    #iptables -t nat -D POSTROUTING -o docker0 -s 172.17.0.0/16 -j ACCEPT 2>/dev/null
    #iptables -t nat -D POSTROUTING -o ${IF} -d ${IPADDR} -j ACCEPT 2>/dev/null
    iptables -t nat -D POSTROUTING -o ${IF} -s 172.0.0.0/8 -j ACCEPT 2>/dev/null
    set -e
}

stop () {
  stop_routing
}

interrupted () {
  echo 'Interrupted, cleaning up...'
  trap - INT
  stop
  kill -INT $$
}

terminated () {
  echo 'Terminated, cleaning up...'
  trap - TERM
  stop
  kill -TERM $$
}

run() {
  start_routing
  # Run at console, kill cleanly if ctrl-c is hit
  trap interrupted INT
  trap terminated TERM
  echo 'Now entering wait, please hit "ctrl-c" to kill proxy and undo routing'
  #docker logs -f "${CID}"
  while true; do
    echo "Waiting for termination in order to withdraw injected routes ..." 
    sleep 300
  done
  echo 'Squid exited unexpectedly, cleaning up...'
  stop
}

config() {
  #CID=$(docker ps --filter label=app=docker-proxy  --filter label=role=squid) 
  #IPADDR=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' ${CID})
  PORT=${WEBFS_PORT:-8000}
  IPADDR=$(curl -s http://localhost:$PORT/bin/ipaddr.sh)
  IF=$(ip -o -f inet route get $IPADDR | awk '{print $3}')
}

config
case $1 in
  clear) 
    stop_routing
    ;;
  *)
    run
    ;;
esac
