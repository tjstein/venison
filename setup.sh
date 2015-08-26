#!/bin/bash

#-- User Defined Variables --#
hostname=''             #Your hostname (e.g. example.com)
sudo_user=''            #Your sudo username
sudo_user_passwd=''     #Your sudo user password
root_passwd=''          #Your new root password
ssh_port='22'           #Your SSH port if you wish to change it from the default
wptitle=''              #Your WordPress site title
wpuser=''               #Your WordPress admin username
wppass=''               #Your WordPress admin password
wpemail=''              #Your WordPress admin user email address
#-- UDV End --#

os_check()
{
  if [ "$(lsb_release -cs)" != "natty" ]; then
  echo "You need to be running Ubuntu 11.04"
    exit
  fi
}

set_locale()
{
  echo -n "Setting up system locale... "
  { locale-gen en_US.UTF-8
    unset LANG
    /usr/sbin/update-locale LANG=en_US.UTF-8
  } > /dev/null 2>&1
  export LANG=en_US.UTF-8
  echo "done."
}  

set_hostname()
{
  if [ -n "$hostname" ]
  then
    echo -n "Setting up hostname... "
    hostname $hostname
    echo $hostname > /etc/hostname
    echo "127.0.0.1 $hostname" >> /etc/hostname
    echo "done."
  fi
}

set_timezone()
{
  echo "America/Los_Angeles" > /etc/timezone
  dpkg-reconfigure -f noninteractive tzdata > /dev/null 2>&1
}

change_root_passwd()
{
  if [ -n "$root_passwd" ]
  then
    echo -n "Changing root password... "
    echo "$root_passwd\n$root_passwd" > tmp/rootpass.$$
    passwd root < tmp/rootpass.$$ > /dev/null 2>&1
    echo "done."
  fi
}

create_sudo_user()
{
  if [ -n "$sudo_user" -a -n "$sudo_user_passwd" ]
  then
    id $sudo_user > /dev/null 2>&1 && echo "Cannot create sudo user! User $sudo_user already exists!" && touch tmp/sudofailed.$$ && return
    echo -n "Creating sudo user... "
    useradd -d /home/$sudo_user -s /bin/bash -m $sudo_user
    echo "$sudo_user:$sudo_user_passwd" | chpasswd
    echo "$sudo_user ALL=(ALL) ALL" >> /etc/sudoers
    { echo 'export PS1="\[\e[32;1m\]\u\[\e[0m\]\[\e[32m\]@\h\[\e[36m\]\w \[\e[33m\]\$ \[\e[0m\]"'
    } >> /home/$sudo_user/.bashrc
    echo "done."
  fi
}

config_ssh()
{
  conf='/etc/ssh/sshd_config'
  echo -n "Configuring SSH... "
  mkdir ~/.ssh && chmod 700 ~/.ssh/
  cp /etc/ssh/sshd_config /etc/ssh/sshd_config.`date "+%Y-%m-%d"`
  sed -i -r 's/\s*X11Forwarding\s+yes/X11Forwarding no/g' $conf
  sed -i -r 's/\s*UsePAM\s+yes/UsePAM no/g' $conf
  sed -i -r 's/\s*UseDNS\s+yes/UseDNS no/g' $conf
  perl -p -i -e 's|LogLevel INFO|LogLevel VERBOSE|g;' $conf
  grep -q "UsePAM no" $conf || echo "UsePAM no" >> $conf
  grep -q "UseDNS no" $conf || echo "UseDNS no" >> $conf
  if [ -n "$ssh_port" ]
  then
    sed -i -r "s/\s*Port\s+[0-9]+/Port $ssh_port/g" $conf 
    cp files/iptables.up.rules tmp/fw.$$
    sed -i -r "s/\s+22\s+/ $ssh_port /" tmp/fw.$$
  fi
  if id $sudo_user > /dev/null 2>&1 && [ ! -e tmp/sudofailed.$$ ]
  then
    sed -i -r 's/\s*PermitRootLogin\s+yes/PermitRootLogin no/g' $conf
    echo "AllowUsers $sudo_user" >> $conf
  fi
  echo "done."
}

setup_firewall()
{
  echo -n "Setting up firewall... "
  cp tmp/fw.$$ /etc/iptables.up.rules
  iptables -F
  iptables-restore < /etc/iptables.up.rules > /dev/null 2>&1 &&
  sed -i 's%pre-up iptables-restore < /etc/iptables.up.rules%%g' /etc/network/interfaces
  sed -i -r 's%\s*iface\s+lo\s+inet\s+loopback%iface lo inet loopback\npre-up iptables-restore < /etc/iptables.up.rules%g' /etc/network/interfaces
  /etc/init.d/ssh reload > /dev/null 2>&1
  echo "done."
}

setup_tmpdir()
{
  echo -n "Setting up temporary directory... "
  echo "APT::ExtractTemplates::TempDir \"/var/local/tmp\";" > /etc/apt/apt.conf.d/50extracttemplates && mkdir /var/local/tmp/
  mkdir ~/tmp && chmod 777 ~/tmp
  mount --bind ~/tmp /tmp
  echo "done."
}

install_base()
{
  echo -n "Setting up base packages... "
  aptitude update > /dev/null 2>&1
  aptitude -y safe-upgrade > /dev/null 2>&1
  aptitude -y full-upgrade > /dev/null 2>&1
  aptitude -y install curl build-essential python-software-properties git-core htop > /dev/null 2>&1
  echo "done."
}

install_php()
{
  echo -n "Installing PHP... "
  mkdir -p /var/www
  aptitude -y install php5-cli php5-common php5-mysql php5-suhosin php5-gd php5-curl > /dev/null 2>&1
  aptitude -y install php5-fpm php5-cgi php-pear php-apc php5-dev libpcre3-dev > /dev/null 2>&1
  perl -p -i -e 's|# Default-Stop:|# Default-Stop:      0 1 6|g;' /etc/init.d/php5-fpm
  cp /etc/php5/fpm/pool.d/www.conf /etc/php5/fpm/pool.d/www.conf.`date "+%Y-%m-%d"`
  chmod 000 /etc/php5/fpm/pool.d/www.conf.`date "+%Y-%m-%d"` && mv /etc/php5/fpm/pool.d/www.conf.`date "+%Y-%m-%d"` /tmp
  perl -p -i -e 's|;listen.allowed_clients = 127.0.0.1|listen.allowed_clients = 127.0.0.1|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;pm.status_path = /status|pm.status_path = /status|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;ping.path = /ping|ping.path = /ping|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;ping.response = pong|ping.response = pong|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;request_terminate_timeout = 0|request_terminate_timeout = 300s|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;request_slowlog_timeout = 0|request_slowlog_timeout = 5s|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;listen.backlog = -1|listen.backlog = -1|g;' /etc/php5/fpm/pool.d/www.conf
  sed -i -r "s/www-data/$sudo_user/g" /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;slowlog = log/\$pool.log.slow|slowlog = /var/log/php5-fpm.log.slow|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;catch_workers_output = yes|catch_workers_output = yes|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|pm.max_children = 50|pm.max_children = 25|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;pm.start_servers = 20|pm.start_servers = 3|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|pm.min_spare_servers = 5|pm.min_spare_servers = 2|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|pm.max_spare_servers = 35|pm.max_spare_servers = 4|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;pm.max_requests = 500|pm.max_requests = 500|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;emergency_restart_threshold = 0|emergency_restart_threshold = 10|g;' /etc/php5/fpm/main.conf
  perl -p -i -e 's|;emergency_restart_interval = 0|emergency_restart_interval = 1m|g;' /etc/php5/fpm/main.conf
  perl -p -i -e 's|;process_control_timeout = 0|process_control_timeout = 5s|g;' /etc/php5/fpm/main.conf
  perl -p -i -e 's|;daemonize = yes|daemonize = yes|g;' /etc/php5/fpm/main.conf
  cp /etc/php5/fpm/php.ini /etc/php5/fpm/php.ini.`date "+%Y-%m-%d"`
  perl -p -i -e 's|;date.timezone =|date.timezone = America/Los_Angeles|g;' /etc/php5/fpm/php.ini
  perl -p -i -e 's|expose_php = On|expose_php = Off|g;' /etc/php5/fpm/php.ini
  perl -p -i -e 's|allow_url_fopen = On|allow_url_fopen = Off|g;' /etc/php5/fpm/php.ini
  perl -p -i -e 's|;cgi.fix_pathinfo=1|cgi.fix_pathinfo=0|g;' /etc/php5/fpm/php.ini
  perl -p -i -e 's|;realpath_cache_size = 16k|realpath_cache_size = 128k|g;' /etc/php5/fpm/php.ini
  perl -p -i -e 's|;realpath_cache_ttl = 120|realpath_cache_ttl = 600|g;' /etc/php5/fpm/php.ini
  perl -p -i -e 's|disable_functions =|disable_functions = "system,exec,shell_exec,passthru,escapeshellcmd,popen,pcntl_exec"|g;' /etc/php5/fpm/php.ini
  cp files/apc.ini /etc/php5/fpm/conf.d/apc.ini
  service php5-fpm stop > /dev/null 2>&1
  service php5-fpm start > /dev/null 2>&1
  echo "done."
}

install_mysql()
{
  echo -n "Installing MySQL... "
  MYSQL_PASS=`echo $(</dev/urandom tr -dc A-Za-z0-9 | head -c 15)`
  echo "mysql-server mysql-server/root_password select $MYSQL_PASS" | debconf-set-selections
  echo "mysql-server mysql-server/root_password_again select $MYSQL_PASS" | debconf-set-selections
  aptitude -y install mysql-server > /dev/null 2>&1
  cat <<EOF > /root/.my.cnf
[client]
user=root
password=$MYSQL_PASS

EOF
  chmod 600 /root/.my.cnf
  mv /etc/mysql/my.cnf /etc/mysql/my.cnf.`date "+%Y-%m-%d"`
  cp files/my.cnf /etc/mysql/
  touch /var/log/mysql/mysql-slow.log
  chown mysql:mysql /var/log/mysql/mysql-slow.log
  service mysql restart > /dev/null 2>&1
  echo "done."
}

config_db()
{
  echo -n "Setting up WordPress database... "
  WP_DB=`echo $(</dev/urandom tr -dc A-Za-z0-9 | head -c 15)`
  WP_USER=`echo $(</dev/urandom tr -dc A-Za-z0-9 | head -c 15)`
  WP_USER_PASS=`echo $(</dev/urandom tr -dc A-Za-z0-9 | head -c 15)`
  mysql -e "CREATE DATABASE $WP_DB"
  mysql -e "GRANT ALL PRIVILEGES ON $WP_DB.* to $WP_USER@localhost IDENTIFIED BY '$WP_USER_PASS'"
  mysql -e "FLUSH PRIVILEGES"
  echo "done."
}

config_nginx()
{
  echo -n "Setting up Nginx... "
  add-apt-repository ppa:nginx/stable > /dev/null 2>&1
  aptitude -y update > /dev/null 2>&1
  aptitude -y install nginx > /dev/null 2>&1
  cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.`date "+%Y-%m-%d"`
  rm -rf /etc/nginx/nginx.conf
  cp files/nginx.conf /etc/nginx/nginx.conf
  /bin/mkdir -p ~/.vim/syntax/
  cp files/nginx.vim ~/.vim/syntax/nginx.vim
  touch ~/.vim/filetype.vim
  echo "au BufRead,BufNewFile /etc/nginx/* set ft=nginx" >> ~/.vim/filetype.vim
  rm -rf /etc/nginx/sites-available/default
  unlink /etc/nginx/sites-enabled/default
  cp files/mydomain.com /etc/nginx/sites-available/$hostname.conf
  rm -rf /etc/nginx/fastcgi_params
  cp files/fastcgi_params /etc/nginx/fastcgi_params
  cp files/fastcgi_cache /etc/nginx/fastcgi_cache
  cp files/fastcgi_rules /etc/nginx/fastcgi_rules
  sed -i -r "s/sudoer/$sudo_user/g" /etc/nginx/nginx.conf
  sed -i -r "s/mydomain.com/$hostname/g" /etc/nginx/sites-available/$hostname.conf
  sed -i -r "s/sudoer/$sudo_user/g" /etc/nginx/sites-available/$hostname.conf
  ln -s -v /etc/nginx/sites-available/$hostname.conf /etc/nginx/sites-enabled/001-$hostname.conf > /dev/null 2>&1
  rm -rf /var/www/nginx-default
  service nginx restart > /dev/null 2>&1
  echo "done."
}

install_postfix()
{
  echo -n "Setting up Postfix... "
  echo "postfix postfix/mailname string $hostname" | debconf-set-selections
  echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
  aptitude -y install postfix > /dev/null 2>&1
  /usr/sbin/postconf -e "inet_interfaces = loopback-only"
  service postfix restart > /dev/null 2>&1
  echo "done."
}

configure_wp()
{
  echo -n "Setting up WordPress... "
  DB_PREFIX=`echo $(</dev/urandom tr -dc A-Za-z0-9 | head -c 7)`
  mkdir -p /home/$sudo_user/$hostname/public/
  wget -q -o ~/install.log -O /home/$sudo_user/$hostname/public/latest.zip http://wordpress.org/latest.zip
  unzip /home/$sudo_user/$hostname/public/latest.zip -d /home/$sudo_user/$hostname/public/ >> ~/install.log
  mv /home/$sudo_user/$hostname/public/wordpress/* /home/$sudo_user/$hostname/public/
  rm -rf /home/$sudo_user/$hostname/public/wordpress
  rm -rf /home/$sudo_user/$hostname/public/latest.zip
  perl -p -i -e "s|database_name_here|$WP_DB|;" /home/$sudo_user/$hostname/public/wp-config-sample.php
  perl -p -i -e "s|username_here|$WP_USER|;" /home/$sudo_user/$hostname/public/wp-config-sample.php
  perl -p -i -e "s|password_here|$WP_USER_PASS|;" /home/$sudo_user/$hostname/public/wp-config-sample.php
  perl -p -i -e "s|\$table_prefix  = 'wp_';|\$table_prefix  = '$DB_PREFIX';|;" /home/$sudo_user/$hostname/public/wp-config-sample.php
  mv /home/$sudo_user/$hostname/public/wp-config-sample.php /home/$sudo_user/$hostname/public/wp-config.php
  wget -O /tmp/wp.keys https://api.wordpress.org/secret-key/1.1/salt/ > /dev/null 2>&1
  sed -i '/#@-/r /tmp/wp.keys' /home/$sudo_user/$hostname/public/wp-config.php
  sed -i "/#@+/,/#@-/d" /home/$sudo_user/$hostname/public/wp-config.php
  rm -rf /home/$sudo_user/$hostname/public/license.txt && rm -rf /home/$sudo_user/$hostname/public/readme.html
  rm -rf /tmp/wp.keys
  curl -d "weblog_title=$wptitle&user_name=$wpuser&admin_password=$wppass&admin_password2=$wppass&admin_email=$wpemail" http://$hostname/wp-admin/install.php?step=2 >/dev/null 2>&1
  mv /home/$sudo_user/$hostname/public/wp-config.php /home/$sudo_user/$hostname/wp-config.php
  sed -i 's/'"$(printf '\015')"'$//g' /home/$sudo_user/$hostname/wp-config.php
  chmod 400 /home/$sudo_user/$hostname/wp-config.php
  sed -i '1 a\
define('WP_CACHE', true);' /home/$sudo_user/$hostname/wp-config.php
  chown -R $sudo_user:$sudo_user /home/$sudo_user/$hostname
  echo "done."
}

install_monit()
{
  echo -n "Setting up Monit... "
  aptitude -y install monit > /dev/null 2>&1
  perl -p -i -e 's|startup=0|startup=1|g;' /etc/default/monit
  mv /etc/monit/monitrc /etc/monit/monitrc.bak
  cp files/monitrc /etc/monit/monitrc
  chmod 700 /etc/monit/monitrc
  sed -i -r "s/mydomain.com/$hostname/g" /etc/monit/monitrc
  sed -i -r "s/monitemail/$wpemail/g" /etc/monit/monitrc
  sed -i -r "s/sshport/$ssh_port/g" /etc/monit/monitrc
  service monit restart > /dev/null 2>&1
  echo "done."
}

print_report()
{
  echo ""
  echo "Venison is delicious... enjoy!"
  echo ""
  echo "Database to be used: $WP_DB"
  echo "Database user: $WP_USER"
  echo "Database user password: $WP_USER_PASS"
  echo ""
}

check_vars()
{
  if [ -n "$hostname" -a -n "$sudo_user" -a -n "$sudo_user_passwd" -a -n "$root_passwd" -a -n "$ssh_port" -a -n "$wptitle" -a -n "$wpuser" -a -n "$wppass" -a -n "$wpemail" ]
  then
    return
  else
    echo "Value of variables cannot be empty."
  fi
}

cleanup()
{
  rm -rf tmp/*
}

#-- Function calls and flow of execution --#

# make sure we are running Ubuntu 11.04
os_check

# clean up tmp
cleanup

# check value of all UDVs
check_vars

# set system locale
set_locale

# set host name of server
set_hostname

# set timezone of server
set_timezone

# change root user password
change_root_passwd

# create and configure sudo user
create_sudo_user

# configure ssh
config_ssh

# set up and activate firewall
setup_firewall

# set up temp directory
setup_tmpdir

# set up base packages
install_base

# install php
install_php

# install mysql
install_mysql

# configure database
config_db

# configure nginx web server
config_nginx

# install postfix
install_postfix

# configure wordpress
configure_wp

# install monit
install_monit

# clean up tmp
cleanup

# print report of db info
print_report
