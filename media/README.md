# 演示与图片

- `mips-cpu-demo.mp4`：78秒、1920×1080、H.264/AAC，带本地中文合成语音和可切换中文字幕。
- `mips-cpu-demo.srt`：同文案字幕；句间时间按实际旁白时长分配，非逐词对齐。
- `fpga-live.png`：真实FPGA串口仪表盘录屏的一帧。
- `crop-display.png`、`crop-gpio.png`：同一真实录屏的数码管/GPIO区域裁图。
- `cover.png`、`datapath.png`：原创教学结构图。
- `pipeline-trace.png`：直接读取真实XSim阶段CSV绘制。
- `cache-performance.png`：读取实际联合回归日志绘制的等待模式对照。
- `narration.json`、`demo-chapters.json`：讲解文案与成片章节。

影片20–52秒是实际窗口录制。窗口连续读取连接开发板的115200串口，并真实发送
`a/0/1/a/b/r/a`命令。其数码管和LED图形是遥测示意，画面内已标注；它们不是实板照片。
最终录制期间保存298份真实数据包，可在`evidence/live-telemetry.jsonl`复查。

旁白由本机Microsoft Huihui语音合成，内容是本项目原创讲解，不是教师录音。
影片未录入现场麦克风声音。蜂鸣器章节证明发出了实板触发命令，不能据此声称
影片含有实际蜂鸣器录音。摄像头检查未拍到开发板，未将该检查画面加入交付文件。

在 Windows 上复现（Python 需带 Tk；安装 Pillow、pyserial、FFmpeg，并有
本地 zh-CN SAPI 语音、微软雅黑和 Consolas 字体）：

```powershell
python -m pip install -r requirements.txt Pillow
python scripts/render_figures.py
python scripts/record_dashboard.py --port COM6
powershell -NoProfile -File scripts/make_narration.ps1
python scripts/compose_demo.py
```

将 COM6 换成实际端口。实际录屏需要已下载配套 bitstream 的开发板；教学图需要
先运行对应仿真生成日志。录屏包含真实控灯、蜂鸣器和 CPU 复位命令。
裁图来自同一录屏，完整帧位于第 3 秒，显示区域为 `1060:336:58:442`，
GPIO 区域取第 11 秒的 `716:336:1142:442`（FFmpeg crop 格式）。

## 浏览器 CPU 工坊

`visual-lab-cpu.png` 与 `visual-lab-circuit.png` 来自真实浏览器执行本仓库 `docs/lab/` 的截图。
前者为默认程序第 7 拍，包含 load-use 停顿、已写入的 12 和逐位全加器；后者为可拼接电路页面。
它们是浏览器软件模型，来源与上面的 FPGA UART 录屏分别记录。

运行本地服务后执行 `npm run test:browser` 可重新生成 `build/visual-lab/` 中的截图；
本次发布分别复制 `cpu-full.png` 与 `circuit-desktop.png`，没有拼接或改写画面中的结果值。
