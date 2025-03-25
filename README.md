# WordPress, now Dockerized! 😉

## Put your wordpress files is in wordpress directory

## This is the fully based structure

- /docker
- /ssl
- /wordpress
- .env
- .env.example
- .gitignore
- docker-compose.yml
- Dockerfile
- README.md

---
## Custom WP Config Sample 
```

/* 
 * Start Custom MGazori Config
*/

define('WP_REDIS_HOST', 'REDIS_SERVICE_NAME');
define('WP_REDIS_PORT', 6379);
define('WP_CACHE_KEY_SALT','KEY_SALT');
define('WP_MEMORY_LIMIT', '512M');
define('WP_MAX_MEMORY_LIMIT', '1024M');

// Detect user real ip behind reverse proxy
if (isset($_SERVER['HTTP_X_FORWARDED_FOR']) && !empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
    $ip_list = explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']);
    $_SERVER['REMOTE_ADDR'] = trim($ip_list[0]);
}

// If website using cloudflare
if (isset($_SERVER['HTTP_CF_CONNECTING_IP']) && !empty($_SERVER['HTTP_CF_CONNECTING_IP'])) {
    $_SERVER['REMOTE_ADDR'] = $_SERVER['HTTP_CF_CONNECTING_IP'];
}

// Set https if we are using ssl protocol
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}

/* 
 * End Custom MGazori Config
*/
```

## Disable wordpress cronjob
For better performance you can disable wordpress cronjob and run it yourself with crontab.

Add this to wp-config.php
```
define('DISABLE_WP_CRON', true);
```

And create cronjob by this. (15 minutes is fine, but you can modify it by your need!)
```
*/15 * * * * docker exec -it CONTAINER_NAME php /var/www/wp-cron.php >/dev/null 2>&1
```
