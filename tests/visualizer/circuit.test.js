import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluateCircuit, validateCircuit, makeCustomUnit, PRESETS, fullAdder, rippleAdd } from '../../docs/lab/engine/circuit.js';

const node = (id,type,width=1,extra={}) => ({id,type,width,x:0,y:0,...extra});
const wire = (a,b,port='a',out='out') => ({from:{node:a,port:out},to:{node:b,port}});
const binary = (type,width=1) => ({nodes:[node('a','INPUT',width,{name:'A'}),node('b','INPUT',width,{name:'B'}),node('g',type,width),node('y','OUTPUT',width,{name:'Y'})],wires:[wire('a','g'),wire('b','g','b'),wire('g','y','in')]});

test('gate truth tables implement actual NAND, NOR, XOR, AND, OR', () => {
  const cases = {NAND:[1,1,1,0],NOR:[1,0,0,0],XOR:[0,1,1,0],AND:[0,0,0,1],OR:[0,1,1,1]};
  for(const [type,expected] of Object.entries(cases)) for(let i=0;i<4;i++)
    assert.equal(evaluateCircuit(binary(type),{A:i>>1,B:i&1}).outputs.Y,expected[i],`${type} ${i}`);
});

test('full adder yields independent eight-row truth table', () => {
  const rows = [[0,0],[1,0],[1,0],[0,1],[1,0],[0,1],[0,1],[1,1]];
  for(let i=0;i<8;i++) assert.deepEqual(fullAdder(i>>2,(i>>1)&1,i&1),{sum:rows[i][0],carry:rows[i][1]});
});

test('ripple carry exposes intermediate bits and uint32 wrap', () => {
  const result=rippleAdd(7,1,4);
  assert.equal(result.value,8);
  assert.deepEqual(result.bits.map(b=>[b.cin,b.sum,b.carry]),[[0,0,1],[1,0,1],[1,0,1],[1,1,0]]);
  assert.equal(rippleAdd(0xffffffff,1).value,0);
  assert.equal(rippleAdd(0x80000000,0).value,2147483648);
  assert.throws(()=>rippleAdd(1,2,33));
});

test('32-bit gates mask values without signed results', () => {
  assert.equal(evaluateCircuit(binary('XOR',32),{A:0xffffffff,B:0x7fffffff}).outputs.Y,2147483648);
  assert.equal(evaluateCircuit(binary('ADD',8),{A:255,B:2}).outputs.Y,1);
});

test('unwired and explicit unknown inputs propagate; controlling values resolve AND/OR', () => {
  const net=binary('XOR'); net.wires.splice(1,1);
  assert.equal(evaluateCircuit(net,{A:1}).outputs.Y,null);
  assert.equal(evaluateCircuit(binary('XOR'),{A:null,B:1}).outputs.Y,null);
  assert.equal(evaluateCircuit(binary('AND'),{A:0,B:null}).outputs.Y,0);
  assert.equal(evaluateCircuit(binary('OR'),{A:1,B:null}).outputs.Y,1);
});

test('stored unknown values stay unknown and malformed signal values do not become zero', () => {
  const net=binary('XOR');net.nodes[0].value=null;
  assert.equal(evaluateCircuit(net,{B:0}).outputs.Y,null);
  assert.equal(evaluateCircuit(net,{A:'bad',B:0}).outputs.Y,null);
  net.nodes[0].type='CONST';
  assert.equal(evaluateCircuit(net,{B:0}).outputs.Y,null);
});

test('MUX selector is one bit and ignores unknown unselected input', () => {
  const net=binary('MUX',8); net.nodes.push(node('s','INPUT',1,{name:'S'})); net.wires.push(wire('s','g','sel'));
  assert.deepEqual(validateCircuit(net),[]);
  assert.equal(evaluateCircuit(net,{A:42,B:null,S:0}).outputs.Y,42);
  assert.equal(evaluateCircuit(net,{A:42,B:7,S:1}).outputs.Y,7);
  assert.equal(evaluateCircuit(net,{A:42,B:42,S:null}).outputs.Y,42);
});

test('DFF samples next state without mutating old state and breaks feedback', () => {
  const net={nodes:[node('q','DFF'),node('n','NOT'),node('y','OUTPUT',1,{name:'Y'})],wires:[wire('q','n','in'),wire('n','q','d'),wire('q','y','in')]};
  assert.deepEqual(validateCircuit(net),[]);
  const state={q:0}; const first=evaluateCircuit(net,{},state);
  assert.equal(first.outputs.Y,0); assert.deepEqual(first.nextState,{q:1}); assert.deepEqual(state,{q:0});
  const second=evaluateCircuit(net,{},first.nextState);
  assert.equal(second.outputs.Y,1); assert.deepEqual(second.nextState,{q:0});
});

test('validation rejects malformed graphs, duplicate drivers, cycles and width mismatch', () => {
  const bads=[null,{}, {nodes:[],wires:'no'}];
  const duplicate=binary('XOR'); duplicate.wires.push(wire('b','g')); bads.push(duplicate);
  const widths=binary('XOR'); widths.nodes[0].width=32; bads.push(widths);
  const cycle={nodes:[node('n','NOT')],wires:[wire('n','n','in')]}; bads.push(cycle);
  const missing=binary('XOR'); missing.wires[0].from.node='absent'; bads.push(missing);
  const port=binary('XOR'); port.wires[0].from.port='fake'; bads.push(port);
  const duplicateId=binary('XOR'); duplicateId.nodes[1].id='a'; bads.push(duplicateId);
  const huge=binary('XOR'); huge.nodes[0].width=33; bads.push(huge);
  const names=binary('XOR'); names.nodes[1].name='A'; bads.push(names);
  for(const net of bads) {assert.ok(validateCircuit(net).length); assert.ok(evaluateCircuit(net).errors.length);}
});

test('first preset is a valid installed 32-bit ADD with immutable captured netlist', () => {
  const net=structuredClone(PRESETS[0].netlist), fn=makeCustomUnit(net);
  assert.equal(fn(7,5),12); assert.equal(fn(0xffffffff,1),0);
  net.nodes.find(n=>n.type==='ADD').type='XOR';
  assert.equal(fn(7,5),12);
  assert.equal(makeCustomUnit(net)(7,5),2);
});

test('CUSTOM rejects sequential, wrong widths, missing ports and unknown output', () => {
  assert.throws(()=>makeCustomUnit(binary('ADD',1)));
  const unknown=binary('ADD',32); unknown.wires.splice(0,1); assert.throws(()=>makeCustomUnit(unknown)(1,2));
  const sequential=binary('ADD',32); sequential.nodes.push(node('ff','DFF',32)); assert.throws(()=>makeCustomUnit(sequential));
  const extra=binary('ADD',32); extra.nodes.push(node('c','INPUT',32,{name:'C'})); assert.throws(()=>makeCustomUnit(extra));
});
