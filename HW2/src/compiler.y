/* Definition section */
%code requires {
    # define YYLTYPE_IS_DECLARED 1
    # define YYLTYPE_IS_TRIVIAL 1
}

%{
    #include "compiler_util.h"
    #include "main.h"
    #include "expression.h"
    #include "value_data.h"
    #include "scope.h"
    #include "control/for.h"
    #include "control/if.h"
    #include "control/while.h"
    #include "control/function.h"

    /* 解析過程中跨規則共享的暫存狀態（用於多值宣告、陣列 push、函式呼叫） */
    static ValueData*    curValData     = NULL;            /* 當前正在組裝的宣告容器 */
    static ValueData     curValDataStore;                  /* 容器實體（curValData 多指向此處） */
    static Object*       curPushArr     = NULL;            /* 「充」的目標陣列 */
    static FuncCallInfo* curFuncCall    = NULL;            /* 當前函式呼叫資訊 */
    static ObjectType    curFuncArgType = OBJECT_TYPE_UNDEFINED; /* 函式定義時的參數型別 */

    /* 深拷貝一個語意值，讓 ctx->last_result / 容器等能安全持有副本 */
    static Object cloneObjectValue(const Object* obj) {
        Object clone = *obj;
        if (obj->type == OBJECT_TYPE_STR && obj->value.str)
            clone.value.str = strdup(obj->value.str);
        else if (ObjectType_isNumber(obj->type) && obj->value.number)
            clone.value.number = cloneStruct(ScientificNotation, obj->value.number);
        else if (obj->type == OBJECT_TYPE_REGISTER && obj->value.symbol)
            clone.value.symbol = symbol_clone(obj->value.symbol);
        return clone;
    }
%}

%define parse.error custom
%locations

/* Variable or self-defined structure */
%union {
    ObjectType var_type;

    bool b_var;
    ScientificNotation n_var;
    char *s_var;

    Object obj_val;
    ValueData val_data;

    FuncCallInfo* func_call;

    bool exp_left;
    ExpOp exp_op;
}

/* ── 終結符（Token）宣告 ── 純關鍵字無攜帶值，其餘對應 %union 欄位 ── */
%token COMMENT
%token HERE_ARE HERE_IS_A SAID NAME_IT
%token PRINT CALL TO_CALL
%token RETURN BREAK
%token PAST TOPIC SET ITS IS_THUS
%token IF ELSE_IF ELSE WHILE_TRUE FOR TIMES END
%token TO_PERFORM_FUNC REQUIRE_ARGS FUNC_BEGIN FUNC_END_FOR FUNC_END
%token THOSE TAKE PUSH LENGTH

%token <n_var> NUMBER_LIT
%token <b_var> BOOL_LIT
%token <var_type> VAR_TYPE VAR_TYPE_FUNC
%token <s_var> STR_LIT IDENT
%token <exp_op> EXP_MATH_OP EXP_MATH_MOD_OP EXP_LOGIC_OP EXP_BINARY_LOGIC_OP
%token <exp_left> EXP_PREPOSITION

/* 「之」索引：左結合 */
%left INDEX

/* ── 帶回傳值的非終結符 ── */
%type <val_data> CreateValueDataListStmt
%type <val_data> FuncCallStmt
%type <obj_val> ValueStmt LitOrVarStmt ValueLiteralStmt VariableStmt ExpressionChainStmt ExpressionStmt ExpressionNextStmt ValueLiteralOrLastStmt

/* ReturnStmt 的優先序：解決 RETURN 與運算式之間的 shift/reduce */
%nonassoc LOWER_THAN_EXPR
%nonassoc RETURN

/* Yacc will start at this nonterminal */
%start Program
%%
/* Grammar section */

/* Scope */
Program
    : GlobalScopeStmt
;

GlobalScopeStmt
    : BodyListStmt
;

/* Scope Body */
BodyListStmt
    : BodyListStmt BodyStmt
    |
;

BodyStmt
    : COMMENT STR_LIT
    | OperationStmt
    | ConditionStmt
    | FunctionStmt
;

/* ───────────────────────── 函式定義 ─────────────────────────
 * 結構：吾有一術 名之曰「f」 欲行是術 [必先得 …參數…] 乃行是術曰 …本體… 是謂「f」之術也
 * 透過 mid-rule action 在登錄符號後立刻 push context/scope，本體結束再 pop。
 * 參數型別經由跨規則的 curFuncArgType 傳遞。
 */
FunctionStmt
    : HERE_ARE NUMBER_LIT VAR_TYPE_FUNC NAME_IT IDENT {
        $<obj_val>$ = func_define(&$2, $5);
      } TO_PERFORM_FUNC FunctionArgsStmt FUNC_BEGIN {
        func_defineBody();
      } BodyListStmt FUNC_END_FOR IDENT FUNC_END {
        func_defineBodyEnd(&$<obj_val>6, $13);
      }
;

FunctionArgsStmt
    : REQUIRE_ARGS FunctionArgListStmt
    |
;

FunctionArgListStmt
    : NUMBER_LIT VAR_TYPE {
        curFuncArgType = $2;
      } SAID IDENT {
        func_defineAddParam(curFuncArgType, $5);
      }
    | FunctionArgListStmt SAID IDENT {
        func_defineAddParam(curFuncArgType, $3);
      }
;

/* ───────────────────── 控制流（IF / WHILE / FOR） ─────────────────────
 * 每種分支都有對應的開始與結束 IR 呼叫；else-if 與 else 皆為可選。
 */
ConditionStmt
    : IF ExpressionStmt TOPIC {
        code_if(&$2);
      } BodyListStmt ElseIfStmt ElseStmt END {
        code_ifEnd();
      }
    | WHILE_TRUE {
        code_whileLoopStart();
      } BodyListStmt END {
        code_whileLoopEnd(NULL);
      }
    | FOR ValueStmt TIMES {
        code_forLoop(&$2);
      } BodyListStmt END {
        code_forLoopEnd(NULL);
      }
;

ElseIfStmt
    : ElseIfStmt ELSE_IF {
        code_elseIfLabel();
      } ExpressionStmt TOPIC {
        code_elseIf(&$4);
      } BodyListStmt
    |
;

ElseStmt
    : ELSE {
        code_else();
      } BodyListStmt
    |
;

/* ───────────────────────── 操作語句 ─────────────────────────
 * 變數宣告 / 命名 / 賦值 / 函式呼叫 / 陣列 push / 印出 / return。
 */
OperationStmt
    /* 宣告 + 命名（未顯式賦值者由 AddDefaults 補零值） */
    : CreateValueDataListStmt {
        curValData = &$1;
        object_ValueDataListAddDefaults(&$1, &@1);
      } VariableDefineStmt {
        object_ValueDataListFree(&$1);
        curValData = NULL;
      }
    /* 宣告值後直接印出 */
    | CreateValueDataListStmt PRINT {
        YYLTYPE printLoc = @2;
        code_stdoutPrint(&$1, true, &printLoc);
        object_ValueDataListFree(&$1);
      }
    /* 宣告值後回傳 */
    | CreateValueDataListStmt RETURN {
        code_returnValue(&$1);
        curValData = NULL;
      }
    /* 運算式結果 + 命名 */
    | ExpressionChainStmt {
        object_ValueDataListCreate(object_getValueType(&$1), NULL, &curValDataStore);
        object_ValueDataListAdd(&curValDataStore, &$1, &@1);
        curValData = &curValDataStore;
      } VariableDefineStmt {
        object_ValueDataListFree(&curValDataStore);
        curValData = NULL;
      }
    /* 運算式結果 取第 N 個 以施 變數（後置函式呼叫）+ 命名 */
    | ExpressionChainStmt {
        object_ValueDataListCreate(object_getValueType(&$1), NULL, &curValDataStore);
        object_ValueDataListAdd(&curValDataStore, &$1, &@1);
        curValData = &curValDataStore;
      } TAKE NUMBER_LIT TO_CALL VariableStmt {
        func_takeAndCall(&$4, &$6, &curValDataStore, &@3);
        object_free(&$6);
      } VariableDefineStmt {
        object_ValueDataListFree(&curValDataStore);
        curValData = NULL;
      }
    /* 昔之「v」者，今 expr 是矣 —— 賦值 */
    | ExpressionChainStmt PAST VariableStmt TOPIC SET ITS IS_THUS {
        yylloc = @3;
        code_assign(&$3, &$1);
      }
    /* 運算式結果直接印出 */
    | ExpressionChainStmt PRINT {
        ValueData valData;
        ScientificNotation one = {.type = I32, .fraction = 1, .fractionLen = 0, .exp = 0};
        object_ValueDataListCreate(object_getValueType(&$1), &one, &valData);
        object_ValueDataListAdd(&valData, &$1, &@1);
        YYLTYPE printLoc = @2;
        code_stdoutPrint(&valData, true, &printLoc);
        object_ValueDataListFree(&valData);
      }
    /* 運算式結果丟棄 */
    | ExpressionChainStmt {
        object_free(&$1);
      }
    /* 單值印出 */
    | ValueStmt PRINT {
        YYLTYPE printLoc = @1;
        printLoc.first_column = @1.last_column + 2;
        printLoc.last_column = printLoc.first_column;
        printLoc.first_column_byte = @1.last_column_byte + 2;
        printLoc.last_column_byte = printLoc.first_column_byte;
        yylloc = printLoc;
        ValueData valData;
        ScientificNotation one = {.type = I32, .fraction = 1, .fractionLen = 1, .exp = 0};
        object_ValueDataListCreate(object_getValueType(&$1), &one, &valData);
        object_ValueDataListAdd(&valData, &$1, &@1);
        code_stdoutPrint(&valData, true, &printLoc);
        object_ValueDataListFree(&valData);
      }
    /* 單值 + 命名 */
    | ValueStmt {
        object_ValueDataListCreate(object_getValueType(&$1), NULL, &curValDataStore);
        object_ValueDataListAdd(&curValDataStore, &$1, &@1);
        curValData = &curValDataStore;
      } VariableDefineStmt {
        object_ValueDataListFree(&curValDataStore);
        curValData = NULL;
      }
    /* 昔之「v」者，今 literal/其 是矣 —— 賦值 */
    | PAST VariableStmt TOPIC SET ValueLiteralOrLastStmt IS_THUS {
        yylloc = @6;
        code_assign(&$2, &$5);
      }
    /* 充「arr」以 v…（陣列 push） */
    | PUSH VariableStmt {
        curPushArr = &$2;
      } PushValueList {
        object_free(&$2);
        curPushArr = NULL;
      }
    /* 函式呼叫結果印出 */
    | FuncCallStmt PRINT {
        YYLTYPE printLoc = @2;
        code_stdoutPrint(&$1, true, &printLoc);
        object_ValueDataListFree(&$1);
      }
    /* 函式呼叫結果命名 */
    | FuncCallStmt {
        curValData = &$1;
        object_ValueDataListAddDefaults(&$1, &@1);
      } VariableDefineStmt {
        object_ValueDataListFree(&$1);
        curValData = NULL;
      }
    /* 乃得 v（回傳一值） */
    | RETURN ValueStmt {
        code_return(&$2);
      }
    /* 乃止（break） */
    | BREAK {
        code_break();
      }
;

CreateValueDataListStmt
    /* 吾有三數… —— 帶數量的多值宣告 */
    : HERE_ARE NUMBER_LIT VAR_TYPE {
        object_ValueDataListCreate($3, &$2, &curValDataStore);
        curValData = &curValDataStore;
      } SaidValueList {
        $$ = curValDataStore;
      }
    /* 有數… —— 單值宣告（無初始值，後續 SaidValueList 為空） */
    | HERE_IS_A VAR_TYPE {
        object_ValueDataListCreate($2, NULL, &curValDataStore);
        curValData = &curValDataStore;
      } SaidValueList {
        $$ = curValDataStore;
      }
    /* 有數 v —— 單值宣告附初始值 */
    | HERE_IS_A VAR_TYPE ValueStmt {
        object_ValueDataListCreate($2, NULL, &$$);
        curValData = &$$;
        object_ValueDataListAdd(&$$, &$3, &@3);
        object_free(&$3);
      }
;

VariableDefineStmt
    : NAME_IT IDENT {
        code_createVariable(curValData, $2, &@2);
      }
    | VariableDefineStmt SAID IDENT {
        code_createVariable(curValData, $3, &@3);
      }
;

/* 曰 v 曰 v … —— 多值宣告的初始值清單（curValData 為當前容器） */
SaidValueList
    : SaidValueList SAID ValueStmt {
        object_ValueDataListAdd(curValData, &$3, &@3);
        object_free(&$3);
      }
    | SaidValueList SAID ValueStmt TAKE NUMBER_LIT TO_CALL VariableStmt {
        object_ValueDataListAdd(curValData, &$3, &@3);
        func_takeAndCall(&$5, &$7, curValData, &@4);
        object_free(&$3);
        object_free(&$7);
      }
    |
;

/* 以 v 以 v …（陣列 push 的值清單） */
PushValueList
    : EXP_PREPOSITION ValueStmt {
        code_arrayPush(curPushArr, &$2, &@2);
      }
    | PushValueList EXP_PREPOSITION ValueStmt {
        code_arrayPush(curPushArr, &$3, &@3);
      }
;

/* 施「f」以 a 以 b …（前置函式呼叫），結果以 ValueData 形式回傳 */
FuncCallStmt
    : CALL VariableStmt {
        curFuncCall = func_callInit(&$2);
      } FuncCallArgList {
        linkedList_init(&$$.valueList);
        $$.valueType = OBJECT_TYPE_AUTO;
        $$.count = 0;
        if (curFuncCall)
            func_call(curFuncCall, &$2, &$$, &@1);
        curFuncCall = NULL;
        object_free(&$2);
      }
;

FuncCallArgList
    : FuncCallArgList EXP_PREPOSITION ValueStmt {
        if (curFuncCall)
            func_callArgAdd(curFuncCall, &$3, &@3);
        object_free(&$3);
      }
    |
;

/* ───────────────────── 運算式（四則 / 邏輯，可鏈式） ─────────────────────
 * 鏈式首項用 code_expression，後續項用 code_expressionChain；ctx->last_result 持有最近結果供「其」引用。
 */
ExpressionChainStmt
    : ExpressionStmt {
        $$ = $1;
        ctx->last_result = cloneObjectValue(&$1);
      }
    | ExpressionChainStmt ExpressionNextStmt {
        object_free(&$1);
        $$ = $2;
        ctx->last_result = cloneObjectValue(&$2);
      }
;

ExpressionStmt
    /* 加 b 於 a / 以 a 加 b 等（EXP_PREPOSITION 決定方向） */
    : EXP_MATH_OP ValueStmt EXP_PREPOSITION ValueStmt {
        $$ = code_expression($1, $3, &$2, &$4, &@2, &@4);
      }
    /* 除 b 於 a 所餘幾何（取餘數） */
    | EXP_MATH_OP ValueStmt EXP_PREPOSITION ValueStmt EXP_MATH_MOD_OP {
        $$ = code_expressionMod($1, $5, $3, &$2, &$4, &@1, &@5);
      }
    /* a 大於 b 等比較運算 */
    | ValueStmt EXP_LOGIC_OP ValueStmt {
        $$ = code_expression($2, true, &$1, &$3, &@1, &@3);
      }
    /* 夫 a b 中有陽乎 / 中無陰乎（二元邏輯） */
    | THOSE ValueStmt ValueStmt EXP_BINARY_LOGIC_OP {
        $$ = code_expression($4, true, &$2, &$3, &@2, &@3);
      }
    /* 函式呼叫作為運算元 */
    | FuncCallStmt {
        Object* obj = object_ValueDataListPop(&$1);
        $$ = obj ? *obj : (Object){.type = OBJECT_TYPE_UNDEFINED};
        free(obj);
        object_ValueDataListFree(&$1);
      }
;

ExpressionNextStmt
    : EXP_MATH_OP ValueLiteralOrLastStmt EXP_PREPOSITION ValueLiteralOrLastStmt {
        $$ = code_expressionChain($1, $3, &$2, &$4, &@2, &@4);
      }
    | EXP_MATH_OP ValueLiteralOrLastStmt EXP_PREPOSITION ValueLiteralOrLastStmt EXP_MATH_MOD_OP {
        $$ = code_expressionChainMod($1, $5, $3, &$2, &$4, &@1, &@5);
      }
;

ValueLiteralOrLastStmt
    : ValueStmt
    | ITS {
        $$ = cloneObjectValue(&ctx->last_result);
      }
;

/* ───────────────────── 值 / 字面值 / 變數查找 ─────────────────────
 * 「其」取 ctx->last_result；陣列索引（之）與長度（之長）為 ValueStmt 的延伸。
 */
ValueStmt
    : LitOrVarStmt
    | ValueStmt INDEX ValueStmt {
        yylloc = @3;
        $$ = object_getIndex(&$1, &$3, &@1, &@3);
        object_free(&$1);
        object_free(&$3);
      }
    | ValueStmt LENGTH {
        $$ = code_getLength(&$1, &@2);
      }
    | THOSE ValueStmt {
        $$ = $2;
      }
    | ExpressionStmt
;

LitOrVarStmt
    : ValueLiteralStmt
    | VariableStmt
;

ValueLiteralStmt
    : STR_LIT {
        $$ = object_createStr($1);
      }
    | NUMBER_LIT {
        $$ = object_createNumber(&$1);
      }
    | BOOL_LIT {
        $$ = object_createBool($1);
      }
;

VariableStmt
    : IDENT {
        $$ = scope_findSymbol($1);
        free($1);
      }
;

%%

#include "compiler.h"
