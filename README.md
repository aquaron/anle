# ANLE Reverse Proxy Image

Nginx build on Alpine with Certbot to use as reverse proxy.

# Setup

To initialize the configurations and get the certificate:

    docker run --rm -t -v /local/data:/data -p 80:80 -p 443:443 \
        aquaron/anle init example.tld me@example.tld

Upon success, edit `/local/data/etc/conf.d/443.conf` and change
configuration for `upstream` hosts to match your settings.

# Run

    docker run -v /local/data:/data -p 80:80 -p 443:443 \
        --name anle -d aquaron/anle

# Debug

Enter the container

    docker run --rm -it -v /local/data:/data -p 80:80 -p 443:443 \
        --entrypoint=/bin/sh aquaron/anle

Once inside use the `runme.sh` to control the server.
