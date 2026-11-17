cmake_minimum_required(VERSION 3.20)
project(lxon_helios_pos C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

option(HOST_BUILD "Build for host (unit tests)" OFF)

add_library(helios_pos
    src/helios.c
)

target_include_directories(helios_pos PUBLIC include)

if(HOST_BUILD)
    add_executable(helios_tests tests/test_helios.c)
    target_link_libraries(helios_tests helios_pos)
    enable_testing()
    add_test(NAME unit COMMAND helios_tests)
endif()