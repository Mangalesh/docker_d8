ENV DRUPAL_VERSION 8.8.1

# Install packages.
RUN apt-get update
RUN apt-get install -y \
	vim \
	git \
	apache2 \
	php-cli \
	php-mysql \
	php-gd \
	php-curl \
	php-xdebug \
	php-bcmath \
	php7.0-sqlite3 \
	libapache2-mod-php \
	curl \
	mysql-server \
	mysql-client \
	openssh-server \
	phpmyadmin \
	wget \
	unzip \
	cron \
    gnupg 
RUN apt-get clean

# Setup PHP.
RUN sed -i 's/display_errors = Off/display_errors = On/' /etc/php/7.0/apache2/php.ini
RUN sed -i 's/display_errors = Off/display_errors = On/' /etc/php/7.0/cli/php.ini


# Setup Apache.
# In order to run our Simpletest tests, we need to make Apache
# listen on the same port as the one we forwarded. Because we use
# 8080 by default, we set it up for that port.
RUN sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
RUN sed -i 's/DocumentRoot \/var\/www\/html/DocumentRoot \/var\/www/' /etc/apache2/sites-available/000-default.conf
RUN sed -i 's/DocumentRoot \/var\/www\/html/DocumentRoot \/var\/www/' /etc/apache2/sites-available/default-ssl.conf
RUN echo "Listen 8080" >> /etc/apache2/ports.conf
RUN echo "Listen 8081" >> /etc/apache2/ports.conf
RUN echo "Listen 8443" >> /etc/apache2/ports.conf
RUN sed -i 's/VirtualHost \*:80/VirtualHost \*:\*/' /etc/apache2/sites-available/000-default.conf
RUN a2enmod rewrite
RUN a2ensite default-ssl.conf

# Setup PHPMyAdmin
RUN echo "\n# Include PHPMyAdmin configuration\nInclude /etc/phpmyadmin/apache.conf\n" >> /etc/apache2/apache2.conf
RUN sed -i -e "s/\/\/ \$cfg\['Servers'\]\[\$i\]\['AllowNoPassword'\]/\$cfg\['Servers'\]\[\$i\]\['AllowNoPassword'\]/g" /etc/phpmyadmin/config.inc.php
RUN sed -i -e "s/\$cfg\['Servers'\]\[\$i\]\['\(table_uiprefs\|history\)'\].*/\$cfg\['Servers'\]\[\$i\]\['\1'\] = false;/g" /etc/phpmyadmin/config.inc.php

# Setup MySQL, bind on all addresses.
RUN sed -i -e 's/^bind-address\s*=\s*127.0.0.1/#bind-address = 127.0.0.1/' /etc/mysql/my.cnf
RUN /etc/init.d/mysql start && \
	mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO drupal@localhost IDENTIFIED BY 'drupal'"

# Setup XDebug.
RUN echo "xdebug.max_nesting_level = 300" >> /etc/php/7.0/apache2/conf.d/20-xdebug.ini
RUN echo "xdebug.max_nesting_level = 300" >> /etc/php/7.0/cli/conf.d/20-xdebug.ini

# Install Composer.
RUN curl -sS https://getcomposer.org/installer | php
RUN mv composer.phar /usr/local/bin/composer

# Install Drush 8.
RUN composer global require drush/drush:8.*
RUN composer global update
# Unfortunately, adding the composer vendor dir to the PATH doesn't seem to work. So:
RUN ln -s /root/.composer/vendor/bin/drush /usr/local/bin/drush

# Install Drupal Console. There are no stable releases yet, so set the minimum 
# stability to dev.
RUN curl https://drupalconsole.com/installer -L -o drupal.phar && \
	mv drupal.phar /usr/local/bin/drupal && \
	chmod +x /usr/local/bin/drupal
RUN drupal init

# Install Drupal.
RUN rm -rf /var/www
RUN cd /var && \
	drush dl drupal-$DRUPAL_VERSION && \
	mv /var/drupal* /var/www
RUN mkdir -p /var/www/sites/default/files && \
	chmod a+w /var/www/sites/default -R && \
	mkdir /var/www/sites/all/modules/contrib -p && \
	mkdir /var/www/sites/all/modules/custom && \
	mkdir /var/www/sites/all/themes/contrib -p && \
	mkdir /var/www/sites/all/themes/custom && \
	cp /var/www/sites/default/default.settings.php /var/www/sites/default/settings.php && \
	cp /var/www/sites/default/default.services.yml /var/www/sites/default/services.yml && \
	chmod 0664 /var/www/sites/default/settings.php && \
	chmod 0664 /var/www/sites/default/services.yml && \
	chown -R www-data:www-data /var/www/
RUN /etc/init.d/mysql start && \
	cd /var/www && \
	drush si -y standard --db-url=mysql://drupal:drupal@localhost/drupal --account-pass=admin && \
	drush dl admin_menu devel && \
	# In order to enable Simpletest, we need to download PHPUnit.
	composer install --dev && \
	# Admin Menu is broken. See https://www.drupal.org/node/2563867 for more info.
	# As long as it is not fixed, only enable simpletest and devel.
	# drush en -y admin_menu simpletest devel
	drush en -y simpletest devel && \
	drush en -y bartik
RUN /etc/init.d/mysql start && \
	cd /var/www && \
	drush cset system.theme default 'bartik' -y

EXPOSE 80 3306
