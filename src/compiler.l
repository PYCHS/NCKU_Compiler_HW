/* Definition section */
%option yymore
%option yylineno

%{
    #include <utf8.c/utf8.h>
    #include "chinese_number.h"
    #include "compiler_util.h"

    #define YY_NO_UNPUT
    #define YY_NO_INPUT

    /* Global tracking variables */
    int g_curr_line = 1;
    int g_utf8_col = 0;
    int g_utf8_len = 0;
    
    int g_tok_start_line = 1;
    int g_tok_start_col = 1;
    int g_is_tok_start_set = 0;
    
    utf8_string yytextUtf8;

    static inline void handle_newline(void) {
        g_curr_line++;
        g_utf8_col = 0;
        g_utf8_len = 0;
    }

    static inline int utf8_strlen(const char *str) {
        int length = 0;
        while (*str) {
            if (((unsigned char)*str & 0xC0) != 0x80) {
                length++;
            }
            str++;
        }
        return length;
    }

    static inline void parse_utf8_token(void) {
        yytextUtf8 = make_utf8_string(yytext);
        if (yytextUtf8.str != NULL) {
            g_utf8_len = utf8_strlen(yytext);
            g_utf8_col += g_utf8_len;
        }
    }

    static inline void extend_utf8_buffer(void) {
        yymore();
        if (yytextUtf8.str != NULL) {
            g_utf8_col -= g_utf8_len;
        }
    }

    static inline void register_token_start(void) {
        if (!g_is_tok_start_set) {
            g_tok_start_line = g_curr_line;
            g_tok_start_col = g_utf8_col + 1;
            g_is_tok_start_set = 1;
        }
        parse_utf8_token();
    }

    #define YY_USER_ACTION register_token_start();

    #define OUTPUT_TOKEN(fmt, ...) do { \
        printf("%d:%d: " fmt "\n", g_tok_start_line, g_tok_start_col, ##__VA_ARGS__); \
        g_is_tok_start_set = 0; \
    } while (0)

    char* extract_clean_token(int padding) {
        static char out_buffer[4096];
        int target_len = yyleng - (padding * 2);
        
        if (target_len < 0) {
            target_len = 0;
        }
        if (target_len >= (int)sizeof(out_buffer)) {
            target_len = sizeof(out_buffer) - 1;
        }
        
        strncpy(out_buffer, yytext + padding, target_len);
        out_buffer[target_len] = '\0';
        return out_buffer;
    }
%}

/* Pattern definitions */
UTF8_BOM          "\357\273\277"
digit             ("零"|"一"|"二"|"兩"|"三"|"四"|"五"|"六"|"七"|"八"|"九"|"十"|"百"|"千"|"萬"|"億")

ASCII             [\x00-\x7f]
U                 [\x80-\xbf]
B2                [\xC2-\xDF]{U}
B3_1              \xE0[\xA0-\xBF]{U}
B3_2              [\xE1-\xEC]{U}{U}
B3_3              \xED[\x80-\x9F]{U}
B3_4              [\xEE-\xEF]{U}{U}
B4_1              \xF0[\x90-\xBF]{U}{U}
B4_2              [\xF1-\xF3]{U}{U}{U}
B4_3              \xF4[\x80-\x8F]{U}{U}

ALL_UTF8          {ASCII}|{B2}|{B3_1}|{B3_2}|{B3_3}|{B3_4}|{B4_1}|{B4_2}|{B4_3}
B3_2_EXCL_QUO     ([\xE1-\xE2]{U}{U})|(\xE3\x80[\x80-\x8C\x8E-\xBF])|(\xE3[\x81-\xBF]{U})|([\xE4-\xEC]{U}{U})
EXCLUDE_QUO       [\x20-\x7E]|{B2}|{B3_1}|{B3_2_EXCL_QUO}|{B3_3}|{B3_4}|{B4_1}|{B4_2}|{B4_3}

%x STATE_STRING
%x STATE_IDENT

%%

"「「" {
    g_tok_start_line = g_curr_line;
    g_tok_start_col = g_utf8_col - g_utf8_len + 1;
    BEGIN(STATE_STRING);
    extend_utf8_buffer();
}

<STATE_STRING>"」」" {
    BEGIN(INITIAL);
    printf("%d:%d: STR_LIT \"%s\"\n", g_tok_start_line, g_tok_start_col, extract_clean_token(6));
    g_is_tok_start_set = 0;
}

<STATE_STRING>\r?\n {
    handle_newline();
    yymore();
}

<STATE_STRING>{EXCLUDE_QUO}+ {
    extend_utf8_buffer();
}

<STATE_STRING>"」" {
    extend_utf8_buffer();
}

"「" {
    g_tok_start_line = g_curr_line;
    g_tok_start_col = g_utf8_col - g_utf8_len + 1;
    BEGIN(STATE_IDENT);
    extend_utf8_buffer();
}

<STATE_IDENT>"」" {
    BEGIN(INITIAL);
    printf("%d:%d: IDENT '%s'\n", g_tok_start_line, g_tok_start_col, extract_clean_token(3));
    g_is_tok_start_set = 0;
}

<STATE_IDENT>\r?\n {
    handle_newline();
    yymore();
}

<STATE_IDENT>{EXCLUDE_QUO}+ {
    extend_utf8_buffer();
}

"陰"                    { OUTPUT_TOKEN("BOOL_LIT false"); }
"陽"                    { OUTPUT_TOKEN("BOOL_LIT true"); }

"加"                    { OUTPUT_TOKEN("EXP_MATH +"); }
"減"                    { OUTPUT_TOKEN("EXP_MATH -"); }
"乘"                    { OUTPUT_TOKEN("EXP_MATH *"); }
"除"                    { OUTPUT_TOKEN("EXP_MATH /"); }
"所餘幾何"              { OUTPUT_TOKEN("EXP_MATH_OP %%"); }

"於"                    { OUTPUT_TOKEN("<-"); }
"以"                    { OUTPUT_TOKEN("->"); }

"中有陽乎"              { OUTPUT_TOKEN("EXP_LOGIC ||"); }
"中無陰乎"              { OUTPUT_TOKEN("EXP_LOGIC &&"); }
"不大於"                { OUTPUT_TOKEN("EXP_LOGIC <="); }
"不小於"                { OUTPUT_TOKEN("EXP_LOGIC >="); }
"大於"                  { OUTPUT_TOKEN("EXP_LOGIC >"); }
"小於"                  { OUTPUT_TOKEN("EXP_LOGIC <"); }
"不等於"                { OUTPUT_TOKEN("EXP_LOGIC !="); }
"等於"                  { OUTPUT_TOKEN("EXP_LOGIC =="); }

"今有"|"吾有"           { OUTPUT_TOKEN("HERE_ARE %s", yytext); }
"有"                    { OUTPUT_TOKEN("HERE_IS_A %s", yytext); }
"名之曰"                { OUTPUT_TOKEN("NAME_IT %s", yytext); }
"曰"                    { OUTPUT_TOKEN("SAID %s", yytext); }
"昔之"                  { OUTPUT_TOKEN("PAST %s", yytext); }
"者"                    { OUTPUT_TOKEN("TOPIC %s", yytext); }
"今"                    { OUTPUT_TOKEN("SET %s", yytext); }
"其"                    { OUTPUT_TOKEN("ITS %s", yytext); }
"是矣"                  { OUTPUT_TOKEN("IS_THUS %s", yytext); }

"術"                    { OUTPUT_TOKEN("VAR_TYPE_FUNC %s", yytext); }
"爻"|"數"|"言"|"長"|"元"|"列" { OUTPUT_TOKEN("VAR_TYPE %s", yytext); }

"若非"                  { OUTPUT_TOKEN("ELSE %s", yytext); }
"或若"                  { OUTPUT_TOKEN("ELSE_IF %s", yytext); }
"若"                    { OUTPUT_TOKEN("IF %s", yytext); }
"恆為是"                { OUTPUT_TOKEN("WHILE_TRUE %s", yytext); }
"為是"                  { OUTPUT_TOKEN("FOR %s", yytext); }
"遍"                    { OUTPUT_TOKEN("TIMES %s", yytext); }
"乃止"                  { OUTPUT_TOKEN("BREAK %s", yytext); }
"乃得"                  { OUTPUT_TOKEN("RETURN %s", yytext); }
"云云"|"也"|"矣"        { OUTPUT_TOKEN("END %s", yytext); }

"欲行是術"              { OUTPUT_TOKEN("TO_PERFORM_FUNC %s", yytext); }
"必先得"                { OUTPUT_TOKEN("REQUIRE_ARGS %s", yytext); }
"乃行是術曰"|"乃是術曰"   { OUTPUT_TOKEN("FUNC_BEGIN %s", yytext); }
"是謂"                    { OUTPUT_TOKEN("FUNC_END_FOR %s", yytext); }
"之術也"                { OUTPUT_TOKEN("FUNC_END %s", yytext); }

"施"                    { OUTPUT_TOKEN("CALL %s", yytext); }
"之長"                  { OUTPUT_TOKEN("LENGTH %s", yytext); }
"之"                    { OUTPUT_TOKEN("INDEX %s", yytext); }
"充"                    { OUTPUT_TOKEN("PUSH %s", yytext); }
"書之"                  { OUTPUT_TOKEN("PRINT %s", yytext); }
"夫"                    { OUTPUT_TOKEN("THOSE %s", yytext); }
"取"                    { OUTPUT_TOKEN("TAKE %s", yytext); }
"注曰"|"疏曰"|"批曰"    { OUTPUT_TOKEN("COMMENT %s", yytext); }

{digit}+"\xC2\xB7"{digit}+ {
    ScientificNotation sci;
    chineseToArabic(yytext, &sci);
    OUTPUT_TOKEN("NUMBER_LIT %g", sciToDouble(&sci));
}

{digit}+ {
    ScientificNotation sci;
    chineseToArabic(yytext, &sci);
    OUTPUT_TOKEN("NUMBER_LIT %lld", (long long)sciToInt32(&sci));
}

"。"|"，"|"、"          { g_is_tok_start_set = 0; }
[ \t]+                  { g_is_tok_start_set = 0; }
\r?\n                   { handle_newline(); g_is_tok_start_set = 0; }
{UTF8_BOM}              { g_is_tok_start_set = 0; g_utf8_col = 0; g_utf8_len = 0; }

<<EOF>>                 { yyterminate(); }

{ALL_UTF8}              { OUTPUT_TOKEN("UNKNOWN CHAR %s", yytext); }
.                       { OUTPUT_TOKEN("UNKNOWN CHAR %s", yytext); }

%%

int yywrap(void) {
    return 1;
}