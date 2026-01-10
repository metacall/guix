# TODO

- [ ] Implement debian and alpine images. Review things like this once we do it:
    https://github.com/metacall/guix/blob/5367229e336416014d6aecf17afde602439f8036/Dockerfile#L70


- [ ] [Produce a self contained image of Guix](https://github.com/metacall/guix/issues/1) inside Docker removing Alpine from base image and using scratch. Possible solution:
    - Multi-build stage and using Guix to pack itself. Then create a layer with Guix files only.
