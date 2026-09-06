# 项目讲解页验证 · 2026-09-06

目标：在原 `/lab/` 展示实际单周期 FPGA CPU、课程 lab1 / lab3 / lab5 / lab7，
把交互过程和真实代码行连接起来；原软件 CPU 与电路拼接保留在 `playground.html`。

- 29 项 Node 测试通过：旧 CPU/电路引擎与本地服务、源码来源和范围、所有阶段 CSV、显示模型、脏行写回，以及逐拍寄存器/RAM 转移。
- 讲解页 11 组 headless Edge 浏览器检查通过：播放/暂停、12 个 RAM 值与输出、8 个章节、源码跟随、课程 Fibonacci、加法输入、Cache 写回、延迟槽 EPC、UART 记录和 390px 布局。
- 原软件 CPU 与电路编辑器浏览器回归通过：拖动与连线、输入、关卡、DFF、导入导出、安装 XOR 后执行 CUSTOM，以及原流水线程序/回退/等待测试。
- 新 SoC 轨迹由 MARS 和 Vivado XSim 2019.2 实际生成：160 拍、12 次 Fibonacci 存储，最后 89、display=0x00810059、LED=0xD8。独立检查全部指令与 ROM、寄存器、RAM 状态及源文件摘要。
- 独立审阅发现并修正 lab3 加法/Fibonacci 的代码跟随错位，以及 UART 摘录遗漏关灯分支首行；修正后重跑通过。
- 已检查桌面讲解页、软件实验台和窄屏截图。截图直接保存浏览器结果，不重写显示数据。

## 可重复命令

```powershell
npm run lab
npm run test:visual
npm run test:exhibit
npm run test:browser
npm run test:exhibit:browser
```

浏览器测试需 Playwright，可用 `PLAYWRIGHT_CHANNEL=msedge`；`LAB_URL` 默认本地 4173。
讲解页测试输出 `build/exhibit/`，旧实验台输出 `build/visual-lab/`。
重新生成轨迹需要 `MARS_JAR`、Java 和 Vivado 2019.2，运行 `python scripts/export_exhibit_trace.py`。

## 证据范围

逐指令播放来自与实板相同的 RTL 的仿真，不是板上指令探针。
串口记录来自历史实板运行，不是实时连接。流水线、CP0 和 Cache 仍以仿真范围展示。
课程算法、显示扫描、Cache 交互与异常步骤明确标为原理模型。
