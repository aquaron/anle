#!/bin/sh

getvol() { echo $(grep ' /data ' /proc/self/mountinfo | cut -f 4 -d" "); }
_vol=$(getvol)
_ports="-p 80:80 -p 443:443"

if [ ! "${_vol}" ]; then 
    echo "ERROR: you need run Docker with the -v parameter, try:"
    echo "    \$ docker run --rm -v /tmp:/data aquaron/anle help"
    exit 1
fi

_run="docker run -t --rm -v ${_vol}:/data ${_ports} aquaron/anle"

HELP=`cat <<EOT
Usage: docker run -t --rm -v <local-dir>:/data ${_ports} aquaron/anle <command> <host> [<email>]

 <local-dir> - directory on the host system to map to container

 <command>   init    - initialize directories if they're empty
             renew   - create env to renew all domains on this host
             daemon  - run in non-detached mode
             test    - test nginx configuration
             start   - start nginx server
             stop    - quick nginx shutdown
             quit    - graceful nginx shutdown
             reload  - reload nginx configuration file
             reopen  - reopens nginx log files
             certbot - create/renew certificate

 <host>     - FDN (eg example.com) to act on

`

if [[ $# -lt 1 ]] || [[ ! "${_vol}" ]]; then echo "$HELP"; exit 1; fi

hint() {
    local hint="| $* |"
    local stripped="${hint//${bold}}"
    stripped="${stripped//${normal}}"
    local edge=$(echo "$stripped" | sed -e 's/./-/g' -e 's/^./+/' -e 's/.$/+/')
    echo "$edge"
    echo "$hint"
    echo "$edge"
}

_cmd=$1
_host=$2
_email=$3
_datadir=/data
_conffile=${_datadir}/etc/nginx.conf
_confdir=${_datadir}/etc/conf.d
_start="docker run -v ${_vol}:/data ${_ports} -d aquaron/anle"
_nginx="nginx -c ${_conffile}"

run_init() {
    if [ ! -d "${_datadir}/etc" ]; then
    hint "Getting Started"
    echo "
     1) Initialize the server
        \$ ${_run} init example.fqn email@example.fqn

     2) Test configuration
        \$ ${_run} test

     3) Start Nginx
        \$ ${_start}

     4) Create Let's Encrypt Certificate
        \$ ${_run} certbot example.fqn
    "

    cp -R /data-default/. /data/
    cp /etc/nginx/mime.types /data/etc/conf.d
    mkdir /data/log
    ln -s /data/letsencrypt /etc/letsencrypt
    rm -r /data/bin /data/templ
    fi
}

write_443_conf() {
    local _filename=$1
    local _hostname=$2
    echo "
    root                            /data/html;
    upstream hosts {
        server                      172.17.0.1:9991;
    }

    server {
        listen                      443 ssl http2;
        server_name                 ${_hostname};
        ssl_certificate             /data/letsencrypt/live/${_hostname}/fullchain.pem;
        ssl_certificate_key         /data/letsencrypt/live/${_hostname}/privkey.pem;
        location / {
            proxy_pass              http://hosts\$request_uri;
        }
        add_header                  Strict-Transport-Security
                                    'max-age=15768000; includeSubDomains; preload';
    }" > ${_filename}
}

write_systemd_file() {
    local _name="$1"
    local _map="$2"
    local _port="$3"
    local _etc="${_datadir}/etc"

    local _service_file="${_etc}/docker-${_name}.service"
    local _script="${_etc}/install-systemd.sh"

    local _writer="/data-default/bin/write_template.sh"

    apk --no-cache add bash

    cat /data-default/templ/systemd.service \
        | $_writer name \""${_name}"\" map \""${_map}"\" port \""${_port}"\" \
        > ${_service_file}

    echo "Created ${_service_file}"

    cat /data-default/templ/install.sh \
        | $_writer name \""${_name}"\" \
        > ${_script}

    chmod 755 ${_script}

    echo "Created ${_script}"

    apk del bash
}

write_test_conf() {
    local _filename=$1
    echo "
    server {
        listen      80;
        root        /data/html;
    }" > ${_filename}
}

write_80_conf() {
    local _filename=$1
    echo "
    server {
        listen          80          default_server;
        listen          [::]:80     default_server ipv6only=on;
        server_name     _;
        return          301         https://\$host\$request_uri;
    }" > ${_filename}
}

host_assert() {
    if [ ! "${_host}" ]; then
        hint "No Host Found"
        echo "  \$ ${_run} init example.fqn email@example.fqn"
        exit 1
    fi
}

running_assert() {
    if [ ! -s "${_datadir}/log/nginx.pid" ]; then
        hint "Nginx STOPPED"
        echo "  \$ ${_start}"
        exit 1
    fi
}

stopped_assert() {
    if [ -s "${_datadir}/log/nginx.pid" ]; then
        hint "Nginx RUNNING"
        echo "   \$ ${_run} stop"
        echo "or \$ ${_run} kill"
        exit 1
    fi
}

run_certbot() {
    if [ ! "${_email}" ]; then
        hint "Email REQUIRED"
        exit 1
    fi

    apk --no-cache add certbot

    certbot certonly \
        --webroot \
        --webroot-path ${_datadir}/html \
        --config-dir ${_datadir}/letsencrypt \
        --no-self-upgrade \
        --agree-tos \
        --email ${_email} \
        --manual-public-ip-logging-ok \
        --non-interactive \
        --must-staple \
        --staple-ocsp \
        --keep \
        -d ${_host}

    if [ "$?" = 1 ]; then
        hint "Certificate FAILED"
        echo "Check your configuration at ${_vol}/etc"            
    else
        _443conf="${_confdir}/443.conf"

        if [ ! -s "${_443conf}" ]; then
            write_443_conf "${_443conf}" ${_host}
            rm ${_confdir}/test.conf
            write_80_conf "${_confdir}/80.conf"
        fi
    fi

    apk del certbot
}

run_certbot_renew() {
    apk --no-cache add certbot

    certbot renew \
        --must-staple \
        --staple-ocsp \
        --webroot-path ${_datadir}/html \
        --config-dir ${_datadir}/letsencrypt \
        --non-interactive 

    if [ "$?" = 1 ]; then
        hint "Certificate FAILED"
        echo "Check your configuration at ${_vol}/etc"
    else
        _443conf="${_confdir}/443.conf"

        if [ ! -s "${_443conf}" ]; then
            write_443_conf "${_443conf}" ${_host}
            rm ${_confdir}/test.conf
            write_80_conf "${_confdir}/80.conf"
        fi
    fi
    apk del certbot
}

conf_assert() {
    if [ ! -s "${_conffile}" ]; then
        hint "Server not setup"
    fi
}

assert_ok() {
    if [ "$?" = 1 ]; then
        hint "Abort"
        exit 1
    fi
}

case "${_cmd}" in
    init | renew)
        run_init

        if [ "${_cmd}" = 'init' ]; then host_assert; fi

        stopped_assert

        if [ -s "${_confdir}/443.conf" ]; then
            hint "Host already has existing config in ${_confdir}"
            exit 1
        fi

        hint "Initializing ${_host}"

        echo "Writing configuration..."
        write_test_conf "${_confdir}/test.conf" ${_host}

        echo "Writing startup script..."
        write_systemd_file "anle" "-v ${_vol}:/data" "${_ports}" 

        echo "Test configuration..."
        $_nginx -t

        assert_ok
        
        echo "Starting nginx..."
        $_nginx

        assert_ok

        echo "Getting LE certificate..."
        if [ "${_cmd}" = 'init' ]; then
            run_certbot
        else
            run_certbot_renew
        fi

        hint "${_start}"
        ;;

    certbot) 
        host_assert
        running_assert
        run_certbot
        ;;

    start) 
        stopped_assert
        conf_assert
        hint "starting nginx server"
        $_nginx
        ;;

    daemon)
        rm -f ${_datadir}/log/nginx.pid
        conf_assert
        $_nginx -g 'daemon off;'
        ;;

    stop|quit) 
        running_assert
        hint "${_cmd} nginx server"
        rm -f ${_datadir}/log/nginx.pid
        $_nginx -s ${_cmd}
        ;;

    reload|reopen) 
        running_assert
        hint "${_cmd} nginx server"
        $_nginx -s ${_cmd}
        ;;

    kill)
        killall nginx
        rm -f ${_datadir}/log/nginx.pid
        ;;

    test)
        hint "Test ${_vol}/etc/nginx.conf"
        $_nginx -t
        ;;
     
    *) echo "ERROR: Command '${_cmd}' not recognized"
        ;;
esac

