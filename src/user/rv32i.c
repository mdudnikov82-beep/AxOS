// RV32I интерпретатор для AxOS
// Поддерживает весь базовый набор RV32I (LUI, AUIPC, JAL, JALR, ветки,
// нагрузки/сохранения, ALU immediate, ALU reg-reg) и три ecall:
//   a7=1  : print_char(a0)
//   a7=4  : print_string(a0) — строка в памяти VM, нуль-терминированная
//   a7=10 : exit
//
// Использование:
//   rv32i          — запустить встроенный hello-world
//   rv32i FILE.RV  — загрузить плоский бинарник с диска и запустить

#include "axiom.h"
#include "malloc.h"

#define VM_MEM_SIZE  (16u * 1024u)
#define VM_MAX_CYCLES 2000000u

void ax_init_stack_guard(void) {}

static unsigned char *vm_mem;
static unsigned int  vm_reg[32];
static unsigned int  vm_pc;
static int           vm_halted;

static unsigned int sext(unsigned int val, unsigned int top_bit) {
    if ((val >> top_bit) & 1u)
        val |= ~((1u << top_bit) - 1u);
    return val;
}

static unsigned int mr8(unsigned int a) {
    if (a >= VM_MEM_SIZE) return 0;
    return vm_mem[a];
}
static unsigned int mr16(unsigned int a) {
    if (a + 1 >= VM_MEM_SIZE) return 0;
    return (unsigned int)vm_mem[a] | ((unsigned int)vm_mem[a+1] << 8);
}
static unsigned int mr32(unsigned int a) {
    if (a + 3 >= VM_MEM_SIZE) return 0;
    return (unsigned int)vm_mem[a]
         | ((unsigned int)vm_mem[a+1] << 8)
         | ((unsigned int)vm_mem[a+2] << 16)
         | ((unsigned int)vm_mem[a+3] << 24);
}
static void mw8(unsigned int a, unsigned int v) {
    if (a < VM_MEM_SIZE) vm_mem[a] = (unsigned char)v;
}
static void mw16(unsigned int a, unsigned int v) {
    if (a + 1 < VM_MEM_SIZE) { vm_mem[a] = v & 0xFF; vm_mem[a+1] = (v >> 8) & 0xFF; }
}
static void mw32(unsigned int a, unsigned int v) {
    if (a + 3 < VM_MEM_SIZE) {
        vm_mem[a]   =  v        & 0xFF;
        vm_mem[a+1] = (v >>  8) & 0xFF;
        vm_mem[a+2] = (v >> 16) & 0xFF;
        vm_mem[a+3] = (v >> 24) & 0xFF;
    }
}

static void vm_ecall(void) {
    unsigned int nr  = vm_reg[17]; // a7
    unsigned int a0  = vm_reg[10];
    if (nr == 1) {
        // print_char
        char buf[2] = { (char)(a0 & 0xFF), 0 };
        ax_print(buf);
    } else if (nr == 4) {
        // print_string из памяти VM
        unsigned int p = a0;
        while (p < VM_MEM_SIZE && vm_mem[p]) {
            char buf[2] = { (char)vm_mem[p++], 0 };
            ax_print(buf);
        }
    } else if (nr == 10) {
        vm_halted = 1;
    }
}

// Возвращает 1 если надо остановиться
static int vm_step(void) {
    if (vm_pc + 3 >= VM_MEM_SIZE) return 1;
    unsigned int ins = mr32(vm_pc);

    unsigned int op  = ins & 0x7Fu;
    unsigned int rd  = (ins >>  7) & 0x1Fu;
    unsigned int f3  = (ins >> 12) & 0x07u;
    unsigned int rs1 = (ins >> 15) & 0x1Fu;
    unsigned int rs2 = (ins >> 20) & 0x1Fu;
    unsigned int f7  = (ins >> 25) & 0x7Fu;

    unsigned int imm_i = sext(ins >> 20, 11);
    unsigned int imm_s = sext(((ins >> 25) << 5) | ((ins >> 7) & 0x1Fu), 11);
    unsigned int imm_b = sext(
        (((ins >> 31) & 1u) << 12) | (((ins >>  7) & 1u) << 11) |
        (((ins >> 25) & 0x3Fu) << 5) | (((ins >> 8) & 0xFu) << 1), 12);
    unsigned int imm_u = ins & 0xFFFFF000u;
    unsigned int imm_j = sext(
        (((ins >> 31) & 1u) << 20) | (((ins >> 12) & 0xFFu) << 12) |
        (((ins >> 20) & 1u) << 11) | (((ins >> 21) & 0x3FFu) << 1), 20);

    unsigned int npc = vm_pc + 4u;
    unsigned int v1  = vm_reg[rs1];
    unsigned int v2  = vm_reg[rs2];
    unsigned int res = 0;
    int write_rd = 1;

    switch (op) {
    case 0x37: res = imm_u; break;                    // LUI
    case 0x17: res = vm_pc + imm_u; break;            // AUIPC
    case 0x6F:                                         // JAL
        res = npc; npc = vm_pc + imm_j; break;
    case 0x67:                                         // JALR
        res = npc; npc = (v1 + imm_i) & ~1u; break;
    case 0x63: {                                       // BRANCH
        int taken = 0;
        switch (f3) {
        case 0: taken = (v1 == v2); break;
        case 1: taken = (v1 != v2); break;
        case 4: taken = ((int)v1 < (int)v2); break;
        case 5: taken = ((int)v1 >= (int)v2); break;
        case 6: taken = (v1 < v2); break;
        case 7: taken = (v1 >= v2); break;
        }
        if (taken) npc = vm_pc + imm_b;
        write_rd = 0; break;
    }
    case 0x03:                                         // LOAD
        switch (f3) {
        case 0: res = sext(mr8(v1+imm_i),  7); break; // LB
        case 1: res = sext(mr16(v1+imm_i),15); break; // LH
        case 2: res = mr32(v1+imm_i);          break; // LW
        case 4: res = mr8(v1+imm_i);           break; // LBU
        case 5: res = mr16(v1+imm_i);          break; // LHU
        default: write_rd = 0; break;
        }
        break;
    case 0x23:                                         // STORE
        switch (f3) {
        case 0: mw8( v1+imm_s, v2); break;
        case 1: mw16(v1+imm_s, v2); break;
        case 2: mw32(v1+imm_s, v2); break;
        }
        write_rd = 0; break;
    case 0x13: {                                       // OP-IMM
        unsigned int sh = rs2; // shamt = imm[4:0]
        switch (f3) {
        case 0: res = v1 + imm_i;                          break; // ADDI
        case 1: res = v1 << sh;                            break; // SLLI
        case 2: res = ((int)v1 < (int)imm_i) ? 1u : 0u;  break; // SLTI
        case 3: res = (v1 < imm_i) ? 1u : 0u;             break; // SLTIU
        case 4: res = v1 ^ imm_i;                          break; // XORI
        case 5: res = (f7 & 0x20u) ? (unsigned int)((int)v1 >> sh) : (v1 >> sh); break; // SRLI/SRAI
        case 6: res = v1 | imm_i;                          break; // ORI
        case 7: res = v1 & imm_i;                          break; // ANDI
        }
        break;
    }
    case 0x33:                                         // OP
        switch (f3) {
        case 0: res = (f7 & 0x20u) ? (v1 - v2) : (v1 + v2); break; // ADD/SUB
        case 1: res = v1 << (v2 & 0x1Fu);                    break; // SLL
        case 2: res = ((int)v1 < (int)v2) ? 1u : 0u;        break; // SLT
        case 3: res = (v1 < v2) ? 1u : 0u;                  break; // SLTU
        case 4: res = v1 ^ v2;                               break; // XOR
        case 5: res = (f7 & 0x20u) ? (unsigned int)((int)v1 >> (v2&31)) : (v1 >> (v2&31)); break; // SRL/SRA
        case 6: res = v1 | v2;                               break; // OR
        case 7: res = v1 & v2;                               break; // AND
        }
        break;
    case 0x73:                                         // SYSTEM
        vm_ecall();
        write_rd = 0; break;
    default:
        vm_halted = 1; write_rd = 0; break;
    }

    if (write_rd && rd) vm_reg[rd] = res;
    vm_reg[0] = 0;
    vm_pc = npc;
    return vm_halted;
}

// Встроенный hello-world (RV32I, загружается по адресу 0 VM)
// auipc s0, 0          — s0 = 0 (адрес программы)
// addi  s0, s0, 0x40  — s0 = 0x40 (строка)
// loop:
//   lbu  a0, 0(s0)
//   beq  a0, x0, done  (+20)
//   addi a7, x0, 1
//   ecall
//   addi s0, s0, 1
//   jal  x0, -20       (loop)
// done:
//   addi a7, x0, 10
//   ecall
// [0x40] "Hello from RV32I!\n\0"
static const unsigned char builtin_hello[] = {
    0x17,0x04,0x00,0x00,  // auipc s0, 0
    0x13,0x04,0x04,0x04,  // addi  s0, s0, 0x40
    0x03,0x45,0x04,0x00,  // lbu   a0, 0(s0)    <- loop
    0x63,0x0A,0x05,0x00,  // beq   a0, x0, +20
    0x93,0x08,0x10,0x00,  // addi  a7, x0, 1
    0x73,0x00,0x00,0x00,  // ecall
    0x13,0x04,0x14,0x00,  // addi  s0, s0, 1
    0x6F,0xF0,0xDF,0xFE,  // jal   x0, -20
    0x93,0x08,0xA0,0x00,  // addi  a7, x0, 10   <- done
    0x73,0x00,0x00,0x00,  // ecall
    // padding to offset 0x40
    0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
    0,0,0,0, 0,0,0,0,
    // string at 0x40
    'H','e','l','l','o',' ','f','r','o','m',' ',
    'R','V','3','2','I','!','\n',0
};

static void print_hex8(unsigned int v) {
    char hex[] = "0123456789ABCDEF";
    char buf[3] = { hex[(v>>4)&0xF], hex[v&0xF], 0 };
    ax_print(buf);
}
static void print_hex32(unsigned int v) {
    ax_print("0x");
    print_hex8(v >> 24); print_hex8(v >> 16);
    print_hex8(v >>  8); print_hex8(v);
}

int main(int argc, char** argv) {
    vm_mem = (unsigned char*)ax_malloc(VM_MEM_SIZE);
    if (!vm_mem) { ax_print("rv32i: out of memory\n"); return 1; }
    unsigned int prog_size = 0;

    if (argc >= 2) {
        prog_size = ax_readfile(argv[1], vm_mem, VM_MEM_SIZE);
        if (prog_size == 0) {
            ax_print("rv32i: cannot load '");
            ax_print(argv[1]);
            ax_print("'\n");
            return 1;
        }
        ax_print("[RV32I] loaded ");
        ax_print(argv[1]);
        ax_print("\n");
    } else {
        prog_size = sizeof(builtin_hello);
        for (unsigned int i = 0; i < prog_size; i++)
            vm_mem[i] = builtin_hello[i];
        ax_print("[RV32I] running built-in hello\n");
    }

    // Инициализация VM
    for (int i = 0; i < 32; i++) vm_reg[i] = 0;
    vm_reg[2] = VM_MEM_SIZE - 16u; // sp
    vm_pc     = 0;
    vm_halted = 0;

    unsigned int cycles = 0;
    while (!vm_halted && cycles < VM_MAX_CYCLES) {
        vm_step();
        cycles++;
    }

    if (cycles >= VM_MAX_CYCLES) {
        ax_print("[RV32I] timeout after ");
        print_hex32(cycles);
        ax_print(" cycles\n");
    } else {
        ax_print("[RV32I] halted at pc=");
        print_hex32(vm_pc);
        ax_print(" after ");
        print_hex32(cycles);
        ax_print(" cycles\n");
    }
    return 0;
}
