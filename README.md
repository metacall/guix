# MetaCall Guix

Docker image for using Guix in a CI/CD environment.

## Design philosophy

The project is designed in the following way:

  - **Guix runs deamonless**: The container has an entry point that allows you to run commands per instance of the command, the daemon is shutdown for each command or group of commands executed. You can group them by passing a script and executing it or running the image interactively and pass multiple commands.

  - **Versions are fixed**: We provide a fixed channel commit into `https://codeberg.org/guix` repository, if you want to patch the `channels.scm` you can find them on `/root/.config/guix/channels.scm`. By default if you do `guix pull` it will always pull to the same commit and not to the latest.

  - **Incrementally builds and tarballs for all architectures**: In order to avoid CI slowness, we build and cache incrementally our own versions of Guix, snapshots are done periodically to the upstream repository in master branch. They are tagged in the following way: `v20260106` for 6th of January of 2026. The binaries are pushed into releases that later on the CI reuses for building the next version so builds are cached in each iteration.

  - **Default list of substitutes**: In order to improve performance, we provide a long list of substitutes a part from the official servers. You can modify them, check the substitute section for doing so.

  - **Report errors in-place**: If your command fails, we copy all the `*.drv.gz` files into the current directory, we unpack them and then we show the contents. By default the working directory of the image is root `/`, so all contents will be put there in case of error. In addition to this, all commands are always traced and printed to stdout with `set -exuo pipefail`, so it can be easily debugged later on and errors are not silently skipped.

All these design decisions are taken because we focus only on providing CI/CD environment. If you want to use this as a normal end user, take it carefully. You can still modify those behaviors easily but those assumptions are taken due to nature of CI/CD itself. In the future we may make it more customizable for end users.

The main objective of this repository is to have a tool for producing ultra portable, reproducible and cross-platform builds for production ready applications that can be installed from a shell script or uncompressing them into root.

## How to use it

This image encapsulates the Guix daemon. You can view the image details and tags in [DockerHub](https://hub.docker.com/r/metacall/guix). For now, Guix does not have a daemonless option, so packaging it into a Docker image has some implications. The Guix daemon needs to fork, and forking a process during build phase is not allowed, so we have to work with it in a different way. There are two options:

1. Running the build with Docker, using the `--privileged` flag and commiting the result on each step. For example, imagine we have the following `Dockerfile`:

   ```docker
   FROM metacall/guix:latest AS example

   # Copy some dependencies
   COPY . .
   ```

   Now we can build the image `metacall/example` with docker run + commit:

   ```sh
   # Build the base image
   docker build -t metacall/example -f Dockerfile .
   # Run a guix pull
   docker run --privileged --name tmp metacall/example sh -c 'guix pull'
   # Commit changes
   docker commit tmp metacall/new-image && docker rm -f tmp
   # Install some package
   docker run --privileged --name tmp metacall/example sh -c 'guix package -i guile'
   # Commit changes
   docker commit tmp metacall/example && docker rm -f tmp
   # Push the final image
   docker push metacall/example
   ```

   A complete working example used in production can be found here: https://github.com/metacall/distributable-linux

2. Running the build with BuildKit using the buildx extension for Docker (like how it is done in this repository: https://github.com/metacall/guix/blob/e9a0e791af919ddf74349cdbb11acc325ee1b48b/Dockerfile#L73). BuildKit allows to pass extra arguments to the `RUN` command in the Dockerfile. With the `--security=insecure` flag we can allow Docker to fork while it is building. For supporting insecure builds, you have to use any docker syntax extension that uses `experimental` or `labs` suffix, like `# syntax=docker/dockerfile:1.1-experimental` or `# syntax=docker/dockerfile:1.4-labs`, because this feature is not standardized yet. The previous example can be transformed into this:

   ```docker
   # syntax=docker/dockerfile:1.4-labs

   FROM metacall/guix:latest AS example

   # Copy some dependencies
   COPY . .

   # Run guix pull and install dependencies
   RUN --security=insecure sh -c '/entry-point.sh guix pull' \
       && sh -c '/entry-point.sh guix package -i guile'
   ```

   For building this image we need Docker `v19.03` or superior and the buildx plugin:

   ```sh
   # Install the buildx plugin
   docker build --platform=local -o . git://github.com/docker/buildx
   mkdir -p ~/.docker/cli-plugins/
   mv buildx ~/.docker/cli-plugins/docker-buildx
   ```

   If you have it already installed, we need to create an insecure builder (this must be run only once):

   ```sh
   # Create an insecure builder
   docker buildx create --use --name insecure-builder --buildkitd-flags '--allow-insecure-entitlement security.insecure'
   ```

   Finally, for building the `Dockerfile` with the already created insecure builder, we have to run this command:

   ```sh
   # Build and push the image with buildx
   docker buildx build -t metacall/example -o type=registry --allow security.insecure .
   ```

## Building the image locally

For building it, we use `buildx` from Buildkit:

```sh
# Run the following command the first time only
docker buildx create --use --name insecure-builder --buildkitd-flags '--allow-insecure-entitlement security.insecure'
# Build the Guix image with the following command
docker buildx build --load -t metacall/guix --allow security.insecure --build-arg METACALL_GUIX_ARCH="x86_64-linux" .
```

## Running the image

For running the image interactively from command line:

```sh
docker run --rm --privileged -it metacall/guix
```

This will give you a prompt where you can write guix commands and execute them directly:

```sh
guix pull
```

If you prefer to have a bash prompt instead, do this:

```sh
docker run --rm --privileged --entrypoint bash -it metacall/guix
```

Then execute guix commands like this:

```sh
/entry-point.sh guix pull
```

## Building and running for other architectures

For building you need to follow the following table:

| Docker Platform (--platform) | Guix Architecture String |
| ---------------------------- | ------------------------ |
| linux/amd64                  | x86_64-linux             |
| linux/386                    | i686-linux               |
| linux/arm/v7                 | armhf-linux              |
| linux/arm64/v8               | aarch64-linux            |
| linux/ppc64le                | powerpc64le-linux        |
| linux/riscv64                | riscv64-linux            |

You will need the following for building and runnig:

```sh
# Required for building:
docker run --privileged --rm tonistiigi/binfmt --install all
# Required for running:
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
```

Now you can build for some architecture, `linux/386` for example:

```sh
# Build the Guix image with the following command
docker buildx build --load -t metacall/guix --platform linux/386 --allow security.insecure --build-arg METACALL_GUIX_ARCH="i686-linux" .
```

## Adding substitute servers

Add all your substitutes public keys in the [substitutes](./substitutes) folder, they must end with .pub extension
Later on add the URL of your substitute server in `SUBSTITUTE_URLS` list on [scripts/entry-point.sh](./scripts/entry-point.sh).

## Troubleshooting

In case of an error of any kind.

### Disk issues with `armhf-linux` / `linux/arm/v7`

When doing `guix pull`, you will get the following error:

```sh
guix pull: error: Git error: could not read directory '/root/.cache/guix/checkouts/lmgz3ewobtxzz4rsyp72z7woeuxeghzyukvmmnxlwpobu76yyi5a/.git/refs': Value too large for defined data type
```

This happens because there is a mismatch in inodes between 32 and 64-bits. The only way to workaround this is to use `tmpfs` for storing the checkouts of Guix, or any other alternative volume that supports 64-bit inodes, for example binding the volume into the host if you are running a 64-bit host. We do this at build time with the following instruction:

```docker
RUN --security=insecure --mount=type=tmpfs,target=/root/.cache/guix \
	sh -c '/entry-point.sh guix pull'
```

Similarly, for doing it at runtime:
```sh
docker run --privileged --platform linux/arm/v7 -it \
	--mount type=tmpfs,target=/root/.cache/guix \
	metacall/guix guix pull
```

### Granting entitlement

If you get the following error:

```sh
error: failed to solve: granting entitlement security.insecure is not allowed by build daemon configuration
```

Run:

```sh
# This will select the insecure-builder previously created if it got unselected for some reason
docker buildx use insecure-builder
```

## Use cases

[`MetaCall Guix GCC Example`](https://github.com/metacall/guix-gcc-example): This repository demonstrates how to use MetaCall Guix Docker Image for building portable self contained packages, in this case GCC@2.95. The idea of this repository is to make a Proof of Concept for Blink Virtual Machine by using GCC and possibly try to do the same with MetaCall in the near future.

[`MetaCall Linux Distributable`](https://github.com/metacall/distributable-linux): This repository provides a self-contained and portrable version of MetaCall Core for Linux.
