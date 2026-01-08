# TODO

- [ ] [Produce a self contained image of Guix](https://github.com/metacall/guix/issues/1) inside Docker removing Alpine from base image and using scratch. Possible solution:
    - Multi-build stage and using Guix to pack itself. Then create a layer with Guix files only.
