# 文言文 LLVM 編譯器（NCKU 編譯系統 HW2）

成大資工（NCKU CSIE）114-2 學期「編譯系統 / Compiler Construction」的課堂作業。
這份作業要做的是一個把**文言文程式語言**（[wenyan-lang](https://wy-lang.org/) 風格）編譯成 **LLVM IR**、再丟給 `llc` 產生原生執行檔的編譯器。

簡單說，下面這種「文言文」：

```
吾有一數。曰三。名之曰「甲」。
吾有一數。曰五。名之曰「乙」。
加「甲」以「乙」。書之。
```

會被這個編譯器解析、做語意分析、生成 LLVM IR，最後跑出來印出 `8`。

## 課程資訊

- 學校：國立成功大學 資訊工程學系（NCKU CSIE）
- 課程：編譯系統（Compiler Construction）
- 學期：114-2
- 作業：HW2 — 文言文 LLVM 編譯器
- 接續 HW1 的 Lexer（Flex），這次補上 Parser（Bison）、語意分析與 IR 生成

## 這份作業做了什麼

整個編譯流程大致是：`文言文原始碼 → Flex 詞法分析 → Bison 語法分析 → 語意分析 / 符號表 → 產生 LLVM IR → llc 編成執行檔`。

實作的部分包含：

- **詞法分析**（`compiler.l`）：文言文 token 規則
- **語法分析**（`compiler.y`）：變數宣告、賦值、運算式、控制流、函式、陣列等文法
- **符號表 / Scope**（`scope.c`）：含巢狀作用域與閉包捕獲
- **值系統**（`object.c`、`value_data.c`）：型別、多值宣告、型別檢查
- **語意動作**（`main.c`、`expression.c`）：變數建立、賦值、運算式、印出、取長度
- **控制流 IR**（`control/for.c`、`if.c`、`while.c`）：for / while / if-elseif-else，含 phi 節點與 basic block

支援的語言功能：整數 / 浮點 / 布林 / 字串 / 陣列、四則與邏輯運算、if-elseif-else、for / while 迴圈與 break、函式定義與呼叫（含閉包）。

## 環境需求

| 工具 | 版本 |
|------|------|
| cmake | ≥ 3.10 |
| flex | ≥ 2.6 |
| bison | ≥ 3.6 |
| gcc | 支援 C11 |
| llvm / llc | 14 |

macOS：

```bash
brew install cmake flex bison llvm
```

Ubuntu / Debian：

```bash
sudo apt install cmake flex bison gcc llvm
```

## 編譯與執行

```bash
# 建置
cmake -B build -S .
cmake --build build

# 跑測試（-n 可跳過重新 build）
./test/test.sh
```

編出來的 `wyc` 可以直接拿來編譯文言文程式：

```bash
./build/wyc -v test/策問/00_快速入門.wy   # -v 印出 verbose 編譯過程
```

## 專案結構

```
src/
├── compiler.l          # Flex 詞法規則
├── compiler.y          # Bison 語法規則 + 語意動作
├── scope.c             # 符號表 / 作用域
├── object.c            # 值 / 型別系統
├── value_data.c        # 多值宣告容器
├── expression.c        # 運算式 IR 生成
├── main.c              # 語意動作核心、編譯器入口
├── control/            # for / if / while / function 的 IR 生成
├── lib/                # 工具函式庫（已提供）
└── wy_rt/              # Runtime（字串 / 陣列 / print，已提供）
test/                   # 測試案例（策問 / 殿試）
```

> 完整的環境建置、填空規格與工具函式說明，請見 [ASSIGNMENT.md](ASSIGNMENT.md)（原始作業文件）。

## 備註

這是修課過程中的作業，放上來主要是當作備份兼紀錄，寫得不夠漂亮的地方還請見諒。
作業骨架（lexer 起始檔、runtime、工具函式庫）由課程助教提供，原始模板為
[WavJaby/NCKU_Compiler_HW2](https://github.com/WavJaby/NCKU_Compiler_HW2)。

如果你也是修這門課的同學——自己動手寫才學得到東西，這份就當參考用就好。
