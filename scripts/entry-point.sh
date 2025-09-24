#!/bin/sh

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

set -exuo pipefail

# Load profile enviroment variables
source $GUIX_PROFILE/etc/profile

# Substitute servers
SUBSTITUTE_URLS="https://cuirass.genenetwork.org https://ci.guix.gnu.org https://bordeaux.guix.gnu.org"

# Run guix daemon
/root/.config/guix/current/bin/guix-daemon --build-users-group=guixbuild --substitute-urls="${SUBSTITUTE_URLS}" &
GUIX_DAEMON=$!

# Execute commands
exec "$@"
