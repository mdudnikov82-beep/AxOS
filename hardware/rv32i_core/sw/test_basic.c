/* Real compiled test program for cpu_core.v - exercises arithmetic,
 * a store/load round trip, a loop (branches), and a taken branch, so
 * passing this is a much stronger signal than the hand-assembled
 * asm_test1.py program (that one only proves the datapath is wired
 * right; this one proves it also runs whatever a real compiler
 * happens to emit for ordinary C control flow). Returns its result
 * through main()'s return value - see start.S for how that becomes
 * the ECALL/tohost value the testbench checks. */
int main(void) {
    volatile int *mem = (volatile int *)0x1800;   /* well clear of .data/.bss */

    int a = 5, b = 10;
    int sum = a + b;          /* ADD */
    mem[0] = sum;             /* SW  */
    int loaded = mem[0];      /* LW  */

    int result = 0;
    for (int i = 0; i < 5; i++) {   /* loop -> branches */
        result += i;
    }
    /* expected so far: 0+1+2+3+4 = 10 */

    if (loaded == sum) {      /* taken branch */
        result += 100;
    }
    /* expected final: 110 */

    return result;
}
