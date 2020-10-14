# image used for the healthcheck binary
FROM golang:1.15.2-alpine AS gobuilder
COPY healthcheck/ /go/src/healthcheck/
RUN CGO_ENABLED=0 go build -ldflags '-w -s -extldflags "-static"' -o /healthcheck /go/src/healthcheck/

#
# ---
#

FROM alpine:latest as source

ENV NGINX_VERSION="1.19.3"

# Download nginx source and verify signature
RUN set -xe; \
	\
	NGINX_URL="https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz"; \
	NGINX_ASC_URL="https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz.asc"; \
	NGINX_SHA256="91e5b74fa17879d2463294e93ad8f6ffc066696ae32ad0478ffe15ba0e9e8df0"; \
	GPG_KEYS="B0F4253373F8F6F510D42178520A9993A1C052F8"; \
	\
	apk update; \
	apk add --no-cache --virtual .build-deps \
		curl \
		gnupg \
	; \
	\
	curl -o nginx.tar.gz $NGINX_URL; \
	\
	if [ -n "$NGINX_SHA256" ]; then \
		echo "$NGINX_SHA256 *nginx.tar.gz" | sha256sum -c -; \
	fi; \
	\
	if [ -n "$NGINX_ASC_URL" ]; then \
		curl -o nginx.tar.gz.asc $NGINX_ASC_URL; \
		export GNUPGHOME="$(mktemp -d)"; \
		for key in $GPG_KEYS; do \
			gpg --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys "$key"; \
		done; \
		gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz; \
		rm -rf "$GNUPGHOME" nginx.tar.gz.asc; \
	fi; \
	\
	apk del .build-deps; \
	rm -rf /var/cache/apk/*

RUN set -xe; \
	\
	apk update; \
	apk add --no-cache --virtual .build-deps \
		curl \
		tar \
		git \
	; \
	\
	mkdir -p /usr/src; \
	mkdir -p /usr/src/nginx; \
	tar -zx -C /usr/src/nginx -f nginx.tar.gz --strip-components 1; \
	rm /nginx.tar.gz;  \
	\
	git clone https://github.com/openresty/headers-more-nginx-module.git /usr/src/headers-more-nginx-module; \
	git clone --recursive https://github.com/google/ngx_brotli.git /usr/src/ngx_brotli; \
	\
	apk del .build-deps; \
	rm -rf /var/cache/apk/*

#
# ---
#

FROM debian:buster-slim AS builder

# LABEL maintainer="Bratteng Solutions <docker@bratteng.solutions>"
# LABEL description="Nginx image built with brotli and custom header support"

# Define nginx configure params
ENV NGINX_CONFIG="\
--prefix=/etc/nginx \
--sbin-path=/usr/sbin/nginx \
--modules-path=/usr/lib/nginx/modules \
--conf-path=/etc/nginx/nginx.conf \
--error-log-path=/dev/stderr \
--http-log-path=/dev/stdout \
--pid-path=/tmp/nginx.pid \
--lock-path=/tmp/nginx.lock \
--http-client-body-temp-path=/tmp/client_temp \
--http-proxy-temp-path=/tmp/proxy_temp \
--http-fastcgi-temp-path=/tmp/fastcgi_temp \
--http-uwsgi-temp-path=/tmp/uwsgi_temp \
--http-scgi-temp-path=/tmp/scgi_temp \
--user=nonroot \
--group=nonroot \
--with-compat \
--with-file-aio \
--with-http_addition_module \
--with-http_auth_request_module \
--with-http_dav_module \
--with-http_flv_module \
--with-http_geoip_module=dynamic \
--with-http_gunzip_module \
--with-http_gzip_static_module \
--with-http_image_filter_module=dynamic \
--with-http_mp4_module \
--with-http_random_index_module \
--with-http_realip_module \
--with-http_secure_link_module \
--with-http_slice_module \
--with-http_ssl_module \
--with-http_stub_status_module \
--with-http_sub_module \
--with-http_v2_module \
--with-http_xslt_module=dynamic \
--with-mail \
--with-mail_ssl_module \
--with-pcre \
--with-pcre-jit \
--with-perl_modules_path=/usr/lib/perl5/vendor_perl \
--with-stream \
--with-stream_geoip_module=dynamic \
--with-stream_realip_module \
--with-stream_ssl_module \
--with-stream_ssl_preread_module \
--with-threads \
--add-dynamic-module=/usr/src/headers-more-nginx-module \
--add-dynamic-module=/usr/src/ngx_brotli \
"

COPY --from=source /usr/src /usr/src

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -xe \
	&& apt update \
	&& apt install --no-install-recommends --no-install-suggests -y \
		build-essential \
		libpcre3-dev \
		libssl-dev \
		zlib1g-dev \
		libxslt1-dev \
		libgd-dev \
		libgeoip-dev \
		libperl-dev \
	\
	&& cd /usr/src/nginx \
	&& ./configure $NGINX_CONFIG \
		--with-cc-opt='-g -O2  -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC' \
		--with-ld-opt='-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie' \
	&& make -j$(getconf _NPROCESSORS_ONLN) \
	&& make install \
	\
	&& rm -rf /etc/nginx/html/ \
	&& mkdir /etc/nginx/conf.d/ \
	&& mkdir -p /usr/share/nginx/html/ \
	\
	&& install -m644 html/index.html /usr/share/nginx/html/ \
	&& install -m644 html/50x.html /usr/share/nginx/html/ \
	\
	&& ln -s /usr/lib/nginx/modules /etc/nginx/modules \
	&& strip /usr/sbin/nginx* \
	&& strip /usr/lib/nginx/modules/*.so

# copy the required libraries out of the official nginx image (based on debian)
RUN rm -r /opt && mkdir /opt \
    && cp -a --parents /etc/nginx /opt \
    && cp -a --parents /usr/lib/nginx /opt \
    && cp -a --parents /usr/share/nginx /opt \
    && cp -a --parents /usr/sbin/nginx /opt \
    && cp -a --parents /lib/x86_64-linux-gnu/libpcre.so.* /opt \
    && cp -a --parents /lib/x86_64-linux-gnu/libz.so.* /opt \
    && cp -a --parents /lib/x86_64-linux-gnu/libc.so.* /opt \
    && cp -a --parents /lib/x86_64-linux-gnu/libdl.so.* /opt \
    && cp -a --parents /lib/x86_64-linux-gnu/libpthread.so.* /opt \
    && cp -a --parents /lib/x86_64-linux-gnu/libcrypt.so.* /opt \
    && cp -a --parents /usr/lib/x86_64-linux-gnu/libssl.so.* /opt \
    && cp -a --parents /usr/lib/x86_64-linux-gnu/libcrypto.so.* /opt \
    && cp -a --parents /lib/x86_64-linux-gnu/libdl-* /opt \
    && cp -a --parents /lib/x86_64-linux-gnu/libpthread-* /opt \
    && cp -a --parents /lib/x86_64-linux-gnu/libcrypt-* /opt \
    && cp -a --parents /lib/x86_64-linux-gnu/libc-* /opt \
	&& mkdir -p /opt/tmp/{clientbody,proxy,fastcgi,uwsgi,scgi} \
	&& rm /opt/etc/nginx/*.default

# start from the distroless scratch image (with glibc), based on debian:buster
FROM gcr.io/distroless/base-debian10:nonroot

# container label annotations
LABEL maintainer="hello@bratteng.solutions"
LABEL name="nginx"
LABEL url="https://github.com/bratteng/docker-nginx"
LABEL description="Hardened nginx image built with brotli and custom header support"

# copy in our healthcheck binary
COPY --from=gobuilder --chown=nonroot /healthcheck /healthcheck

# copy in our required libraries
COPY --from=builder --chown=nonroot /opt /

# Copy the config files into nginx folder
COPY --chown=nonroot nginx.conf mime.types /etc/nginx/
COPY --chown=nonroot default.conf /etc/nginx/conf.d/

# run as an unprivileged user
USER nonroot

# default nginx port
EXPOSE 8080

# healthcheck to report the container status
HEALTHCHECK --interval=5s --timeout=10s --retries=3 CMD [ "/healthcheck", "8080" ]

# CMD ["nginx", "-g", "daemon off;"]
CMD ["/usr/sbin/nginx", "-c", "/etc/nginx/nginx.conf"]
