// Slowed-down functional explanations, separate from the recorded RTL traces.
const glyphs=[126,48,109,121,51,91,95,112,127,123,119,31,78,61,79,71];
export class DisplayLab {
  constructor(){this.value=0;this.byte=0;}
  capture(value){this.value=((this.value&~(255<<(this.byte*8)))|((value&255)<<(this.byte*8)))>>>0;this.byte=(this.byte+1)%4;}
  scan(phase){const low=(this.value>>>(phase*4))&15,high=(this.value>>>(16+phase*4))&15;return{digits:0x11<<phase,low,high,segments0:glyphs[low],segments1:glyphs[high]};}
}
export class CacheLab {
  constructor(){this.sets=Array.from({length:16},()=>({ways:[null,null],lru:0}));this.backing=new Map();this.hits=0;this.misses=0;this.writebacks=0;}
  access(address,write){
    if(!Number.isInteger(address)||address<0||address>0xffffffff||address%4)throw new Error('请输入 32 位范围内、4 字节对齐的地址。');
    const set=(address>>>4)&15,tag=address>>>8,word=(address>>>2)&3,group=this.sets[set];
    let way=group.ways.findIndex(line=>line?.tag===tag),kind='hit',evicted=null;
    if(way>=0)this.hits++;
    else{
      this.misses++;kind='miss';way=group.ways.findIndex(line=>line===null);if(way<0)way=group.lru;
      const old=group.ways[way];
      if(old?.dirty){this.writebacks++;kind='writeback';evicted=old.tag*256+set*16;old.data.forEach((value,i)=>this.backing.set(evicted+i*4,value));}
      const base=Math.floor(address/16)*16;
      group.ways[way]={tag,dirty:false,data:Array.from({length:4},(_,i)=>this.backing.get(base+i*4)||0)};
    }
    const line=group.ways[way];if(write!==undefined){line.data[word]=write>>>0;line.dirty=true;}
    group.lru=1-way;return{kind,set,tag,word,way,value:line.data[word],evicted,address,write:write!==undefined};
  }
}
