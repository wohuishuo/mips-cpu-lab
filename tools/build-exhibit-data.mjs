// Portable, deterministic extraction of project-owned code and published evidence.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
const root=new URL('../',import.meta.url);
const read=p=>readFileSync(new URL(p,root),'utf8');
const json=p=>JSON.parse(read(p));
const step=(title,body,path,start,end)=>({title,body,path,start,end});
const evidence=(label,value,kind,path)=>({label,value,kind,path});
const sim=(label,value)=>evidence(label,value,'rtl-simulation','evidence/results.json');
const course=(label,value)=>evidence(label,value,'rtl-simulation','evidence/course_basics.json');
const board=(label,value)=>evidence(label,value,'physical-board','evidence/board.json');
const chapters=[
 {id:'board',title:'板子怎样算出 89',kicker:'EES-338 · 单周期 SoC',question:'一段程序，怎样变成 RAM 中的 12 个数和板上的输出？',intro:'我们用 Verilog 在 FPGA 开发板里搭出一颗 CPU。它读入 MIPS 程序，一次次把两个数相加，最后把 89 送到显示电路。',steps:[
  step('从 0 和 1 开始','汇编把 RAM 基址、外设基址与循环次数装入寄存器。','software/board_demo.S',4,9),
  step('每轮保存一个数','sw 保存当前项；两次加法推进递推。分支后的地址递增是延迟槽。','software/board_demo.S',10,17),
  step('把结果交给外设','最后一项是 89。开关值移到显示高半字，并与结果异或形成 LED 值。','software/board_demo.S',18,31),
  step('真实板级连线','SoC 实例化单周期核；顶层同步开关输入并转换数码管输出接口。','rtl/soc/ees338_top.v',17,25)
 ],evidence:[board('实板串口','Fibonacci=89 · stores=12 · display=0x00810059 · LED=0xD8'),sim('SoC 仿真','12 次存储、40 字节 UART、GPIO 与 restart')],limits:'当前下板镜像是单周期 SoC。逐指令画面来自 RTL 仿真回放；串口是已保存的实板记录。GPIO 证明输出驱动值，不等于相机拍摄的数字外观。'},
 {id:'lab1',title:'Lab 1 · 开关与数码管',kicker:'输入、消抖、扫描',question:'八个开关怎样依次写满八位十六进制显示？',intro:'一次稳定按下保存一个字节；四个扫描相位轮流点亮两组数码管。',steps:[
  step('先让按键稳定','两级同步之后累计稳定时间，短脉冲不触发写入。','rtl/integration/lab1_num_led.v',10,23),
  step('一次写一个字节','从低字节开始写入，四次后回绕；长按只写一次。','rtl/integration/lab1_num_led.v',23,32),
  step('数字变成七根线','abcdefg 高有效段码将十六进制 0–F 变成各段亮灭。','rtl/integration/lab1_num_led.v',41,56),
  step('四个相位拼成完整显示','位选和两个段码同时由同一个相位生成。','rtl/integration/lab1_num_led.v',57,62)
 ],evidence:[course('自写模块','672 次外部输出断言'),course('原框架本地修复副本','独立运行同样 672 次断言')],limits:'交互是按自写 RTL 放慢的原理演示。课程接口段码高有效，与新板级 SoC 接口不同；这些仿真不构成 lab1 原工程上板证据。'},
 {id:'lab3',title:'Lab 3 · 程序驱动 CPU',kicker:'加法与 Fibonacci',question:'同一颗 CPU，为什么换 ROM 就能做两件事？',intro:'程序决定运算步骤，适配器把 CPU 的取指与读写接回课程原顶层。',steps:[
  step('保留课程地址接口','复位 PC 为 0xbfc00000；原 ROM/RAM 端口接入自写单周期核。','rtl/integration/lab3_mycpu.v',4,16),
  step('检查写入粒度','原单比特写使能只能表达整字存储；不把窄写放大成整字。','rtl/integration/lab3_mycpu.v',17,20),
  step('加法直接核对 A+B','测试通过原按键输入操作，独立计算预期和 LED 低八位。','tests/tb_lab3.sv',43,56),
  step('20 项和 12 项的区别','课程程序保存 20 项，最后 17711；板级独立程序保存 12 项，最后 89。','tests/tb_lab3.sv',63,77)
 ],evidence:[course('原 Fibonacci','20 次 RAM 写入，首次显示，218 周期'),course('明示加速版本','20 次显示；加法 36 个边界输入组合'),course('原加法程序','255 + 255 = 510，LED 低八位 254')],limits:'原 Fibonacci 镜像只运行到首次显示；全部显示来自等待常数加速版本。36 对输入不是穷举。这里是课程原顶层联合仿真，不是原 lab3 bitstream 实板测试。'},
 {id:'pipeline',title:'五级流水线',kicker:'扩展 · 真实 XSim 阶段记录',question:'前一条指令还没结束，后一条能否开始？',intro:'五个阶段重叠工作，数据相关和内存等待会让部分阶段暂停。',steps:[
  step('把指令保存在阶段寄存器','ID、EX、MEM、WB 各自保留有效位、PC 和指令。','rtl/core/pipeline_cpu.v',16,26),
  step('新结果前推给下一条','操作数按最新的流水阶段写回结果修正。','rtl/core/pipeline_cpu.v',28,38),
  step('相关时暂停前端','load-use 与 CP0 串行约束参与暂停判断。','rtl/core/pipeline_cpu.v',135,143),
  step('用独立模型判定退休','Python 参考模型构造预期执行行为，而不是复制波形输出。','tests/pipeline_reference.py',1,28)
 ],evidence:[evidence('阶段 CSV','三种等待模式，真实阶段快照','rtl-simulation','evidence/pipeline-stages.csv'),sim('独立退休对照','等待、13 次精确异常处理、外部/定时中断、活动复位')],limits:'这是流水线 RTL 仿真记录，不是当前下板镜像，也不是浏览器 CPU 引擎生成的波形。CSV 中无效阶段的 PC/指令仅为寄存器残留。'},
 {id:'lab5',title:'Lab 5 · 让 CPU 接受对照',kicker:'课程功能回归',question:'看到程序结束，是否就足够证明 CPU 算对了？',intro:'把每次寄存器写回与 golden trace 对照，第一处差异能定位执行偏离。',steps:[
  step('先核实实际启用项','运行器从 start.S 提取实际调用，并要求 TEST_NUM 为 19。','tests/run_teach_soc.py',25,40),
  step('检查参考记录完整性','golden trace 必须有 28,970 行且每行字段格式正确。','tests/run_teach_soc.py',49,51),
  step('故意制造差异检验判定','运行器支持 wrong、truncated、extra 和 missing golden 负例。','tests/run_teach_soc.py',52,64),
  step('保留每次运行的来源','结果保存实际启用调用、来源摘要和仿真边界。','tests/run_teach_soc.py',88,100)
 ],evidence:[sim('课程 SoC','28,970 行对照；420 次存储；19 个启用点'),evidence('GNU 重建','原 ROM 重建与 unchanged golden 对照','rtl-simulation','evidence/gnu-rebuild.json')],limits:'文档写有 89 个功能点，提供的配置实际启用 19 个；不声称全部 89 点通过。浏览器注入的差异是教学例子，不是历史回归失败。教师原 ROM 和 golden 文件不随公开站点分发。'},
 {id:'exceptions',title:'异常与返回',kicker:'扩展 · CP0',question:'遇到异常时，CPU 怎样记住从哪里返回？',intro:'程序出错时，CPU 先记下原因和位置，再去执行处理程序。CP0 就是保存这些信息的一组特殊寄存器。',steps:[
  step('读取原因和返回位置','Status、Cause、EPC 等寄存器提供异常处理程序需要的状态。','rtl/core/cp0.v',25,36),
  step('异常优先保存现场','设置 EXL，并在进入第一层异常时保存 EPC 和 BD。','rtl/core/cp0.v',46,50),
  step('执行 eret','返回时清除 EXL；软件写入优先级低于异常和 eret。','rtl/core/cp0.v',51,59),
  step('在流水线提交异常','CP0 接收 WB 保存的异常信息和返回控制。','rtl/core/pipeline_cpu.v',44,49)
 ],evidence:[sim('CP0 单元','25 次检查'),sim('流水线联合测试','13 次精确异常处理，以及外部和定时器中断')],limits:'浏览器 EPC/BD 示例是原理演示；13 次处理流程来自独立 RTL 回归。该扩展没有当前下板证据，也不表示完整 MIPS32 特权体系兼容。'},
 {id:'lab7',title:'Lab 7 · 两路 Cache',kicker:'命中、回填与脏写回',question:'CPU 反复读同一片内存，能否少等待几次？',intro:'两路缓存保留最近使用的数据行；脏行被替换前必须写回内存。',steps:[
  step('每组保留两路数据','两套 tag、valid、dirty 状态与数据阵列记录缓存内容。','rtl/cache/data_cache.v',38,55),
  step('用地址寻找数据','地址分解后比较请求行与两路标签，有效且相等才命中。','rtl/cache/data_cache.v',108,122),
  step('挑选替换的旧行','替换策略同时确定旧行是否已修改、原内存行地址是什么。','rtl/cache/data_cache.v',124,138),
  step('写回之后再回填','后端请求根据 WRITEBACK / REFILL 状态选择方向和地址。','rtl/cache/data_cache.v',140,152)
 ],evidence:[sim('CPU + Cache 联合回归','2 种几何配置 × 3 种等待模式 = 6 组'),sim('独立 Cache 回归','3 个有效变体；4 个非法参数测试')],limits:'浏览器交互是两路 Cache 原理模型。6 组联合回归来自真实 RTL；Cache 和流水线均不是当前下板镜像。'},
 {id:'uart',title:'串口里的真实板子',kicker:'实板记录 · 115200 8N1',question:'电脑怎样知道板子算出了什么，并改变 LED？',intro:'电脑问一次，板子回答一份状态。这里保留了实际的关灯、开灯、恢复自动控制和重新运行记录。',steps:[
  step('准备一份一致的快照','UART 有接收器、发送器与 320 位快照缓冲区。','rtl/peripherals/uart_control.v',13,23),
  step('查询返回 40 字节','? 命令保存 telemetry 和 MCPU 标识，随后每次发送一个字节。','rtl/peripherals/uart_control.v',30,33),
  step('关灯、开灯、恢复、重启','0、1、a 控制 LED 覆盖；r 只触发 CPU 复位脉冲。','rtl/peripherals/uart_control.v',33,38),
  step('每个字段从哪里来','SoC 把错误、退休、GPIO、显示、存储、周期、结果、PC、状态组装为遥测。','rtl/soc/lab_soc.v',88,93)
 ],evidence:[board('实板命令序列','automatic → led_off → led_on → automatic_restored → cpu_restarted'),evidence('连续采样','真实串口带时间戳记录','physical-board','evidence/live-telemetry.jsonl')],limits:'点击只选择或播放已保存的记录，不会发送板卡命令。40 字节协议帧可由记录字段重新编码，但 JSONL 保存的是解码后的字段，不是原始串口字节抓包。蜂鸣器命令记录不能证明实录声音。'}
];
const paths=new Set(chapters.flatMap(c=>c.steps.map(s=>s.path)));
for(const p of ['rtl/core/single_cycle_cpu.v','rtl/peripherals/seven_segment.v','rtl/peripherals/uart_rx.v','rtl/peripherals/uart_tx.v','rtl/integration/teach_mycpu_top.v','rtl/integration/cached_cpu.v','tests/tb_lab1.sv','tests/tb_cp0.sv','tests/tb_pipeline.sv','tests/tb_soc.sv','tests/tb_teach_soc.sv','tests/tb_cache.sv','tests/tb_cpu_cache.sv','tests/run_pipeline.py','tests/run_course_basics.py','tests/run_cpu_cache.py','tests/course_memory_models.sv','docs/course-map.md','docs/course-basics.md','docs/capabilities.md','docs/hardware.md','docs/cp0-contract.md','docs/teach-soc.md','docs/cache.md','evidence/README.md']) paths.add(p);
const sources=Object.fromEntries([...paths].sort().map(path=>{const bytes=Buffer.from(readFileSync(new URL(path,root),'utf8').replace(/\r\n/g,'\n'));return [path,{path,text:bytes.toString('utf8'),sha256:createHash('sha256').update(bytes).digest('hex')}];}));
for(const c of chapters)for(const s of c.steps)if(s.start<1||s.end<s.start||s.end>sources[s.path].text.split('\n').length)throw new Error(`Invalid source range: ${c.id} ${s.path}:${s.start}-${s.end}`);
const [header,...rows]=read('evidence/pipeline-stages.csv').trim().split(/\r?\n/);const fields=header.split(',');
const pipeline=rows.map(line=>Object.fromEntries(line.split(',').map((cell,i)=>[fields[i],/_(pc|instr)$/.test(fields[i])?cell:Number(cell)])));
const project={schema:1,sources,chapters,board:json('evidence/board.json'),telemetry:read('evidence/live-telemetry.jsonl').trim().split(/\r?\n/).map(JSON.parse),pipeline,results:json('evidence/results.json'),course:json('evidence/course_basics.json')};
mkdirSync(new URL('docs/lab/data/',root),{recursive:true});
writeFileSync(new URL('docs/lab/data/project.json',root),JSON.stringify(project,null,2)+'\n');
console.log(`Generated project.json: ${paths.size} exact sources, ${chapters.length} chapters, ${pipeline.length} pipeline rows, ${project.telemetry.length} telemetry records`);
