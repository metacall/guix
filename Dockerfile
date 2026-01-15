# syntax=docker/dockerfile:1.4-labs

#
#	MetaCall Guix by Parra Studios
#	Docker image for using Guix in a CI/CD environment.
#
#	Copyright (C) 2016 - 2026 Vicente Eduardo Ferrer Garcia <vic798@gmail.com>
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
	&& apt-get install -y --no-install-recommends jq xz-utils wget ca-certificates

ARG METACALL_GUIX_ARCH

# Download Guix binary distribution
RUN set -exuo pipefail \
	&& mkdir -p /guix \
	&& export LATEST_RELEASE=$(wget --spider --server-response https://github.com/metacall/guix/releases/latest 2>&1 | grep -i "Location:" | tail -n 1 | awk '{print $2}' | sed 's/tag/download/') \
	&& export METADATA=$(wget -qO- "${LATEST_RELEASE}/build.json" | jq -r ".\"${METACALL_GUIX_ARCH}\"") \
	&& export BINARY_DOWNLOAD_URL=$(echo "${METADATA}" | jq -r '.url') \
	&& export BINARY_EXPECTED_SHA=$(echo "${METADATA}" | jq -r '.sha256') \
	&& wget -O /guix/guix-binary.${METACALL_GUIX_ARCH}.tar.xz "${BINARY_DOWNLOAD_URL}" \
	&& if ! echo "${BINARY_EXPECTED_SHA}  /guix/guix-binary.${METACALL_GUIX_ARCH}.tar.xz" | sha256sum -c - > /dev/null 2>&1; then echo echo "ERROR: Binary checksum verification failed!" && exit 1; fi \
	&& export CACHE_DOWNLOAD_URL=$(echo "${METADATA}" | jq -r '.cache.url') \
	&& export CACHE_EXPECTED_SHA=$(echo "${METADATA}" | jq -r '.cache.sha256') \
	&& if [ "${CACHE_DOWNLOAD_URL}" != "null" ] && [ "${CACHE_EXPECTED_SHA}" != "null" ]; then \
		wget -O /guix/guix-cache.${METACALL_GUIX_ARCH}.tar.xz "${CACHE_DOWNLOAD_URL}" \
		&& if ! echo "${CACHE_EXPECTED_SHA}  /guix/guix-cache.${METACALL_GUIX_ARCH}.tar.xz" | sha256sum -c - > /dev/null 2>&1; then echo echo "ERROR: Cache checksum verification failed!" && exit 1; fi; \
	fi \
	&& wget -O /guix/channels.scm "${LATEST_RELEASE}/channels.scm" \
	&& wget -O /guix/install.sh "${LATEST_RELEASE}/install.sh"

FROM debian:trixie-slim AS guix

# Image descriptor
LABEL copyright.name="Vicente Eduardo Ferrer Garcia" \
	copyright.address="vic798@gmail.com" \
	maintainer.name="Vicente Eduardo Ferrer Garcia" \
	maintainer.address="vic798@gmail.com" \
	vendor="MetaCall Inc." \
	version="0.1"

# Install dependencies
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends netbase ca-certificates xz-utils wget gnupg

ARG METACALL_GUIX_ARCH

# Install Guix and copy latest channel
RUN --mount=type=bind,from=download,source=/guix,target=/guix \
	set -exu \
	&& export GUIX_BINARY_FILE_NAME=/guix/guix-binary.${METACALL_GUIX_ARCH}.tar.xz \
	&& yes '' | sh /guix/install.sh \
	&& chmod +x /etc/profile.d/zzz-guix.sh \
	&& cp /guix/channels.scm /root/.config/guix/channels.scm \
	&& /root/.config/guix/current/bin/guix-daemon --version \
	&& if [ -f "/guix/guix-cache.${METACALL_GUIX_ARCH}.tar.xz" ]; then \
			tar -xJf /guix/guix-cache.${METACALL_GUIX_ARCH}.tar.xz -C /root/; \
		else \
			echo "Cache file not found, skipping extraction"; \
		fi

# TODO: Move this to the end and try to remove ca-certificates too (once nss-certs have been installed)
RUN set -exuo pipefail \
	&& export APT_GNUPG= \
	&& grep -q Trisquel /etc/os-release || APT_GNUPG=gnupg \
	&& export DEBIAN_FRONTEND=noninteractive \
	&& apt-get remove --purge -y xz-utils wget $APT_GNUPG \
	&& apt-get autoremove --purge -y \
	&& rm -rfv /var/cache/apt/* /var/lib/apt/lists/*

# Copy entry point
COPY --chmod=0755 scripts/entry-point.sh /entry-point.sh

# Copy substitute servers
COPY substitutes/ /var/guix/profiles/per-user/root/current-guix/share/guix/

# Apply substitutes
RUN . /var/guix/profiles/per-user/root/current-guix/etc/profile \
	&& for file in /var/guix/profiles/per-user/root/current-guix/share/guix/*.pub; do \
		guix archive --authorize < ${file}; \
	done

# Environment variables
ENV GUIX_PROFILE="/root/.config/guix/current" \
	GUIX_LOCPATH="/root/.config/guix/current/share/locale" \
	LC_ALL="C.utf8" \
	SSL_CERT_DIR="/root/.guix-profile/etc/ssl/certs" \
	SSL_CERT_FILE="/root/.guix-profile/etc/ssl/certs/ca-certificates.crt" \
	GIT_SSL_FILE="/root/.guix-profile/etc/ssl/certs/ca-certificates.crt" \
	GIT_SSL_CAINFO="/root/.guix-profile/etc/ssl/certs/ca-certificates.crt" \
	CURL_CA_BUNDLE="/root/.guix-profile/etc/ssl/certs/ca-certificates.crt"

# Run pull (https://github.com/docker/buildx/blob/master/README.md#--allowentitlement)
# Uses tmpfs in order to avoid issues with large files in 32-bit file system (armhf-linux)
RUN --security=insecure --mount=type=tmpfs,target=/tmp/.cache \
	set -exuo pipefail \
	&& mkdir -p /tmp/.cache /root/.cache \
	&& export XDG_CACHE_HOME=/tmp/.cache \
	&& sh -c '/entry-point.sh guix describe' \
	&& sh -c '/entry-point.sh guix pull --fallback' \
	&& sh -c '/entry-point.sh guix package --fallback -i nss-certs' \
	&& sh -c '/entry-point.sh guix gc' \
	&& sh -c '/entry-point.sh guix gc --optimize' \
	&& cp -a /tmp/.cache/. /root/.cache/

ENTRYPOINT ["/entry-point.sh"]
CMD ["sh"]
