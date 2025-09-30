# syntax = docker/dockerfile:1.1-experimental

#
#	MetaCall Guix by Parra Studios
#	Docker image for using Guix in a CI/CD environment.
#
#	Copyright (C) 2016 - 2025 Vicente Eduardo Ferrer Garcia <vic798@gmail.com>
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

FROM debian:trixie-slim AS download

RUN apt-get update \
	&& apt-get install -y --no-install-recommends xz-utils wget ca-certificates

ARG METACALL_GUIX_VERSION
ARG METACALL_GUIX_ARCH

# Download and unpack Guix binary distribution
RUN wget -O - https://ftpmirror.gnu.org/gnu/guix/guix-binary-${METACALL_GUIX_VERSION}.${METACALL_GUIX_ARCH}.tar.xz | tar -xJv -C /

FROM debian:trixie-slim AS guix

# Image descriptor
LABEL copyright.name="Vicente Eduardo Ferrer Garcia" \
	copyright.address="vic798@gmail.com" \
	maintainer.name="Vicente Eduardo Ferrer Garcia" \
	maintainer.address="vic798@gmail.com" \
	vendor="MetaCall Inc." \
	version="0.1"

# Copy binary distribution
COPY --from=download /gnu/store /gnu/store
COPY --from=download /var/guix /var/guix

# Copy entry point
COPY scripts/entry-point.sh /entry-point.sh

# Install Guix
RUN set -exuo pipefail \
	&& groupadd --system guix-builder \
	&& chgrp guix-builder -R /gnu/store \
	&& chmod 0755 /gnu/store \
	&& for i in `seq -w 0 9`; do \
			useradd -g guix-builder -G guix-builder \
				-d /var/empty -s $(which nologin) \
				-c "Guix build user #${i}" --system guix-builder-${i}; \
		done \
	&& mkdir -p /root/.config/guix \
	&& ln -sf /var/guix/profiles/per-user/root/current-guix /root/.config/guix/ \
	&& mkdir -p /usr/local/bin \
	&& ln -s /var/guix/profiles/per-user/root/current-guix/bin/guix /usr/local/bin/ \
	&& mkdir -p /usr/local/share/info \
	&& for i in /var/guix/profiles/per-user/root/current-guix/share/info/*; do \
			ln -s ${i} /usr/local/share/info/; \
		done \
	&& chmod +x /entry-point.sh

# Copy substitute servers
COPY substitutes/ /var/guix/profiles/per-user/root/current-guix/share/guix/

# Apply substitutes
RUN . /var/guix/profiles/per-user/root/current-guix/etc/profile \
	&& for file in /var/guix/profiles/per-user/root/current-guix/share/guix/*.pub; do \
			guix archive --authorize < ${file}; \
		done

ENV GUIX_PROFILE="/root/.config/guix/current-guix" \
	GUIX_LOCPATH="/root/.guix-profile/lib/locale" \
	LANG="en_US.UTF-8" \
	SSL_CERT_DIR="/root/.guix-profile/etc/ssl/certs" \
	SSL_CERT_FILE="/root/.guix-profile/etc/ssl/certs/ca-certificates.crt" \
	GIT_SSL_FILE="/root/.guix-profile/etc/ssl/certs/ca-certificates.crt" \
	GIT_SSL_CAINFO="/root/.guix-profile/etc/ssl/certs/ca-certificates.crt" \
	CURL_CA_BUNDLE="/root/.guix-profile/etc/ssl/certs/ca-certificates.crt"

# Copy additional channels
COPY channels/ /root/.config/guix/

# Copy services
COPY scripts/etc/services /etc/services

# Run pull (https://github.com/docker/buildx/blob/master/README.md#--allowentitlement)
# Restart with latest version of the daemon and garbage collect
# Verify if the certificates exist and the version is correct (it is fixed to the channels.scm)
RUN --security=insecure sh -c '/entry-point.sh guix pull && guix package --fallback -i nss-certs' \
	&& sh -c '/entry-point.sh guix gc && guix gc --optimize' \
	&& [ -e /root/.guix-profile/etc/ssl/certs/ca-certificates.crt ] \
	&& [ "`cat /root/.config/guix/channels.scm | grep commit | cut -d'"' -f 2`" = "`guix --version | head -n 1 | awk '{print $NF}'`" ]

ENTRYPOINT ["/entry-point.sh"]
CMD ["sh"]
