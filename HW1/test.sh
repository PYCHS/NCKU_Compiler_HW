#!/bin/bash

# Default values
FILE_FILTER=""
INTERACTIVE=false
STOP_ON_FIRST_ERROR=false
NO_COMPILE=false

# Argument parsing
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -f|--file) FILE_FILTER="$2"; shift ;;
        -i|--interactive) INTERACTIVE=true ;;
        -s|--stop-on-first-error) STOP_ON_FIRST_ERROR=true ;;
        -n|--no-compile) NO_COMPILE=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# ANSI color codes
CYAN='\033[0;36m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Compilation
if [ "$NO_COMPILE" = false ]; then
    echo -e "${CYAN}Compiling project...${NC}"
    if [ ! -d "build" ]; then
        cmake -B build -S .
    fi
    cmake --build build
    if [ $? -ne 0 ]; then
        echo -e "${RED}Compilation failed!${NC}"
        exit 1
    fi
fi

# Lexer executable paths
LEXER_EXE="./build/lexer_test"
if [ ! -f "$LEXER_EXE" ]; then
    LEXER_EXE="./cmake-build-debug/lexer_test"
fi

if [ ! -f "$LEXER_EXE" ]; then
    echo -e "${RED}Lexer executable not found!${NC}"
    exit 1
fi

TEST_DIRS=("test/策問" "test/殿試")
EXPECTED_DIR="test/對勘"
TEMP_OUT="temp_out.txt"
TEMP_EXPECTED="temp_expected.txt"

ALL_PASSED=true
TOTAL_SCORE=0

for dir in "${TEST_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        continue
    fi

    if [ "$STOP_ON_FIRST_ERROR" = true ] && [ "$ALL_PASSED" = false ]; then
        break
    fi

    # Scoring logic
    POINTS_PER_TEST=2
    if [[ "$dir" == *"策問"* ]]; then
        POINTS_PER_TEST=8
    fi

    # Find files and sort them
    FILES=$(find "$dir" -maxdepth 1 -name "*.wy" | sort)

    for f in $FILES; do
        FILENAME=$(basename "$f")
        
        # File filter check
        if [ -n "$FILE_FILTER" ] && [[ "$FILENAME" != *"$FILE_FILTER"* ]]; then
            continue
        fi

        echo -n "Running Test: $FILENAME"

        BASENAME="${FILENAME%.wy}"
        EXPECTED_PATH="$EXPECTED_DIR/$BASENAME.out"

        if [ ! -f "$EXPECTED_PATH" ]; then
            echo -e "\n${YELLOW}Warning: Expected output file not found for $FILENAME${NC}"
            continue
        fi

        # Run lexer and capture output, normalizing line endings and BOM
        # Use tr -d '\r' to handle Windows-style line endings and sed to remove BOM
        ACTUAL=$("$LEXER_EXE" "$f" 2>&1 | sed '1s/^\xef\xbb\xbf//' | tr -d '\r' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' | sed '/./,$!d')
        EXPECTED=$(cat "$EXPECTED_PATH" | sed '1s/^\xef\xbb\xbf//' | tr -d '\r' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' | sed '/./,$!d')

        if [ "$ACTUAL" != "$EXPECTED" ]; then
            ALL_PASSED=false
            echo -e " ${RED}Failed${NC}"

            echo "$ACTUAL" > "$TEMP_OUT"
            echo "$EXPECTED" > "$TEMP_EXPECTED"

            DIFF_OPTS="-c core.autocrlf=false diff --ignore-cr-at-eol --no-index --color-words"
            if [ "$INTERACTIVE" = false ]; then
                git --no-pager $DIFF_OPTS "$TEMP_EXPECTED" "$TEMP_OUT"
            else
                git $DIFF_OPTS "$TEMP_EXPECTED" "$TEMP_OUT"
            fi
            echo "----------------------------------------"

            if [ "$STOP_ON_FIRST_ERROR" = true ]; then
                break 2 # Break out of both loops
            fi
        else
            echo -e " ${GREEN}Passed (+${POINTS_PER_TEST} points)${NC}"
            TOTAL_SCORE=$((TOTAL_SCORE + POINTS_PER_TEST))
        fi
    done
done

# Cleanup
[ -f "$TEMP_OUT" ] && rm "$TEMP_OUT"
[ -f "$TEMP_EXPECTED" ] && rm "$TEMP_EXPECTED"

echo -e "${CYAN}Final Score: $TOTAL_SCORE/100${NC}"

if [ "$ALL_PASSED" = true ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
