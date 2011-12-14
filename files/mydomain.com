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
        if ($request_uri  ~ ^.*[^/]$) {
          return 405;
        }
        if ($request_uri  ~ ^.*//.*$) {
          return 405;
        }
        if ($request_method ~ POST) {
          return 405;
        }
        if ($query_string  ~ ^.*=.*$) {
          return 405;
        }
        if ($http_cookie ~ ^.*(comment_author_|wordpress_logged_in|wp-postpass_).*$) {
          return 405;
        }
        if ($http_x_wap_profile ~ ^[a-z0-9\"]+$) {
          return 405;
        }
        if ($http_profile ~ ^[a-z0-9\"]+$) {
          return 405;
        }
        if ($http_user_agent ~ ^.*(2.0\ MMP|240x320|400X240|AvantGo|BlackBerry|Blazer|Cellphone|Danger|DoCoMo|Elaine/3.0|EudoraWeb|Googlebot-Mobile|hiptop|IEMobile|KYOCERA/WX310K|LG/U990|MIDP-2.|MMEF20|MOT-V|NetFront|Newt|Nintendo\ Wii|Nitro|Nokia|Opera\ Mini|Palm|PlayStation\ Portable|portalmmm|Proxinet|ProxiNet|SHARP-TQ-GX10|SHG-i900|Small|SonyEricsson|Symbian\ OS|SymbianOS|TS21i-10|UP.Browser|UP.Link|webOS|Windows\ CE|WinWAP|YahooSeeker/M1A1-R2D2|iPhone|iPod|Android|BlackBerry9530|LG-TU915\ Obigo|LGE\ VX|webOS|Nokia5800).*$) {
          return 405;
        }
        if ($http_user_agent ~ ^(w3c\ |w3c-|acs-|alav|alca|amoi|audi|avan|benq|bird|blac|blaz|brew|cell|cldc|cmd-|dang|doco|eric|hipt|htc_|inno|ipaq|ipod|jigs|kddi|keji|leno|lg-c|lg-d|lg-g|lge-|lg/u|maui|maxo|midp|mits|mmef|mobi|mot-|moto|mwbp|nec-|newt|noki|palm|pana|pant|phil|play|port|prox|qwap|sage|sams|sany|sch-|sec-|send|seri|sgh-|shar|sie-|siem|smal|smar|sony|sph-|symb|t-mo|teli|tim-|tosh|tsm-|upg1|upsi|vk-v|voda|wap-|wapa|wapi|wapp|wapr|webc|winw|winw|xda\ |xda-).*$) {
          return 405;
        }
        error_page 405 = @nocache;

        expires epoch;
        add_header Vary "Cookie";
        add_header Cache-Control "store, must-revalidate, post-check=0, pre-check=0";

        try_files /wp-content/cache/supercache/${host}${uri}index.html @nocache;
    }
	
    location @nocache {
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