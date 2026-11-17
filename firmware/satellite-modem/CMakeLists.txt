cmake_minimum_required(VERSION 3.20)
project(lxon_satellite_modem C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Target: ESP32-S3 (POS) and RP2350 (satellite bus)
# Build for host with -DHOST_BUILD=ON for unit tests
option(HOST_BUILD "Build for host (unit tests)" OFF)

add_library(lxon_satellite_modem
    src/iridium.c
    src/astrocast.c
    src/at_parser.c
    src/sbd_framing.c
    src/pq_sign.c
    src/uart_hal.c
)

target_include_directories(lxon_satellite_modem PUBLIC include)

if(HOST_BUILD)
    # One executable per test file (each defines main()).
    add_executable(lxon_test_iridium tests/test_iridium.c)
    target_link_libraries(lxon_test_iridium lxon_satellite_modem m)
    add_test(NAME iridium COMMAND lxon_test_iridium)

    add_executable(lxon_test_at_parser tests/test_at_parser.c)
    target_link_libraries(lxon_test_at_parser lxon_satellite_modem m)
    add_test(NAME at_parser COMMAND lxon_test_at_parser)

    add_executable(lxon_test_pq_sign tests/test_pq_sign.c)
    target_link_libraries(lxon_test_pq_sign lxon_satellite_modem m)
    add_test(NAME pq_sign COMMAND lxon_test_pq_sign)
endif()