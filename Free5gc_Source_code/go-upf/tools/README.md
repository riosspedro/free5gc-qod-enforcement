# gtp5g-tunnel

Prebuilt utility used to inspect PDR and QER rules installed in the Linux gtp5g kernel module.

## Origin

- Project: free5gc/go-gtp5gnl
- Repository: https://github.com/free5gc/go-gtp5gnl
- Module: github.com/free5gc/go-gtp5gnl/cmd/gogtp5g-tunnel
- Version: v1.6.2
- Commit: efe4d8ebd0d9d4b1e9c8dc4b254f4da0fdd360b1

## Binary

- File: gtp5g-tunnel
- Target: Linux amd64
- CGO: disabled
- SHA-256: d65b88aa0da6dfd6d0b7f0ba2f3d4778646521a76c3a0e54484e0415ae1da45f

The Dockerfile copies this binary to /free5gc/gtp5g-tunnel.
It is consumed by scripts/inspect-qod-rules.sh.

## License

The upstream project is distributed under the Apache License 2.0.
A copy is provided in LICENSE.go-gtp5gnl.
