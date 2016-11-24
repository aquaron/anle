# ANLE Reverse Proxy Image

Nginx build on Alpine with Certbot to use as a reverse proxy.

## `runme.sh`

Launches `nginx` by default. If configuration is not found, initializes with default configuration.
`runme.sh` accepts these commands:

| Command   | Description                                      |
| --------- | ------------------------------------------------ |
| init      | initialize directories if they're empty          |
| daemon    | run in non-detached mode                         |
| certbot   | create/renew certificate                         |
| start     | start `nginx` server                             |
| stop      | stop `nginx` server                              |
| quit      | gracefully stop `nginx` server                   |
| reload    | reloads `nginx` configurations                   |
| reopen    | reopens `nginx` log files                        |
| kill      | `killall nginx`                                  |
| test      | check `nginx`'s configuration                    |

### `init`

Initializes the server with all the necessary configurations and certificate.
Example:

    runme.sh init virtual-host.example.com certs@example.com

`virtual-host.example.com` is the target to get Let's Encrypt certificate for.
`certs@example.com` is your email address required by LE.

### `daemon`

Put `nginx` in the foreground so that it wouldn't stop when the container detatches.

### `certbot`

Get or renew a certificate for the specified host:

    runme.sh certbot virtual-host.example.com certs@example.com

### `start`, `stop`, `quit`, `kill`

These are convenience commands when you're inside the running container use for
starting and stopping.

### `reload`, `reopen`, `test`

When you change configurations, reload and test it.

-------------------------------------------------------------------------------

# `<local-dir>/data`

`anle` requires this stucture if you're not using the `init` command to create

    /<local-dir>/data (anywhere you want)
    |
    +-- /etc                (configurations)
    |   |
    |   +-- nginx.conf      (default)
    |   +-- mime.types      (default)
    |   +-- /conf.d
    |       |
    |       +-- proxy.conf  (default)
    |       +-- 80.conf     (auto generated)
    |       +-- 443.conf    (auto generated, edit REQUIRED)
    |    
    +-- /html               (root)
    |   |
    |   +-- index.html      (default)
    |   +-- 50x.html        (soft-link to index.html)
    |
    +-- /letsencrypt        (certificates)
    |   |
    |   +-- dhparam.pem     (default)
    |   +-- /accounts       (le auto generated)
    |   +-- /keys           (le auto generated)
    |   +-- /csr            (le auto generated)
    |   +-- /renewal        (le auto generated)
    |   +-- /live           (le auto generated - REQUIRED)
    |   +-- /archive        (le auto generated)
    |
    +-- /log                (logs and pid files)

All the default files are required, donnot delete. 
`auto generated` files are not required, they will be generated.

-------------------------------------------------------------------------------

# Usage Instruction

## Initialize & Let's Encrypt Certificate

Initialize the configurations and get the certificate:

    docker run --rm -t -v <local-dir>:/data \
        -p 80:80 -p 443:443 \
        aquaron/anle \
            init <email> <hostname>

### Edit `443.conf`

Edit `<local-dir>/etc/conf.d/443.conf` and change
configuration for `upstream` hosts to match your virtual hosts settings.

### `install.sh`

Installs `docker-anle.service` to your `systemd` configuration.
Find this script in your `<local-dir>/etc` directory.

## Run Daemon

### Using `systemctl`

If you've used the `install.sh` script, you can issue these commands
to start/stop your service:

    systemctl start docker-anle.service
    systemctl stop docker-anle.service

### Manual

You can manually start the container by running the commands found in `docker-anle.service`:

    docker run -v <local-dir>:/data \
        -p 80:80 -p 443:443 \
        --name anle -h anle \
        -d aquaron/anle


## Debugging

Enter the container and poke around:

    docker run --rm -it -v <local-dir>:/data \
        -p 80:80 -p 443:443 \
        --entrypoint=/bin/sh \
        aquaron/anle

Once inside use the `runme.sh` to control the server.
