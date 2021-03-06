#!/bin/bash

REPO_PATH='/home/vmail'

if [ -f $REPO_PATH/installer/config.conf ]; then

    ## Config file
    chmod 600 $REPO_PATH/installer/config.conf
    source $REPO_PATH/installer/config.conf


    ## Update
    pacman -Syu --noconfirm
    pacman-db-upgrade


    ## Install some tools
    pacman -S wget gzip git apg --noconfirm


    ## Change the hardware clock time standard to localtime
    timedatectl set-timezone $CONFIG_TIMEZONE
    #timedatectl --adjust-system-clock set-local-rtc 0


    ## Protection against OS detection
    touch /etc/sysctl.d/99-sysctl.conf
    echo "net.ipv4.ip_default_ttl=142" >> /etc/sysctl.d/99-sysctl.conf
    echo "Protection against OS detection [OK]."


    ## Hostname
    hostnamectl set-hostname $CONFIG_REVERSE_PRIMARY
    echo "Hostname [OK]."


    ## Journald
    mv /etc/systemd/journald.conf /etc/systemd/journald.conf.save
    cp $REPO_PATH/installer/journald/journald.conf /etc/systemd/journald.conf
    systemctl restart systemd-journald.service
    echo "Journald [OK]."


    ## Iptables
    pacman -S iptables --noconfirm
    cp $REPO_PATH/installer/iptables/* /etc/iptables/
    systemctl enable iptables.service
    systemctl start iptables.service
    iptables-restore < /etc/iptables/iptables.rules
    echo "Iptables [OK]."


    ## BIND
    pacman -S bind --noconfirm
    mv /etc/named.conf /etc/named.conf.save
    cp $REPO_PATH/installer/bind/named.conf /etc/named.conf
    cp $REPO_PATH/installer/bind/zone /var/named/$CONFIG_DOMAIN
    sed -i -e "s/CONFIG_IP_SECONDARY/$CONFIG_IP_SECONDARY/g" /etc/named.conf
    sed -i -e "s/CONFIG_DOMAIN/$CONFIG_DOMAIN/g" /etc/named.conf
    sed -i -e "s/CONFIG_REVERSE_PRIMARY/$CONFIG_REVERSE_PRIMARY/g" /var/named/$CONFIG_DOMAIN
    sed -i -e "s/CONFIG_DOMAIN/$CONFIG_DOMAIN/g" /var/named/$CONFIG_DOMAIN
    sed -i -e "s/CURRENT_DATE/$(date +"%Y%m%d")/g" /var/named/$CONFIG_DOMAIN
    sed -i -e "s/CONFIG_REVERSE_SECONDARY/$CONFIG_REVERSE_SECONDARY/g" /var/named/$CONFIG_DOMAIN
    sed -i -e "s/CONFIG_IP_PRIMARY/$CONFIG_IP_PRIMARY/g" /var/named/$CONFIG_DOMAIN
    systemctl enable named.service
    systemctl start named.service
    echo "BIND [OK]."


    ## MariaDB
    pacman -S mariadb expect --noconfirm
    mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
    systemctl start mysqld.service

    expect << EOF
    spawn mysql_secure_installation
    expect "Enter current password for root (enter for none):"
    send "\r"
    expect "Set root password?"
    send "n\r"
    expect "Remove anonymous users?"
    send "y\r"
    expect "Disallow root login remotely?"
    send "y\r"
    expect "Remove test database and access to it?"
    send "y\r"
    expect "Reload privilege tables now?"
    send "y\r"
    interact
EOF

    mysql -u root -e "CREATE DATABASE IF NOT EXISTS vmailme;"
    mysql -u root -e "CREATE USER 'www'@'localhost' IDENTIFIED BY '$CONFIG_MARIADB_WWW_PASSWORD';"
    mysql -u root -e "GRANT ALL ON vmailme.* TO 'www'@'localhost';"
    mysql -u root -e "CREATE USER 'server'@'localhost' IDENTIFIED BY '$CONFIG_MARIADB_SERVER_PASSWORD';"
    mysql -u root -e "GRANT ALL ON vmailme.* TO 'server'@'localhost';"

    mysql -u root -e "CREATE DATABASE IF NOT EXISTS roundcube;"
    mysql -u root -e "CREATE USER 'roundcube'@'localhost' IDENTIFIED BY '$CONFIG_MARIADB_ROUNDCUBE_PASSWORD';"
    mysql -u root -e "GRANT ALL ON roundcube.* TO 'roundcube'@'localhost';"

    mysql -u root -e "CREATE DATABASE IF NOT EXISTS piwik;"
    mysql -u root -e "CREATE USER 'piwik'@'localhost' IDENTIFIED BY '$CONFIG_MARIADB_PIWIK_PASSWORD';"
    mysql -u root -e "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, CREATE TEMPORARY TABLES, LOCK TABLES ON piwik.* TO 'piwik'@'localhost';"

    mysql -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$CONFIG_MARIADB_ROOT_PASSWORD');"
    mysql -u root -p"$CONFIG_MARIADB_ROOT_PASSWORD" -e "SET PASSWORD FOR 'root'@'127.0.0.1' = PASSWORD('$CONFIG_MARIADB_ROOT_PASSWORD');"
    mysql -u root -p"$CONFIG_MARIADB_ROOT_PASSWORD" -e "SET PASSWORD FOR 'root'@'::1' = PASSWORD('$CONFIG_MARIADB_ROOT_PASSWORD');"

    mysql -u root -p"$CONFIG_MARIADB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

    systemctl enable mysqld.service
    echo "MariaDB [OK]."


    ## SSL/TLS
    openssl req -nodes -newkey rsa:4096 -nodes -keyout /etc/ssl/private/server.key -out /etc/ssl/certs/server.csr -subj "/C=$CONFIG_SSL_COUNTRY_CODE/ST=$CONFIG_SSL_STATE/L=$CONFIG_SSL_CITY/O=$CONFIG_DOMAIN/OU=Secure Services Department/CN=*.$CONFIG_DOMAIN"
    openssl x509 -req -days 365 -in /etc/ssl/certs/server.csr -signkey /etc/ssl/private/server.key -out /etc/ssl/certs/server.crt
    chown nobody:nobody /etc/ssl/private/server.key
    chmod 600 /etc/ssl/private/server.key
    openssl dhparam -out /etc/ssl/dhparams.pem 2048
    echo "SSL/TLS [OK]."


    ## PHP-FPM
    pacman -S php php-fpm php-apcu php-gd php-intl --noconfirm
    mv /etc/php/php.ini /etc/php/php.ini.save
    cp $REPO_PATH/installer/php/php.ini /etc/php/php.ini
    sed -i -e "s/CONFIG_DOMAIN/$CONFIG_DOMAIN/g" /etc/php/php.ini
    sed -i -e "s#CONFIG_TIMEZONE#$CONFIG_TIMEZONE#g" /etc/php/php.ini
    chmod 644 /etc/php/php.ini
    systemctl enable php-fpm.service
    systemctl start php-fpm.service
    echo "PHP [OK]."


    ## Nginx
    pacman -S nginx --noconfirm
    mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.save
    cp $REPO_PATH/installer/nginx/nginx.conf /etc/nginx/nginx.conf
    sed -i -e "s/CONFIG_DOMAIN/$CONFIG_DOMAIN/g" /etc/nginx/nginx.conf
    systemctl enable nginx.service
    systemctl start nginx.service
    echo "Nginx [OK]."


    ## Roundcube
    pacman -S roundcubemail mysql-python --noconfirm
    cp $REPO_PATH/installer/roundcube/config.inc.php /etc/webapps/roundcubemail/config/config.inc.php
    sed -i -e "s/SECRET/$(apg -MCLN -m 24 -n 1)/g" /etc/webapps/roundcubemail/config/config.inc.php
    rm -r /usr/share/webapps/roundcubemail/installer/
    echo '' > /usr/share/webapps/roundcubemail/skins/classic/includes/header.html
    echo '' > /usr/share/webapps/roundcubemail/skins/larry/includes/header.html
    sed -i -e "s/ <roundcube:object name=\"version\" \/>//g" /usr/share/webapps/roundcubemail/skins/*/templates/about.html

    sed -i -e "s/CONFIG_MARIADB_ROUNDCUBE_PASSWORD/$CONFIG_MARIADB_ROUNDCUBE_PASSWORD/g" /etc/webapps/roundcubemail/config/config.inc.php
    sed -i -e "s/CONFIG_DOMAIN/$CONFIG_DOMAIN/g" /etc/webapps/roundcubemail/config/config.inc.php

    mysql -u root -p"$CONFIG_MARIADB_ROOT_PASSWORD" roundcube < /usr/share/webapps/roundcubemail/SQL/mysql.initial.sql

    chown -R http:http /usr/share/webapps/roundcubemail
    chown -R http:http /etc/webapps/roundcubemail
    chmod 600 /etc/webapps/roundcubemail/config/config.inc.php
    touch /var/log/roundcubemail/userlogins
    touch /var/log/roundcubemail/sendmail
    chown http:http /var/log/roundcubemail/userlogins
    chown http:http /var/log/roundcubemail/sendmail
    echo "Roundcube [OK]."


    ## Piwik
    wget https://aur.archlinux.org/packages/pi/piwik/piwik.tar.gz
    tar zxvf piwik.tar.gz
    cd piwik
    makepkg -s --asroot
    pacman -U *.xz --noconfirm
    cd ../
    rm -f piwik.tar.gz
    rm -r piwik
    echo "Piwik [OK]."


    ## Postfix (MTA)
    pacman -S postfix --noconfirm
    mkdir -p /etc/aliases
    newaliases # fix me
    mv /etc/postfix/master.cf /etc/postfix/master.cf.save
    mv /etc/postfix/main.cf /etc/postfix/main.cf.save
    cp $REPO_PATH/installer/postfix/*.cf /etc/postfix/
    cp -r $REPO_PATH/installer/postfix/mysql /etc/postfix/
    cp $REPO_PATH/installer/postfix/pfdel.pl /usr/local/bin/pfdel
    sed -i -e "s/CONFIG_REVERSE_PRIMARY/$CONFIG_REVERSE_PRIMARY/g" /etc/postfix/main.cf
    sed -i -e "s/CONFIG_DOMAIN/$CONFIG_DOMAIN/g" /etc/postfix/main.cf
    sed -i -e "s/CONFIG_IP_PRIMARY/$CONFIG_IP_PRIMARY/g" /etc/postfix/main.cf
    sed -i -e "s/CONFIG_MARIADB_SERVER_PASSWORD/$CONFIG_MARIADB_SERVER_PASSWORD/g" /etc/postfix/mysql/virtual_alias_maps.cf
    sed -i -e "s/CONFIG_MARIADB_SERVER_PASSWORD/$CONFIG_MARIADB_SERVER_PASSWORD/g" /etc/postfix/mysql/virtual_mailbox_maps.cf
    sed -i -e "s/CONFIG_MARIADB_SERVER_PASSWORD/$CONFIG_MARIADB_SERVER_PASSWORD/g" /etc/postfix/mysql/sender_login_maps.cf

    groupadd -g 5000 vmail
    useradd -u 5000 -g vmail -s /sbin/nologin -d /home/mailboxes -m vmail
    chmod 750 /home/mailboxes
    chmod +x /usr/local/bin/pfdel

    systemctl enable postfix.service
    systemctl start postfix.service
    echo "Postfix [OK]."


    ## Spamassassin
    pacman -S spamassassin --noconfirm
    /usr/bin/vendor_perl/sa-update
    systemctl enable spamassassin.service
    systemctl start spamassassin.service
    echo "Spamassassin [OK]."


    ## Postgrey
    pacman -S postgrey --noconfirm
    systemctl enable postgrey.service
    systemctl start postgrey.service
    echo "Postgrey [OK]."


    ## Postfwd
    pacman -S postfwd --noconfirm
    cp $REPO_PATH/installer/postfwd/postfwd.cf /etc/postfwd/postfwd.cf
    systemctl enable postfwd.service
    systemctl start postfwd.service
    echo "Postfwd [OK]."


    ## OpenDKIM
    pacman -S opendkim --noconfirm
    cp $REPO_PATH/installer/opendkim/opendkim.conf /etc/opendkim/opendkim.conf
    sed -i -e "s/CONFIG_DOMAIN/$CONFIG_DOMAIN/g" /etc/opendkim/opendkim.conf
    opendkim-genkey --bits 2048 --restrict --selector mx1 --domain $CONFIG_DOMAIN -D /etc/opendkim --verbose
    chmod 600 /etc/opendkim/mx1.private
    cat /etc/opendkim/mx1.txt >> /var/named/$CONFIG_DOMAIN
    sed -i -e "s/^2[0-9]\{9\}/$(date +"%Y%m%d")02/g" /var/named/$CONFIG_DOMAIN
    sed -i -e "s/\$OPENDKIM_FILTER/-x \/etc\/opendkim\/opendkim.conf/g" /usr/lib/systemd/system/opendkim.service
    systemctl enable opendkim.service
    systemctl start opendkim.service
    systemctl restart named.service
    echo "OpenDKIM [OK]."


    ## Dovecot (MDA)
    pacman -S dovecot --noconfirm
    cp $REPO_PATH/installer/dovecot/* /etc/dovecot/
    sed -i -e "s/CONFIG_MARIADB_SERVER_PASSWORD/$CONFIG_MARIADB_SERVER_PASSWORD/g" /etc/dovecot/dovecot-sql.conf
    sed -i -e "s/CONFIG_DOMAIN/$CONFIG_DOMAIN/g" /etc/dovecot/dovecot.conf

    systemctl enable dovecot.service
    systemctl start dovecot.service
    echo "Dovecot [OK]."


    ## Fail2ban
    pacman -S gamin fail2ban --noconfirm
    cp $REPO_PATH/installer/fail2ban/jail.local /etc/fail2ban/jail.local
    sed -i -e "s/CONFIG_IP_PRIMARY/$CONFIG_IP_PRIMARY/g" /etc/fail2ban/jail.local
    cp $REPO_PATH/installer/fail2ban/filter.d/symfony2-auth.conf /etc/fail2ban/filter.d/symfony2-auth.conf
    cp $REPO_PATH/installer/fail2ban/filter.d/piwik-auth.conf /etc/fail2ban/filter.d/piwik-auth.conf
    systemctl enable fail2ban.service
    systemctl start fail2ban.service
    echo "Fail2ban [OK]."


    ## Shortcuts
    ln -s /var/log /home/log
    ln -s /var/lib/mysql /home/database
    ln -s /var/spool/postfix /home/queue
    echo "Shortcuts [OK]."


    ## Cron
    pacman -S cronie --noconfirm
    cp $REPO_PATH/installer/cron/backup.sh /usr/local/bin/backup.sh
    sed -i -e "s/CONFIG_MARIADB_ROOT_PASSWORD/$CONFIG_MARIADB_ROOT_PASSWORD/g" /usr/local/bin/backup.sh
    chmod +x /usr/local/bin/backup.sh
    source $REPO_PATH/installer/cron/cron.sh
    systemctl enable cronie.service
    systemctl start cronie.service
    echo "Cronie [OK]."


    ## Composer
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer


    echo "Install server [OK]."
fi
