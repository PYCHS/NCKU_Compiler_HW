# NCKU 1142_編譯系統 COMPILER CONSTRUCTION 作業一

## 可以先看 [學期作業規劃以及說明](https://hackmd.io/@WavJaby/NCKU_1142_COMPILER_HW)

## 環境設定

可以使用任何自己習慣的編輯器

### Windows
請先安裝 [MSYS2](https://www.msys2.org/) ，安裝完成後，開啟 MSYS2 UCRT64 的終端機：

![image](https://hackmd.io/_uploads/HkIlNV83Zx.png)

在終端機中執行下列命令安裝套件：
```shell
pacman -Syu
pacman -S --needed mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja flex
```

安裝完成後需要將可執行檔加入環境變數中：
- 開啟設定 -&gt; 系統　-&gt; 系統資訊 -&gt; 相關設定　-&gt; 進階系統設定
- 點擊 `環境變數`，在上方使用者變數中找到 `Path` 後點擊編輯，加入以下路徑：
  ```
  C:\msys64\usr\bin
  C:\msys64\ucrt64
  ```
  >MSYS 預設的安裝位置為 `C:\msys64`，如果你在安裝過程中有修改位置，請將上述的路徑替換為對應的位置。
  
- 完成後按下確定關閉所有視窗

設定完環境變數後，開啟終端機執行以下命令測試套件是否都被正確安裝了：
```
gcc --version
cmake --version
ninja --version
flex -V
```
>
> 有可能需要建立環境變數才可以安裝還有編譯
> ```
> C:\msys64\usr\bin
> C:\msys64\ucrt64
> ```
> MSYS 預設的安裝位置為 `C:\msys64`，如果你在安裝過程中有修改位置，請將上述的路徑替換為對應的位置。
>
> ![image](https://hackmd.io/_uploads/By85CzWnZe.png)
> 

### Linux

- Ubuntu / Debian / Linux Mint / WSL Ubuntu:
    ```shell
    sudo apt update
    sudo apt install -y build-essential cmake flex git
    ```
- Arch Linux:
    ```shell
    sudo pacman -Syu 
    sudo pacman -S base-devel cmake flex git
    ```

## 作業設定

下載作業模板以及測資:
```shell
git clone --recurse-submodules https://github.com/WavJaby/NCKU_Compiler_HW1
```

### 運行測試
運行測試後就可以看到分數，所見即所得

Windows Powershell 執行測試:
```shell
.\test.ps1
```


> 如果遇到這個錯誤:
> ```shell
> &gt; .\test.ps1
> .\test.ps1 : File E:\MyProjects\C\114-2-NCKU-CompilerHW1\test.ps1 cannot be loaded. The file E:\MyProjects\C\114-2-NCKU
> -CompilerHW1\test.ps1 is not digitally signed. You cannot run this script on the current system. For more information a
> bout running scripts and setting execution policy, see about_Execution_Policies at https:/go.microsoft.com/fwlink/?Link
> ID=135170.
> At line:1 char:1
> + .\test.ps1
> + ~~~~~~~~~~
>     + CategoryInfo          : SecurityError: (:) [], PSSecurityException
>     + FullyQualifiedErrorId : UnauthorizedAccess
> ```
> 要先執行 `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` 允許script執行


Linux 執行測試:
```shell
chmod +x test.sh
./test.sh
```


### Debug 用指令

- `-Interactive` (Linux: `--interactive`, `-i`):
  可以用上下左右看每個git diff，可以清楚的debug錯誤在哪裡
- `-StopOnFirstError` (Linux: `--stop-on-first-error`, `-s`):
  可以在第一個錯誤出現的時候停下，不會把每個檔案都印出來

![image](https://hackmd.io/_uploads/Hy0J_Of2-x.png)

![image](https://hackmd.io/_uploads/H1Cb5_z3-g.png)