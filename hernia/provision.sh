#!/bin/sh

# hernia: The highly opinionated wannabe-love-child of FAI, Ansible & Heroku
#
# © Copyright 2014-2016 Rowan Thorpe
# Any contributions noted in the AUTHORS file.
#
# This file is part of hernia.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

# emacs ==> -*- mode: sh; eval: (auto-complete-mode 1); -*-

set -e

if ! test 1 = "$SELF_LOGGING"; then
    test 0 -eq $# || \
        { printf 'This script should be run with no commandline arguments\n' >&2; exit 1; }
    test 0 -ne $(id -u) || \
        { printf 'You must run this as non-root user - sudo is used internally when needed\n' >&2; exit 1; }
fi

# Should probably always be set to 1, but edit it if you want
debug=1
scriptpath="$(readlink -e "$0")" && \
    scriptdir="$(dirname "$scriptpath")" && \
    libfile="${scriptdir}/lib.sh" && \
    test -s "$libfile" && \
    . "$libfile" || \
        { printf 'Failed using readlink, basename or dirname, or sourcing lib file\n' >&2; exit 1; }
info 'Sourced lib file\n'

cd "$(git rev-parse --show-toplevel)" || \
    die 'Failed to enter the repo'\''s toplevel directory\n'
info 'Entered the repo'\''s toplevel directory\n'

#NB: Remember all interactive stuff must happen before starting self-logging, to have access to the terminal...
if ! test 1 = "$SELF_LOGGING"; then
    # Set defaults
    test -n "$USER" || \
        USER=$(id -un 2>/dev/null) || \
        USER=$(whoami 2>/dev/null) || \
        ! printf %s\\n "$HOME" | grep -q '^/home/' || \
        USER=$(printf %s\\n "$HOME" | sed -e 's:^/home/::')
    DEF_KEY_TYPE=''
    for _type in ed25519 ecdsa rsa dsa; do
        if test -s ~/.ssh/id_$_type; then
            DEF_KEY_TYPE="$_type"
            break
        fi
    done
    DEF_REPO_PATH="$(basename "$(pwd)")"
    DEF_BRANCH="$(git branch --column=never --color=never | sed -ne 's/^\* //; t PRINT; b; : PRINT; p; q')" || \
        die 'You need "git" and "sed" locally\n'
    DEF_EMAIL="$(sed -rne 's/^@[ \t]+IN[ \t]+SOA[ \t]+[^ \t]+[ \t]+([^ \t]+)[ \t].*$/\1/; t PRINT; b; : PRINT; s/\./@/; s/\.$//; p; q' zonefile.txt 2>/dev/null || :)"
    DEF_PUBLIC_IPV4_ADDRESS="$(sed -rne 's/^@[ \t]+IN[ \t]+A[ \t]+([^; \t]+).*$/\1/; t PRINT; b; : PRINT; p; q' zonefile.txt 2>/dev/null || :)"
    DEF_PUBLIC_IPV6_ADDRESS="$(sed -rne 's/^@[ \t]+IN[ \t]+AAAA[ \t]+([^; \t]+).*$/\1/; t PRINT; b; : PRINT; p; q' zonefile.txt 2>/dev/null || :)"
    DEF_SERVER_DOMAIN="$(sed -rne '/^\$ORIGIN[ \t].*\.e164\.(org|arpa)\.($|[; \t])/ b; s/^\$ORIGIN[ \t]+([^; \t]+).*$/\1/; t PRINT; b; : PRINT; s/\.$//; p; q' zonefile.txt 2>/dev/null || :)"
    _ip_aliases="$(sed -rne 's/^([^@ \t]+)[ \t]+IN[ \t]+(A|AAAA)[ \t]+('"$(printf '%s%s%s\n' "$DEF_PUBLIC_IPV4_ADDRESS" "${DEF_PUBLIC_IPV4_ADDRESS:+${DEF_PUBLIC_IPV6_ADDRESS:+|}}" "$DEF_PUBLIC_IPV6_ADDRESS" | sed -e 's/\./\\./g')"')$/\1/; t PRINT; b; : PRINT; p' zonefile.txt 2>/dev/null || :)"
    _first_ip_alias="$(printf '%s\n' "$_ip_aliases" | head -n 1)"
    if test -n "$_first_ip_alias"; then
        _ip_aliases="$(printf '%s\n' "$_ip_aliases" | grep -v "^$(printf '%s\n' "$_first_ip_alias" | sed -e 's/\./\\./g')\$" | sort -u | tr '\n' ' ' | sed -e 's/ $//')"
        _ip_aliases="$_first_ip_alias${_ip_aliases:+ }${_ip_aliases}"
    fi
    DEF_SERVER_ALIASES="$(sed -rne 's/^([^ \t]+)[ \t]+IN[ \t]+CNAME[ \t]+('"$(printf '%s\n' "$_ip_aliases" | sed -e 's/ /|/g')${_ip_aliases:+|}"'@)([; \t].*)?$/\1/; t PRINT; b; : PRINT; p' zonefile.txt 2>/dev/null | tr '\n' ' ' | sed -e 's/ $//' || :)"
    DEF_SERVER_ALIASES="${_ip_aliases}${DEF_SERVER_ALIASES:+ }$DEF_SERVER_ALIASES"

    prompt -p SERVICES_PASSWORD '"root" password for various services - not necessarily the same as the root-login password'
    prompt -d "$DEF_SERVER_DOMAIN" SERVER_DOMAIN 'bare domain name'
    prompt -z -d "$DEF_SERVER_ALIASES" SERVER_ALIASES 'non-FQDN/hostname aliases, and first alias + bare domain = main FQDN'
    prompt -z WHITELIST_ADDRESSES 'space-separated list of ip-addresses you want to allow full access through the firewall - be careful'
    prompt -d "$DEF_PUBLIC_IPV4_ADDRESS" PUBLIC_IPV4_ADDRESS
    prompt -d "$DEF_PUBLIC_IPV6_ADDRESS" PUBLIC_IPV6_ADDRESS
    prompt -d "$USER" USER_NAME 'for login to the server'
    prompt -d "$DEF_EMAIL" EMAIL 'address for use by things like certbot, and optionally receiving system emails remotely - see next question'
    prompt -d 'no' EMAIL_REMOTE 'only exact value "yes" without quotes enables this - NB: we patch exim-config to require send-over-TLS, if "yes" here ensure you keep that patching to not expose log data'
    prompt -d "$DEF_KEY_TYPE" KEY_TYPE 'one of: dsa, rsa, ecdsa, ed25519'
    prompt -d "$DEF_REPO_PATH" REPO_PATH 'on server, either relative to home-dir or absolute path, without trailing ".git"'
    prompt -d "$DEF_BRANCH" BRANCH 'which branch in the repo to deploy from'
    prompt -d 'en_GB en_US el_GR' LOCALE_GEN 'space-separated list of locale prefixes for locale-gen, first entry also used for update-locale'
    prompt -d 'Europe/Athens' TZ_DATA 'timezone data in the form "Area/Zone"'
    prompt -d "-1" SWAPFILE_SIZE 'size of /swapfile in MB, -1 means don'\''t create it'
    prompt -d 'no' AUTO_DEPLOY_AFTER_PROVISION 'only exact value "yes" without quotes enables this'

    # Whitespace-trim, *don't* include SERVICES_PASSWORD here..
    for _varname in SERVER_DOMAIN SERVER_ALIASES WHITELIST_ADDRESSES PUBLIC_IPV4_ADDRESS PUBLIC_IPV6_ADDRESS USER_NAME EMAIL EMAIL_REMOTE KEY_TYPE REPO_PATH BRANCH LOCALE_GEN TZ_DATA SWAPFILE_SIZE AUTO_DEPLOY_AFTER_PROVISION; do
        eval "${_varname}=\$(printf '%s\\n' \"\$$_varname\" | sed -re 's/ +/ /g; s/^ //; s/ \$//')"
    done

    # Keep the -h in the ssh invocations here, so the first connection is without StrictHostChecking
    if do_ssh_su -h : 2>/dev/null; then
        ACCESS_TYPE='su'
    elif do_ssh_r -h : 2>/dev/null; then
        ACCESS_TYPE='r'
    elif do_ssh_r -t 'Ensure root ssh-by-key' -p -h '
        test -d /root/.ssh || \
            mkdir /root/.ssh
        printf %s '"$(quote_wrap_p <~/.ssh/id_${KEY_TYPE}.pub)"' >/root/.ssh/authorized_keys
        sed --follow-symlinks -i -re '\''
            s/^#?PermitRootLogin[ \t].*$/PermitRootLogin without-password/
            s/^#?PubkeyAuthentication[ \t].*$/PubkeyAuthentication yes/
        '\'' /etc/ssh/sshd_config
        service ssh restart
    '; then
        # Do this here so password is only ever requested once, even if it
        # means presuming a few packages are installed on the server (and
        # so we get the interactivity out of the way before starting logging)
        ACCESS_TYPE='r'
    else
        die 'I don'\''t have effective access to the server\n'
    fi

    PIPE="$(mktemp -u)"
    mkfifo "$PIPE"
    env SELF_LOGGING=1 libfile="$libfile" SERVICES_PASSWORD="$SERVICES_PASSWORD" SERVER_DOMAIN="$SERVER_DOMAIN" SERVER_ALIASES="$SERVER_ALIASES" WHITELIST_ADDRESSES="$WHITELIST_ADDRESSES" PUBLIC_IPV4_ADDRESS="$PUBLIC_IPV4_ADDRESS" PUBLIC_IPV6_ADDRESS="$PUBLIC_IPV6_ADDRESS" USER_NAME="$USER_NAME" EMAIL="$EMAIL" EMAIL_REMOTE="$EMAIL_REMOTE" KEY_TYPE="$KEY_TYPE" REPO_PATH="$REPO_PATH" BRANCH="$BRANCH" LOCALE_GEN="$LOCALE_GEN" TZ_DATA="$TZ_DATA" SWAPFILE_SIZE="$SWAPFILE_SIZE" AUTO_DEPLOY_AFTER_PROVISION="$AUTO_DEPLOY_AFTER_PROVISION" ACCESS_TYPE="$ACCESS_TYPE" "$0" "$@" 2>&1 | sed -ure 's/\r$//; s/^.*\r([^\r]*)$/\1/' >"$PIPE" 2>&1 &
    PID=$!
    tee "/tmp/hernia-${scriptname}.log" <"$PIPE" &
    /bin/sleep 0.1
    rm -f "$PIPE" # this pipe will still stick around until the child releases it
    wait $PID
    exit $?
fi
info 'Started self-logging\n'

## Don't do anything interactive below here (the above self-logging hack will prevent it anyway)

# Notes:
#  * debian-goodies has "checkrestart"
#  * $packages_manual is generated from prototype VM by the following (excluding those already in $packages_essential):
#     aptitude -F %p --disable-columns search '?installed ?not(?automatic)' | tr '\n' ' ' | sed -e 's/ $//'
#  * $packages_auto is generated from prototype VM by the following:
#     aptitude -F %p --disable-columns search '?installed ?automatic' | tr '\n' ' ' | sed -e 's/ $//'
packages_initial='memlockd ssh aptitude'
packages_userssh_sudo='adduser coreutils grep passwd sed sudo sysvinit-utils'
packages_essential="$packages_initial $packages_userssh_sudo debconf fail2ban ferm git grub-pc locales sysfsutils"
packages_manual="$packages_essential acl acpi acpi-support-base acpid adequate apt-file apt-listchanges apt-utils arping arptables base-files bash bzip2 checksecurity colordiff conntrack cruft dbus debian-goodies debian-keyring debsums diffutils dnsutils emacs-nox emacs24-common-non-dfsg findutils fizsh gnutls-bin gzip hostname htop init inotify-tools iotop ipset iptables iputils-ping kbd keyboard-configuration less linux-image-amd64 lksctp-tools lockfile-progs login logrotate logwatch lsb-release lsof ltrace lzip mailutils man-db manpages-posix mlocate mount nano ncurses-base ncurses-bin net-tools netcat-openbsd nfacct openntpd openssh-blacklist-extra openssl openssl-blacklist-extra patch patchutils procmail resolvconf rsync rsyslog socat socket ssl-cert ssl-cert-check strace swaks tagcoll task-english task-spooler task-ssh-server time tmux traceroute ttysnoop unicode wdiff wget whois xz-utils zutils"
packages_auto='anacron apt aptitude-common base-passwd bash-completion bind9-host bsd-mailx bsdmainutils bsdutils busybox ca-certificates cpio cron curl dash dctrl-tools debconf-i18n debian-archive-keyring debianutils dialog dmsetup dpkg e2fslibs e2fsprogs emacs24-bin-common emacs24-common emacs24-nox emacsen-common exim4 exim4-base exim4-config exim4-daemon-light file gcc-4.9-base geoip-database gettext-base git-man gnupg gnupg-curl gpgv groff-base grub-common grub-pc-bin grub2-common guile-2.0-libs host ifupdown init-system-helpers initramfs-tools initscripts insserv iproute2 isc-dhcp-client isc-dhcp-common iso-codes klibc-utils kmod krb5-locales libacl1 libalgorithm-c3-perl libapt-inst1.5 libapt-pkg-perl libapt-pkg4.12 libarchive-extract-perl libasound2 libasound2-data libasprintf0c2 libattr1 libaudit-common libaudit1 libbind9-90 libblkid1 libboost-iostreams1.55.0 libbsd0 libbz2-1.0 libc-bin libc6 libcap-ng0 libcap2 libcap2-bin libcgi-fast-perl libcgi-pm-perl libclass-accessor-perl libclass-c3-perl libclass-c3-xs-perl libcomerr2 libconfig-file-perl libcpan-meta-perl libcryptsetup4 libcurl3 libcurl3-gnutls libcwidget3 libdata-optlist-perl libdata-section-perl libdate-manip-perl libdb5.3 libdbus-1-3 libdebconfclient0 libdevmapper1.02.1 libdigest-hmac-perl libdns-export100 libdns100 libdpkg-perl libedit2 libelfg0 liberror-perl libestr0 libevent-2.0-5 libexpat1 libfcgi-perl libffi6 libfile-fcntllock-perl libfile-fnmatch-perl libfreetype6 libfribidi0 libfuse2 libgc1c2 libgcc1 libgcrypt20 libgdbm3 libgeoip1 libglib2.0-0 libglib2.0-data libgmp10 libgnutls-deb0-28 libgnutls-openssl27 libgpg-error0 libgpm2 libgsasl7 libgssapi-krb5-2 libhogweed2 libicu52 libidn11 libinotifytools0 libio-socket-inet6-perl libio-string-perl libipset3 libirs-export91 libisc-export95 libisc95 libisccc90 libisccfg-export90 libisccfg90 libjson-c2 libk5crypto3 libkeyutils1 libklibc libkmod2 libkrb5-3 libkrb5support0 libkyotocabinet16 libldap-2.4-2 liblist-moreutils-perl liblocale-gettext-perl liblockfile-bin liblockfile1 liblog-message-perl liblog-message-simple-perl liblogging-stdlog0 liblognorm1 liblwres90 liblzma5 liblzo2-2 libmagic1 libmailutils4 libmnl0 libmodule-build-perl libmodule-pluggable-perl libmodule-signature-perl libmount1 libmro-compat-perl libmysqlclient18 libncurses5 libncursesw5 libnet-dns-perl libnet-ip-perl libnet-ssleay-perl libnet1 libnetfilter-acct1 libnettle4 libnfnetlink0 libntlm0 libopts25 libp11-kit0 libpackage-constants-perl libpam-cap libpam-modules libpam-modules-bin libpam-runtime libpam-systemd libpam0g libparams-util-perl libparse-debianchangelog-perl libpcap0.8 libpcre3 libperl4-corelibs-perl libpipeline1 libpng12-0 libpod-latex-perl libpod-readme-perl libpopt0 libprocps3 libpsl0 libpython-stdlib libpython2.7 libpython2.7-minimal libpython2.7-stdlib libreadline6 libregexp-assemble-perl libregexp-common-perl librtmp1 libsasl2-2 libsasl2-modules libsasl2-modules-db libsctp1 libselinux1 libsemanage-common libsemanage1 libsepol1 libsigc++-2.0-0c2a libslang2 libsmartcols1 libsocket6-perl libsoftware-license-perl libsqlite3-0 libss2 libssh2-1 libssl1.0.0 libstdc++6 libsub-exporter-perl libsub-install-perl libsub-name-perl libsys-cpu-perl libsystemd0 libtasn1-6 libterm-ui-perl libtext-charwidth-perl libtext-iconv-perl libtext-soundex-perl libtext-template-perl libtext-wrapi18n-perl libtimedate-perl libtinfo5 libudev1 libunistring0 libusb-0.1-4 libustr-1.0-1 libuuid-perl libuuid1 libwrap0 libxapian22 libxml2 libxtables10 linux-base linux-image-3.16.0-4-amd64 lsb-base mailutils-common manpages mawk mime-support multiarch-support mysql-common ncurses-term netbase openssh-blacklist openssh-client openssh-server openssh-sftp-server openssl-blacklist perl perl-base perl-modules procps psmisc python python-apt python-apt-common python-minimal python-pyinotify python-support python2.7 python2.7-minimal readline-common rename sensible-utils sgml-base startpar systemd systemd-sysv sysv-rc tar tasksel tasksel-data tcpd tzdata ucf udev unicode-data util-linux util-linux-locales uuid-runtime xml-core zlib1g zsh zsh-common'
test -1 -eq $SWAPFILE_SIZE || \
    packages_essential="$packages_essential mount"

. "$libfile" || \
    { printf 'Failed sourcing lib file\n' >&2; exit 1; }
info 'Sourced lib file\n'

_apt_conf="$(quote_wrap_p <'content/add/_provision/apt_conf/apt.conf')"
do_ssh_$ACCESS_TYPE -t 'Modify /etc/apt/apt.conf' '
    printf %s\\n '"$_apt_conf"' >/etc/apt/apt.conf
' || die

do_ssh_$ACCESS_TYPE -t 'Ensure packages for package-management and user-ssh-with-sudo are installed' '
    apt-get --quiet --assume-yes update
    apt-get --quiet --assume-yes --no-install-recommends install '"$packages_initial"'
    aptitude --quiet --assume-yes --without-recommends -o Aptitude::Delete-Unused=0 install '"$packages_userssh_sudo"'
' || die

if test 'r' = "$ACCESS_TYPE"; then
    do_ssh_r -t 'Ensure non-root-user ssh-by-key with passwordless sudo' '
        sed --follow-symlinks -i -re '\''
            s/^(#+[ \t]*)?(%sudo[ \t].*)([ \t]ALL)$/\2 NOPASSWD:\3/
        '\'' /etc/sudoers
        grep -q "^'"$USER_NAME"':" /etc/passwd || \
            adduser --quiet --disabled-password --gecos "" "'"$USER_NAME"'"
        grep -q "^sshusers:" /etc/group || \
            addgroup --quiet sshusers
        usermod -a -G sudo,sshusers,staff '"$USER_NAME"'
        mkdir -p ~'"$USER_NAME"'/.ssh
        cp -f /root/.ssh/authorized_keys ~'"$USER_NAME"'/.ssh/
        chown '"${USER_NAME}:$USER_NAME"' ~'"$USER_NAME"'/.ssh/authorized_keys
        sed --follow-symlinks -i -re '\''
            s/^#?UsePAM[ \t].*$/UsePAM yes/
        '\'' /etc/ssh/sshd_config
        grep -q '\''^AllowGroups[[:blank:]]\+sshusers[[:blank:]]*$'\'' /etc/ssh/sshd_config || \
            printf '\''\nAllowGroups sshusers\n'\'' >>/etc/ssh/sshd_config
        service ssh restart
    ' || die
    _loosen_strict_host='-h'
else
    _loosen_strict_host=''
fi

# temporary $_loosen_strict_host=-h allows a newly created user to auto-accept the "new" host key
do_ssh_su -t 'Ensure sane sshd settings, remove root key if present' $_loosen_strict_host '
    sed --follow-symlinks -i -re '\''
        s/^#?[ \t]*Protocol[ \t].*$/Protocol 2/
        s/^#?[ \t]*UsePrivilegeSeparation[ \t].*$/UsePrivilegeSeparation yes/
        s/^#?[ \t]*PermitEmptyPasswords[ \t].*$/PermitEmptyPasswords no/
        s/^#?[ \t]*StrictModes[ \t].*$/StrictModes yes/
        s/^#?[ \t]*IgnoreRhosts[ \t].*$/IgnoreRhosts yes/
        s/^#?[ \t]*X11Forwarding[ \t].*$/X11Forwarding no/
        s/^#?[ \t]*MaxStartups[ \t].*$/MaxStartups 10:30:60/
        s/^#?[ \t]*AcceptEnv[ \t].*$/AcceptEnv LANG LC_*/
        s/^#?[ \t]*UsePAM[ \t].*$/UsePAM yes/
        s/^#?[ \t]*PermitRootLogin[ \t].*$/PermitRootLogin no/
        s/^#?[ \t]*PubkeyAuthentication[ \t].*$/PubkeyAuthentication yes/
        s/^#?[ \t]*PasswordAuthentication[ \t].*$/PasswordAuthentication no/
        s/^#?[ \t]*ChallengeResponseAuthentication[ \t].*$/ChallengeResponseAuthentication no/
        s/^#?[ \t]*HostbasedAuthentication[ \t].*$/HostbasedAuthentication no/
        s/^#?[ \t]*RSAAuthentication[ \t].*$/RSAAuthentication no/
        s/^#?[ \t]*RhostsRSAAuthentication[ \t].*$/RhostsRSAAuthentication no/
        s/^#?[ \t]*KerberosAuthentication[ \t].*$/KerberosAuthentication no/
        s/^#?[ \t]*GSSAPIAuthentication[ \t].*$/GSSAPIAuthentication no/
    '\'' /etc/ssh/sshd_config
    service ssh restart
    rm -f /root/.ssh/authorized_keys 2>/dev/null || :
' || die

do_ssh_su -t 'Install essential packages' '
    aptitude --quiet --assume-yes --with-recommends -o Aptitude::Delete-Unused=0 install '"$packages_essential"'
' || die

do_ssh_su -t 'Ensure noop scheduler for SSD disks' '
    printf '\''block/sda/queue/scheduler = noop\n'\'' >/etc/sysfs.d/10-disk.conf
    service sysfsutils restart
' || die

do_ssh_su -t 'Ensure useful permissions under /usr/local/bin' '
    chown -R root:staff /usr/local/bin
    chmod -R u=rwx,g=rwx,o=rx /usr/local/bin
    chmod g+s /usr/local/bin
' || die

for _content in $(cd content/add/_provision/usr_local_bin && \ls -1 * 2>/dev/null | tr '\n' ' ' || :); do
    do_scp_u 'out' "content/add/_provision/usr_local_bin/$_content" /usr/local/bin -t "Copy \"$_content\" to /usr/local/bin" || \
        die
done
info 'Copied files to /usr/local/bin\n'

do_ssh_su -t 'Patch ferm and fail2ban configs, and conf defaults' '
    # set these variables inside the ssh-invocation, to be used by the eval-loop
    _ferm_patch_content='"$(quote_wrap_p <"content/patch/_provision/ferm_conf.diff")"'
    _fail2ban_patch_content='"$(quote_wrap_p <"content/patch/_provision/fail2ban_conf.diff")"'

    for _package in ferm fail2ban; do
        if test -h /etc/$_package; then
            _versioned_dirs="$(ls -1td /etc/${_package}.[0-9][0-9][0-9]* 2>/dev/null || :)"
            test -z "'"$past_timestamped_dirs_to_keep"'" || \
                test '"$past_timestamped_dirs_to_keep"' -ge $(printf %s\\n "$_versioned_dirs" | wc -l) || \
                rm -fr $(printf %s\\n "$_versioned_dirs" | tail -n +$(expr '"$past_timestamped_dirs_to_keep"' + 1) | tr "\\n" " ")
        else
            mv -fT /etc/$_package /etc/${_package}.-1
        fi
        ln -nfsT ${_package}.-1 /etc/$_package
        rm -fr /etc/${_package}.0 2>/dev/null || :
        cp -axfT /etc/${_package}.-1 /etc/${_package}.0
            cd /etc/${_package}.0
            eval '\''printf %s\\n "$_'\''$_package'\''_patch_content"'\'' | patch -p1
    done
    sed --follow-symlinks -i -e "s/__WHITELISTADDRESSES__/'"$(printf %s\\n "$WHITELIST_ADDRESSES" | sed -e 's/[\/&]/\\&/g')"'/g" \
        /etc/ferm.0/vars.conf

    if grep -q "^ENABLED=" /etc/default/ferm 2>/dev/null; then
        sed --follow-symlinks -i -re "s/^ENABLED=.*$/ENABLED=\"yes\"/" /etc/default/ferm
    else
        printf '\''\nENABLED="yes"\n'\'' >>/etc/default/ferm
    fi
    if ! grep -q "^ulimit -s" /etc/default/fail2ban 2>/dev/null; then
        printf '\''\n## manually added to help with memory consumption\nulimit -s 2048 # default=8192\n'\'' \
        >>/etc/default/fail2ban
    fi
    ln -nfsT ferm.0 /etc/ferm
    ln -nfsT fail2ban.0 /etc/fail2ban
    fwadmin restart
' || die

_primary_locale="$(printf %s\\n "$LOCALE_GEN" | cut -d' ' -f1)"
do_ssh_su -t 'Ensure correct locale settings' '
    sed --follow-symlinks -i -re '\''
        s/^#?/#/
    '\'' /etc/locale.gen
    for _loc in '"$LOCALE_GEN"'; do
        sed --follow-symlinks -i -re "
            /^#?[ \\t]*${_loc}.UTF-8[ \\t]+UTF-8[ \\t]*\$/ d
            \$ a \\
${_loc}.UTF-8 UTF-8
        " /etc/locale.gen
    done
    locale-gen
    update-locale LANG='"$_primary_locale"'.UTF-8 LANGUAGE
    _tz_area=$(printf %s\\n '"$TZ_DATA"' | cut -d/ -f1)
    _tz_zone=$(printf %s\\n '"$TZ_DATA"' | cut -d/ -f2-)
    printf '\''tzdata\ttzdata/Areas\tselect\t%s
tzdata\ttzdata/Zones/%s\tselect\t%s
'\'' "$_tz_area" "$_tz_area" "$_tz_zone" | debconf-set-selections
    dpkg-reconfigure tzdata
' || die

do_ssh_su -t 'Tweak grub' '
    sed --follow-symlinks -i -re '\''
        s/^[ \t]*#?[ \t]*GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=2/
        s/^[ \t]*#?[ \t]*GRUB_TERMNAL=.*$/GRUB_TERMINAL=console/
        s/^[ \t]*#?[ \t]*GRUB_CMDLINE_LINUX_DEFAULT=.*$/GRUB_CMDLINE_LINUX_DEFAULT="quiet consoleblank=0 elevator=noop"/
    '\'' /etc/default/grub
    update-grub
' || die

if test -1 -ne $SWAPFILE_SIZE; then
    do_ssh_su -t 'Add swapfile' '
        swapoff -a
        dd if=/dev/zero of=/swapfile bs=1024 count=$(expr 1024 \* '"$SWAPFILE_SIZE"')
        chmod go= /swapfile
        mkswap -L SWAP /swapfile
        sed --follow-symlinks -i -re '\''
            /^[ \t]*\/swapfile[ \t]+/ d
            $ a \
/swapfile none swap sw 0 0
        '\'' /etc/fstab
    ' || die
fi
do_ssh_su -t 'Set swappiness and activate swaps' '
    printf vm.swappiness=1\\n >/etc/sysctl.d/50-swap.conf
    sysctl -p/etc/sysctl.d/50-swap.conf
    swapon -a
' || die

#NB:   This is country-code of the *VM* (for using debian-mirror local to the VM, for faster updating),
#      not necessarily same as that of the user.
_country_code="$(
    do_ssh_su '
        sed -nre '\''
            s%^deb http://ftp\.([a-z]{2})\.debian\.org/debian/? jessie.*$%\1%;
            t PRINT;
            b;
            : PRINT;
            p;
            q;
        '\'' /etc/apt/sources.list
    '
)" && \
    test -n "$_country_code" || \
        die 'Failed to get country code from /etc/apt/sources.list\n'
info 'Got country code from /etc/apt/sources.list\n'

do_ssh_su -t 'Ensure apt backports sources exist' '
    sed --follow-symlinks -i -re '\''
        s/^([^#]+\<jessie-backports\>)/#\1/
    '\'' /etc/apt/sources.list $(find /etc/apt/sources.list.d -type f -printf "%p ")
    printf '\''deb http://ftp.%s.debian.org/debian/ jessie-backports main contrib non-free\ndeb-src http://ftp.%s.debian.org/debian/ jessie-backports main contrib non-free\n'\'' "'"$_country_code"'" "'"$_country_code"'" \
        >/etc/apt/sources.list.d/backports.list
'

do_ssh_su -t 'Ensure contrib and non-free are included in "/etc/apt/sources.list"' '
    sed --follow-symlinks -i -re '\''
        s%[ \t]+jessie((-|/)updates)?[ \t]+main[ \t]*$% jessie\1 main contrib non-free%
    '\'' /etc/apt/sources.list
'

do_ssh_su -t 'Update and upgrade apt' '
    aptitude --quiet --assume-yes update
    aptitude --quiet --assume-yes safe-upgrade
'

printf %s\\n "$REPO_PATH" | grep -q '\.git$' || \
    REPO_PATH="${REPO_PATH}.git"
printf %s\\n "$REPO_PATH" | grep -q '^/' || REPO_PATH="$(
    do_ssh_u '
        readlink -f '"$(quote_wrap "$REPO_PATH")"'
    ' 2>/dev/null
)" || die 'Failed getting absolute $REPO_PATH (+ trailing .git)\n'

do_ssh_u -t 'Ensure bare git repo on server synced to local repo' '
    if test -d "'"$REPO_PATH"'"; then
        rm -fr "'"$REPO_PATH"'.bak" 2>/dev/null || :
        mv -fT "'"$REPO_PATH"'" "'"$REPO_PATH"'.bak"
    fi
    mkdir -p "'"$REPO_PATH"'"
    cd "'"$REPO_PATH"'"
    git --bare init
    # Be double-sure the first push does not trigger a deploy from the repo
    ! test -e "'"$REPO_PATH"'/hooks/post-receive" || \
        mv -fT "'"$REPO_PATH"'/hooks/post-receive" "'"$REPO_PATH"'/hooks/post-receive.disabled"
' || die

_git_alias_exec="$(git config --null --get-all alias.exec | tr -d '\0')"
if test -n "$_git_alias_exec"; then
    test 'x!exec ' = "x$_git_alias_exec"
else
    git config alias.exec '!exec '
fi || \
    die 'Failed to ensure "exec" git-alias\n'
info 'Ensured "exec" git-alias\n'

for _hookname in pre-commit pre-push; do
    if ! test -s .git/hooks/$_hookname || ! test ../../hernia/hooks/$_hookname = "$(readlink -e .git/hooks/$_hookname 2>/dev/null || :)"; then
        mv -fT .git/hooks/$_hookname .git/hooks/${_hookname}.bak 2>/dev/null || :
        ln -nfsT ../../hernia/hooks/$_hookname .git/hooks/$_hookname
    fi || \
        die 'Failed to update local %s hook\n' "$_hookname"
    info 'Updated local %s hook\n' "$_hookname"
done

git config push.default simple && \
    if git remote 2>/dev/null | grep -q '^vm$'; then
        warn 'git remote "vm" already exists, renaming it to "vm.bak"\n'
        git remote remove vm.bak 2>/dev/null || :
        git remote rename vm vm.bak
    fi && \
    git remote add vm "ssh://${USER_NAME}@${SERVER_DOMAIN}/$REPO_PATH" && \
    git push -u --all vm || \
        die 'Failed to setup git remote\n'
info 'Setup git remote\n'

# convoluted syntax used here to ensure safe transfer of passwords without being process-sniffable
main_alias="$(printf '%s\n' "$SERVER_ALIASES" | cut -d' ' -f1)"
ns_1="$(sed -rne 's/^@[ \t]+IN[ \t]+NS[ \t]+([^ \t]+)\.$/\1/; t PRINT; b; : PRINT; p; q' zonefile.txt)"
test -n "$ns_1" || ns_1='8.8.8.8'
PATH= printf '%s\nservices_password=%s\nrepo=%s\nbranch=%s\nemail=%s\nwhitelist_addresses=%s\nbare_domain=%s\nserver_aliases=%s\nmain_alias=%s\nns_1=%s\npublic_ipv4_address=%s\n' "$(quote_p <'external_vars.sh')" "$(quote_wrap "$SERVICES_PASSWORD")" "$(quote_wrap "$REPO_PATH")" "$(quote_wrap "$BRANCH")" "$(quote_wrap "$EMAIL")" "$(quote_wrap "$WHITELIST_ADDRESSES")" "$(quote_wrap "$SERVER_DOMAIN")" "$(quote_wrap "$SERVER_ALIASES")" "$(quote_wrap "$main_alias")" "$(quote_wrap "$ns_1")" "$(quote_wrap "$PUBLIC_IPV4_ADDRESS")" | \
    do_ssh_su -N -t 'Safely copy gitignored external_vars file' '
        _input="$(cat)"
        touch /root/external_vars.sh
        chown root:root /root/external_vars.sh
        chmod u=rw,go= /root/external_vars.sh
        PATH= printf "%s\\n" "$_input" >/root/external_vars.sh
    ' || die

do_ssh_u -t 'Setup autodeploy hook, ensure correct branch gets used' '
    cd '"$REPO_PATH"'
    printf %s\\n '"$(quote_wrap_p <'hernia/hooks/post-receive')"' >hooks/post-receive
    chmod +x hooks/post-receive
    git symbolic-ref HEAD refs/heads/'"$BRANCH"'
' || die

for _pref in content/add/_provision/apt_conf/preferences.d/*; do
    _pref_basename="$(basename "$_pref")"
    do_ssh_su -t "Copy /etc/apt/preferences.d/$_pref_basename" '
        printf %s\\n '"$(quote_wrap_p <"$_pref")"' >/etc/apt/preferences.d/'"$_pref_basename"'
    ' || die
done

packages_installed=$(
    do_ssh_u '
        aptitude --quiet --display-format %p --disable-columns search '\''?installed'\''
    ' | tr -s '\n' ' '
) || die 'Failed creating presently-installed packages list\n'
info 'Created presently-installed packages list\n'

packages_all_search=$(printf '%s %s\n' "$packages_manual" "$packages_auto" | sed -re '$ s/ +$//; s/^/^/; s/$/$/; s/ +/$, ^/g')

packages_leftover=$(
    do_ssh_u '
        aptitude --quiet --display-format %p --disable-columns search '\''
            ?installed ?not(?or(?reverse-depends(?or('"$packages_all_search"')), '"$packages_all_search"'))
        '\''
    ' | tr -s '\n' ' '
) || die 'Failed creating leftover packages list\n'
info 'Created leftover packages list\n'

do_ssh_su -t 'Install remaining manual and automatic packages' '
    aptitude --quiet --assume-yes -o Aptitude::Delete-Unused=0 install '"$packages_manual $packages_auto"'
' || die

do_ssh_su -t 'Mark all packages as automatically installed' '
    aptitude --quiet --assume-yes -o Aptitude::Delete-Unused=0 markauto '"$packages_installed"'
' || die

do_ssh_su -t 'Mark packages as manually installed' '
    aptitude --quiet --assume-yes -o Aptitude::Delete-Unused=0 unmarkauto '"$packages_manual"'
' || die

#NB: Backup letsencrypt info here, it should re-setup all account info & certs OK even if we don't, but
#    if we are testing - and blitz the directory too many times - we might hit a letsencrypt usage limit.
do_ssh_su  -t 'Backup potentially existing letsencrypt info' '
    ! test -d /etc/letsencrypt || \
        mv -fT /etc/letsencrypt /etc/letsencrypt.hernia-backup
'

do_ssh_su -t 'Explicitly purge leftover packages' '
    test -z "'"$packages_leftover"'" || \
        aptitude --quiet --assume-yes -o Aptitude::Delete-Unused=0 purge '"$packages_leftover"'
' || die

do_ssh_su -t 'Auto-purge remaining unused packages' '
    aptitude --quiet --assume-yes install
' || die

if printf %s\\n "$SERVER_ALIASES" | grep -E -q '(^| )mail($| )'; then
    _mail_host='mail'
else
    _mail_host="$main_alias"
fi
_mail_name="${_mail_host}.$SERVER_DOMAIN"
_otherfqdns="$(printf %s\\n "$SERVER_ALIASES" | sed -re "s/(^$main_alias | $main_alias\$)//; s/ $main_alias / /; s/( |\$)/.$SERVER_DOMAIN\\1/g")"
do_ssh_su -t 'Patch and configure hostname, hosts, mailname & aliases files, and Exim settings' '
    printf %s\\n "'"$main_alias"'" >/etc/hostname
    cat <<EOF >/etc/hosts
'"$PUBLIC_IPV4_ADDRESS ${main_alias}.$SERVER_DOMAIN $_otherfqdns $SERVER_ALIASES
$PUBLIC_IPV6_ADDRESS ${main_alias}.$SERVER_DOMAIN $_otherfqdns $SERVER_ALIASES"'

127.0.0.1                       localhost
::1                             localhost               ip6-localhost ip6-loopback
fe00::0                         ip6-localnet
ff00::0                         ip6-mcastprefix
ff02::1                         ip6-allnodes
ff02::2                         ip6-allrouters
ff02::3                         ip6-allhosts
EOF
    printf '\'''"$_mail_name"'\n'\'' >/etc/mailname
    sed --follow-symlinks -i -e '\''s/^root:.*$/root: '"$(
        if test 'yes' = "$EMAIL_REMOTE"; then
            printf '%s' "$EMAIL"
        else
            printf '%s' "$USER_NAME"
        fi
    )"'/'\'' /etc/aliases
    sed --follow-symlinks -i -re '\''
        s/^([ \t]*[^ \t#])/#\1/
    '\'' /etc/email-addresses
    grep -E -q "hosts_require_tls *= *REMOTE_SMTP_HOSTS_REQUIRE_TLS" /etc/exim4/exim4.conf.template || \
        sed --follow-symlinks -i -re '\''
            /^\.ifdef +REMOTE_SMTP_HOSTS_AVOID_TLS/ i \
.ifdef REMOTE_SMTP_HOSTS_REQUIRE_TLS\
  hosts_require_tls = REMOTE_SMTP_HOSTS_REQUIRE_TLS\
.endif
        '\'' /etc/exim4/exim4.conf.template
    for _varname in MAIN_TLS_ENABLE REMOTE_SMTP_HOSTS_REQUIRE_TLS; do
        if grep -E -q "^$_varname *=" /etc/exim4/exim4.conf.localmacros 2>/dev/null; then
            sed --follow-symlinks -i -re "
                s/^$_varname *=.*\$/$_varname = yes/
            " /etc/exim4/exim4.conf.localmacros
        else
            printf '\''%s = yes\n'\'' "$_varname" \
                >>/etc/exim4/exim4.conf.localmacros
        fi
    done
    hostname "'"$main_alias"'"
    printf '\''
exim4-config\texim4/use_split_config\tboolean\tfalse
exim4-config\texim4/dc_localdelivery\tselect\tmbox format in /var/mail/
exim4-config\texim4/dc_postmaster\tstring\t'"$(
    if test 'yes' = "$EMAIL_REMOTE"; then
        printf '%s' "$EMAIL"
    else
        printf '%s' "$USER_NAME"
    fi
)"'
exim4-config\texim4/dc_readhost\tstring\t
exim4-config\texim4/dc_minimaldns\tboolean\tfalse
exim4-config\texim4/dc_relay_domains\tstring\t
exim4-config\texim4/mailname\tstring\t'"$_mail_name"'
exim4-config\texim4/dc_local_interfaces\tstring\t127.0.0.1 ; ::1
exim4-config\texim4/dc_other_hostnames\tstring\t'"$(
    printf '%s %s\n' "$_otherfqdns" "$SERVER_ALIASES" | \
        sed -re 's/^ +//; s/ +$//; s/ +/ ; /g'
)"'
exim4-config\texim4/dc_smarthost\tstring\t
exim4-config\texim4/dc_eximconfig_configtype\tselect\tinternet site; mail is sent and received directly using SMTP
exim4-config\texim4/hide_mailname\tboolean\ttrue
exim4-config\texim4/dc_relay_nets\tstring\t
exim4-config\texim4/no_config\tboolean\ttrue
'\'' | \
        debconf-set-selections --verbose
    rm -f /etc/exim4/update-exim4.conf.conf #otherwise this overrides debconf
    dpkg-reconfigure --frontend=noninteractive exim4-config
    service exim4 restart
' || die

do_ssh_su -t 'Update user-shell to fizsh' '
    chsh -s "/usr/bin/fizsh" "'"$USER_NAME"'"
' || die

do_scp_u 'out' 'content/add/_provision/home_dir/.emacs.minimal' '~' -t 'Copy ".emacs.minimal" to ~' && \
    do_scp_u 'out' 'content/add/_provision/home_dir/.emacs' '~' -t 'Copy ".emacs" to ~' || \
        die

# Finished provisioning
info 'Provisioning phase finished. Logfile stored at "%s". Now you should be able to trigger deployment by doing:\n  git push vm\n' "/tmp/provision.log"

if test yes = "$AUTO_DEPLOY_AFTER_PROVISION"; then
    do_ssh_u -t 'Trigger an auto-deploy' '
        cd '"$REPO_PATH"'
        { git log -2 --pretty=format:%H --reverse | tr \\n " "; printf \ '"$BRANCH"'\\n; } | ./hooks/post-receive
    ' || die
fi
