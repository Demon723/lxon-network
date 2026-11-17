# Helios POS Firmware

Helios is the LXON point-of-sale / validator terminal. It runs on an
ESP32-S3 with an ATECC608A secure element and signs telemetry with
ML-DSA-65 (PQClean).

## Hardware

| Component | Purpose |
|-----------|---------|
| ESP32-S3 @ 240 MHz | Dual-core application processor |
| ATECC608A (Microchip) | Secure key storage, ECDSA, SHA-256 |
| PQClean ml-dsa-65 | Post-quantum signing in software |
| Wi-Fi / Ethernet | Uplink to LXON gateway |

## Performance

| Operation | Time (Cortex-M4 @ 168 MHz) |
|-----------|---------------------------|
| ML-DSA-65 keygen | ~60 ms |
| ML-DSA-65 sign | ~64 ms (variable, rejection sampling) |
| ML-DSA-65 verify | ~14 ms |

On ESP32-S3 @ 240 MHz, signing is ~200 ms. Budget accordingly.

## Firmware layout

```
firmware/helios-pos/
  include/helios.h      # Public API
  src/helios.c          # Implementation
  tests/test_helios.c   # Host unit tests
  CMakeLists.txt        # Build
```

## Building

### Host (unit tests)

```bash
mkdir build && cd build
cmake -DHOST_BUILD=ON ..
make
ctest --output-on-failure
```

### Embedded

```bash
mkdir build && cd build
cmake -DCMAKE_TOOLCHAIN_FILE=../tools/esp32-toolchain.cmake ..
make
```

## Secure element

The ATECC608A stores the ECDSA identity key. The ML-DSA-65 keypair is
derived from the secure element's random seed. All secret material is
zeroed from RAM after use via `helios_wipe`.

## Fail-closed

When PQClean or the secure element is not linked, all operations fail
closed. This is intentional — never trust an unprovisioned terminal.