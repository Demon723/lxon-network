cmake_minimum_required(VERSION 3.20)
project(lxon_regulatory C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

option(HOST_BUILD "Build for host (unit tests)" OFF)

add_library(regulatory
    src/regulatory.c
)

target_include_directories(regulatory PUBLIC include)

if(HOST_BUILD)
    add_executable(reg_tests tests/test_regulatory.c)
    target_link_libraries(reg_tests regulatory)
    enable_testing()
    add_test(NAME unit COMMAND reg_tests)
endif()