#!/bin/bash

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
source ${GUIX_PROFILE}/etc/profile

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
substitute_urls <<EOF
https://bordeaux-us-east-mirror.cbaines.net
https://hydra-guix-129.guix.gnu.org
https://bordeaux-guix.jing.rocks
https://mirror.yandex.ru/mirrors/guix/
https://mirrors.sjtug.sjtu.edu.cn/guix
https://berlin-guix.jing.rocks
https://bordeaux-singapore-mirror.cbaines.net
EOF

# Genenetwork mirror (USA)
substitute_urls <<EOF
https://cuirass.genenetwork.org
EOF

# Tobias (Germany)
substitute_urls <<EOF
https://guix.tobias.gr
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

# Run guix daemon
${GUIX_PROFILE}/bin/guix-daemon --build-users-group=guix-builder --substitute-urls="${SUBSTITUTE_URLS}" &
GUIX_DAEMON=$!

# Execute commands
exec "$@"
