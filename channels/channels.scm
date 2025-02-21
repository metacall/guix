;	MetaCall Guix by Parra Studios
;	Docker image for using Guix in a CI/CD environment.
;
;	Copyright (C) 2016 - 2024 Vicente Eduardo Ferrer Garcia <vic798@gmail.com>
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

(list (channel
       (name 'guix)
       (url "https://git.savannah.gnu.org/git/guix.git")
       (branch "master")
       (commit "f0d4daa13f0b57f5c03af73d449b2c6dd3160d08")) ; 2025-02-17 14:29:56 +0100
)
