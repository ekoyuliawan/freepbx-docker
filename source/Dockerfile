FROM debian:bookworm-slim

WORKDIR /usr/src
ENV DEBIAN_FRONTEND=noninteractive

# Install requirements
RUN apt-get update && apt-get -y install build-essential git curl wget libnewt-dev libssl-dev libncurses5-dev subversion libsqlite3-dev libjansson-dev libxml2-dev uuid-dev default-libmysqlclient-dev htop sngrep lame ffmpeg mpg123 \
  && apt-get -y install git vim curl wget libnewt-dev libssl-dev libncurses5-dev subversion libsqlite3-dev build-essential libjansson-dev libxml2-dev uuid-dev expect \
  && apt-get install -y build-essential linux-headers-`uname -r` openssh-server apache2 mariadb-server mariadb-client bison flex php8.2 php8.2-curl php8.2-cli php8.2-common php8.2-mysql php8.2-gd php8.2-mbstring php8.2-intl php8.2-xml php-pear curl sox libncurses5-dev libssl-dev mpg123 libxml2-dev libnewt-dev sqlite3 libsqlite3-dev pkg-config automake libtool autoconf git unixodbc-dev uuid uuid-dev libasound2-dev libogg-dev libvorbis-dev libicu-dev libcurl4-openssl-dev odbc-mariadb libical-dev libneon27-dev libsrtp2-dev libspandsp-dev sudo subversion libtool-bin python-dev-is-python3 unixodbc vim wget libjansson-dev software-properties-common nodejs npm ipset iptables fail2ban php-soap

# Install NodeJS
RUN curl -sL https://deb.nodesource.com/setup_14.x | bash - && apt-get install -y nodejs
RUN npm install -g pm2

# Modifications for Apache
RUN sudo sed -i 's/upload_max_filesize = 20M/upload_max_filesize = 120M/' /etc/php/7.4/apache2/php.ini
RUN sed -i 's/www-data/asterisk/' /etc/apache2/envvars

# Install MySQL Connector ODBC
RUN apt install unixodbc-dev unixodbc dpkg-dev libodbc1 odbcinst1debian2 wget -y
COPY odbc /usr/src/odbc
RUN cd odbc/ && dpkg -i mysql-common_8.0.27-1debian11_amd64.deb
RUN cd odbc/ && dpkg -i mysql-community-client-plugins_8.0.27-1debian11_amd64.deb
RUN cd odbc/ && dpkg -i mysql-community-client-core_8.0.27-1debian11_amd64.deb
RUN cd odbc/ && dpkg -i mysql-community-client_8.0.27-1debian11_amd64.deb
RUN cd odbc/ && dpkg -i mysql-connector-odbc_8.0.33-1debian11_amd64.deb

# Copy FreePBX files
COPY freepbx/installlib/files/odbc.ini /etc/odbc.ini
COPY freepbx/installlib/files/odbcinst.ini /etc/odbcinst.ini

# Download Asterisk source files
COPY asterisk-16.30.0 asterisk/
# Build Asterisk
RUN asterisk/contrib/scripts/install_prereq install
RUN cd asterisk/ && ./configure \
  --with-pjproject-bundled --with-jansson-bundled
RUN cd asterisk/ && make menuselect.makeopts && menuselect/menuselect \
  --enable app_macro menuselect.makeopts
# Install and configure Asterisk
RUN cd asterisk/ && make 
RUN cd asterisk/ && make install 
RUN cd asterisk/ && make config 
RUN cd asterisk/ && ldconfig 
RUN update-rc.d -f asterisk remove
RUN useradd -m asterisk
RUN chown asterisk. /var/run/asterisk
RUN chown -R asterisk. /etc/asterisk
RUN chown -R asterisk. /var/lib/asterisk
RUN chown -R asterisk. /var/log/asterisk
RUN chown -R asterisk. /var/spool/asterisk
RUN chown -R asterisk. /usr/lib/asterisk && rm -rf /var/www/html

# Download and install FreePBX
COPY freepbx freepbx/
RUN touch /etc/asterisk/modules.conf && touch /etc/asterisk/cdr.conf

# Install and configure Fail2ban
RUN apt-get install iptables jq vim sudo fail2ban -y && mv /etc/fail2ban/jail.conf /etc/fail2ban/jail.conf-original
RUN adduser docker && adduser docker sudo
RUN su - docker
COPY fail2ban/ /etc/fail2ban/

COPY entrypoint.sh /usr/src/entrypoint.sh
CMD ["sh", "/usr/src/entrypoint.sh"]