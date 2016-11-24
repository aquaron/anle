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
    cp /etc/nginx/mime.types /data/etc/
    ln -s /data/letsencrypt /etc/letsencrypt
    rm -r /data/bin
    fi
}

write_443_conf() {
    local _filename=$1
    local _hostname=$2
    echo "
    upstream hosts {
        server 172.17.0.1:9991;
    }

    server {
        listen                       443 ssl;
        server_name                  ${_hostname};
        ssl_certificate              /data/letsencrypt/live/${_hostname}/fullchain.pem;
        ssl_certificate_key          /data/letsencrypt/live/${_hostname}/privkey.pem;
        location / {
            proxy_pass               http://hosts\$request_uri;
        }
        root                         /data/html;
    }
    " > ${_filename}
}

write_systemd_file() {
    local _name="$1"
    local _map="$2"
    local _port="$3"

    local _service_file="${_etc}/docker-${_name}.service"
    local _script="${_etc}/install-systemd.sh"

	apk --no-cache add bash

    cat ${_datadir}/templ/systemd.service \
        | write_template.sh name \""${_name}"\" map \""${_map}"\" port \""${_port}"\" \
        > ${_service_file}

    echo "Created ${_service_file}"

    cat ${_datadir}/templ/install.sh \
        | write_template.sh name \""${_name}"\" \
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
        listen      80;
        return      301         https://\$host\$request_uri;
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

    certbot certonly \
        --webroot \
        --webroot-path ${_datadir}/html \
        --config-dir ${_datadir}/letsencrypt \
        --no-self-upgrade \
        --agree-tos \
        --email ${_email} \
        --manual-public-ip-logging-ok \
        --non-interactive \
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
    init)
        run_init

        host_assert
        stopped_assert

        if [ -s "${_confdir}/443.conf" ]; then
            hint "Host already has existing config in ${_confdir}"
            exit 1
        fi

        hint "Initializing ${_host}"

        echo "Writing configuration..."
        write_test_conf "${_confdir}/test.conf" ${_host}

        write_systemd_file "anle" "${_vol}:/data" "${_ports}" 

        echo "Test configuration..."
        $_nginx -t

        assert_ok
        
        echo "Starting nginx..."
        $_nginx

        assert_ok

        echo "Getting LE certificate..."
        run_certbot

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

    stop|quit|reload|reopen) 
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

