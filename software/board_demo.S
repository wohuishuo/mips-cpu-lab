# Original MIPS program. Enable delayed branching in MARS.
.text
.globl main
main:
    lui $s0, 0x1001
    lui $s1, 0x1f00
    addiu $t0, $zero, 0
    addiu $t1, $zero, 1
    addiu $t3, $zero, 12
fib_loop:
    sw $t0, 0($s0)
    addu $t4, $t0, $t1
    addu $t0, $t1, $zero
    addu $t1, $t4, $zero
    addiu $t3, $t3, -1
    bne $t3, $zero, fib_loop
    addiu $s0, $s0, 4
    lw $s2, -4($s0)
    sw $s2, 4($s1)
    sw $s2, 8($s1)
    addiu $t0, $zero, 1
    sw $t0, 32($s1)
display_loop:
    lw $t0, 0($s1)
    sll $t1, $t0, 16
    or $t1, $t1, $s2
    sw $t1, 8($s1)
    xor $t1, $t0, $s2
    sw $t1, 4($s1)
    j display_loop
    nop
