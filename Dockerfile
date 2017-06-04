FROM ubuntu:14.04

MAINTAINER Kevin Littlejohn <kevin@littlejohn.id.au>,  \
           Alex Fraser <alex@vpac-innovations.com.au>, \
           Fabian Dörk <fabian.doerk@de.clara.net>

WORKDIR /root
COPY squid3.patch mime.conf /root/
RUN export DEBIAN_FRONTEND=noninteractive TERM=linux \
    # DEPS
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        dpkg-dev \
        iptables \
        libssl-dev \
        patch \
        squid-langpack \
        ssl-cert \
        webfs \
    && apt-get source -y squid3 squid-langpack \
    && apt-get build-dep -y squid3 squid-langpack \
    && cd squid3-3.?.? \
    # BUILD
    && patch -p1 < /root/squid3.patch \
    && export NUM_PROCS=`grep -c ^processor /proc/cpuinfo` \
    # It's silly, but run dpkg-buildpackage again if it fails the first time. This
    # is needed because sometimes the `configure` script is busy when building in
    # Docker after autoconf sets its mode +x.
    && (dpkg-buildpackage -b -j${NUM_PROCS} || dpkg-buildpackage -b -j${NUM_PROCS}) \
    && dpkg -i \
        ../squid3-common_3.?.?-?ubuntu?.?_all.deb \
        ../squid3_3.?.?-?ubuntu?.?_*.deb \
    && mkdir -p /etc/squid3/ssl_cert \
    && cat /root/mime.conf >> /usr/share/squid3/mime.conf \
    # CLEANUP
    && rm -vrf /root/squid* \
    && apt-get autoremove -y \
    && apt-get remove -y \
        build-essential \
        dpkg-dev \
        libssl-dev \
        $(apt-cache showsrc squid3 | sed -e '/Build-Depends/!d;s/Build-Depends: \|,\|([^)]*),*\|\[[^]]*\]//g') \
    && apt-get clean -y \
    && rm -vrf /var/lib/apt/lists/*

COPY squid.conf /etc/squid3/squid.conf
COPY start_squid.sh /usr/local/bin/start_squid.sh
COPY routing.sh /usr/local/bin/routing.sh
COPY ipaddr.sh /usr/local/bin/ipaddr.sh

VOLUME /var/spool/squid3 /etc/squid3/ssl_cert
EXPOSE 3128 3129 3130 8000

CMD ["/usr/local/bin/start_squid.sh"]
