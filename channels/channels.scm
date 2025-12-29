;	MetaCall Guix by Parra Studios
;	Docker image for using Guix in a CI/CD environment.
;
;	Copyright (C) 2016 - 2025 Vicente Eduardo Ferrer Garcia <vic798@gmail.com>
;
;	Licensed under the Apache License, Version 2.0 (the "License");
;	you may not use this file except in compliance with the License.
;	You may obtain a copy of the License at
;
;		http://www.apache.org/licenses/LICENSE-2.0
;
;	Unless required by applicable law or agreed to in writing, software
;	distributed under the License is distributed on an "AS IS" BASIS,
;	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;	See the License for the specific language governing permissions and
;	limitations under the License.
;

(list
    (channel
        (name 'guix)
        (url "https://codeberg.org/guix/guix.git")
        (branch "master")
        (commit "2d4ed08662714ea46cfe0b41ca195d1ef845fd1b") ; Tue Dec 16 12:26:57 2025 +0100
        (introduction
            (make-channel-introduction
                "2d4ed08662714ea46cfe0b41ca195d1ef845fd1b" ; Tue 23 Dec 2025 10:16:06 AM EET
            (openpgp-fingerprint
                "6B51 071A 0FB1 52AD ED93  6360 0322 7982 69E4 71C3")))) ; git verify-commit <commit-hash>
)
