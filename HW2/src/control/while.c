//
// Created by Wavjaby on 2026/3/27.
//

#include "while.h"

#include <stdarg.h>
#include <WJCL/string/wjcl_string.h>

#include "lib/code_gen.h"
#include "../compiler_util.h"
#include "scope.h"

bool code_whileLoopStart() {
    compilerLog("> (while loop)\n");

    const ScopeData* scope = scope_pushType(SCOPE_WHILE_LOOP);

    buffPrintln(&ctx->code, "");
    buffPrintln(&ctx->code, "br label %%loop%d.body", scope->id);
    buffPrintlnS(&ctx->code, "loop%d.body:", scope->id);

    return false;
}

bool code_whileLoopEnd(Object* obj) {
    const ScopeData* scope = scope_peek();

    buffPrintln(&ctx->code, "br label %%loop%d.body", scope->id);
    buffPrintlnS(&ctx->code, "loop%d.exit:", scope->id);
    buffPrintln(&ctx->code, "");

    scope_dump();
    compilerLog("< (while loop end)\n");
    return false;
}

bool code_break() {
    // 找到最近的迴圈 scope；不在迴圈內則報錯
    const ScopeData* loopScope = scope_findNearestLoop();
    if (!loopScope) {
        yyerrorf("乃止當在循環之內\n");
        return true;
    }
    // 跳到該迴圈的 exit 標籤（while/for 收尾皆使用 loop<id>.exit）
    compilerLog("break (loop%d)\n", loopScope->id);
    buffPrintln(&ctx->code, "br label %%loop%d.exit", loopScope->id);
    return false;
}
