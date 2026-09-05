# Project-owned encoded MIPS fixture. Little endian; reset PC 0.
# .word preserves exact instructions and explicit delay slots; no MARS claim.
.text
    .word 0x3c14ffff # PC 0000: lui r20,0xffff ; uncached MMIO
    .word 0x24011000 # PC 0004: addiu r1,r0,0x1000 ; Fibonacci destination
    .word 0x24020000 # PC 0008: addiu r2,r0,0 ; F0
    .word 0x24030001 # PC 000c: addiu r3,r0,1 ; F1
    .word 0x24040014 # PC 0010: addiu r4,r0,20
    .word 0xac220000 # PC 0014: sw r2,0(r1) ; actual Fibonacci loop
    .word 0x8c250000 # PC 0018: lw r5,0(r1)
    .word 0x00a33021 # PC 001c: addu r6,r5,r3 ; immediate load use
    .word 0x00601021 # PC 0020: addu r2,r3,r0
    .word 0x00c01821 # PC 0024: addu r3,r6,r0
    .word 0xae840000 # PC 0028: sw r4,0(r20) ; exactly once per iteration
    .word 0x24210004 # PC 002c: addiu r1,r1,4
    .word 0x2484ffff # PC 0030: addiu r4,r4,-1
    .word 0x1480fff7 # PC 0034: bne r4,r0,fibonacci_loop
    .word 0x00000000 # PC 0038: nop ; branch delay slot
    .word 0x2007fff9 # PC 003c: addi r7,r0,-7 ; successful signed arithmetic
    .word 0x20e8000c # PC 0040: addi r8,r7,12
    .word 0x00e84820 # PC 0044: add r9,r7,r8
    .word 0x01075022 # PC 0048: sub r10,r8,r7
    .word 0x3c0b80ff # PC 004c: lui r11,0x80ff
    .word 0x356b81fe # PC 0050: ori r11,r11,0x81fe
    .word 0xac0b2300 # PC 0054: sw r11,0x2300(r0)
    .word 0x240c0090 # PC 0058: addiu r12,r0,144
    .word 0xa00c2300 # PC 005c: sb r12,0x2300(r0)
    .word 0x800d2300 # PC 0060: lb r13,lane(r0) ; sign extend
    .word 0x900e2300 # PC 0064: lbu r14,lane(r0)
    .word 0x240c0091 # PC 0068: addiu r12,r0,145
    .word 0xa00c2301 # PC 006c: sb r12,0x2301(r0)
    .word 0x800d2301 # PC 0070: lb r13,lane(r0) ; sign extend
    .word 0x900e2301 # PC 0074: lbu r14,lane(r0)
    .word 0x240c0092 # PC 0078: addiu r12,r0,146
    .word 0xa00c2302 # PC 007c: sb r12,0x2302(r0)
    .word 0x800d2302 # PC 0080: lb r13,lane(r0) ; sign extend
    .word 0x900e2302 # PC 0084: lbu r14,lane(r0)
    .word 0x240c0093 # PC 0088: addiu r12,r0,147
    .word 0xa00c2303 # PC 008c: sb r12,0x2303(r0)
    .word 0x800d2303 # PC 0090: lb r13,lane(r0) ; sign extend
    .word 0x900e2303 # PC 0094: lbu r14,lane(r0)
    .word 0xa40b2304 # PC 0098: sh r11,halfword(r0)
    .word 0x840d2304 # PC 009c: lh r13,halfword(r0)
    .word 0x940e2304 # PC 00a0: lhu r14,halfword(r0)
    .word 0xa40b2306 # PC 00a4: sh r11,halfword(r0)
    .word 0x840d2306 # PC 00a8: lh r13,halfword(r0)
    .word 0x940e2306 # PC 00ac: lhu r14,halfword(r0)
    .word 0x240f0064 # PC 00b0: addiu r15,r0,unique_value
    .word 0xac0f2000 # PC 00b4: sw r15,0x2000(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 00b8: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102000 # PC 00bc: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 00c0: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f0065 # PC 00c4: addiu r15,r0,unique_value
    .word 0xac0f2100 # PC 00c8: sw r15,0x2100(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 00cc: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102100 # PC 00d0: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 00d4: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f0066 # PC 00d8: addiu r15,r0,unique_value
    .word 0xac0f2200 # PC 00dc: sw r15,0x2200(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 00e0: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102200 # PC 00e4: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 00e8: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f0067 # PC 00ec: addiu r15,r0,unique_value
    .word 0xac0f2000 # PC 00f0: sw r15,0x2000(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 00f4: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102000 # PC 00f8: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 00fc: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f0068 # PC 0100: addiu r15,r0,unique_value
    .word 0xac0f2100 # PC 0104: sw r15,0x2100(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 0108: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102100 # PC 010c: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 0110: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f0069 # PC 0114: addiu r15,r0,unique_value
    .word 0xac0f2200 # PC 0118: sw r15,0x2200(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 011c: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102200 # PC 0120: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 0124: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f006a # PC 0128: addiu r15,r0,unique_value
    .word 0xac0f2000 # PC 012c: sw r15,0x2000(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 0130: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102000 # PC 0134: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 0138: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f006b # PC 013c: addiu r15,r0,unique_value
    .word 0xac0f2100 # PC 0140: sw r15,0x2100(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 0144: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102100 # PC 0148: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 014c: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f006c # PC 0150: addiu r15,r0,unique_value
    .word 0xac0f2200 # PC 0154: sw r15,0x2200(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 0158: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102200 # PC 015c: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 0160: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f006d # PC 0164: addiu r15,r0,unique_value
    .word 0xac0f2000 # PC 0168: sw r15,0x2000(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 016c: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102000 # PC 0170: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 0174: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f006e # PC 0178: addiu r15,r0,unique_value
    .word 0xac0f2100 # PC 017c: sw r15,0x2100(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 0180: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102100 # PC 0184: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 0188: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f006f # PC 018c: addiu r15,r0,unique_value
    .word 0xac0f2200 # PC 0190: sw r15,0x2200(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 0194: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102200 # PC 0198: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 019c: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f0070 # PC 01a0: addiu r15,r0,unique_value
    .word 0xac0f2000 # PC 01a4: sw r15,0x2000(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 01a8: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102000 # PC 01ac: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 01b0: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f0071 # PC 01b4: addiu r15,r0,unique_value
    .word 0xac0f2100 # PC 01b8: sw r15,0x2100(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 01bc: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102100 # PC 01c0: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 01c4: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f0072 # PC 01c8: addiu r15,r0,unique_value
    .word 0xac0f2200 # PC 01cc: sw r15,0x2200(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 01d0: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102200 # PC 01d4: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 01d8: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f0073 # PC 01dc: addiu r15,r0,unique_value
    .word 0xac0f2000 # PC 01e0: sw r15,0x2000(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 01e4: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102000 # PC 01e8: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 01ec: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f0074 # PC 01f0: addiu r15,r0,unique_value
    .word 0xac0f2100 # PC 01f4: sw r15,0x2100(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 01f8: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102100 # PC 01fc: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 0200: addu r17,r16,r15 ; load-use forwarding
    .word 0x240f0075 # PC 0204: addiu r15,r0,unique_value
    .word 0xac0f2200 # PC 0208: sw r15,0x2200(r0) ; conflicting dirty tag
    .word 0xae8f0004 # PC 020c: sw r15,4(r20) ; MMIO behind cache miss
    .word 0x8c102200 # PC 0210: lw r16,conflicting_address(r0)
    .word 0x020f8821 # PC 0214: addu r17,r16,r15 ; load-use forwarding
    .word 0x8e920008 # PC 0218: lw r18,8(r20) ; uncached constant read
    .word 0x024a9821 # PC 021c: addu r19,r18,r10
    .word 0x8c154000 # PC 0220: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154008 # PC 0224: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154010 # PC 0228: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154018 # PC 022c: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154020 # PC 0230: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154028 # PC 0234: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154030 # PC 0238: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154038 # PC 023c: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154040 # PC 0240: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154048 # PC 0244: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154050 # PC 0248: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154058 # PC 024c: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154060 # PC 0250: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154068 # PC 0254: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154070 # PC 0258: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154078 # PC 025c: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154080 # PC 0260: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154088 # PC 0264: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154090 # PC 0268: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c154098 # PC 026c: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1540a0 # PC 0270: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1540a8 # PC 0274: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1540b0 # PC 0278: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1540b8 # PC 027c: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1540c0 # PC 0280: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1540c8 # PC 0284: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1540d0 # PC 0288: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1540d8 # PC 028c: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1540e0 # PC 0290: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1540e8 # PC 0294: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1540f0 # PC 0298: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1540f8 # PC 029c: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155000 # PC 02a0: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155008 # PC 02a4: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155010 # PC 02a8: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155018 # PC 02ac: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155020 # PC 02b0: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155028 # PC 02b4: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155030 # PC 02b8: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155038 # PC 02bc: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155040 # PC 02c0: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155048 # PC 02c4: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155050 # PC 02c8: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155058 # PC 02cc: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155060 # PC 02d0: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155068 # PC 02d4: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155070 # PC 02d8: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155078 # PC 02dc: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155080 # PC 02e0: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155088 # PC 02e4: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155090 # PC 02e8: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c155098 # PC 02ec: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1550a0 # PC 02f0: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1550a8 # PC 02f4: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1550b0 # PC 02f8: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1550b8 # PC 02fc: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1550c0 # PC 0300: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1550c8 # PC 0304: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1550d0 # PC 0308: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1550d8 # PC 030c: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1550e0 # PC 0310: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1550e8 # PC 0314: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1550f0 # PC 0318: lw r21,flush_address(r0) ; eviction sweep
    .word 0x8c1550f8 # PC 031c: lw r21,flush_address(r0) ; eviction sweep
    .word 0x2416600d # PC 0320: addiu r22,r0,0x600d ; final retired marker
    .word 0x080000c9 # PC 0324: halt: j halt
    .word 0x00000000 # PC 0328: nop
