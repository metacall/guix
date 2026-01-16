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

# Check if we are already in bash or zsh or ash
if [ -z "$BASH_VERSION" ] && [ -z "$ZSH_VERSION" ] && ! /bin/sh --help 2>&1 | grep -q "BusyBox"; then
	# Try to find bash, then fallback to zsh
	EXEC_SHELL=`command -v bash || command -v zsh`
	if [ -z "$EXEC_SHELL" ]; then
		echo "The script requires a modern shell to run"
		exit 1
	fi
	exec "$EXEC_SHELL" "$0" "$@"
fi

set -exuo pipefail

# Debug current version
guix describe
guix pull --list-generations

# Pull with fallback
guix pull --fallback

# Delete previous generations
guix pull --delete-generations

WORKDIR=$(pwd)
cd /var/guix/profiles/per-user/root
GUIX_CURRENT_GENERATION=$(readlink -f current-guix)

for link in current-guix-*-link; do
	target=$(readlink -f "${link}")
	if [ "${target}" != "${GUIX_CURRENT_GENERATION}" ] && [ -d "${target}" ]; then
		rm -rf "${target}"
	fi
done

rm -f current-guix current-guix-*-link
ln -sf "${GUIX_CURRENT_GENERATION}" current-guix-1-link
ln -sf current-guix-1-link current-guix
cd "${WORKDIR}"

# Debug current version
guix describe
guix pull --list-generations

# Install dependencies
guix package --fallback -i nss-certs

# Garbage Collect
guix gc
guix gc --optimize
