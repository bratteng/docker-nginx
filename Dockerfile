FROM debian:bullseye-20230208-slim@sha256:8eaee63a5ea83744e62d5bf88e7d472d7f19b5feda3bfc6a2304cc074f269269 as source

ENV NGINX_VERSION=1.23.3

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# Download nginx and openssl source
RUN \
	apt-get update \
	&& apt-get install --no-install-recommends --no-install-suggests -y \
		ca-certificates \
		curl \
		tar \
		git \
	\
	&& curl -o openssl.tar.gz https://www.openssl.org/source/openssl-3.0.8.tar.gz \
	&& curl -o nginx.tar.gz https://nginx.org/download/nginx-1.23.3.tar.gz \
	\
	&& echo "6c13d2bf38fdf31eac3ce2a347073673f5d63263398f1f69d0df4a41253e4b3e *openssl.tar.gz" | sha256sum -c - \
	&& echo "75cb5787dbb9fae18b14810f91cc4343f64ce4c24e27302136fb52498042ba54 *nginx.tar.gz" | sha256sum -c - \
	&& mkdir -p /usr/src/{nginx,openssl} \
	&& tar -zx -C /usr/src/nginx -f nginx.tar.gz --strip-components 1 \
	&& tar -zx -C /usr/src/openssl -f openssl.tar.gz --strip-components 1 \
	&& rm /{nginx,openssl}.tar.gz \
	\
	&& git clone https://github.com/openresty/headers-more-nginx-module.git /usr/src/headers-more-nginx-module \
	&& git clone --recursive https://github.com/google/ngx_brotli.git /usr/src/ngx_brotli

# Builder stage
FROM debian:bullseye-20230208-slim@sha256:8eaee63a5ea83744e62d5bf88e7d472d7f19b5feda3bfc6a2304cc074f269269 AS builder

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
--with-openssl=/usr/src/openssl \
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
WORKDIR /usr/src/nginx

RUN \
	apt-get update \
	&& apt-get install --no-install-recommends --no-install-suggests -y \
		build-essential \
		libpcre3-dev \
		libssl-dev \
		zlib1g-dev \
		libxslt1-dev \
		libgd-dev \
		libgeoip-dev \
		libperl-dev \
	\
	&& ./configure $NGINX_CONFIG \
		--with-cc-opt='-g -O2  -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC' \
		--with-ld-opt='-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie' \
	&& make -j "$(getconf _NPROCESSORS_ONLN)" \
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
    && cp -a --parents /lib/x86_64-linux-gnu/libc-* /opt \
	&& mkdir -p /opt/tmp/{clientbody,proxy,fastcgi,uwsgi,scgi} \
	&& rm /opt/etc/nginx/*.default

# start from the distroless scratch image (with glibc), based on debian:bullseye
FROM gcr.io/distroless/base-debian11:nonroot@sha256:42311d85daf49d0822fad6961031f0de2015fc94ff6e49a7f30cab9b40553bfb

# copy in our required libraries
COPY --from=builder --chown=nonroot /opt /

# Copy the config files into nginx folder
COPY --chown=nonroot ./conf/nginx.conf /etc/nginx/
COPY --chown=nonroot ./conf/mime.types /etc/nginx/
COPY --chown=nonroot ./conf/default.conf /etc/nginx/conf.d/

# run as an unprivileged user
USER nonroot

# default nginx port
EXPOSE 8080

# CMD ["nginx", "-g", "daemon off;"]
CMD ["/usr/sbin/nginx", "-c", "/etc/nginx/nginx.conf"]
