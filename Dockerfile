# syntax = docker/dockerfile:1.1-experimental

#
#	MetaCall Guix by Parra Studios
#	Docker image for using Guix in a CI/CD environment.
#
#	Copyright (C) 2016 - 2020 Vicente Eduardo Ferrer Garcia <vic798@gmail.com>
#
#	Licensed under the Apache License, Version 2.0 (the "License");
#	you may not use this file except in compliance with the License.
#	You may obtain a copy of the License at
#
#		http://www.apache.org/licenses/LICENSE-2.0
#
#	Unless required by applicable law or agreed to in writing, software
#	distributed under the License is distributed on an "AS IS" BASIS,
#	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#	See the License for the specific language governing permissions and
#	limitations under the License.
#

FROM alpine:3.9 AS guix

# Image descriptor
LABEL copyright.name="Vicente Eduardo Ferrer Garcia" \
	copyright.address="vic798@gmail.com" \
	maintainer.name="Vicente Eduardo Ferrer Garcia" \
	maintainer.address="vic798@gmail.com" \
	vendor="MetaCall Inc." \
	version="0.1"

ARG METACALL_GUIX_VERSION
ARG METACALL_GUIX_ARCH

ENV GUIX_PROFILE="/root/.config/guix/current" \
	GUIX_LOCPATH="/root/.guix-profile/lib/locale/" \
	SSL_CERT_DIR="/root/.guix-profile/etc/ssl/certs" \
	SSL_CERT_FILE="/root/.guix-profile/etc/ssl/certs/ca-certificates.crt" \
	GIT_SSL_FILE="$SSL_CERT_FILE" \
	GIT_SSL_CAINFO="$SSL_CERT_FILE" \
	CURL_CA_BUNDLE="$SSL_CERT_FILE"

# Copy entry point
COPY scripts/entry-point.sh /entry-point.sh

# Install Guix
RUN mkdir -p /gnu/store \
	&& addgroup guixbuild \
	&& addgroup guix-builder \
	&& chgrp guix-builder -R /gnu/store \
	&& chmod 1777 /gnu/store \
	&& for i in `seq -w 1 10`; do \
			adduser -G guixbuild -h /var/empty -s `which nologin` -S guixbuilder$i; \
		done \
	&& wget -O - https://ftp.gnu.org/gnu/guix/guix-binary-${METACALL_GUIX_VERSION}.${METACALL_GUIX_ARCH}-linux.tar.xz | tar -xJv -C / \
	&& mkdir -p /root/.config/guix \
	&& ln -sf /var/guix/profiles/per-user/root/current-guix /root/.config/guix/current \
	&& mkdir -p /usr/local/bin \
	&& ln -s /var/guix/profiles/per-user/root/current-guix/bin/guix /usr/local/bin/ \
	&& mkdir -p /usr/local/share/info \
	&& for i in /var/guix/profiles/per-user/root/current-guix/share/info/*; do \
			ln -s $i /usr/local/share/info/; \
		done \
	&& chmod +x /entry-point.sh \
	&& source $GUIX_PROFILE/etc/profile \
	&& guix archive --authorize < /root/.config/guix/current/share/guix/ci.guix.gnu.org.pub

# Copy additional channels
COPY channels/ /root/.config/guix/

# Run pull (https://github.com/docker/buildx/blob/master/README.md#--allowentitlement)
# Restart with latest version of the daemon and garbage collect
RUN --security=insecure sh -c '/entry-point.sh guix pull' \
	&& sh -c '/entry-point.sh guix package --fallback -i nss-certs && guix gc && guix gc --optimize'

ENTRYPOINT ["/entry-point.sh"]
CMD ["sh"]
