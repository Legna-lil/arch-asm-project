# =============================================================================
# run_sim.ps1 - 一键命令行仿真（xvlog / xelab / xsim），覆盖工程内全部 testbench
#
# 工程目录分类（与 Vivado IDE 的 file set 显示一一对应）：
#   Lab2.srcs/sources_1/new/cpu     <- 计组：五级流水线 CPU、溢出检测(标志寄存器)、M 扩展乘除法
#   Lab2.srcs/sources_1/new/periph  <- 汇编：USB-UART / 蓝牙 BLE / LCD / 数码管 外设 + SoC 顶层
#   Lab2.srcs/sim_1/new/cpu         <- 计组 testbench
#   Lab2.srcs/sim_1/new/periph      <- 汇编 testbench
#
# 用法（PowerShell，路径随意）：
#   powershell -File E:\VivadoProject\Lab2\scripts\run_sim.ps1              # 全部 34 个 tb
#   powershell -File ...\run_sim.ps1 -Group cpu                            # 只跑计组
#   powershell -File ...\run_sim.ps1 -Group periph                         # 只跑汇编
#   powershell -File ...\run_sim.ps1 -Tb tb_overflow                       # 单个
#   powershell -File ...\run_sim.ps1 -Tb tb_ALU,tb_PC_IM                   # 多个（逗号分隔）
#
# 说明：
#   * tbs that instantiate EES338Top (with the MMCM) need the Xilinx primitive
#     library; the script compiles MMCME2_BASE / MMCME2_ADV / BUFG into the
#     library "unisims_ver" automatically -> no GUI needed.
#   * 工作目录：<工程根>\.workbuddy\sim_run\a\b
# =============================================================================
param(
    [string[]] $Tb = @(),
    [string]   $Group = 'all',                    # all | cpu | periph
    [string]   $SrcRoot = '',
    [string]   $VivadoBin = 'E:\Vivado2019.2\Vivado\2019.2\bin'
)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrEmpty($SrcRoot)) {
    $SrcRoot = Split-Path -Parent $PSScriptRoot          # repo root (scripts\..)
}
$SrcRoot = (Resolve-Path $SrcRoot).Path

$src  = Join-Path $SrcRoot 'Lab2.srcs\sources_1\new'
$tbdir = Join-Path $SrcRoot 'Lab2.srcs\sim_1\new'
$srcDirs = @((Join-Path $src 'cpu'), (Join-Path $src 'periph'))       # 计组 / 汇编 源码
$tbDirs  = @((Join-Path $tbdir 'cpu'), (Join-Path $tbdir 'periph'))   # 计组 / 汇编 testbench
# 注意：工作目录必须位于工程根目录下 **4 层**（与 Vivado GUI 的
# Lab2.sim\sim_1\behav\xsim 同深度），因为 testbench 里的
# "../../../../Lab2.file/xxx.hex" 是相对路径；4 层正好指回工程根目录。
$sim  = Join-Path $SrcRoot '.workbuddy\sim_run\a\b'

if (-not (Test-Path (Join-Path $VivadoBin 'xvlog.bat'))) {
    Write-Host "ERROR: cannot find xvlog.bat under $VivadoBin" -ForegroundColor Red
    exit 1
}
$env:PATH = "$VivadoBin;" + $env:PATH

New-Item -ItemType Directory -Force -Path $sim | Out-Null
Push-Location $sim

# ---- 默认 test 列表：计组(cpu) + 汇编(periph) 全跑；-Group 可选单跑一类 ----
# 允许 -Tb a,b,c 或 -Tb a -Tb b 两种写法（-File 传参不会自动按逗号分割）
$Tb = @($Tb | ForEach-Object { $_ -split ',' } | Where-Object { $_ -ne '' })
$cpuTbs = @('tb_ALU', 'tb_alu_flags', 'tb_divunit',
            'tb_overflow', 'tb_forward', 'tb_hazard', 'tb_branch', 'tb_inst_alu',
            'tb_muldiv', 'tb_compare', 'tb_CPU', 'tb_CPU_pipeline',
            'tb_CPU_singlecycle', 'tb_PC_IM', 'tb_RegisterFile', 'tb_ImmGen')
$asmTbs = @('tb_uart_tx', 'tb_uart_rx', 'tb_lcd128128', 'tb_segdisplay',
            'tb_EES338_lcd', 'tb_EES338_lcdtest', 'tb_EES338_lcdread',
            'tb_EES338_bt', 'tb_EES338_btcheck', 'tb_EES338_btat', 'tb_EES338_btcfg',
            'tb_EES338_btseg', 'tb_EES338_sort', 'tb_EES338_flags', 'tb_flags',
            'tb_EES338_hello', 'tb_EES338_echo', 'tb_EES338_helloecho')
if ($Tb.Count -eq 0) {
    switch ($Group) {
        'cpu'    { $Tb = $cpuTbs }
        'periph' { $Tb = $asmTbs }
        default  { $Tb = $cpuTbs + $asmTbs }
    }
}

Write-Host '=== [1/3] compile RTL into xil_defaultlib (cpu/ + periph/) ===' -ForegroundColor Cyan
$rtl = @()
foreach ($d in $srcDirs) {
    if (Test-Path $d) { $rtl += (Get-ChildItem (Join-Path $d '*.v') | ForEach-Object { $_.FullName }) }
}
& xvlog.bat --incr --relax --work xil_defaultlib -i $src -i $srcDirs[0] -i $srcDirs[1] @rtl 2>&1 |
    Select-String -Pattern 'ERROR|error' | Select-Object -First 10

# glbl (GSR) is used by designs containing Xilinx primitives
$glbl = Join-Path $SrcRoot 'Lab2.sim\sim_1\behav\xsim\glbl.v'
if (-not (Test-Path $glbl)) {
    $glbl = Join-Path $VivadoBin '..\data\verilog\src\glbl.v'
}
if (Test-Path $glbl) {
    & xvlog.bat --work xil_defaultlib $glbl 2>&1 |
        Select-String -Pattern 'ERROR|error' | Select-Object -First 5
} else {
    Write-Host "WARN: glbl.v not found (tests using EES338Top may fail to elaborate)"
}

Write-Host '=== [2/3] compile Xilinx primitives (MMCME2/BUFG) into unisims_ver ===' -ForegroundColor Cyan
$ux = Join-Path $VivadoBin '..\data\verilog\src\unisims'
if (Test-Path $ux) {
    & xvlog.bat --work unisims_ver (Join-Path $ux 'MMCME2_BASE.v') `
                                   (Join-Path $ux 'MMCME2_ADV.v') `
                                   (Join-Path $ux 'BUFG.v') 2>&1 |
        Select-String -Pattern 'ERROR|error' | Select-Object -First 5
} else {
    Write-Host "WARN: unisims directory not found: $ux"
}

Write-Host '=== [3/3] elaborate + run testbenches ===' -ForegroundColor Cyan
$failed = @()
foreach ($t in $Tb) {
    $file = $null
    foreach ($d in $tbDirs) {                    # cpu/ 找不到就到 periph/ 里找
        $p = Join-Path $d "$t.v"
        if (Test-Path $p) { $file = $p; break }
    }
    if ($null -eq $file) { Write-Host "SKIP (no such tb): $t"; continue }
    Write-Host ""
    Write-Host "---------- $t ----------" -ForegroundColor Yellow

    & xvlog.bat --incr --relax --work xil_defaultlib -i $src -i $srcDirs[0] -i $srcDirs[1] $file 2>&1 |
        Select-String -Pattern 'ERROR|error' | Select-Object -First 10
    & xelab.bat -L unisims_ver --debug typical "xil_defaultlib.$t" xil_defaultlib.glbl `
                -s "${t}_snap" 2>&1 | Select-String -Pattern 'ERROR|error' | Select-Object -First 10
    $out = & xsim.bat "${t}_snap" -runall 2>&1
    $out | Select-String -Pattern 'PASS|FAIL|ALL PASS|Error|error' | Select-Object -First 40
    # 通过判据：无 FAIL，且有显式通过标记（ALL PASS / RESULT: PASS / 逐条 PASS:）
    if (($out -notmatch 'FAIL') -and
        (($out -match 'ALL PASS') -or ($out -match 'RESULT: PASS') -or ($out -match 'PASS:'))) {
        Write-Host "$t : ALL PASS" -ForegroundColor Green
    }
    else {
        Write-Host "$t : SEE LOG ABOVE" -ForegroundColor Red
        $failed += $t
    }
}

Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host "==== ALL TESTBENCHES PASS ====" -ForegroundColor Green
} else {
    Write-Host ("==== FAILED: " + ($failed -join ', ') + " ====") -ForegroundColor Red
}
Pop-Location
