#
#	MetaCall Guix by Parra Studios
#	Docker image for using GuixSD in a CI/CD environment.
#
#	Copyright (C) 2016 - 2019 Vicente Eduardo Ferrer Garcia <vic798@gmail.com>
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

FROM alpine:latest AS guix

# Image descriptor
LABEL copyright.name="Vicente Eduardo Ferrer Garcia" \
	copyright.address="vic798@gmail.com" \
	maintainer.name="Vicente Eduardo Ferrer Garcia" \
	maintainer.address="vic798@gmail.com" \
	vendor="MetaCall Inc." \
	version="0.1"

ENV GUIX_PROFILE="/root/.config/guix/current"

# Add Guix build users
RUN apk add --no-cache --update --virtual .build-deps shadow \
	&& mkdir -p /gnu/store \
	&& addgroup guixbuild \
	&& addgroup guix-builder \
	&& chgrp guix-builder -R /gnu/store \
	&& chmod 1775 /gnu/store \
	&& for i in `seq -w 1 10`; do \
			useradd -g guixbuild -G guixbuild -d /var/empty -s `which nologin` -c "Guix build user $i" --system guixbuilder$i; \
		done \
	&& apk del .build-deps

ARG METACALL_GUIX_VERSION
ARG METACALL_GUIX_ARCH

# Install Guix
RUN wget -O - https://ftp.gnu.org/gnu/guix/guix-binary-${METACALL_GUIX_VERSION}.${METACALL_GUIX_ARCH}-linux.tar.xz | tar -xJv -C / \
	&& mkdir -p ~root/.config/guix \
	&& ln -sf /var/guix/profiles/per-user/root/current-guix ~root/.config/guix/current \
	&& source $GUIX_PROFILE/etc/profile \
	&& mkdir -p /usr/local/bin \
	&& ln -s /var/guix/profiles/per-user/root/current-guix/bin/guix /usr/local/bin/ \
	&& mkdir -p /usr/local/share/info \
	&& for i in /var/guix/profiles/per-user/root/current-guix/share/info/*; do \
			ln -s $i /usr/local/share/info/; \
		done \
	&& guix archive --authorize < ~root/.config/guix/current/share/guix/ci.guix.gnu.org.pub

# Run pull
RUN --security=insecure source $GUIX_PROFILE/etc/profile \
	&& ~root/.config/guix/current/bin/guix-daemon --build-users-group=guixbuild & guix pull

# Set up entry point
COPY scripts/entry-point.sh /entry-point.sh

RUN chmod +x /entry-point.sh

ENTRYPOINT ["/entry-point.sh"]
CMD ["sh"]
