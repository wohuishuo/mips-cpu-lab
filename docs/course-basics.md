# 课程 lab1 / lab3 集成验收

本页将课程原工程与本仓库的新 SoC 分开记录。原始课程资料只从用户本地
`bitmips_experiments-master/bitmips_experiments-master` 读取；不把教师源码、
COE 或 XCI 复制进公开仓库。运行时生成的副本及镜像位于忽略的 `build/`。

## lab1：补全输入与八位十六进制显示

`rtl/integration/lab1_num_led.v` 是自写的、与原 `num_led` 引脚接口一致的实现：
`rst` 低有效，`switch[7:0]` 与中心键作为输入；两组 `digital_num[6:0]`
使用 **abcdefg、高电平点亮** 的段码，`digital_cs` 为 0x11、0x22、0x44、0x88。
这与板级 SoC 中归一化的低有效数码管接口不同，不能直接互换旧 XDC。

每次消抖后的按下把开关字节写入低字节、次低字节、高半字低字节、最高字节，
然后回绕。实现包含双触发器同步和稳定时间消抖；默认 COUNTER_WIDTH=20。
数码管位选和段码从同一扫描相位解码，避免原框架中两级独立寄存造成相位错位。

回归测试还实际编译课程 `num_led.v` 的本地修复副本：保留其字节写入逻辑与按键
结构，将整个未完成的扫描/段码区替换为自写 `lab1_hex_display` 实例。副本另修复
`center_btn_key_end` 的释放条件缺少取反，以及 `center_btn_key_r2` 没有复位。
原件没有改动。测试参数缩小为 4，只加速消抖与扫描时间。

两个版本各检查 672 次外部输出，覆盖 16 种字形、全部扫描相位、连续输入、
长按只写一次、短脉冲拒绝、字节位置回绕和活动中复位。未补全的原文件在
420 ns 因缺失扫描相位失败；这也是 `--mutate lab1-missing` 的预期结果。

## lab3：原顶层、原地址译码与原程序

`rtl/integration/lab3_mycpu.v` 提供原顶层缺失的 `mycpu` 模块，内部连接本仓库
`single_cycle_cpu`，复位 PC 为 0xbfc00000，rstn 低有效。测试直接编译原
`single_cycle.v`，使用原 confreg 和原 ROM/RAM 连接，不读取损坏的 XPR 外部路径。

| 原端口或地址 | 本仓库对应行为 |
|---|---|
| inst_rom_addr / inst_rom_rdata | 单周期核组合取指；ROM 以地址 [11:2] 选字 |
| data_ram_addr / wdata / rdata | 32 位字地址总线，RAM 以地址 [11:2] 选字 |
| data_ram_wen | 仅完整 4 字节 strobe 转换为原单比特写使能 |
| 0xbfaf8000 / 8004 / 8008 | 原数码管寄存器 / 开关 / LED |
| 0xbfaf800c / 8014 / 8018 | 原中心键 / 右键 / 上键 |
| 0xbfc10000…004c | Fibonacci 的 20 个数组字，落入原 RAM 的前 20 字 |

原 XCI 配置是 **1024×32 位 distributed memory、输入和输出均不寄存**。
`tests/course_memory_models.sv` 因而用异步组合读、上升沿 RAM 写；不是一拍
同步读 BRAM 的替代品。运行器核对 XCI 的深度、位宽和输入/输出寄存配置。
没有模拟 vendor IP 的器件延迟，也不以行为模型结果声称原 IP 时序通过。

原单比特 WE 无法表达字节/半字写，因此该适配层的契约是对齐字访问；不会把
窄写静默扩成完整字破坏相邻字节。课程两份程序只使用对齐 lw/sw。

两份原汇编与原 COE 都在 beq/j 后明确使用 NOP，适配核执行 MIPS 延迟槽。
未删除 NOP、未改分支目标，也没有把原镜像当作“无延迟槽”程序重解释。
核的单周期 ADD/SUB 溢出采用回绕；本次加法输入与 Fibonacci 不发生有符号溢出。

## 六个回归配置与边界

| 配置 | 原件/副本范围 | 判定 |
|---|---|---|
| lab1_owned | 自写模块，同原端口 | 672 次输出断言 |
| lab1_original_overlay | 原框架的显示补全和按键修复副本 | 相同 672 次输出断言 |
| lab3_fibonacci_original | 原顶层、原 confreg、原 COE | 20 次 RAM 写地址/数据、RAM 内容、首次显示；218 周期 |
| lab3_fibonacci_fast_display | 仅把 ROM 中等待常数 20000000 改为 4 | 全部 20 次显示，数学递推独立判定 |
| lab3_adder_original | 原顶层、原 confreg、原 COE，实际驱动原始按键输入 | 255+255=510、LED 低八位 254、长按不重复加 |
| lab3_adder_boundaries | 等待常数 100000 改为 4；按键计数器由 20 位缩为 4 位 | {0,1,127,128,254,255} 的 36 个有序输入组合 |

加速配置不修改计算、分支或数据通路。改动前核对原等待指令的准确机器码，
防止误改其他版本；保留改前/改后镜像于本地构建目录。边界测试不等于穷举
65536 个输入组合。Fibonacci 原镜像仅跑到第一次显示；全部显示序列来自明示
的加速版本。按键测试通过原输入端口驱动，没有 force 内部消抖结果或寄存器。

使用独立的 SystemVerilog 整数递推构造 Fibonacci 预期值，
加法预期直接为输入 a+b，不从 CPU 寄存器或实际输出复制。另检查实际 RAM 内容、
每次 RAM 写地址、MMIO 输出值、LED 截断和非法指令。故意将 Fibonacci 存储
偏移改为 4，或将 adder 的 ADD 替换为 SUB，均必须失败。

## 复现

```powershell
# 可选；未设置时使用仓库旁本地课程目录与 E:/Xilinx/Vivado/2019.2/bin
$env:BITMIPS_ROOT = 'D:/cpu/bitmips_experiments-master/bitmips_experiments-master'
$env:VIVADO_BIN = 'E:/Xilinx/Vivado/2019.2/bin'
python tests/run_course_basics.py
# 以下三个负例应返回非零退出码：
python tests/run_course_basics.py --mutate lab1-missing
python tests/run_course_basics.py --mutate fib-store
python tests/run_course_basics.py --mutate adder-sum
```

记录在 `build/course_basics/normal/result.json`，逐配置日志在对应子目录。
两个 lab1 配置和原 Fibonacci 配置还生成 `course_test.wdb`，可在 XSim 查看真实仿真波形。
result.json 仅在全部通过后创建，记录本地原文件 SHA-256，并核对运行前后未变。
失败日志不等于成功证据。原课程资料缺失时运行器明确报错，不自动下载来源不明材料。

这些证据补足 C01 的 lab1 软件实现和 C04 的课程 ROM/RAM 集成。它们本身不构成
lab1 原工程上板记录或原 lab3 bitstream 实测；本仓库另有新 SoC 的 FPGA 上板
证据，两者在最终验收表中应分别陈述。
