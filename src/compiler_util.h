cd ~/HW1/NCKU_Compiler_HW1/src
cp compiler.l compiler.l.bak
cat > compiler.l <<'EOF'
/* Definition section */
%option yylineno
%option noyywrap
%{
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <stdbool.h>
    #include <stdint.h>

    #include <utf8.c/utf8.h>
    #include "chinese_number.h"
    #include "compiler_util.h"

    #define YY_NO_UNPUT
    #define YY_NO_INPUT

    static int yyline = 1;
    static int yycol = 1;
    static int yytokenLine = 1;
    static int yytokenColumn = 1;

    static int savedLine = 1;
    static int savedCol = 1;

    static char tokenBuffer[65536];
    static int tokenBufferLen = 0;

    static int utf8CharLen(unsigned char c) {
        if (c < 0x80) return 1;
        if ((c & 0xE0) == 0xC0) return 2;
        if ((c & 0xF0) == 0xE0) return 3;
        if ((c & 0xF8) == 0xF0) return 4;
        return 1;
    }

    static void advanceText(const char* s) {
        for (int i = 0; s[i] != '\0'; ) {
            if (s[i] == '\r') {
                if (s[i + 1] == '\n') i++;
                yyline++;
                yycol = 1;
                i++;
            } else if (s[i] == '\n') {
                yyline++;
                yycol = 1;
                i++;
            } else {
                int len = utf8CharLen((unsigned char)s[i]);
                yycol++;
                i += len;
            }
        }
    }

    static void resetBuffer(void) {
        tokenBufferLen = 0;
        tokenBuffer[0] = '\0';
    }

    static void appendBuffer(const char* s) {
        int n = strlen(s);
        if (tokenBufferLen + n >= (int)sizeof(tokenBuffer)) return;
        memcpy(tokenBuffer + tokenBufferLen, s, n);
        tokenBufferLen += n;
        tokenBuffer[tokenBufferLen] = '\0';
    }

    static int chineseDigitValue(const char* s, int* bytes) {
        if (strncmp(s, "零", 3) == 0) { *bytes = 3; return 0; }
        if (strncmp(s, "一", 3) == 0) { *bytes = 3; return 1; }
        if (strncmp(s, "二", 3) == 0) { *bytes = 3; return 2; }
        if (strncmp(s, "兩", 3) == 0) { *bytes = 3; return 2; }
        if (strncmp(s, "两", 3) == 0) { *bytes = 3; return 2; }
        if (strncmp(s, "三", 3) == 0) { *bytes = 3; return 3; }
        if (strncmp(s, "四", 3) == 0) { *bytes = 3; return 4; }
        if (strncmp(s, "五", 3) == 0) { *bytes = 3; return 5; }
        if (strncmp(s, "六", 3) == 0) { *bytes = 3; return 6; }
        if (strncmp(s, "七", 3) == 0) { *bytes = 3; return 7; }
        if (strncmp(s, "八", 3) == 0) { *bytes = 3; return 8; }
        if (strncmp(s, "九", 3) == 0) { *bytes = 3; return 9; }
        *bytes = utf8CharLen((unsigned char)s[0]);
        return -1;
    }

    static long long parseChineseInteger(const char* s) {
        long long total = 0, section = 0, num = 0;
        bool hasUnit = false;

        for (int i = 0; s[i] != '\0'; ) {
            int bytes = 0;
            int d = chineseDigitValue(s + i, &bytes);

            if (d >= 0) {
                num = d;
                i += bytes;
                continue;
            }

            if (strncmp(s + i, "十", 3) == 0) {
                if (num == 0) num = 1;
                section += num * 10;
                num = 0;
                hasUnit = true;
                i += 3;
            } else if (strncmp(s + i, "百", 3) == 0) {
                if (num == 0) num = 1;
                section += num * 100;
                num = 0;
                hasUnit = true;
                i += 3;
            } else if (strncmp(s + i, "千", 3) == 0) {
                if (num == 0) num = 1;
                section += num * 1000;
                num = 0;
                hasUnit = true;
                i += 3;
            } else if (strncmp(s + i, "萬", 3) == 0 || strncmp(s + i, "万", 3) == 0) {
                section += num;
                total += section * 10000;
                section = 0;
                num = 0;
                hasUnit = true;
                i += 3;
            } else if (strncmp(s + i, "億", 3) == 0 || strncmp(s + i, "亿", 3) == 0) {
                section += num;
                total += section * 100000000LL;
                section = 0;
                num = 0;
                hasUnit = true;
                i += 3;
            } else {
                i += utf8CharLen((unsigned char)s[i]);
            }
        }

        if (!hasUnit) {
            long long value = 0;
            for (int i = 0; s[i] != '\0'; ) {
                int bytes = 0;
                int d = chineseDigitValue(s + i, &bytes);
                if (d >= 0) value = value * 10 + d;
                i += bytes;
            }
            return value;
        }

        return total + section + num;
    }

    static char* normalizeNumber(const char* s) {
        static char out[256];

        if (s[0] >= '0' && s[0] <= '9') {
            snprintf(out, sizeof(out), "%s", s);
            return out;
        }

        const char* dot = strstr(s, "·");
        if (!dot) {
            snprintf(out, sizeof(out), "%lld", parseChineseInteger(s));
            return out;
        }

        char intPart[256];
        int intLen = dot - s;
        if (intLen >= (int)sizeof(intPart)) intLen = sizeof(intPart) - 1;
        memcpy(intPart, s, intLen);
        intPart[intLen] = '\0';

        snprintf(out, sizeof(out), "%lld.", parseChineseInteger(intPart));

        const char* p = dot + strlen("·");
        while (*p) {
            int bytes = 0;
            int d = chineseDigitValue(p, &bytes);
            if (d >= 0) {
                char tmp[2] = { (char)('0' + d), '\0' };
                strncat(out, tmp, sizeof(out) - strlen(out) - 1);
            }
            p += bytes;
        }
        return out;
    }

    #define YY_USER_ACTION \
        do { \
            yytokenLine = yyline; \
            yytokenColumn = yycol; \
            advanceText(yytext); \
        } while (0);

    #define PRINT_AT(line, col, format, ...) \
        printf("%d:%d: " format "\n", (line), (col), ##__VA_ARGS__)

    #define PRINT_TOKEN(format, ...) \
        PRINT_AT(yytokenLine, yytokenColumn, format, ##__VA_ARGS__)
%}

/* Define regular expression label */
UTF8_BOM "\357\273\277"

ASCII   [\x00-\x7f]
U       [\x80-\xbf]

B2      [\xC2-\xDF]{U}
B3_1    \xE0[\xA0-\xBF]{U}
B3_2    [\xE1-\xEC]{U}{U}
B3_3    \xED[\x80-\x9F]{U}
B3_4    [\xEE-\xEF]{U}{U}
B4_1    \xF0[\x90-\xBF]{U}{U}
B4_2    [\xF1-\xF3]{U}{U}{U}
B4_3    \xF4[\x80-\x8F]{U}{U}

ALL_UTF8 {ASCII}|{B2}|{B3_1}|{B3_2}|{B3_3}|{B3_4}|{B4_1}|{B4_2}|{B4_3}

B3_2_EXCLUDE_QUO ([\xE1-\xE2]{U}{U})|(\xE3\x80[\x80-\x8C\x8E-\xBF])|(\xE3[\x81-\xBF]{U})|([\xE4-\xEC]{U}{U})
EXCLUDE_QUO [\x20-\x7E]|{B2}|{B3_1}|{B3_2_EXCLUDE_QUO}|{B3_3}|{B3_4}|{B4_1}|{B4_2}|{B4_3}

CD (零|一|二|兩|两|三|四|五|六|七|八|九)
CUNIT (十|百|千|萬|万|億|亿)
CNUM ({CD}|{CUNIT})+(·{CD}+)?
ANUM [0-9]+(\.[0-9]+)?

%x IDENT_CON
%x STR_CON

%%
/* String literal: 「「 ... 」」 */
"「「" {
    savedLine = yytokenLine;
    savedCol = yytokenColumn;
    resetBuffer();
    BEGIN(STR_CON);
}
<STR_CON>"」」" {
    PRINT_AT(savedLine, savedCol, "STR_LIT \"%s\"", tokenBuffer);
    BEGIN(INITIAL);
}
<STR_CON>"」" {
    appendBuffer(yytext);
}
<STR_CON>\r?\n {
    appendBuffer("\n");
}
<STR_CON>{EXCLUDE_QUO}+ {
    appendBuffer(yytext);
}

/* Identifier: 「 ... 」 */
"「" {
    savedLine = yytokenLine;
    savedCol = yytokenColumn;
    resetBuffer();
    BEGIN(IDENT_CON);
}
<IDENT_CON>"」" {
    PRINT_AT(savedLine, savedCol, "IDENT '%s'", tokenBuffer);
    BEGIN(INITIAL);
}
<IDENT_CON>\r?\n {
    appendBuffer("\n");
}
<IDENT_CON>{EXCLUDE_QUO}+ {
    appendBuffer(yytext);
}

/* Comments */
"注曰"|"疏曰"|"批曰" {
    PRINT_TOKEN("COMMENT %s", yytext);
}

/* Declarations and assignment */
"吾有"|"今有" {
    PRINT_TOKEN("HERE_ARE %s", yytext);
}
"有" {
    PRINT_TOKEN("HERE_IS_A %s", yytext);
}
"名之曰" {
    PRINT_TOKEN("NAME_IT %s", yytext);
}
"曰" {
    PRINT_TOKEN("SAID %s", yytext);
}
"昔之" {
    PRINT_TOKEN("PAST %s", yytext);
}
"者" {
    PRINT_TOKEN("TOPIC %s", yytext);
}
"今" {
    PRINT_TOKEN("SET %s", yytext);
}
"其" {
    PRINT_TOKEN("ITS %s", yytext);
}
"是矣" {
    PRINT_TOKEN("IS_THUS %s", yytext);
}

/* Types and literals */
"長"|"數"|"言"|"爻"|"元"|"列"|"術" {
    PRINT_TOKEN("VAR_TYPE %s", yytext);
}
"陽" {
    PRINT_TOKEN("BOOL_LIT true");
}
"陰" {
    PRINT_TOKEN("BOOL_LIT false");
}
{CNUM}|{ANUM} {
    PRINT_TOKEN("NUMBER_LIT %s", normalizeNumber(yytext));
}

/* Math and logic operators */
"所餘幾何" {
    PRINT_TOKEN("OP_MOD %s", yytext);
}
"中有陽乎" {
    PRINT_TOKEN("OP_OR %s", yytext);
}
"中無陰乎" {
    PRINT_TOKEN("OP_AN %s", yytext);
}
"不大於" {
    PRINT_TOKEN("OP_LE %s", yytext);
}
"不小於" {
    PRINT_TOKEN("OP_GE %s", yytext);
}
"大於" {
    PRINT_TOKEN("OP_GT %s", yytext);
}
"小於" {
    PRINT_TOKEN("OP_LT %s", yytext);
}
"不等於" {
    PRINT_TOKEN("OP_NE %s", yytext);
}
"等於" {
    PRINT_TOKEN("OP_EQ %s", yytext);
}
"加" {
    PRINT_TOKEN("OP_ADD %s", yytext);
}
"減" {
    PRINT_TOKEN("OP_SUB %s", yytext);
}
"乘" {
    PRINT_TOKEN("OP_MUL %s", yytext);
}
"除" {
    PRINT_TOKEN("OP_DIV %s", yytext);
}
"於" {
    PRINT_TOKEN("PREP_LEFT %s", yytext);
}
"以" {
    PRINT_TOKEN("PREP_RIGHT %s", yytext);
}

/* Control flow */
"或若" {
    PRINT_TOKEN("ELSE_IF %s", yytext);
}
"若非" {
    PRINT_TOKEN("ELSE %s", yytext);
}
"若" {
    PRINT_TOKEN("IF %s", yytext);
}
"恆為是" {
    PRINT_TOKEN("WHILE_TRUE %s", yytext);
}
"為是" {
    PRINT_TOKEN("FOR %s", yytext);
}
"遍" {
    PRINT_TOKEN("TIMES %s", yytext);
}
"乃止" {
    PRINT_TOKEN("BREAK %s", yytext);
}
"乃得" {
    PRINT_TOKEN("RETURN %s", yytext);
}
"云云"|"也"|"矣" {
    PRINT_TOKEN("END %s", yytext);
}

/* Functions */
"欲行是術" {
    PRINT_TOKEN("TO_PERFORM_FUNC %s", yytext);
}
"必先得" {
    PRINT_TOKEN("REQUIRE_ARGS %s", yytext);
}
"乃行是術曰"|"乃是術曰" {
    PRINT_TOKEN("FUNC_BEGIN %s", yytext);
}
"是謂" {
    PRINT_TOKEN("FUNC_END_FOR %s", yytext);
}
"之術也" {
    PRINT_TOKEN("FUNC_END %s", yytext);
}
"施" {
    PRINT_TOKEN("CALL %s", yytext);
}

/* Arrays and other operations */
"之長" {
    PRINT_TOKEN("ARRAY_LENGTH %s", yytext);
}
"書之" {
    PRINT_TOKEN("PRINT %s", yytext);
}
"之" {
    PRINT_TOKEN("INDEX %s", yytext);
}
"充" {
    PRINT_TOKEN("PUSH %s", yytext);
}
"夫" {
    PRINT_TOKEN("THOSE %s", yytext);
}
"取" {
    PRINT_TOKEN("TAKE %s", yytext);
}

/* Decorative punctuation */
"。"|"，" {
}

/* Whitespace and BOM */
[ \t]+ {
}
\r?\n {
}
{UTF8_BOM} {
}

/* EOF */
<<EOF>> {
    yyterminate();
}

/* Unknown */
{ALL_UTF8} {
    PRINT_TOKEN("UNKNOWN CHAR %s", yytext);
}
. {
    PRINT_TOKEN("UNKNOWN CHAR %s", yytext);
}

%%
EOF