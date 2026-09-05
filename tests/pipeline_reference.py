"""Independent instruction interpreter and deterministic generated test program."""
import random
def I(op,rs,rt,imm):return (op<<26)|(rs<<21)|(rt<<16)|(imm&65535)
def R(rs,rt,rd,fn,sa=0):return rs<<21|rt<<16|rd<<11|sa<<6|fn
def signed(v):return v if v<0x80000000 else v-0x100000000
def generate(path,mutate=False):
    rng=random.Random(0x5A17)
    code=[I(9,0,1,7),I(9,1,2,-3),R(2,2,3,33),I(43,0,3,0),I(35,0,4,0),R(4,4,5,33),I(43,0,5,4),I(4,5,5,2),I(9,5,6,1),I(43,0,1,100),I(5,5,6,2),I(9,6,7,1),I(43,0,1,100)]
    for n in range(220):
        a,b,d=[rng.randrange(1,16) for _ in range(3)]
        if n%11==0:code += [I(43,0,a,(n%32)*4),I(35,0,b,(n%32)*4),R(b,b,d,33)]
        elif n%3==0:code.append(R(a,b,d,rng.choice([33,35,36,37,38,39,42,43])))
        elif n%3==1:code.append(I(rng.choice([9,10,11,12,13,14]),a,d,rng.randrange(-32768,32768)))
        else:code.append(R(0,b,d,rng.choice([0,2,3]),rng.randrange(32)))
    # Lane stores, signed/unsigned loads, variable shifts and zero writes.
    code += [I(15,0,16,0x80ff),I(13,16,16,0x81fe),I(43,0,16,160)]
    for off in range(4):code += [I(32,0,17,160+off),I(36,0,18,160+off),I(40,0,16,180+off)]
    for off in (0,2):code += [I(33,0,17,160+off),I(37,0,18,160+off),I(41,0,16,184+off)]
    for shift in range(32):
        code += [I(9,0,17,shift)]+[R(17,16,18,fn) for fn in (4,6,7)]
    code += [R(18,18,0,33),I(9,0,19,-1)]
    for op in (4,5,6,7,1):
        for positive in (False,True):
            code += [I(9,0,19,1 if positive else -1),I(op,19,19 if op in (4,5) else 0,2),I(9,0,20,12),I(9,0,20,13)]
    # REGIMM link both outcomes, JAL and JALR (rs==rd), backward loop.
    for rt in (1,16,17):
        for val in (-1,1):code += [I(9,0,19,val),I(1,19,rt,2),I(9,31,20,1),I(9,0,20,13)]
    base=len(code)*4;code += [(3<<26)|((base+12)//4),I(9,31,20,0),I(9,0,20,99)]
    base=len(code)*4;code += [I(9,0,21,base+16),R(21,0,21,9),I(9,21,20,0),I(9,0,20,99)]
    code += [I(9,0,22,3),I(9,22,22,-1),I(7,22,0,-2),I(9,20,20,1),I(43,0,7,252)]
    regs=[0]*32;mem=[0]*256;pc=0;pending=None;expected=[]
    while pc//4<len(code):
        ins=code[pc//4];op=ins>>26;rs=(ins>>21)&31;rt=(ins>>16)&31;rd=(ins>>11)&31;sa=(ins>>6)&31;fn=ins&63
        a,b=regs[rs],regs[rt];imm=ins&65535;si=imm if imm<32768 else imm-65536;dest=rt;we=0;val=0;mw=0;ma=0;md=0;target=None
        if op==0 and fn in (8,9):
            target=a;dest=rd;we=int(fn==9);val=pc+8
        elif op==0:
            dest=rd;we=1
            val={0:lambda:b<<sa,2:lambda:b>>sa,3:lambda:signed(b)>>sa,4:lambda:b<<(a&31),6:lambda:b>>(a&31),7:lambda:signed(b)>>(a&31),33:lambda:a+b,35:lambda:a-b,36:lambda:a&b,37:lambda:a|b,38:lambda:a^b,39:lambda:~(a|b),42:lambda:int(signed(a)<signed(b)),43:lambda:int(a<b)}[fn]()
        elif op in (1,4,5,6,7):
            take={1:lambda:signed(a)<0 if rt in (0,16) else signed(a)>=0,4:lambda:a==b,5:lambda:a!=b,6:lambda:signed(a)<=0,7:lambda:signed(a)>0}[op]()
            target=pc+4+si*4 if take else pc+8
            if op==1 and rt in (16,17):dest=31;we=1;val=pc+8
        elif op in (2,3):target=((pc+4)&0xf0000000)|((ins&0x3ffffff)<<2);we=int(op==3);dest=31;val=pc+8
        elif op in (40,41,43):
            ma=(a+si)&0xffffffff;offset=ma&3;size={40:1,41:2,43:4}[op];md=(b<<(offset*8))&0xffffffff;mw=((1<<size)-1)<<offset
            for lane in range(4):
                if mw&(1<<lane):mem[ma//4]=(mem[ma//4]&~(255<<(8*lane)))|(md&(255<<(8*lane)))
        elif op in (32,33,35,36,37):
            addr=(a+si)&0xffffffff;size={32:1,33:2,35:4,36:1,37:2}[op];bits=size*8
            val=(mem[addr//4]>>((addr&3)*8))&((1<<bits)-1);we=1
            if op in (32,33) and val&(1<<(bits-1)):val-=1<<bits
        else:
            we=1;val={9:lambda:a+si,10:lambda:int(signed(a)<si),11:lambda:int(a<(si&0xffffffff)),12:lambda:a&imm,13:lambda:a|imm,14:lambda:a^imm,15:lambda:imm<<16}[op]()
        val &= 0xffffffff;we=int(bool(we and dest));
        if we:regs[dest]=val
        expected.append((pc,ins,we,dest if we else 0,val if we else 0,mw,ma,md))
        pc,pending=(pending if pending is not None else pc+4),target
    if mutate:
        row=list(expected[0]);row[4]^=1;expected[0]=tuple(row)
    (path/'pipeline_program.hex').write_text('\n'.join(f'{v:08x}' for v in code)+'\n')
    (path/'pipeline_expected.txt').write_text(str(len(expected))+'\n'+'\n'.join(' '.join(f'{v:x}' for v in row) for row in expected)+'\n')
