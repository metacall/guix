# TODO

- [x] [Implement multi-platform builds](https://github.com/metacall/guix/issues/2):
    - [x] `linux/amd64`
    - [x] `linux/386`
    - [x] `linux/arm/v7`
    - [x] `linux/arm64/v8`
    - [x] `linux/ppc64le`
    - [ ] `linux/riscv64` (no official binaries available yet)
- [ ] [Produce a self contained image of Guix](https://github.com/metacall/guix/issues/1) inside Docker removing Alpine from base image and using scratch. Possible solution:
    - Multi-build stage and using Guix to pack itself. Then create a layer with Guix files only.
