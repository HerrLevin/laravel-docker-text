# Stage 1: Build dependencies
FROM composer:latest AS builder
WORKDIR /app
COPY . .
RUN composer install --no-dev --optimize-autoloader

# Stage 2: Build PHP application
FROM php:8.4-fpm-alpine

# Install required system dependencies
RUN apk add --no-cache \
    nginx \
    supervisor \
    icu-dev \
    libzip-dev \
    zlib-dev \
    oniguruma-dev \
    shadow \
    bash \
    sqlite-dev \
    nodejs \
    npm

# Install required PHP extensions
RUN docker-php-ext-install \
        bcmath \
        pdo_mysql \
        pdo_sqlite \
        zip \
        intl \
        opcache

# Set working directory
WORKDIR /var/www/html

# Copy application files
COPY . .

# Copy dependencies from builder stage
COPY --from=builder /app/vendor ./vendor

# Build frontend assets
RUN npm install
RUN npm run build

# Set permissions
RUN set -e \
  && PHP_LOG_DIR="/var/log/php" \
  && NGINX_LOG_DIR="/var/log/nginx" \
  && NGINX_LIB_DIR="/var/lib/nginx" \
  && install -d -o www-data -g www-data -m 775 /var/www/html/storage /var/www/html/bootstrap/cache $NGINX_LIB_DIR/logs $NGINX_LIB_DIR/tmp /run/nginx \
  && install -d -o www-data -g www-data -m 755 /var/run/php $PHP_LOG_DIR $NGINX_LOG_DIR $NGINX_LIB_DIR /run/nginx \
  && touch $PHP_LOG_DIR/php-fpm.log $PHP_LOG_DIR/php-fpm.err $NGINX_LOG_DIR/error.log $NGINX_LOG_DIR/access.log \
  && chown www-data:www-data $PHP_LOG_DIR/php-fpm.log $PHP_LOG_DIR/php-fpm.err $NGINX_LOG_DIR/error.log $NGINX_LOG_DIR/access.log \
  && chmod 664 $PHP_LOG_DIR/php-fpm.log $PHP_LOG_DIR/php-fpm.err $NGINX_LOG_DIR/error.log $NGINX_LOG_DIR/access.log

# Exclude SQLite database file
RUN rm -f /var/www/html/database/database.sqlite

# Environment variables
ENV SERVER_NAME={HOSTNAME}

# Copy configuration files
COPY docker/php/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker/supervisor/supervisord.conf /etc/supervisord.conf
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose ports
EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost/ || exit 1

CMD ["/entrypoint.sh"]
