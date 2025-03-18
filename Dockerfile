FROM php:8.4-fpm

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    libonig-dev \
    libzip-dev \
    libicu-dev \
    libmagickwand-dev \
    zlib1g-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libwebp-dev \
    autoconf \
    automake \
    make \
    libtool \
    libssl-dev \
    libxml2-dev \
    libmemcached-dev \
    ghostscript \
    imagemagick \
    unzip \
    libwebp-dev \
    && rm -rf /var/lib/apt/lists/*

# Configure and install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) \
    gd \
    mysqli \
    pdo_mysql \
    exif \
    bcmath \
    intl \
    opcache \
    zip \
    pcntl \
    soap \
    sockets \
    mbstring

# Install Imagick PHP extension properly
RUN set -e; \
    # Install Imagick extension
    mkdir -p /tmp/imagick; \
    cd /tmp/imagick; \
    git clone https://github.com/Imagick/imagick.git .; \
    phpize; \
    ./configure; \
    make; \
    make install; \
    docker-php-ext-enable imagick; \
    cd /; \
    rm -rf /tmp/imagick

# Install ionCube Loader properly
RUN set -e; \
    mkdir -p /tmp/ioncube; \
    cd /tmp/ioncube; \
    curl -fSL 'https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz' -o ioncube.tar.gz; \
    tar -xf ioncube.tar.gz; \
    # List all available ionCube loaders and select the one for PHP 8.4
    ls -la /tmp/ioncube/; \
    PHP_EXT_DIR=$(php -i | grep extension_dir | head -n1 | awk '{print $3}'); \
    # Copy the correct file for PHP 8.4 (using a pattern match to find it)
    cp /tmp/ioncube/ioncube/ioncube_loader_lin_8.4.so "${PHP_EXT_DIR}/ioncube_loader.so"; \
    echo "zend_extension=ioncube_loader.so" > /usr/local/etc/php/conf.d/00-ioncube.ini; \
    rm -rf /tmp/ioncube


# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

RUN mkdir -p /.composer
RUN chmod -R 777 /.composer

# Test that ionCube is correctly installed
RUN php -m | grep -i 'ionCube' || { echo "ionCube not installed correctly"; exit 1; }

# WordPress recommended PHP settings
RUN { \
        echo 'upload_max_filesize = 512M'; \
        echo 'post_max_size = 512M'; \
        echo 'memory_limit = 1024M'; \
        echo 'max_execution_time = 300'; \
        echo 'max_input_vars = 3000'; \
        echo 'date.timezone = Asia/Tehran'; \
        echo 'opcache.enable=1'; \
        echo 'opcache.enable_cli=1'; \
        echo 'opcache.memory_consumption=128'; \
        echo 'opcache.interned_strings_buffer=8'; \
        echo 'opcache.max_accelerated_files=4000'; \
        echo 'opcache.revalidate_freq=2'; \
        echo 'opcache.fast_shutdown=1'; \
    } > /usr/local/etc/php/conf.d/wordpress-recommended.ini

# Verify all required extensions are properly installed
RUN php -m | grep -E 'gd|mysqli|pdo_mysql|exif|bcmath|intl|opcache|zip|pcntl|soap|sockets|mbstring' && \
    php -m | grep -i 'imagick' && \
    php -m | grep -i 'ionCube'

EXPOSE 9000
CMD ["php-fpm"]