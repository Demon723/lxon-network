# LXON Satellite Modem Firmware

C driver library for satellite modems used by LXON hardware:

- **Iridium 9603** — Short Burst Data (SBD) over Iridium's L-band network
- **Astrocast Astronode S** — L-band store-and-forward for IoT

## Building

### Host (unit tests)

```bash
mkdir build && cd build
cmake -DHOST_BUILD=ON ..
make
ctest --output-on-failure
```

### Embedded (ESP32-S3 / RP2350)

```bash
mkdir build && cd build
cmake -DCMAKE_TOOLCHAIN_FILE=../tools/esp32-toolchain.cmake ..
make
```

## PQ signing

Production builds link against PQClean's `ml-dsa-65` reference
implementation. Define `LXON_HAVE_PQCLEAN` and add the PQClean object
files to the link line in CMakeLists.txt.

## Iridium 9603 notes

- Default baud: 19200, 8N1, 3.3V logic
- Max SBD MO message: 340 bytes
- SBD session latency: store-and-forward, ~minutes to hours
- Power: 250 mA peak during transmit

## Astrocast notes

- Uplink: 1626.5–1660.5 MHz L-band
- Max user data: 160 bytes per message
- Downlink commands: 8 or 40 bytes
- Average latency: 5–7 hours (store-and-forward)