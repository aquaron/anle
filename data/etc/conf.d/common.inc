listen                      443 ssl http2;
location /50x.html {
    root                    /data/html;
}
add_header                  Strict-Transport-Security 'max-age=15768000; includeSubDomains; preload';
add_header                  X-Frame-Options DENY;
add_header                  X-Content-Type-Options nosniff;
