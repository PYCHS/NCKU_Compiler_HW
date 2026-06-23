#include <stdio.h>
#include <stdlib.h>
#include "compiler_util.h"
#include "utf8_console.h"

int main(int argc, char** argv) {
    utf8_init();
    if (argc < 2) {
        printf("Usage: %s <input_file>\n", argv[0]);
        return 1;
    }

    yyin = fopen(argv[1], "rb");
    if (!yyin) {
        fprintf(stderr, "Could not open file: %s\n", argv[1]);
        return 1;
    }

    while (yylex()) {
    }

    fclose(yyin);
    yylex_destroy();
    return 0;
}
