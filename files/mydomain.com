server {
    server_name www.mydomain.com;
    rewrite ^ $scheme://mydomain.com$request_uri?;
}

server {
    server_name mydomain.com;
    root /home/sudoer/mydomain.com/public;
    index index.php index.html;
    charset UTF-8;
    default_type text/html;

    access_log /var/log/nginx/mydomain.com-access.log;
    error_log /var/log/nginx/mydomain.com-error.log;

    location / {
        gzip_static on;
        try_files $uri $uri/ /index.php?q=$uri&$args;
    }

    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    location ~ /\.git/* {
        deny all;
    }

    location /nginx_status {
        stub_status on;
        access_log off;
    }

    location ~ \.php$ {
        try_files $uri =404;
        include fastcgi_cache;		
        include fastcgi_params;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_intercept_errors on;
        fastcgi_ignore_client_abort on;
        fastcgi_pass php-fpm;
    }

    location ~* \.(xml|ogg|ogv|svg|svgz|eot|otf|woff|mp4|ttf|css|rss|atom|js|jpg|jpeg|gif|png|ico|zip|tgz|gz|rar|bz2|doc|xls|exe|ppt|tar|mid|midi|wav|bmp|rtf)\$ {
        try_files $uri =404;
        expires max;
        add_header Pragma "public";
        add_header Cache-Control "public, must-revalidate, proxy-revalidate";
        access_log off;
    }

    location ~ ^/(status|ping)$ {
        include /etc/nginx/fastcgi_params;
        fastcgi_pass unix:/var/run/php5-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $fastcgi_script_name;
        allow 127.0.0.1;
        deny all;
    }
}