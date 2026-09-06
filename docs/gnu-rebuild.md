# C08：从 GNU 源码重新编译课程 19 点程序

本次已经实际运行 GNU 预处理、汇编、归档、链接、反汇编、`objcopy` 和主机 C 转换程序。按明确的课程函数布局重新编译后，生成的 `inst_ram.coe` 与老师提供的文件 **逐字节相同**，并在独立的 `teach_soc` 仿真副本中通过原始、未经改写的 golden trace。

这补充了此前直接加载预编译 COE 的回归。源码目录虽然含 89 个功能点，`start.S` 实际启用的是 19 点；本次结论仍限于这 19 点。

## 软件与隔离方式

| 项目 | 实际使用 |
|---|---|
| Linux 内核 | 已可运行的 WSL2；使用 `docker-desktop` 发行版提供的内核与 root/chroot |
| 独立用户空间 | 官方 Ubuntu Base 24.04.4 amd64 |
| MIPS GCC | 12.4.0，包 `12.4.0-2ubuntu1~24.04cross8` |
| MIPS Binutils | 2.42，包 `2.42-2ubuntu1cross5` |
| 主机 GCC | 13.3.0，编译课程 `convert.c` |
| GNU Make | 4.3，包 `4.3-4.1build2` |
| RTL 仿真 | Vivado/XSim 2019.2 |

Ubuntu、安装的软件包、复制的课程源文件和编译结果全部保存在被 Git 忽略的 `build/gnu-rebuild/`。脚本创建私有 ext4 镜像，在独立 mount namespace 中挂载并 chroot；结束时卸载。不注册发行版，不改变默认 WSL，不修改 Docker Desktop 系统配置，也不需要 Docker daemon。

Ubuntu Base 来自 [Ubuntu 官方发布目录](https://cdimage.ubuntu.com/ubuntu-base/releases/24.04.4/release/)，归档 SHA-256 固定为：

```text
c1e67ef7b17a6300e136118bd1dc04725009cb376c1aad10abcf8cd453628d58
```

GNU 包来自 Ubuntu 官方 APT 仓库，由 APT 校验签名元数据。脚本保存完整软件包版本清单；首次安装会取得该仓库当时的更新，后续可直接使用保留的镜像重编译。它没有声称未来的 APT 更新会产生相同 ELF 文件。

## 三项明确适配

1. 工具前缀从旧的 `mipsel-linux-` 改为 Ubuntu 的 `mipsel-linux-gnu-`。
2. 在 **构建副本** 的 Makefile 追加 `-mfp32`。不加时 GCC 12 实际报错：`'-march=mips1' requires '-mfp32'`。这明确了 MIPS-I 的浮点寄存器宽度，课程整数汇编指令不变。
3. 在 **构建副本** 的链接脚本丢弃 `.MIPS.abiflags`。该 ELF ABI 元数据是现代工具链新增的 orphan section；原脚本将 `.data` 的加载地址设为 `rodata_end`，实测产生 LMA 重叠。它不是执行指令或初始化 RAM 数据。

课程原目录的全部 103 个文件均在构建前后计算 SHA-256 并比对，保持不变。转换程序从 C 源码重新编译，旧的预编译 `convert` 和任何旧目标文件均不进入构建副本。

## 两种布局都保留

默认使用课程 `inst/Makefile` 的通配符成员顺序。现代构建得到按文件名排列的归档成员及函数布局，19 个启动 `jal` 的目标和相应函数地址因此变化：同样是 46,951 个 ROM 字，有 44,854 个字的位置/值与旧 COE 不同。这不等于 44,854 条指令的语义改变，也不能把旧地址的 golden 直接用于该布局。

`--match-supplied-layout` 从原 COE 启动区中 19 个功能函数 `jal` 的目标地址确定原函数排列，再在构建副本中明确归档成员顺序。辅助函数调用被排除，函数名来自原 `start.S`，不读取 CPU 运行结果。此次重新编译后 **46,951 个字全部相同，整个 COE 文件 SHA-256 也相同**。

这说明本次镜像差异来自函数布局；没有通过改汇编指令、修改测试常量或改写 golden 去适配 CPU。旧工程没有提供其当年的 GNU 版本，因此这里不推断旧链接器为何选择那个排列。

课程原转换器在 EOF 处重复输出最后一个字。本次保留该行为以匹配原镜像；`main.bin` 为 187,800 字节，COE 为 46,951 字，而不是把 COE 的每个字都视为不同的有效机器指令。

## 复现命令

先配置可用的 root-capable WSL 和 Vivado。课程文件只从本地读取，不由公开仓库重新分发。

```powershell
$env:BITMIPS_LAB5 = 'D:/cpu/bitmips_experiments-master/bitmips_experiments-master/lab5'
$env:VIVADO_BIN = 'E:/Xilinx/Vivado/2019.2/bin'

# 首次建立私有 GNU 环境，并保留默认布局结果。
python scripts/rebuild_course_program.py --bootstrap

# 明确原布局，重新编译，并用未修改的原 golden 验证新镜像。
python scripts/rebuild_course_program.py --match-supplied-layout --verify
```

普通 Ubuntu WSL 可指定 `--distro Ubuntu --wsl-host-root /mnt`。脚本默认 Docker Desktop 的驱动器挂载前缀 `/mnt/host`；这只是使用现有 WSL 内核，不是在 Docker 中启动容器。

每次都创建新的 `build/gnu-rebuild/source-*` 目录，保存 `obj/`、`build-result.json`、构建日志、工具版本和软件包清单；顶层 `result.json` 指向最近一次成功构建。`--verify` 在自己的 `verification-project` 和 `verification-lab5` 内运行，不能覆盖常规 `build/teach_soc/normal` 的证据。ROM 不相同时，它拒绝拿旧 golden 验证。

## 本次实际结果

```text
PASS GNU_REBUILD points=19 words=46951 identical_supplied=True
PASS TEACH_SOC rows=28970 cycles=49959 stores=420 display=13000013 led=0f enabled_points=19 reset_cancel=1 checked_tail=32
```

| 输出/基准 | SHA-256 |
|---|---|
| 新旧 `inst_ram.coe` | `c9dcea20a6dd95fdd0c3d7f28ed6bebbcfcc86db9ab8d70ed46257a136c934b9` |
| 新 `main.bin` | `ebad62f3c4203395ad4c02aeb751e27bbfba19d08638905ae669e85cd08dc35a` |
| 未修改的原 golden | `1047fc04c8408cd2eafc649f9f7f6898f47afba34743a1db7009d09e5039d6ab` |

独立 XSim 回归检查 28,970 次寄存器写回、420 次存储、19 点结束显示、复位取消存储和结束循环。其半周期适配、同步行为存储器及仿真边界仍按 [teach_soc 说明](teach-soc.md) 执行；这次没有重新下载 FPGA，也没有把该程序扩展成全部 89 点。
