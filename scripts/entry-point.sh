#!/bin/sh

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

# Check if we are already in bash or zsh
if [ -z "$BASH_VERSION" ] && [ -z "$ZSH_VERSION" ]; then
	# Try to find bash, then fallback to zsh
	EXEC_SHELL=$(command -v bash || command -v zsh)
	exec "$EXEC_SHELL" "$0" "$@"
fi

set -exuo pipefail

# Load profile enviroment variables
export INFOPATH="/usr/share/info"
export MANPATH="/usr/share/man"
. /etc/profile.d/zzz-guix.sh
export GUIX_PROFILE="/root/.config/guix/current"

# Substitute servers global variable
SUBSTITUTE_URLS=""

# Function to add substitute URLs
function substitute_urls() {
	local input

	# Read all input, replace newlines with spaces and trim leading/trailing whitespace
	input=$(cat | tr '\n' ' ' | xargs)

	# Append to global variable
	SUBSTITUTE_URLS="${SUBSTITUTE_URLS} ${input}"
}

# Official build farms
substitute_urls <<EOF
https://ci.guix.gnu.org
https://bordeaux.guix.gnu.org
EOF

# Unofficial mirrors (sharing same public keys of official farms)
# https://libreplanet.org/wiki/Group:Guix/Mirrors
substitute_urls <<EOF
https://bordeaux-us-east-mirror.cbaines.net
https://hydra-guix-129.guix.gnu.org
https://bordeaux-guix.jing.rocks
https://mirror.yandex.ru/mirrors/guix/
https://berlin-guix.jing.rocks
https://bordeaux-singapore-mirror.cbaines.net
EOF

# Nonguix substitutes
substitute_urls <<EOF
https://substitutes.nonguix.org
EOF

# Unofficial mirrors removed because of slow connection problems:
# https://mirrors.sjtug.sjtu.edu.cn/guix # Unnoficial mirror (People's Republic of China)
# https://guix.tobias.gr # Tobias (Germany)

# Genenetwork mirror (USA)
substitute_urls <<EOF
https://cuirass.genenetwork.org
EOF

# Guix Moe CI
substitute_urls <<EOF
https://cache-cdn.guix.moe
https://cache-de.guix.moe
https://cache-fi.guix.moe
https://cache-us-lax.guix.moe
https://cache-sg.guix.moe
https://cache-it.guix.moe
EOF

# Define extra arguments depending on the architecture
ARCH=$(uname -m)
GUIX_DAEMON_EXTRA_ARGS=""
case ${ARCH} in
	armv7l|armv7*|arm|armhf)
	# guix error: cloning builder process: Invalid argument (https://lists.gnu.org/archive/html/help-guix/2017-12/msg00023.html)
	GUIX_DAEMON_EXTRA_ARGS="--disable-chroot";;

	aarch64|arm64)
	# ARM64 also needs --disable-chroot under QEMU emulation
	GUIX_DAEMON_EXTRA_ARGS="--disable-chroot";;

	ppc64le|powerpc64le)
	# PowerPC64 LE also needs --disable-chroot under QEMU emulation
	GUIX_DAEMON_EXTRA_ARGS="--disable-chroot";;

	riscv64)
	# RISC-V also needs --disable-chroot under QEMU emulation
	GUIX_DAEMON_EXTRA_ARGS="--disable-chroot";;
esac

# Run guix daemon
${GUIX_PROFILE}/bin/guix-daemon ${GUIX_DAEMON_EXTRA_ARGS} --build-users-group=guixbuild --substitute-urls="${SUBSTITUTE_URLS}" --max-jobs=$(nproc) &
GUIX_DAEMON=$!

# Execute commands (avoid exit on error so we can print the logs in case of fail)
set +e
"$@"
GUIX_RESULT=$?

# Print logs in case of error
if [ ${GUIX_RESULT} -ne 0 ]; then
	cp -v /var/log/guix/drvs/*/*.drv.gz .
	gzip -d *.gz
	tail -v -n1000 *.drv
fi

# Kill guix daemon
kill -9 $GUIX_DAEMON

exit ${GUIX_RESULT}
