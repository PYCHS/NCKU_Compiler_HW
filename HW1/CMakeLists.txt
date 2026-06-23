cmake_minimum_required(VERSION 3.10)
project(NCKU_Compiler_HW1 C)

set(CMAKE_C_STANDARD 11)

find_package(FLEX REQUIRED)

# Include directories
include_directories(
        ${CMAKE_CURRENT_SOURCE_DIR}/lib
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${CMAKE_CURRENT_SOURCE_DIR}/src/lib
)

# Flex Target
FLEX_TARGET(
        Scanner
        src/compiler.l
        ${CMAKE_CURRENT_BINARY_DIR}/lex.yy.c
)

# Executable
add_executable(
        lexer_test
        src/main.c
        src/lib/chinese_number.c
        lib/utf8.c/utf8.c
        ${FLEX_Scanner_OUTPUTS}
)

target_link_libraries(lexer_test m)