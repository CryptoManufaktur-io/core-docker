# core-docker

Docker compose for Core chain.

Meant to be used with [central-proxy-docker](https://github.com/CryptoManufaktur-io/central-proxy-docker) for traefik
and Prometheus remote write; use `:ext-network.yml` in `COMPOSE_FILE` inside `.env` in that case.

## Quick setup

Run `cp default.env .env`, then `nano .env`, and update values like NETWORK, GETH_BUILD_TARGET, and SNAPSHOT.

If you want the consensus node RPC ports exposed locally, use `rpc-shared.yml` in `COMPOSE_FILE` inside `.env`.

- `./cored install` brings in docker-ce, if you don't have Docker installed already.
- `./cored up`

To update the software, run `./cored update` and then `./cored up`

## Version

Core Docker uses a semver scheme.

This is core-docker v1.0.0
