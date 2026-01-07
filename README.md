# MetaCall Guix
Docker image for using Guix in a CI/CD environment.

## How to use it

This image encapsulates the Guix daemon. For now, Guix does not have a daemonless option, so packaging it into a Docker image has some implications. The Guix daemon needs to fork, and forking a process during build phase is not allowed, so we have to work with it in a different way. There are two options:

1) Running the build with Docker, using the `--privileged` flag and commiting the result on each step. For example, imagine we have the following `Dockerfile`:
    ```dockerfile
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
    A complete working example used in production can be found here: https://github.com/metacall/distributable

2) Running the build with BuildKit using the buildx extension for Docker (like how it is done in this repository: https://github.com/metacall/guix/blob/e9a0e791af919ddf74349cdbb11acc325ee1b48b/Dockerfile#L73). BuildKit allows to pass extra arguments to the `RUN` command in the Dockerfile. With the `--security=insecure` flag we can allow Docker to fork while it is building. The previous example can be transformed into this:
    ```dockerfile
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

## Adding substitute servers

Add all your substitutes public keys in the [substitutes](./substitutes) folder, they must end with .pub extension
Later on add the URL of your substitute server in `SUBSTITUTE_URLS` list on [scripts/entry-point.sh](./scripts/entry-point.sh).

## Troubleshooting

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
