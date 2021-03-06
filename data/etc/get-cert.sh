#!/bin/bash

HELP=`cat <<EOT
Usage: sudo $0 <hostname> [<path>] [<email>]
EOT
`

if [[ ! "$(whoami)" = "root" ]] || [[ $# -lt 1 ]]; then echo "$HELP"; exit 1; fi

bold=$(tput bold)
normal=$(tput sgr0)
function bd() { echo "${bold}$1${normal}"; }

function assert() {
    if [ "$?" -eq 1 ]; then exit 1; fi
}

function hint() {
    local hint="| $* |"
    local stripped="${hint//${bold}}"
    stripped="${stripped//${normal}}"
    local edge=$(echo "$stripped" | sed -e 's/./-/g' -e 's/^./+/' -e 's/.$/+/')
    echo "$edge"
    echo "$hint"
    echo "$edge"
}

function stop_server() {
    local _hostname="$1"
    local _service="docker-anle.service"
    local _is_running=$(curl -s "http://${_hostname}" | grep '<html')

    if [ "${_is_running}" ]; then

        if [ "$(systemctl is-enabled ${_service} 2>&1)" = "enabled" ]; then
            echo "Found: ${_service} OK"
        else
            hint "ANLE systemd service not found!"
            echo "ABORT: Please install ANLE with systemd service to continue"
            exit 1
        fi

        systemctl stop docker-anle.service

        echo "Service $(bd docker-anle.service) stopped"
    fi
}

function update_config() {
    local _path1="$1"
    local _path2="$2"

    if [ -d "${_path1}/le-old" ]; then
        rm -r ${_path1}/le-old
    fi

    mv ${_path1}/letsencrypt ${_path1}/le-old

    echo "Certificate added... OK"
    mv ${_path2}/letsencrypt ${_path1}/.

    if [ ! "${_email}" ]; then
        echo "Configuration added... OK"
        tail -12 ${_path2}/etc/conf.d/443.conf | tee --append ${_path1}/etc/conf.d/443.conf
    fi
}

function check_server() {
    local _hostname="$1"
    local _oldpath="$2"

    echo "Service $(bd docker-anle.service) starting..."

    systemctl start docker-anle.service

    sleep 2

    local _is_running=$(curl -s "https://${_hostname}" | grep '<html')

    if [ "${_is_running}" ]; then
        if [ -d "${_oldpath}" ]; then
            rm -r ${_oldpath}
        fi
        hint "https://${_hostname} is up and running"
    else
        hint "Cannot reach https://${_hostname}"
        exit 1
    fi
}

if [ ! -f "docker-anle.service" ]; then
    echo "ABORT: Cannot find docker-anle.service in current dir"
    exit 1
fi

_path="$2"

if [ ! -d "${_path}" ]; then
    read -p "ANLE data dir: " _path
fi

_domain="$1"

_root=$(cd "$_path/.."; pwd);
_npath="${_root}/anle-${_domain}"

if [ -d "${_npath}" ]; then
    hint "Dir ${_npath} exists"
    read -p "$(bd ${_npath}) exists: [R]emove or [U]pdate or [Q]uit? " yn
    case $yn in
        [Rr]*)
            rm -r ${_npath}
            echo "Removing ${_npath}... OK"
            ;;

        [Uu]*)
            update_config "${_path}" "${_npath}"
            exit 0
            ;;

        *)
            echo "ABORT: You need to figure out why it's there and remove it"
            exit 1
            ;;
    esac
fi

if  [[ -d "${_path}/letsencrypt" ]] && [[ -d "${_path}/etc" ]] && [[ -d "${_path}/html" ]]
then
    cp -R ${_path} ${_npath}
    rm -r ${_npath}/etc/conf.d/443.conf ${_npath}/etc/conf.d/80.conf ${_npath}/log/*
    echo "Creating $(bd ${_npath})... OK"
else
    hint "ABORT: Cannot find configuration files"
    exit 1;
fi

_ledir="${_path}/letsencrypt"

echo "Found: ${_ledir} OK"

if [ -d "${_ledir}/live/${_domain}" ]; then
    echo "Found: $(bd ${_domain}) ... renewing"
else
    _email="$3"
    if [ ! "${_email}" ]; then
        read -p "Admin email: " _email
    fi
fi

stop_server "${_domain}"

echo "Running certbot client..."

_args=$(grep 'ExecStart=' docker-anle.service | sed -e 's/^[^:]*://')

if [ ! "${_email}" ]; then
    _res=$(docker run --rm -t -v ${_npath}:${_args} renew)
else
    _res=$(docker run --rm -t -v ${_npath}:${_args} init ${_domain} ${_email})
fi

case ${_res} in
    *'no action taken'*|\
    *'No renewals were attempted'*)
        echo "Ignore: no new certificates!"
        rm -r ${_npath}
        ;;

    *'following errors'*)
        hint "ABORT: Errors!"
        rm -r ${_npath}
        echo -e $_res
        exit 1
        ;;

    *'Congratulations'*)
        update_config "${_path}" "${_npath}"
        ;;

    *)
        echo -e $_res
        exit 1
        ;;
esac

check_server "${_domain}" "${_npath}"

exit 0
