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
        (commit "f0d4daa13f0b57f5c03af73d449b2c6dd3160d08") ; Mon Feb 17 14:29:21 2025 +0100
        (introduction
            (make-channel-introduction
                "f0d4daa13f0b57f5c03af73d449b2c6dd3160d08" ; Tue May 26 22:30:51 2020 +0200
            (openpgp-fingerprint
                "BCA6 89B6 3655 3801 C3C6  2150 197A 5888 235F ACAC")))) ; git verify-commit <commit-hash>
)
