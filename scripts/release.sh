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

# Get the parameters
ARCH=$1
DEST=$2
VERSION=$3

# Build the tarball
guix pack -f tarball -C xz --system=${ARCH} --localstatedir --profile-name=current-guix guix

# Copy the tarball
TARBALL_PATH=$(find /gnu/store/ -maxdepth 1 -name "*-guix-tarball-pack.tar.xz")
mv "${TARBALL_PATH}" "${DEST}/guix-binary-${VERSION}.${ARCH}.tar.xz"

# Generate the cache
cd $HOME
guix shell xz -- tar -cJf "${DEST}/guix-cache-${VERSION}.${ARCH}.tar.xz" --hard-dereference .cache
