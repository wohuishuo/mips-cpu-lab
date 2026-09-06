# CPU 可视化实验台

用户要求：默认项目定制 CPU，从输入、逻辑电路、五级流水线直到寄存器和内存变化均可交互观察，并可像数字电路游戏一样拼接元件。

交付为 docs/lab/ 下零 CDN 的浏览器应用，以本项目 MIPS 语义为基础。浏览器软件模型与已验证 RTL 的范围分别说明；CUSTOM 为浏览器扩展，不宣称已在 FPGA 实现。既有 RTL、板级证据保持原含义。

## 垂直能力与验收

1. 输入到结果：可编辑汇编、A/B 输入、示例、加载错误定位、复位；默认程序必须实际使用 CUSTOM 并写入 RAM。
2. 周期到流水线：真实 IF/ID/EX/MEM/WB 状态、暂停/时钟单步/回退/速度、冒险停顿与转发事件；每条指令有 PC 与文本。
3. 状态到存储：32 个寄存器、至少 256 字节小端 RAM、变化高亮、时序记录。
4. 运算到逻辑门：可选择位，展示真实 A/B/Y 与 carry 的全加器 XOR/AND/OR 网络，CPU 绘为有端口和连线的电路板。
5. 元件到 CPU：可拖动门、点击端口连线、输入开关、DFF 时钟、删除、JSON 导入导出、关卡判定；32 位 A/B/Y 电路可装入 CPU，改变 CUSTOM 运算结果。

## 冻结模块接口

所有文件为原生 ES modules (.js)，根 package.json type=module。无 eval、无外部 CDN。

### CPU: docs/lab/engine/cpu.js

Exports `assemble(source)` -> `{instructions, labels}`; instruction fields at least `{pc,word,op,text,line}`. Throw Error with line for invalid source. Accept standard $names/$0..$31, decimal/hex signed immediates, labels, comments, .text/.globl (ignore), pseudo li/move/nop/halt and custom rd,rs,rt. Document supported subset; target standard 44 MIPS ops, no fake CP0.

Exports `PipelineCPU` constructor `(program, {inputA=7,inputB=5,waitCycles=0,custom=(a,b)=>(a+b)>>>0}={})`.
Methods `step()` returns snapshot; `snapshot()` returns deep JSON-serializable data; `restore(snapshot)` restores exact machine state (custom callback remains). No UI or DOM dependency.
Snapshot contains `{cycle,pc,halted,registers:number[32],memory:number[],stages:{IF,ID,EX,MEM,WB},events:string[],writes:{registers:number[],memory:number[]},retired:number,customTrace:null|{a,b,y}}`; stages null or `{pc,op,text,...}`. memory is byte array >=256 bytes. Other private state may be stored in snapshot for rewind. `$a0/$a1` initialized A/B. Real 5 stages, forwarding, load-use stalls, configurable data-memory wait, one branch delay slot, side effects exactly once; halt drains older instructions. Bounds/alignment throw visible error. Explicit zero, byte/half signed extension semantics.

### Circuit: docs/lab/engine/circuit.js

Exports `PRESETS` array of `{id,name,description,netlist}`; first is valid 32-bit custom ADD with named INPUT A/B and OUTPUT Y. Netlist `{nodes:[{id,type,width,x,y,name?,value?}],wires:[{from:{node,port},to:{node,port}}]}`.
Exports `evaluateCircuit(netlist,inputs={},state={})` -> `{outputs:{[name]:number|null},values:{[nodeId]:{[outputPort]:number|null}},nextState:{},errors:string[]}`; null is unknown. Inputs override INPUT name values. DFF output from state/default zero, nextState from D; evaluate never clocks state.
Exports `validateCircuit(netlist)` -> errors array. Reject duplicate drivers, combinational cycles, invalid/oversized structures, widths mismatch; DFF breaks combinational feedback.
Exports `makeCustomUnit(netlist)` -> `(a,b)=>uint32`, throw on invalid interface/unknown outputs; require combinational 32-bit A/B/Y. Exports `fullAdder(a,b,cin)` -> `{sum,carry}`; `rippleAdd(a,b,width=32)` -> `{value,bits:[{a,b,cin,sum,carry}]}`.
Exports `GATE_TYPES` object entries `{label,inputs:[port],outputs:[port]}` for INPUT(out),OUTPUT(in),CONST(out),NOT(in,out),AND/OR/XOR/NAND/NOR(a,b,out),MUX(a,b,sel,out),ADD(a,b,out),DFF(d,out). MUX sel width1; other ports nodewidth.

### Editor: docs/lab/circuit-editor.js and circuit-editor.css

Exports `mountCircuitEditor(container,{onInstall})` -> `{getNetlist(),destroy()}`. Owns DOM only inside container, CSS scoped .circuit-editor. onInstall(netlist) called by explicit install action after validation. Include draggable nodes/click output->input wires/input toggles/clock/delete/presets/import-export/live evaluation/challenges. No CPU imports. Provide reachable programmatic-free UI for all operations, keyboard-readable button labels, concise Chinese copy. Primary root UI supplies surrounding tab and status.

## Validation

Node tests independently cover ISA outcomes, timing hazards/branches/waits/rewind and gate truth tables, DFF and malformed graphs. Real browser tests exercise user controls and prove changed custom circuit changes CPU result; screenshots visually checked. Existing Python portable tests stay passing. Documentation provides one-command local launch, supported scope, tests and custom model/RTL distinction.
