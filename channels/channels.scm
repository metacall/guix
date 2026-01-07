;	MetaCall Guix by Parra Studios
;	Docker image for using Guix in a CI/CD environment.
;
;	Copyright (C) 2016 - 2026 Vicente Eduardo Ferrer Garcia <vic798@gmail.com>
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

; TODO: Download latest channel.scm:
; https://ci.guix.gnu.org/eval/latest/channels.scm?spec=guix

(list
    (channel
        (name 'guix)
        (url "https://codeberg.org/guix/guix.git")
        (branch "master")
        (commit "6913fd701884fad3af579efdc298ae444aeaf57c") ; Tue Jan 6 08:59:57 2026 -0500
        (introduction
            (make-channel-introduction
                "9edb3f66fd807b096b48283debdcddccfea34bad"
            (openpgp-fingerprint
                "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA"))))
)
