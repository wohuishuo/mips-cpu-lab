# CP0 integration contract

Module `cp0`: synchronous active-high rst; register reads combinational.
`read_addr[4:0] -> read_data[31:0]`; `write_valid`, `write_addr[4:0]`,
`write_data[31:0]` for committed MTC0 only. Exception commit inputs:
`exception_valid`, `exception_code[4:0]`, `exception_pc[31:0]`,
`exception_bd`, `exception_badvaddr[31:0]`; `eret` for committed return.
`hw_irq[5:0]` is synchronous to clk. Outputs status/cause/epc/badvaddr and
`irq_pending`. Cause IP[7:2] = hw_irq, IP[7] also includes timer. Software IP[1:0]
are writable through Cause bits 9:8. Count normally increments every clock in this
teaching implementation. An accepted Count write commits the software value instead
of that increment; writing Count equal to Compare sets sticky timer pending, while
writing it away from Compare does not. Equality is evaluated from the Count value
actually committed on the edge, including wrap from `0xffffffff` to zero. An accepted
Compare write clears timer pending even when its value equals the Count committed on
that edge.
Exception entry sets EXL; EPC/BD preserve the first exception while EXL is set.
Caller supplies branch PC for BD exceptions. ERET clears EXL. Priority:
reset > exception > eret > software write. Exception or ERET suppresses a simultaneous
Count write, so Count takes its normal increment and timer comparison on that edge.
BadVAddr is updated on AdEL/AdES only. PRId is a fixed teaching identifier.

Implemented register numbers: 8 BadVAddr, 9 Count, 11 Compare, 12 Status,
13 Cause, 14 EPC, 15 PRId. Unsupported reads return zero. No TLB, nested
exception stack or operating system compatibility is claimed.
