# Original educational fixture; MIPS little endian, explicit delay slots.
# Store F(0)..F(11) at byte addresses 0..44, then stop at PC 0x3c.
.set noreorder
.text
    addiu $t0, $zero, 0
    addiu $t1, $zero, 1
    addiu $t2, $zero, 0
    addiu $t3, $zero, 12
loop:
    sw    $t0, 0($t2)
    addu  $t4, $t0, $t1
    addu  $t0, $t1, $zero
    addu  $t1, $t4, $zero
    addiu $t2, $t2, 4
    addiu $t3, $t3, -1
    bne   $t3, $zero, loop
    sll   $zero, $zero, 0
    j     done
    sll   $zero, $zero, 0
    sll   $zero, $zero, 0
done:
    j     done
    sll   $zero, $zero, 0
