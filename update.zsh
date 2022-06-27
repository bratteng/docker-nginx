#!/usr/bin/env zsh

function command_exists() {
	command -v "$@" >/dev/null 2>&1
}

if ! command_exists envsubst; then
	echo "The command envsubst is required"
	exit 1
fi

export NGINX_VERSION="1.23.0"
export OPENSSL_VERSION="3.0.4"

export NGINX_URL="https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz"
export OPENSSL_URL="https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"

export NGINX_SHA256=$(sha256sum <(curl -s $NGINX_URL) | head -c 64)
export OPENSSL_SHA256=$(sha256sum <(curl -s $OPENSSL_URL) | head -c 64)

envsubst \${NGINX_SHA256},\${OPENSSL_SHA256},\${NGINX_URL},\${OPENSSL_URL},\${NGINX_VERSION} < Dockerfile.template > Dockerfile
