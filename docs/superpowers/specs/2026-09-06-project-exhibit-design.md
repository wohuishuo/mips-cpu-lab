# 真实项目讲解站

用户纠正：不是初始化。需要在现有 localhost 网站演示真实板子 CPU 和每一个 lab，展示可视化及对应代码，让初学者快速理解。反对现有深色荧光、口号和模板化外观。

## 产品与事实

首页为浅色实验讲义，白/暖灰背景、墨色字、少量砖红色重点，左侧固定目录，中部交互讲解，右侧真实源码。默认叙事是 EES-338 上的单周期 SoC 如何算出 89。资料实际只有 lab1、lab3、lab5、lab7；另外展示流水线、异常、UART 作为扩展。不杜撰缺失实验编号。

每章包含：要解决的问题、一句话直觉、输入/操作、过程图、结果、对应源码行、验证依据。普通人先读结论，技术读者可展开源码。来源明确为实板串口记录、真实 RTL 仿真或可交互原理演示；不得把五级流水线/CUSTOM/Cache 说成当前下板镜像。

## 路由和代码

现有 docs/lab/index.html 改为讲解站入口。原 CPU/电路工坊保留到 docs/lab/playground.html，导航返回主站；原 JS 引擎和测试继续可用。原环境静态 HTML/ES modules，无新增框架或 CDN，保留用户当前 localhost:4173 地址。

章节 id：board、lab1、lab3、pipeline、lab5、exceptions、lab7、uart。hash 保留选中章节。

来源数据 docs/lab/data/project.json：
`{schema:1,sources:{[repoPath]:{path,text,sha256}},chapters:[{id,title,kicker,question,intro,steps:[{title,body,path,start,end}],evidence:[{label,value,kind,path}],limits:string}],board:{...board.json},telemetry:[{t,packet}],pipeline:[{mode,cycle,if_valid,if_pc,if_instr,...}],results:{...results.json},course:{...course_basics.json}}`。
所有源码原样提取，行号真实有效，摘要不复制教师课件。tools/build-exhibit-data.mjs 生成该文件，tests/exhibit/data.test.js 核对与 repo 源文件一致。pipeline PC/指令保持 CSV 十六进制字符串，cycle/mode/valid 是数字。telemetry 为真实记录。lab 编号与证据通过数据测试约束。

真实下板 SoC 的逐指令演示来自相同 RTL 的新 XSim 采样，另放 docs/lab/data/board-trace.json：
`{kind:'rtl-simulation',description,sourcePaths,romSha256,rows:[{cycle,pc,instr,regWrite,rd,value,memWrite,address,storeValue,readValue,registers:number[32],ram:number[12],display,led,done}],checks:{...}}`。pc/instr 等数值均 uint32；rows 为边沿执行的指令，registers/RAM/display/led 是该指令完成之后的值。未写 RAM 字用 null，不能谎称物理 RAM 复位清零。

## 交互

- board：逐步回放实际 RTL 执行，同步高亮 board_demo.S 和 single_cycle_cpu.v，RAM 12 项逐渐出现，展示七段显示/LED驱动。切换查看真实串口采样，明确不是实时连接。程序 89、display=0x00810059、LED=0xD8 应得到真实轨迹和板级记录支持。
- lab1：8 位开关、消抖后写一个字节、4 扫描相位、段码。交互是依据自写 RTL 的放慢演示，既有672检查为独立仿真证据。
- lab3：加法 A+B 和 Fibonacci 前20项演示，内存/程序步骤对应实际适配器与测试；课程最后17711与板子12项89分别说明。
- pipeline：读取真实阶段CSV，可按mode选等待，单步/播放，不能用旧JS教学流水线冒充这些记录。
- lab5：展示真实回归条目、golden trace对照流程、启用19点与89点文档声明区别；可交互注入一个示例差异并定位，不声称它是原回归失败。
- exceptions：异常保存EPC/BD/返回的教学例子，代码CP0与实测13处理流程相连。
- lab7：可操作两路cache tag/index/offset、命中/未命中/脏写回，明确浏览器原理模型与6组真实联合回归区别。
- uart：播放实板记录的off/on/auto/restart步骤，解码40字节MCPU协议，按键选择记录不发送板卡命令。

## 验收

全部8章可达、有真实源码高亮和验证来源；4个实际lab编号齐全；board轨迹来自XSim且核心结果断言；数据生成可重复；浏览器操作与手机布局验证；旧工坊功能保持通过。没有真实板照片时使用标明为连接示意的原创SVG，不生成伪造照片。
