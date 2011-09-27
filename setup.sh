#!/bin/bash
# __    __                
#/\ \__/\ \               
#\ \ ,_\ \ \___      __   
# \ \ \/\ \  _ `\  /'__`\ 
#  \ \ \_\ \ \ \ \/\  __/ 
#   \ \__\\ \_\ \_\ \____\
#    \/__/ \/_/\/_/\/____/                         
#                                                          
#                       __          __                     
# __  __  _____   _ __ /\_\    ____/\_\    ___      __     
#/\ \/\ \/\ '__`\/\`'__\/\ \  /',__\/\ \ /' _ `\  /'_ `\   
#\ \ \_\ \ \ \L\ \ \ \/ \ \ \/\__, `\ \ \/\ \/\ \/\ \L\ \  
# \ \____/\ \ ,__/\ \_\  \ \_\/\____/\ \_\ \_\ \_\ \____ \ 
#  \/___/  \ \ \/  \/_/   \/_/\/___/  \/_/\/_/\/_/\/___L\ \
#           \ \_\                                   /\____/
#            \/_/                                   \_/__/ 
#                            __                          
#                           /\ \__  __                   
#  ___   _ __    __     __  \ \ ,_\/\_\  __  __     __   
# /'___\/\`'__\/'__`\ /'__`\ \ \ \/\/\ \/\ \/\ \  /'__`\ 
#/\ \__/\ \ \//\  __//\ \L\.\_\ \ \_\ \ \ \ \_/ |/\  __/ 
#\ \____\\ \_\\ \____\ \__/.\_\\ \__\\ \_\ \___/ \ \____\
# \/____/ \/_/ \/____/\/__/\/_/ \/__/ \/_/\/__/   \/____/

#-- User Defined Variables --#
hostname=''    #Your hostname (e.g. theuprisingcreative.com)
sudo_user=''    #Your username
sudo_user_passwd=''     #your password
root_passwd=''    #Your new root password
ssh_port='22'   #Your SSH port if you wish to change it from the default
wptitle=''    #Your WordPress site title
wpuser=''	#Your WordPress admin username
wppass=''	#Your WordPress admin password
wpemail=''	#Your WordPress admin user email address
#-- UDV End --#

os_check()
{
  if [ "$(cat /etc/lsb-release | grep natty)" != "DISTRIB_CODENAME=natty" ]; then
  echo "You need to be running Ubuntu 11.04"
    exit
  fi
}

set_locale()
{
  echo -n "Setting up system locale..."
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
    echo -n "Setting up hostname..."
    hostname $hostname
    echo $hostname > /etc/hostname
    echo "127.0.0.1 $hostname" >> /etc/hostname
    echo "done."
  fi
}

set_timezone()
{
  echo "America/Los_Angeles" > /etc/timezone
  dpkg-reconfigure -f noninteractive tzdata
}

change_root_passwd()
{
  if [ -n "$root_passwd" ]
  then
    echo -n "Changing root password..."
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
    echo -n "Creating sudo user..."
    useradd -d /home/$sudo_user -s /bin/bash -m $sudo_user
    echo "$sudo_user_passwd\n$sudo_user_passwd" > tmp/sudopass.$$
    passwd $sudo_user < tmp/sudopass.$$ > /dev/null 2>&1
    echo "$sudo_user ALL=(ALL) ALL" >> /etc/sudoers
    { echo 'export PS1="\[\e[32;1m\]\u\[\e[0m\]\[\e[32m\]@\h\[\e[36m\]\w \[\e[33m\]\$ \[\e[0m\]"'
      echo 'alias ll="ls -la"'
      echo 'alias a2r="sudo /etc/init.d/apache2 stop && sleep 2 && sudo /etc/init.d/apache2 start"'
      echo 'alias n2r="sudo /etc/init.d/nginx stop && sleep 2 && sudo /etc/init.d/nginx start"'
      echo 'alias ver="cat /etc/lsb-release"'
    } >> /home/$sudo_user/.bashrc
    echo "done."
  fi
}

config_ssh()
{
  conf='/etc/ssh/sshd_config'
  echo -n "Configuring SSH..."
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
  echo -n "Setting up firewall..."
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
  echo -n "Setting up temporary directory..."
  echo "APT::ExtractTemplates::TempDir \"/var/local/tmp\";" > /etc/apt/apt.conf.d/50extracttemplates && mkdir /var/local/tmp/
  mkdir ~/tmp && chmod 777 ~/tmp
  mount --bind ~/tmp /tmp
  echo "done."
}

install_base()
{
  echo -n "Setting up base packages..."
  aptitude -y install curl subversion build-essential python-software-properties git-core htop
  echo "done."
}

install_php()
{
  echo "Installing PHP..."
  mkdir -p /var/www
  aptitude update
  aptitude -y safe-upgrade
  aptitude -y full-upgrade
  aptitude -y install php5-cli php5-common php5-mysql php5-suhosin php5-gd php5-curl
  aptitude -y install php5-fpm php5-cgi php-pear php5-dev libpcre3-dev
  perl -p -i -e 's|# Default-Stop:|# Default-Stop:      0 1 6|g;' /etc/init.d/php5-fpm
  cp /etc/php5/fpm/pool.d/www.conf /etc/php5/fpm/pool.d/www.conf.`date "+%Y-%m-%d"`
  chmod 000 /etc/php5/fpm/pool.d/www.conf.`date "+%Y-%m-%d"` && mv /etc/php5/fpm/pool.d/www.conf.`date "+%Y-%m-%d"` /tmp
  perl -p -i -e 's|listen = 127.0.0.1:9000|listen = /var/run/php5-fpm.sock|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;listen.allowed_clients = 127.0.0.1|listen.allowed_clients = 127.0.0.1|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;pm.status_path = /status|pm.status_path = /status|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;ping.path = /ping|ping.path = /ping|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;ping.response = pong|ping.response = pong|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;request_terminate_timeout = 0|request_terminate_timeout = 300s|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;request_slowlog_timeout = 0|request_slowlog_timeout = 5s|g;' /etc/php5/fpm/pool.d/www.conf
  perl -p -i -e 's|;listen.backlog = -1|listen.backlog = -1|g;' /etc/php5/fpm/pool.d/www.conf
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
  service php5-fpm stop && sleep 2
  service php5-fpm start
  echo "Done."
}

install_mysql()
{
  echo "Installing MySQL..."
  MYSQL_PASS=`echo $(</dev/urandom tr -dc A-Za-z0-9 | head -c 15)`
  echo "mysql-server mysql-server/root_password select $MYSQL_PASS" | debconf-set-selections
  echo "mysql-server mysql-server/root_password_again select $MYSQL_PASS" | debconf-set-selections
  aptitude -y install mysql-server
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
  service mysql restart
  echo "Done."
}

config_db()
{
  echo -n "Setting up WordPress..."
  WP_DB=`echo $(</dev/urandom tr -dc A-Za-z0-9 | head -c 15)`
  WP_USER=`echo $(</dev/urandom tr -dc A-Za-z0-9 | head -c 15)`
  WP_USER_PASS=`echo $(</dev/urandom tr -dc A-Za-z0-9 | head -c 15)`
  mysql -e "CREATE DATABASE $WP_DB"
  mysql -e "GRANT ALL PRIVILEGES ON $WP_DB.* to $WP_USER@localhost IDENTIFIED BY '$WP_USER_PASS'"
  mysql -e "FLUSH PRIVILEGES"
  echo -n "Done."
}

config_web()
{
  echo -n "Setting up Nginx..."
  WP_VERSION=`curl -s http://api.wordpress.org/core/version-check/1.4/ | grep -r "^[0-9]"|head -1`
  svn co http://svn.automattic.com/wordpress/tags/$WP_VERSION/ /var/www/$hostname/public/
  add-apt-repository ppa:nginx/stable 
  aptitude -y update 
  aptitude -y install nginx
  cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.`date "+%Y-%m-%d"`
  rm -rf /etc/nginx/nginx.conf
  cp files/nginx.conf /etc/nginx/nginx.conf
  rm -rf /etc/nginx/sites-available/default
  unlink /etc/nginx/sites-enabled/default
  cp files/mydomain.com /etc/nginx/sites-available/$hostname.conf
  sed -i -r "s/mydomain.com/$hostname/g" /etc/nginx/sites-available/$hostname.conf
  ln -s -v /etc/nginx/sites-available/$hostname.conf /etc/nginx/sites-enabled/$hostname.conf
  rm -rf /var/www/nginx-default
  service nginx restart
  echo -n "Done."
}

install_postfix()
{
  echo -n "Setting up Postfix..."
  echo "postfix postfix/mailname string $hostname" | debconf-set-selections
  echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
  aptitude -y install postfix
  usr/sbin/postconf -e "inet_interfaces = loopback-only"
  service postfix restart
  echo "Done."
}

configure_wp()
{
  echo -n "Setting up WordPress..."
  perl -p -i -e "s|database_name_here|$WP_DB|;" /var/www/$hostname/public/wp-config-sample.php
  perl -p -i -e "s|username_here|$WP_USER|;" /var/www/$hostname/public/wp-config-sample.php
  perl -p -i -e "s|password_here|$WP_USER_PASS|;" /var/www/$hostname/public/wp-config-sample.php
  mv /var/www/$hostname/public/wp-config-sample.php /var/www/$hostname/public/wp-config.php
  rm -rf license.txt readme.html
  wget -O /tmp/wp.keys https://api.wordpress.org/secret-key/1.1/salt/
  sed -i '/#@-/r /tmp/wp.keys' /var/www/$hostname/public/wp-config.php
  rm /tmp/wp.keys
  curl -d "weblog_title=$wptitle&user_name=$wpuser&admin_password=$wppass&admin_password2=$wppass&admin_email=$wpemail" http://$hostname/wp-admin/install.php?step=2 >/dev/null 2>&1
  sed -i "/#@+/,/#@-/d" /var/www/$hostname/public/wp-config.php
  mv /var/www/$hostname/public/wp-config.php /var/www/$hostname/wp-config.php
  chmod 400 /var/www/$hostname/wp-config.php
  sed -i '1 a\
  define('WP_CACHE', true);' /var/www/$hostname/wp-config.php
  chown -R www-data:www-data /var/www/$hostname
  echo "Done."
}

print_report()
{
  echo "WP install script: http://$hostname/"
  echo "Database to be used: $WP_DB"
  echo "Database user: $WP_USER"
  echo "Database user password: $WP_USER_PASS"
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
config_web

# install postfix
install_postfix

# configure wordpress
configure_wp

# clean up tmp
cleanup

# print report of db info
print_report