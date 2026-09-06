# 12 个垂直 capabilities：交付与证据

“垂直”表示从输入、实现、验证到可见结果的一条完整路径。ALU、寄存器堆等是
路径内部模块。以下是本项目的工程验收记录，不是未提供的 2026 学校评分表。

| ID | 能力 / 软件 | 已完成的交付与测试 | 边界或剩余现场证据 |
|---|---|---|---|
| C01 | 工程到数码管；Vivado/XSim、EES-338 | lab1 自写与原框架修复副本各 672 检查；新 XDC；SoC 综合、布线、下载；显示值串口读回 | 原 lab1 bitstream 未单独下板；实际数字外观待观察 |
| C02 | 汇编到机器码；Java/MARS | 实际汇编并执行 Fibonacci；同 ROM 进入 RTL；完整存储地址和 12 个值对照 | MARS 延迟槽必须开启 |
| C03 | 单周期算术执行；XSim | 44 条普通指令、2,113 检查；非法/不对齐无错误副作用 | 单周期 ADD/ADDI/SUB 环绕，不提供精确异常 |
| C04 | 完整单周期程序；MARS/XSim | 原 lab3 顶层、confreg、ROM/RAM 接口；20 个 Fibonacci RAM 值；加法 255+255 及 36 组边界 | 全部显示序列和多组加法采用明确标注的等待加速副本 |
| C05 | CPU 与板上 I/O；Vivado/UART | CPU 读取实际开关 0x81，显示寄存器 0x00810059、LED 驱动值 0xD8；仿真和实板遥测一致 | 没有物理拨动开关的视频；LED 方向与显示外观待观察 |
| C06 | UART 控灯与 IP；IP Packager/pyserial | 8N1 独立采样、坏停止位、复位；40 字节 SoC 协议；实板 off/on/auto；封装 IP 在新项目调用成功 | 图形表示驱动值，未拍摄实物 LED |
| C07 | 五级流水线；XSim/Python 参考 | 三种等待模式各 494 次退休；前推、load-use、延迟槽、存储恰好一次；真实阶段 CSV | 流水线尚未生成板级镜像 |
| C08 | 可重复功能回归；XSim/GNU/课程原件 | 原 teach_soc 接入流水线；28,970 trace 行、420 存储；另实际 GNU 重编译 46,951 字，与原 COE 一致，再跑原 golden 通过 | 当前启用 19 点；明确归档顺序以保持原函数地址，不声称全部 89 点 |
| C09 | 异常进入与返回；XSim | CP0 25 检查；流水线 13 个处理流程；BD/EPC、ERET、对齐、RI、溢出、syscall/break、外部/定时中断 | 文档声明的教学 CP0 子集 |
| C10 | 带 Cache 的 CPU；XSim/Python | 两路写回；3 个合法参数单元配置、4 个非法参数拒绝；6 组 CPU 联合回归、全后备 RAM 对照 | MMIO 绕过；无 flush 命令，测试以强制脏替换验证持久性 |
| C11 | 蜂鸣器扩展；Vivado/UART | 频率/禁用/复位断言、独立综合、SoC 串口触发和实际板卡命令 | 尚无实际声音录音；VGA 未选用 |
| C12 | 复现、评估、讲解、视频与公开代码 | 干净克隆 11 套回归；GNU 原程序重建；板卡重建；独立审查；资源/时序/CPI；中文 PDF、78 秒影片和裁图 | 物理外观/声音未观察；GitHub CI 仅提供未启用模板 |

这 12 项均已有实现与自动验证入口。C01/C05/C06/C11 的光学或声学观察没有被
串口遥测替代；C08 的结果限定为确实编译和执行的 19 点配置。不能据此写“所有学校验收
要求全部通过”。

## 证据入口

- [机器回归汇总](../evidence/results.json)：实际测试提交、11 项状态、PASS 标记、日志哈希。
- [课程基础结果](../evidence/course_basics.json)：六个配置和本地输入 SHA-256。
- [GNU 源码重建](gnu-rebuild.md)：现代工具链兼容调整、原布局依据和新镜像验证。
- [实板测试](../evidence/board.json) / [录屏](../evidence/recording.json) / [原始遥测](../evidence/live-telemetry.jsonl)。
- [FPGA 时序](../evidence/board-timing.rpt)、[资源](../evidence/board-utilization.rpt)、[DRC](../evidence/board-drc.rpt)。
- [课程基础说明](course-basics.md)、[teach_soc 适配](teach-soc.md)、[CPU/Cache 对照](cpu-cache.md)。

复现从 [reproduce.md](reproduce.md) 开始。测试源码中的断言是可运行的验收条件；
README 和截图是索引，不是测试替代品。
