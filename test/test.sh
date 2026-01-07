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

# Get directories of the current script
SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

# Verify if the certificates exist
if [[ ! -e /root/.guix-profile/etc/ssl/certs/ca-certificates.crt ]]; then
	echo "ERROR: Certificates do not exist"
	exit 1
fi

# Verify if version is correct (it is fixed to the channels.scm)
CHANNELS_CHECK="${SCRIPT_DIR}/channels-check.scm"
CHANNELS_COMMIT=$(guix repl "${CHANNELS_CHECK}")
GUIX_VERSION=$(guix --version | head -n 1 | awk '{print $NF}')

if [[ "${CHANNELS_COMMIT}" != "${GUIX_VERSION}" ]]; then
	echo "ERROR: Guix version does not match with channels.scm"
	exit 1
fi

# Install a package for testing
if ! guix install hello; then
	echo "ERROR: Guix install command failed"
	exit 1
fi

# List installed packages
if ! guix package --list-installed; then
	echo "ERROR: Guix package command failed"
	exit 1
fi
