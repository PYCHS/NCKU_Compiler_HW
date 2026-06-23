# NCKU 1142_編譯系統 COMPILER CONSTRUCTION 作業二 - 文言文 LLVM 編譯器

本作業以[作業一](https://github.com/WavJaby/NCKU_Compiler_HW1)的詞法分析器（`compiler.l`）為基礎，要求同學實作：
1. Yacc 語法規則（`compiler.y`）
2. 符號表管理（`scope.c` 兩個函式）
3. 物件系統（`object.c`、`value_data.c` 部分函式）
4. 語意動作核心（`main.c` 部分函式）
5. 控制流 IR 生成（`control/for.c`、`if.c`、`while.c`）
6. 函式定義符號登錄（`control/function.c` 兩個函式）

**工具函式庫（`lib/`）、Runtime（`wy_rt/`）已預先完整提供，同學無需實作。**

---

## 文件導覽

| 文件 | 用途 | 何時讀 |
|------|------|--------|
| [作業說明（HackMD）](https://hackmd.io/@WavJaby/NCKU_1142_COMPILER_HW2) | 作業說明、YACC 概念入門、四週進度 | **最先讀** |
| 本文件（`README.md`） | 環境建置、填空規格、工具函式速查 | 開始實作前通讀，實作中隨時查 |
| [`YACC_CHEATSHEET.md`](YACC_CHEATSHEET.md) | `compiler.y` 進階語法：`$<type>N`、`$0`/`$-1`、mid-rule action、shift/reduce 衝突除錯 | 寫 `compiler.y` 遇到問題時查 |
| [`LLVM_IR_CHEATSHEET.md`](LLVM_IR_CHEATSHEET.md) | 所有 IR 指令參考、phi 節點、if/for/while block 結構 | 實作 IR 生成函式時查 |

---

## 環境建置

### 取得作業檔案

```bash
git clone --recurse-submodules https://github.com/WavJaby/NCKU_Compiler_HW2.git
cd NCKU_Compiler_HW2
```

若已 clone 但忘記加 `--recurse-submodules`：

```bash
git submodule update --init
```

### 版本需求

| 工具 | 最低版本 | 說明 |
|------|---------|------|
| `cmake` | 3.10 | 建置系統 |
| `flex` | 2.6 | Lexer 生成器 |
| `bison` | 3.6 (≥ 3.8 for counterexample hints) | Parser 生成器 |
| `gcc` | C11 支援 | 編譯器與 linker |
| `llvm` / `llc` | 14 | IR → 執行檔 |

### Windows（MSYS2）

上次作業已安裝 MSYS2，開啟 **MSYS2 UCRT64** 終端機執行：

```bash
# 安裝所需工具（已裝過的可跳過）
pacman -S bison flex mingw-w64-ucrt-x86_64-cmake \
          mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-llvm

# 建置
cmake -B build -S . -G "MinGW Makefiles"
cmake --build build
```

> 請使用 **UCRT64** 終端機，不要用 MSYS 終端機，否則工具鏈路徑不相容。

### Linux（Ubuntu / Debian）

```bash
sudo apt install cmake flex bison gcc llvm

cmake -B build -S .
cmake --build build
```

### macOS

```bash
brew install cmake flex bison llvm

cmake -B build -S .
cmake --build build
```

### 測試建置是否成功

```bash
./test/test.sh -n    # -n 跳過重新 build，直接跑測試（初次請去掉 -n）
```

Windows 原生 PowerShell（不進 MSYS2）：

```powershell
.\test\test.ps1 -NoCompile   # -NoCompile 跳過重新 build
```

### 測試腳本選項（`test.sh` / `test.ps1`）

| 短選項 | PowerShell 參數 | 說明 |
|--------|----------------|------|
| `-f <name>` | `-File <name>` | 依檔名子字串篩選測試案例 |
| `-s` | `-Stop` | 遇到第一個失敗即停止 |
| `-n` | `-NoCompile` | 跳過 CMake 重新建置 |
| `-i` | `-Interactive` | 互動式 diff（透過 pager 翻頁） |
| `-b <dir>` | `-BuildDir <dir>` | 指定自訂 build 目錄 |

---

## 上次作業 `compiler.l` 需要調整的地方

本次提供的 `compiler.l` 起始檔包含：
- **`%{...%}` 段**：已預先更新，包含 Bison 所需的 include、`yylloc` 位置追蹤、錯誤字元緩衝機制
- **基礎規則**：`。`、`，`、空白、換行、EOF、非法字元——已提供
- **Token 規則區（TODO）**：空白，需要貼入你的 HW1 成果並做以下兩處調整

規則區沿用你 HW1 的成果，需要做兩件事：

### 1. 每條規則改為設定 `yylval` 並回傳 Token

把每條規則從 `PRINT_TOKEN(...)` 改為：
- 將 Token 攜帶的值寫入 `yylval` 的對應欄位
- 呼叫 `return TOKEN_NAME` 把 Token 回傳給 Bison

哪些 Token 需要寫 `yylval`、要寫哪個欄位，對照 `compiler.y` 頂部的 `%union` 定義與 `%token <欄位>` 宣告。  
沒有宣告 `<欄位>` 的純關鍵字 Token 只需要 `return`。

### 2. 新增與修改兩條規則

| 項目 | 說明 |
|------|------|
| 新增 `"以施"` | 對應 Token `TO_CALL`，函式後置呼叫語法（HW1 沒有這條） |
| 修改 `"乃得"` | 加入可選後綴「矣」，即 `"乃得""矣"?` |

---

## 檔案分工

### 入口 & 驅動

| 檔案 | 狀態 | 說明 |
|------|------|------|
| `src/wyc.c` | ✅ 完整提供 | 編譯器主程式入口、命令列參數處理 |
| `src/compiler.l` | ✏️ HW1 成果修改 | Flex 詞法規則（規則區改 yylval + return，`%{%}` 段已給） |
| `src/compiler.y` | ✏️ 填空 | Bison 語法規則與語意動作 |
| `src/compiler.h` | ✅ 完整提供 | `yyerror` 實作 |
| `src/compiler_util.c` / `.h` | ✅ 完整提供 | 錯誤訊息、編譯狀態、共用巨集 |

### 語意分析 & 符號表

| 檔案 | 狀態 | 說明 |
|------|------|------|
| `src/scope.c` / `.h` | ✏️ 填空 | 符號表（`scope_addSymbol`、`scope_findSymbol`） |
| `src/object.c` / `.h` | ✏️ 填空 | Object 值系統；陣列索引取值 IR（`object_getIndex`）已提供 |
| `src/object_type.h` | ✅ 完整提供 | 型別列舉（`ObjectType`） |
| `src/value_data.c` / `.h` | ✏️ 填空 | 多值宣告容器（`ValueData`） |
| `src/main.c` / `.h` | ✏️ 填空 | 語意動作核心函式 |
| `src/expression.c` / `.h` | ✏️ 填空 | 運算式 IR 生成（`code_expression`、`code_expressionChain` 等） |

### 控制流 IR 生成

| 檔案 | 狀態 | 說明 |
|------|------|------|
| `src/control/for.c` / `.h` | ✏️ 填空 | for 迴圈 IR 生成 |
| `src/control/if.c` / `.h` | ✏️ 填空 | if / else IR 生成 |
| `src/control/while.c` / `.h` | ✏️ 填空 | while 迴圈 IR 生成 |
| `src/control/function.c` / `.h` | ✅ 完整提供 | 所有 C 函式已提供；第四週工作在 `compiler.y` 的函式語法規則 |
| `src/control/function_info.h` | ✅ 完整提供 | `FuncInfo`、`FuncCallInfo`、`CapturedEntry` 結構定義 |
| `src/control/function_builtin.h` | ✅ 完整提供 | 內建函式定義 |

### 工具函式庫（`src/lib/`）

| 檔案 | 狀態 | 說明 |
|------|------|------|
| `src/lib/code_gen.c` / `.h` | ✅ 完整提供 | LLVM IR 輸出工具（`buffPrintln`、`ByteBuffer` 等） |
| `src/lib/byte_buffer.c` / `.h` | ✅ 完整提供 | 動態字串緩衝區 |
| `src/lib/chinese_number.c` / `.h` | ✅ 完整提供 | 中文數字轉換（`chineseToArabic`） |
| `src/lib/console_color.c` / `.h` | ✅ 完整提供 | 終端顏色輸出 |
| `src/lib/tab_width.h` | ✅ 完整提供 | Tab 寬度計算 |
| `src/lib/utf8_console.h` | ✅ 完整提供 | UTF-8 終端輸出輔助 |

### Runtime

| 檔案 | 狀態 | 說明 |
|------|------|------|
| `src/wy_rt/wy_rt.c` / `.h` | ✅ 完整提供 | 執行期函式庫（字串操作、陣列操作、print） |

### 外部函式庫（`lib/`）

| 目錄 | 說明 |
|------|------|
| `lib/WJCL/` | 資料結構庫（LinkedList、HashMap 等） |
| `lib/utf8.c/` | UTF-8 字串處理 |

---

## 填空模組說明

### 函式填空一覽

| 檔案 | 函式 | 類型 | 備註 |
|------|------|------|------|
| `compiler.y` | 語法規則（見下節） | 完全填空 | — |
| `scope.c` | `scope_addSymbol` | 部分填空 | 化簡版已提供（Quick Start 可用）；補重複符號檢查 |
| `scope.c` | `scope_findSymbol` | 部分填空 | 閉包跨 context 捕獲分支已提供；補 `searchCtx == ctx` 回傳 |
| `object.c` | `object_createStrConst` | ✅ 完整提供 | — |
| `object.c` | `object_createStr` | ✅ 完整提供 | — |
| `object.c` | `object_createArray` | ✅ 完整提供 | — |
| `object.c` | `object_createNumber` | ✅ 完整提供 | — |
| `object.c` | `object_createBool` | ✅ 完整提供 | — |
| `object.c` | `object_loadRegAndPromote` | ✅ 完整提供 | 取得運算元字串並做型別升級（NUM→I32 等）；`code_expression` 等填空函式的必備工具 |
| `object.c` | `object_nameLiteralOrLoadReg` | 部分填空 | SYMBOL 一般 load / I32/I64/F64 / BOOL / STR 已提供；補 REGISTER（Week 2）、capturedIndex / funcArg / FUNC（Week 4） |
| `value_data.c` | `object_ValueDataListCreate` | 部分填空 | 化簡版已提供（Quick Start 可用）；補 count 驗證 |
| `value_data.c` | `object_ValueDataListAdd` | 部分填空 | 化簡版已提供（Quick Start 可用）；補型別檢查與 count 上限 |
| `value_data.c` | `object_ValueDataListAddDefaults` | 完全填空 | 各型別補零值（`02_流轉_易值` 起需要） |
| `value_data.c` | `object_ValueDataListPop` | ✅ 完整提供 | — |
| `value_data.c` | `object_ValueDataListFree` | ✅ 完整提供 | — |
| `main.c` | `code_stdoutPrintObject` | 部分填空 | `object_nameLiteralOrLoadReg` 呼叫與 BOOL 分支已提供；補 I32/I64/F64/STR 的 `@printf` 呼叫 |
| `main.c` | `code_stdoutPrint` | ✅ 完整提供 | — |
| `main.c` | `code_createVariable` | 部分填空 | 化簡版已提供（Quick Start 可用）；補 `object_nameLiteralOrLoadReg` 支援符號引用與非數字型別 |
| `main.c` | `code_assign` | 完全填空 | dest 型別驗證已提供；其餘全部填空 |
| `main.c` | `code_getLength` | 完全填空 | 型別驗證已提供；其餘全部填空 |
| `main.c` | `code_arrayPush` | ✅ 完整提供 | — |
| `expression.c` | `object_sameRegister` | ✅ 完整提供 | static helper |
| `expression.c` | `isExpressionOperationLegal` | ✅ 完整提供 | static helper |
| `expression.c` | `code_expression` | 部分填空 | 型別推導（`getPromotedType`）已提供；補暫存器分配、opLeft 方向判斷、運算元載入、IR 指令、回傳 |
| `expression.c` | `code_expressionMod` | ✅ 完整提供 | thin wrapper，含除法前置檢查 |
| `expression.c` | `code_expressionChain` | ✅ 完整提供 | thin wrapper |
| `expression.c` | `code_expressionChainMod` | ✅ 完整提供 | thin wrapper |
| `control/for.c` | `code_forLoop` | 完全填空 | undefined 檢查已提供 |
| `control/for.c` | `code_forLoopEnd` | 完全填空 | — |
| `control/if.c` | `code_if` | 完全填空 | compilerLog 已提供 |
| `control/if.c` | `code_elseIfLabel` | 完全填空 | — |
| `control/if.c` | `code_elseIf` | 完全填空 | compilerLog 已提供 |
| `control/if.c` | `code_else` | 完全填空 | — |
| `control/if.c` | `code_ifEnd` | 完全填空 | — |
| `control/while.c` | `code_whileLoopStart` | ✅ 完整提供 | — |
| `control/while.c` | `code_whileLoopEnd` | ✅ 完整提供 | — |
| `control/while.c` | `code_break` | 完全填空 | 引導式 TODO：先讀 `scope_findNearestLoop`、已提供的 whileLoopEnd/forLoopEnd，再實作（約 4 行） |
| `control/function.c` | `func_define` | ✅ 完整提供 | — |
| `control/function.c` | `func_defineAddParam` | ✅ 完整提供 | — |
| `control/function.c` | `func_defineBodyEnd` | ✅ 完整提供 | — |
| `control/function.c` | `code_return` | ✅ 完整提供 | — |

**各檔案完整提供的函式（不需填空）：**

| 檔案 | 完整提供的函式 |
|------|--------------|
| `scope.c` | `scope_push*`、`scope_dump`、`scope_peek`、`scope_getFunction`、`scope_findNearestLoop`、`context_push`、`context_pop`、`scope_free_all` 等 |
| `object.c` | `object_loadRegAndPromote`、`object_getIndex`、`object_packAsPtr`、`object_createRegisterSymbol`、`object_print`、`object_free`、`object_getValueType`、`object_getPromotedType`、`symbol_clone`、`symbol_freeReg`、`symbol_freeSelf` 等 |
| `main.c` | `code_arrayPush`、`writeOutputHeader`、`writeOutputMain`、`freeAll`、`main` |
| `control/while.c` | `code_whileLoopStart`、`code_whileLoopEnd` |
| `control/function.c` | `func_defineBody`、`func_defineBodyEnd`、`code_return`、`code_returnValue`、`func_callInit`、`func_callArgAdd`、`func_call`、`func_takeAndCall` |

---

## 工具函式速查

填空時會直接呼叫的框架函式／巨集。

### IR 輸出

| 函式 | 用途 | 備註 |
|------|------|------|
| `buffPrintln(&ctx->code, fmt, ...)` | 向當前 context 的 IR 緩衝寫一行 | `%` 需寫 `%%`；縮排自動依 scope 層級 |
| `compilerLog(fmt, ...)` | 輸出 verbose 日誌（`-v` 時顯示，含位置前綴） | 格式同 printf |
| `lexerLog(fmt, ...)` | 輸出 lexer token 日誌（`-l` 時顯示，含位置前綴） | 僅用於 `.l` 規則區；`-v` 不顯示 |

### 符號表 / HashMap

| 函式 | 用途 |
|------|------|
| `map_putpp(&map, key, value)` | 插入 key/value（均為指標）；重複 key 會覆蓋 |
| `map_get(&map, key)` | 查找，找不到回傳 NULL |

### LinkedList

| 函式 | 用途 |
|------|------|
| `linkedList_init(&list)` | 分配 sentinel 節點並初始化；list 變數宣告後**必須** init 才能使用 |
| `linkedList_addp(&list, freeFlag, ptr)` | 加在尾端；`freeFlag=1` 表示 deleteNode 時自動 `free(value)`，`0` 則不自動 free |
| `linkedList_deleteNode(&list, node)` | 刪除指定節點（**不**釋放 value，除非 freeFlag=1） |
| `linkedList_freeA(&list, freeFn)` | 逐一用 freeFn 釋放 value 後釋放所有節點（含 sentinel）；free 後不可再使用 |
| `linkedList_foreach(&list, node)` | 迴圈巨集，`node` 為當前 `LinkedListNode*`，從頭到尾走訪 |

### 記憶體 / 字串

| 函式 | 用途 |
|------|------|
| `cloneStruct(Type, ptr)` | `malloc(sizeof(Type))` + `memcpy`，回傳新指標 |
| `sciToStr(sn)` | `ScientificNotation*` → 堆積字串，呼叫端須 `free()` |
| `strdup(s)` | 複製 C 字串到新分配的記憶體（標準 POSIX） |

### Object 操作

#### `object_nameLiteralOrLoadReg` — 核心運算元轉換（部分填空）

```c
Object object_nameLiteralOrLoadReg(const Object* src, char* buffer, size_t bufferLen);
```

接收任意 `Object`，把它轉成 LLVM IR 可直接貼上的運算元字串，寫入 `buffer`，並回傳一個代表「已就緒值」的 Object。

幾乎所有語意動作都需要先透過這個函式（或包裝它的 `object_loadRegAndPromote`）才能使用 Object 的值。

| `src->type` | buffer 寫入 | 回傳 | 週次 |
|-------------|------------|------|------|
| `REGISTER` | `%%reg<name>` | `*src`（不複製） | **Week 2 TODO** |
| `SYMBOL`（一般變數） | `%%reg<N>` | 新 REGISTER（`cloneStruct`） | ✅ 已提供；輸出 `load` IR |
| `SYMBOL`（capturedIndex≥0） | `%%upval.<idx>` | 新 REGISTER（`symbol_clone`） | Week 4 TODO |
| `SYMBOL`（funcArg） | `%%var.<idx>`，無 load | 新 REGISTER（`symbol_clone`） | Week 4 TODO |
| `SYMBOL`（FUNC type） | `@func_<ctxId>_<idx>` | 新 REGISTER（`symbol_clone`） | Week 4 TODO |
| `I32 / I64 / F64` | 數字字串 | `*src` | ✅ 已提供 |
| `BOOL` | `0` 或 `1` | `*src` | ✅ 已提供 |
| `STR` | `@str.<N>`（寫入 constBuff） | `*src` | ✅ 已提供 |

**記憶體規則**：
- 回傳 REGISTER 且 `src->type == OBJECT_TYPE_SYMBOL` → 回傳值是新分配的，**用完需 `object_free`**
- 其他情況回傳 `*src`（借用），**不要** free 回傳值

#### 其他 Object 工具

| 函式 | 簽名 | 用途 |
|------|------|------|
| `object_loadRegAndPromote` | `(src, targetType, buffer, bufferLen)` | 呼叫 `object_nameLiteralOrLoadReg` 後視需要升級型別（I32→I64、I32→F64 等）；大多數需要型別一致的 IR 指令（`add`、`icmp` 等）用這個而不是直接呼叫上面的函式 |
| `scope_dump` | `()` | 彈出當前 scope（`-v` 模式印出符號表）；for/if/while/function 結尾都要呼叫 |
| `object_createRegisterSymbol` | `(type)` | 分配下一個暫存器編號，回傳 `SymbolData`（非指標）；用於 IR 指令的 LHS |

### 錯誤回報

| 函式 | 用途 |
|------|------|
| `yyerrorf(fmt, ...)` | 報語意錯誤（不含位置），設 `compileError = true` |
| `yyerrorlf(fmt, loc, ...)` | 同上，但附上 `YYLTYPE` 位置資訊 |

> `yyerrorf` / `yyerrorlf` **不會自動停止解析**，需自行加 `YYABORT`（見 YACC_CHEATSHEET.md §YYABORT）。

### LLVM 內建函式與全域常數

`writeOutputHeader` 在輸出的 IR 開頭宣告了以下內容，填空時可直接引用。

**`@printf` 格式字串**

命名規則：`@fmt_<llvmType>[_n]`，`_n` = 附換行（`\n`）。

| 全域常數 | 對應 C 格式 | 適用型別 |
|---------|------------|---------|
| `@fmt_i32` / `@fmt_i32_n` | `%d` | I32 |
| `@fmt_i64` / `@fmt_i64_n` | `%lld` | I64 |
| `@fmt_double` / `@fmt_double_n` | `%g` | F64 |
| `@fmt_ptr` / `@fmt_ptr_n` | `%s` | STR |

`llvmType` 與 `ObjectType` 的對應由 `objectType2llvmType[srcValueType]` 取得，可直接用在格式字串名稱裡：

```llvm
call i32 (ptr, ...) @printf(ptr @fmt_i32_n, i32 %reg0)
```

**布林輸出字串**

| 全域常數 | 內容 |
|---------|------|
| `@str_true` / `@str_true_n` | `陽` / `陽\n` |
| `@str_false` / `@str_false_n` | `陰` / `陰\n` |

搭配 `select` + `fwrite` 使用（`sizeof("陽") - 1` = 不含 null 的位元組數；附換行再 +1）。

**其他常數**

| 全域常數 | 說明 |
|---------|------|
| `@space` | 空格（1 byte），用 `@fwrite` 輸出值間空格 |

**`%g_stdout`**

`@main` 開頭從 `@stdout` load 出來的 `FILE*`，在整個 `@main` 內有效：

```llvm
%g_stdout = load ptr, ptr @stdout
```

`@fwrite` 簽名：`declare i64 @fwrite(ptr data, i64 size, i64 count, ptr stream)`

---

## Quick Start — 第一條語句

**目標**：讓下面這句產生 verbose output，確認語法分析、符號表、IR 生成的基本管道全部通順。

```
吾有一數。曰一。名之曰「甲」。
```

預期 verbose output（第一行由框架自動輸出）：

```
test/策問/00_快速入門.wy:1:2     |> (scope id: 0, type: SCOPE_MAIN)
test/策問/00_快速入門.wy:1:12    |    var 「甲」 <- 1
```

---

### Step 1 — 在 `OperationStmt` 直接寫規則（不拆子規則）

先把 `吾有一數。曰一。名之曰「甲」。` 對應的 token 序列**全部直接寫在 OperationStmt** 裡，不建立任何子 stmt：

| # | token | 對應文字 |
|---|-------|---------|
| $1 | `HERE_ARE` | 吾有（`"吾有"\|"今有"` → `HERE_ARE`；單獨的 `"有"` 才是 `HERE_IS_A`） |
| $2 | `NUMBER_LIT` | 一（宣告數量） |
| $3 | `VAR_TYPE` | 數 |
| $4 | `SAID` | 曰（值跟在後面） |
| $5 | `NUMBER_LIT` | 一（初始值） |
| $6 | `NAME_IT` | 名之曰（`"名之曰"` 是單一 token，曰 已包含在內） |
| $7 | `IDENT` | 「甲」（`VariableDefineStmt` 的第一個 IDENT 不需要前置 SAID） |

> **注意**：Quick Start 完成後，這些 token 序列會被移入子規則（`CreateValueDataListStmt`、`ValueLiteralStmt`、`VariableDefineStmt`）。OperationStmt 只是第一步的暫存地，之後需要重構。

將以下規則寫入 `compiler.y` 的 `OperationStmt`：

```yacc
OperationStmt
    : HERE_ARE NUMBER_LIT VAR_TYPE SAID NUMBER_LIT NAME_IT IDENT {
        ValueData valData;
        object_ValueDataListCreate($<var_type>3, &$<n_var>2, &valData); /* 建容器：type=數, count=一 */
        Object num = object_createNumber(&$<n_var>5);                   /* 包裝初始值 一 */
        object_ValueDataListAdd(&valData, &num, &@5);                   /* 加入容器 */
        code_createVariable(&valData, $<s_var>7);                       /* 建變數、輸出 IR + verbose */
        object_ValueDataListFree(&valData);                             /* 釋放容器 */
    }
;
```

各 `$N` 對應：

| `$N` | token | 取值方式 | 說明 |
|------|-------|----------|------|
| `$2` | `NUMBER_LIT` | `$<n_var>2` | 宣告數量「一」（傳給 Create 的 count） |
| `$3` | `VAR_TYPE` | `$<var_type>3` | 型別「數」 |
| `$5` | `NUMBER_LIT` | `$<n_var>5` | 初始值「一」（傳給 createNumber） |
| `$7` | `IDENT` | `$<s_var>7` | 變數名「甲」（傳給 createVariable，函式內部會 free） |
| `@5` | — | `&@5` | token $5 的來源位置，用於錯誤訊息定位 |

`$<type>N` 手動標注的原因：`NUMBER_LIT` 已宣告 `%token <n_var>`，理論上 `$2` 直接可用；但 `VAR_TYPE` 等同理。只有當 token 沒有 `%token <欄位>` 宣告時才必須手動標注——此處標注是為了讓語意明確，也是往後寫其他規則的統一習慣。

---

### Step 2 — Quick Start 所需函式均已預先提供

Quick Start 階段**不需要實作任何 C 函式**，以下函式皆已提供化簡版可直接呼叫：

| 檔案 | 函式 | 化簡版限制（之後補） |
|------|------|---------------------|
| `scope.c` | `scope_addSymbol` | 無重複符號檢查 |
| `object.c` | `object_createNumber` 等 | 完整版，無限制 |
| `value_data.c` | `object_ValueDataList*` | 無型別檢查、無多值驗證 |
| `main.c` | `code_createVariable` | 僅支援數字字面值（不支援符號引用、布林、字串） |

`scope_findSymbol` 與 `object_nameLiteralOrLoadReg` 此步驟不需要。

---

### Step 3 — 驗收

```bash
./test/test.sh -f 00_快速入門
```

測試分兩部分：Part 1 比對 verbose 輸出、Part 2 比對執行結果。Quick Start 只實作了第一句，Part 1 會顯示 FAIL，但 diff 會顯示**已通過的行數**，可以看到進度。

確認 verbose diff 的前兩行出現即代表 Quick Start 完成：

```
test/策問/00_快速入門.wy:1:2     |> (scope id: 0, type: SCOPE_MAIN)
test/策問/00_快速入門.wy:1:12    |    var 「甲」 <- 1
```

---

## Quick Start Advanced — 讀變數 + 印出

**前提**：已完成 Quick Start，`甲` 已宣告在 scope 中。

**目標**：讓這句產生 verbose PRINT 輸出並印出實際值：

```
吾有一數。曰「甲」。書之。
```

預期 verbose output：

```
test/策問/00_快速入門.wy:2:11    |    PRINT: 「甲」
```

---

### Step 1 — 在 `OperationStmt` 新增一條規則

| # | token | 對應文字 |
|---|-------|---------|
| $1 | `HERE_ARE` | 吾有 |
| $2 | `NUMBER_LIT` | 一（宣告數量） |
| $3 | `VAR_TYPE` | 數 |
| $4 | `SAID` | 曰 |
| $5 | `IDENT` | 「甲」（變數名，需查符號表） |
| $6 | `PRINT` | 書之 |

```yacc
| HERE_ARE NUMBER_LIT VAR_TYPE SAID IDENT PRINT
    {
        ValueData valData;
        object_ValueDataListCreate($<var_type>3, &$<n_var>2, &valData);
        Object var = scope_findSymbol($<s_var>5);     /* 查符號表取得 甲 的 Object */
        if (var.type == OBJECT_TYPE_UNDEFINED) YYABORT;
        object_ValueDataListAdd(&valData, &var, &@5);
        code_stdoutPrint(&valData, true);             /* 已提供，內部呼叫 object_nameLiteralOrLoadReg */
        object_ValueDataListFree(&valData);
    }
```

> `scope_findSymbol` 回傳 `OBJECT_TYPE_SYMBOL`，`object_print` 對它輸出 `「甲」`，所以 verbose log 顯示 `PRINT: 「甲」`。

---

### Step 2 — 需實作的函式

**`scope_findSymbol` — 補 `searchCtx == ctx` 分支**

找到 `scope.c` 裡的 TODO，回傳格式參考已提供的閉包分支：

```c
return (Object){OBJECT_TYPE_SYMBOL, .capturedIndex = -1, .value.symbol = symbol};
```

> `object_nameLiteralOrLoadReg` 完整提供，包含所有型別分支，不需實作。

**`code_stdoutPrintObject` — 補 I32 的 printf 呼叫**

找到 `main.c` 的 TODO，在 `case OBJECT_TYPE_I32:` 的 `break` 前用 `buffPrintln` 輸出：

```
call i32 (ptr, ...) @printf(ptr @fmt_i32_n, i32 %regN)
```

- `objectType2llvmType[srcValueType]` 取得 LLVM 型別字串（`"i32"`）
- `newLine` 為 `true` 時用 `@fmt_i32_n`，否則用 `@fmt_i32`
- `regName` 即上一步 `object_nameLiteralOrLoadReg` 寫入的運算元字串
- 格式字串命名規則見 README.md §LLVM 內建函式與全域常數

> Quick Start Advanced 只需處理 I32（`一數`），I64/F64/STR 同理，留作第一週補完。

---

### Step 3 — 驗收

```bash
./test/test.sh -f 00_快速入門
```

verbose diff 全部通過、Part 2 輸出 `1` 即完成。

---

## Quick Start 之後 — 重構方向

Quick Start 的 `OperationStmt` 長規則是暫存結構，Week 1 第一步是把它拆進已有的子規則骨架。

### `BodyStmt` 分派（骨架已提供，不需修改）

```
BodyStmt → COMMENT STR_LIT
         | OperationStmt
         | ConditionStmt
         | FunctuonStmt
```

### 子規則骨架與 token 序列

以下 non-terminal 已在 `compiler.y` 骨架中宣告（空白規則），填空時補入 token 序列即可。

**`CreateValueDataListStmt`** — 已宣告 `%type <val_data>`，`$$` 即 ValueData 容器

| 語法 | token 序列 |
|------|-----------|
| 吾有一數（HERE_IS_A） | `HERE_IS_A VAR_TYPE` |
| 吾有三數（HERE_ARE） | `HERE_ARE NUMBER_LIT VAR_TYPE` |

semantic action: `object_ValueDataListCreate($<var_type>N, count_ptr, &$$)`

---

**`ValueLiteralStmt`** — 純字面值；需自行加 `%type <obj_val>`

| 語法 | token 序列 | semantic action |
|------|-----------|-----------------|
| 曰一（數字） | `NUMBER_LIT` | `object_createNumber` |
| 曰陽／曰陰（布林） | `BOOL_LIT` | `object_createBool` |
| 曰「你好」（字串） | `STR_LIT` | `object_createStr` |

> `ValueLiteralStmt` **不含** SAID；SAID 留在上層規則（`OperationStmt` 或 `LitOrVarStmt`）。

---

**`VariableStmt`** — IDENT 查符號表；需自行加 `%type <obj_val>`

| 語法 | token 序列 | semantic action |
|------|-----------|-----------------|
| 「甲」（變數引用） | `IDENT` | `scope_findSymbol($<s_var>1)` |

---

**`LitOrVarStmt`** — 字面值或 SAID + 變數引用（`SAID` 在此層消費）；需自行加 `%type <obj_val>`

| 語法 | token 序列 |
|------|-----------|
| 數字 / 布林 / 字串 | `SAID ValueLiteralStmt` |
| 變數引用 | `SAID VariableStmt` |

semantic action: `$$ = $2`（pass-through）

---

**`VariableDefineStmt`** — 命名，不需回傳值

| 語法 | token 序列 | 說明 |
|------|-----------|------|
| 名之曰「甲」 | `NAME_IT IDENT` | 第一個名稱 |
| 曰「乙」 | `SAID IDENT` | 後續名稱（多值宣告時重複） |

---

### 拆解後的 OperationStmt（單值宣告）

原 Quick Start 長規則對應到：

```
OperationStmt
    : CreateValueDataListStmt LitOrVarStmt { add $2 to $1; } VariableDefineStmt
      /* $1 = val_data；mid-rule action 將 $2 加入容器；VariableDefineStmt 透過 $<val_data>0 取容器 */
    | CreateValueDataListStmt LitOrVarStmt { add $2 to $1; } PRINT
      /* 印出語句：呼叫 code_stdoutPrint */
    ;
```

`VariableDefineStmt` 透過 `$<val_data>0` 取得左側 mid-rule action 存放的 `val_data`（`$0` 代表最近一個 mid-rule action 或 shift 的值）。

> **重要**：`%type` 宣告決定 `$$` 的型別；`ValueLiteralStmt`、`VariableStmt`、`LitOrVarStmt` 需在 `compiler.y` 頂部加上：
> ```yacc
> %type <obj_val> ValueLiteralStmt VariableStmt LitOrVarStmt
> ```
> Mid-rule action 與 `$0` 用法詳見 YACC_CHEATSHEET.md §Mid-Rule Action。

---

## 關鍵資料結構速查

```
CompilerContext (ctx)
├── scopeStack: LinkedList<ScopeData>   ← scope 堆疊（尾端 = 當前 scope）
├── variableCount: int                  ← 下一個變數的 index
├── registerCount: int                  ← 下一個暫存器的 index
└── code: ByteBuffer                    ← 當前 context 的 LLVM IR 輸出

ScopeData
├── symbolMap: Map<char*, SymbolData*>  ← 此 scope 的符號表
├── type: ScopeType                     ← MAIN / FUNCTION / FOR_LOOP / IF_STMT 等
└── u.funcSymbol: SymbolData*           ← 若 type == SCOPE_FUNCTION，指向函式符號

SymbolData
├── type: ObjectType                    ← 型別（I32 / F64 / BOOL / FUNC 等）
├── name: char*                         ← 符號名稱
├── index: int32_t                      ← LLVM 中的變數編號
├── funcInfo: FuncInfo*                 ← 若為函式，含參數列與捕獲變數
└── funcArg: bool                       ← 是否為函式參數

Object                                  ← yacc 非終端符號的語意值
├── type: ObjectType
├── capturedIndex: int                  ← -1=區域, >=0=上值索引（已預先處理）
└── value.symbol: SymbolData*           ← 指向符號表
```

---

## 文言文語法參考資源

實作語意動作前，先對文言語法有基本認識，有助於理解 token 序列的語義。

| 資源 | 說明 | 用途 |
|------|------|------|
| [Syntax Cheatsheet（Wiki）](https://github.com/wenyan-lang/wenyan/wiki/Syntax-Cheatsheet) | 語法速查表，每條文言語法旁附 JavaScript 對照；涵蓋變數、控制流、運算、陣列、函式、import | **寫 Yacc 規則時最常查的頁面** |
| [Beginner Cheatsheet（PDF）](https://github.com/alainsaas/wenyan/blob/master/wenyan-lang%20beginner%20cheatsheet.pdf) | 入門速查，附拼音與英文說明，適合不熟文言文的同學 | 對照 token 的中文含義 |
| [官方線上 IDE](https://ide.wy-lang.org/) | 瀏覽器直接編寫並執行文言程式，無需本地環境 | 快速驗證某段文言語法的行為 |
| [文言入門教科書](https://book.wy-lang.org/) | 官方互動式教科書，以文言文書寫，示範變數、迴圈、函式基礎語法 | 理解語言整體設計理念 |
| [教科書第一章（GitHub）](https://github.com/wenyan-lang/book/blob/master/01%20%E6%98%8E%E7%BE%A9%E7%AC%AC%E4%B8%80.md) | Markdown 版首章，介紹程式概念並給出第一個文言範例 | 快速入門，無需安裝 |
| [官方語言規格書](https://wy-lang.org/spec) | 完整語法規格，含每種語句的 BNF 定義與語義說明 | 確認邊界條件與語義細節 |

> **建議讀法**：先看 Syntax Cheatsheet 建立整體印象，實作特定語句時查規格書確認語義，有疑問時在線上 IDE 直接跑程式驗證。

---

## 延伸挑戰（選做）

完成四週基本作業後，有興趣的同學可以嘗試以下方向。這些功能在現有架構上均可延伸實作，難度不等。

### 語言功能延伸

| 項目 | 說明 | 切入點 | 難度 |
|------|------|--------|------|
| **二維陣列** | 支援 `列之列` 型別與對應的索引語法 | 擴充 `OBJECT_TYPE_ARRAY`，在 `object_getIndex` 加入多維處理 | ★★☆ |
| **函式型別變數（First-class Function）** | 允許將函式賦值給變數、作為引數傳遞 | `OBJECT_TYPE_FUNC` 已存在，補充賦值與傳遞的 IR 生成 | ★★☆ |
| **模組 Import** | 寫好的文言函式可以獨立成 `.wy` 檔，被其他程式 import 使用 | 在 `main.c` 加入多檔編譯流程，合併 symbol table | ★★★ |
| **數字中文輸出** | 目前 `書之` 輸出阿拉伯數字，改為輸出中文數字（一、二、十一…） | 在 runtime（`wy_rt.c`）加入 `wy_rt_print_chinese` 並修改 `code_stdoutPrint` | ★☆☆ |
| **多重回傳值** | `乃得甲乙` 同時回傳多個值 | 用 `sret` 或包成 anonymous struct 傳出；呼叫端解包 | ★★★ |
| **字串插值** | 在字串字面值中嵌入變數，如 `「計得「甲」也」` | Lexer 加狀態機切換，runtime concat 拼接 | ★★★ |
| **常數折疊** | `一加二` 在編譯期直接算成 `三`，不輸出 IR | 在 Yacc action 層偵測兩側均為字面值時提前計算 | ★★☆ |
| **Pattern matching** | 擴充 `若` 語法，支援型別解構與多條件匹配 | 新增 non-terminal，搭配 `switch` IR 的 `br` 鏈 | ★★★ |

### 編譯器工程延伸

| 項目 | 說明 | 切入點 | 難度 |
|------|------|--------|------|
| **Tail Call Optimization** | 遞迴函式尾呼叫改為迴圈，避免 stack overflow | 在 `code_return` 偵測尾呼叫，輸出 `musttail call` | ★★☆ |
| **Dead code elimination** | 永遠不執行的分支（`若陰者`）給予警告並省略 IR | 在 `code_if` 偵測條件為字面 bool | ★★☆ |
| **DWARF debug info** | 讓 `gdb` 能對應到 `.wy` 原始行號 | 輸出 `!dbg` metadata，搭配 `DILocation` | ★★★ |
| **LLVM optimization pass** | 編譯後呼叫 `opt -O2`，觀察 IR 優化結果 | 在 `wyc.c` 主流程後 pipe 給 `opt` | ★☆☆ |
| **WASM backend** | 把文言程式編譯成 WebAssembly，跑在瀏覽器 | 換 `llc --target wasm32`，補 WASI runtime shim | ★★☆ |
| **文言虛擬碼反印** | 把 AST 印成人類可讀的中文虛擬碼（教學工具） | 新增 AST visitor，在 scope/symbol 層加 print hook | ★★☆ |

### Runtime 延伸

| 項目 | 說明 | 難度 |
|------|------|------|
| **垃圾回收（GC）** | 目前字串與陣列靠手動 free；可在 `wy_rt.c` 實作 mark-and-sweep 或 reference counting | ★★★★ |
| **測試框架** | `斷言甲等乙` 語法，不匹配時印出行號與期望值；無需額外工具 | ★★☆ |
| **視窗 UI** | 串接 GTK / SDL / Dear ImGui，讓文言程式顯示圖形介面 | ★★★ |
| **GPU 加速（MLIR/LLVM）** | 透過 MLIR 的 GPU dialect 或 LLVM NVPTX backend 發射到 GPU | ★★★★ |

### 工具生態

| 項目 | 說明 | 切入點 | 難度 |
|------|------|--------|------|
| **REPL** | `wyc` 無引數時進入互動模式，逐行 parse 並即時輸出 | JIT（`lli`）或直譯器模式；需處理 scope 跨行保留 | ★★★★ |
| **LSP server** | Hover 顯示變數型別、go-to-definition 跳轉定義 | 包裝現有 scope/symbol table，實作 JSON-RPC | ★★★★ |

> **建議起點**（學習價值 × 改動量最佳比）：
> 1. **LLVM optimization pass** — 一行 `system()` 呼叫，立即看到 IR 差異
> 2. **常數折疊** — 純 Yacc action 層，鞏固語意分析理解
> 3. **Tail Call Optimization** — 數行改動，讓遞迴文言程式跑萬次不爆 stack

---

## 注意事項

1. **沒有修改限制**：所有提供的程式碼（包含 `compiler.l`、`lib/`、`.h` 標頭、runtime）都可以任意改動。唯一的要求是 `cmake --build build` 產出的 `wyc` 能把 `.wy` 編譯成可執行檔並通過測試。
2. **提供的程式碼是簡化的參考實作**，僅供理解流程使用。可以自行設計函式、新增 helper、改變資料結構，不需要照著我的實作方式寫。
4. 所有語意動作中的錯誤回報請使用 `yyerrorf()`（格式化）或 `yyerrorlf()`（含位置），不要用 `printf`。
5. 記憶體管理：`scope_addSymbol` 內部使用 `strdup` 複製名稱，呼叫端不需自行 free。
6. `ctx->variableCount` 的遞增由 `scope_addSymbol` 在分配 index 時一併完成（`ctx->variableCount++`），呼叫端不需再自行遞增。
7. 閉包（Closure）捕獲邏輯已預先實作，同學的 `scope_findSymbol` 只需處理 `searchCtx == ctx` 的情況。
