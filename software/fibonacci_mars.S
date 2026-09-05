# Original teaching program. MARS 4.5, delayed branches ENABLED.
# Store F(0)..F(11) at 0x10010000. No simulator-only syscalls.
.data
sequence: .space 48
.text
.globl main
main:
    lui   $s0, 0x1001
    addiu $t0, $zero, 0
    addiu $t1, $zero, 1
    addiu $t3, $zero, 12
loop:
    sw    $t0, 0($s0)
    addu  $t4, $t0, $t1
    addu  $t0, $t1, $zero
    addu  $t1, $t4, $zero
    addiu $t3, $t3, -1
    bne   $t3, $zero, loop
    addiu $s0, $s0, 4
done:
    j done
    nop
