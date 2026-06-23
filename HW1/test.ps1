param(
    [string]$File = "",
    [switch]$Interactive = $false,
    [switch]$StopOnFirstError = $false,
    [switch]$NoCompile = $false
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

if (-not $NoCompile) {
    Write-Host "Compiling project..." -ForegroundColor Cyan
    if (-not (Test-Path build)) {
        cmake -B build -S .
    }
    cmake --build build
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Compilation failed!" -ForegroundColor Red
        exit 1
    }
}

$lexer_exe = ".\build\lexer_test.exe"
if (-not (Test-Path $lexer_exe)) {
    $lexer_exe = ".\cmake-build-debug\lexer_test.exe"
}

$test_dirs = @("test\策問", "test\殿試")
$expected_dir = "test\對勘"
$temp_out = ".\temp_out.txt"
$temp_expected = ".\temp_expected.txt"

$all_passed = $true
$total_score = 0

foreach ($dir in $test_dirs) {
    if (-not (Test-Path $dir)) { continue }

    if ($StopOnFirstError -and -not $all_passed) {
        break
    }

    $files = Get-ChildItem -Path $dir -Filter "*.wy"
    $points_per_test = if ($dir -match "策問") { 8 } else { 2 }

    foreach ($f in $files) {
        $fileName = $f.Name
        if ($File -and -not ($fileName -like "*$File*")) {
            continue
        }

        Write-Host "Running Test: $fileName"

        $baseName = $f.BaseName
        $expectedPath = Join-Path $expected_dir "$baseName.out"

        if (-not (Test-Path $expectedPath)) {
            Write-Host "Warning: Expected output file not found for $fileName" -ForegroundColor Yellow
            continue
        }

        # Use cmd /c for redirection
        # We need to ensure output is captured as-is
        # Using [System.IO.File]::WriteAllText with normalized output from native command
        $actual_raw = cmd /c "`"$lexer_exe`" `"$($f.FullName)`" 2>&1"
        $actual = $actual_raw -join "`n"
        $expected = Get-Content $expectedPath -Raw

        if ($null -eq $actual) { $actual = "" }
        if ($null -eq $expected) { $expected = "" }

        # Normalize and Trim to avoid trailing newline issues
        $actual_norm = ($actual -replace "^\xEF\xBB\xBF", "" -replace "`r", "").Trim()
        $expected_norm = ($expected -replace "^\xEF\xBB\xBF", "" -replace "`r", "").Trim()

        if ($actual_norm -ne $expected_norm) {
            $all_passed = $false
            Write-Host " Failed" -ForegroundColor Red

            [System.IO.File]::WriteAllText((Resolve-Path .).Path + "\$temp_out", $actual_norm)
            [System.IO.File]::WriteAllText((Resolve-Path .).Path + "\$temp_expected", $expected_norm)

            if ($Interactive) {
                git -c core.autocrlf=false diff --ignore-cr-at-eol --no-index --color-words $temp_expected $temp_out
            } else {
                git -c core.autocrlf=false --no-pager diff --ignore-cr-at-eol --no-index --color-words $temp_expected $temp_out
            }
            Write-Host "----------------------------------------"

            if ($StopOnFirstError) {
                break
            }
        } else {
            Write-Host " Passed (+$points_per_test points)" -ForegroundColor Green
            $total_score += $points_per_test
        }
    }
}

if (Test-Path $temp_out) { Remove-Item $temp_out }
if (Test-Path $temp_expected) { Remove-Item $temp_expected }

Write-Host "Final Score: $total_score/100" -ForegroundColor Cyan

if ($all_passed) {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests failed." -ForegroundColor Red
    exit 1
}
