// RV32IM интерпретатор для AxOS с MTE (программный аналог ARM) и CHERI capability pointers
// Поддерживает RV32I + расширение M (умножение/деление) и ecall:
//   a7=1  : print_char(a0)
//   a7=4  : print_string(a0) — строка в памяти VM, нуль-терминированная
//   a7=10 : exit
//   a7=20 : mte_malloc(size=a0) → tagged ptr в a0 (0=OOM)
//   a7=21 : mte_free(tagged_ptr=a0) — retag гранул, ловит UAF на след. обращении
//   a7=22 : mte_tag(ptr=a0, size=a1, tag=a2) — вручную тегировать регион
//   a7=57 : close(fd=a0) → a0=0
//   a7=63 : read(fd=a0, buf=a1, count=a2) → a0=bytes
//   a7=64 : write(fd=a0, buf=a1, count=a2) → a0=bytes (fd=1,2 → экран)
//   a7=93 : exit (Linux compat, a0=exit_code)
//   a7=1024: open(filename=a0, flags=a1) → a0=fd (-1 error)
//
// MTE (Memory Tagging Extension — программный аналог ARM MTE):
//   Каждые 16 байт VM-памяти (гранула) имеют 8-битный тег в shadow-массиве.
//   Биты [31:24] указателя = ожидаемый тег. Тег=0 → нетегированный доступ
//   (проверка пропускается). Несовпадение тегов → MTE FAULT, VM останавливается.
//   mte_malloc возвращает tagged ptr; mte_free меняет тег гранул → UAF = fault.
//
// CHERI ecalls (30-41):
//   a7=30 : cap_malloc(size=a0) → cap_regs[10] = {base,len,perms=R|W,tag=1}
//   a7=31 : cap_free           → cap_regs[10].tag=0 (UAF ловится TAG fault)
//   a7=32 : cap_restrict(perms=a0) → монотонное сужение прав (нельзя добавить)
//   a7=33 : cap_getbase        → a0 = cap_regs[10].base
//   a7=34 : cap_getlen         → a0 = cap_regs[10].length
//   a7=35 : cap_getperms       → a0 = cap_regs[10].perms
//   a7=36 : cap_seal           → cap_regs[10].sealed=1 (нельзя deref)
//   a7=38 : cap_load8(offset=a0)          → a0, bounds+perm check
//   a7=39 : cap_store8(offset=a0, val=a1) → bounds+perm check
//   a7=40 : cap_load32(offset=a0)         → a0
//   a7=41 : cap_store32(offset=a0, val=a1)
//
// Использование:
//   rv32i_full               — встроенный hello-world
//   rv32i_full --mte-test    — тест MTE (UAF через shadow retag)
//   rv32i_full --cheri-test  — тест CHERI bounds checking
//   rv32i_full --cheri-uaf   — тест CHERI use-after-free (TAG fault)
//   rv32i_full --cheri-perm  — тест CHERI permission narrowing (PERM fault)
//   rv32i_full --cheri-seal  — тест CHERI sealed capability (SEALED fault)
//   rv32i_full FILE.RV       — загрузить плоский бинарник с диска

#include "axiom.h"
#include "malloc.h"

#define VM_MEM_SIZE   (16u * 1024u)
#define VM_MAX_CYCLES 2000000u

// --- MTE константы ---
#define MTE_GRANULE    16u                   // байт на гранулу (как ARM MTE)
#define MTE_SHIFT      24u                   // тег в битах [31:24] указателя
#define MTE_TAG_MASK   0xFFu                 // 8-битный тег (vs 4-бит ARM MTE)
#define MTE_ADDR_MASK  0x00FFFFFFu           // маска адреса (биты [23:0])
#define MTE_NGRANULES  (VM_MEM_SIZE / MTE_GRANULE)  // 1024

void ax_init_stack_guard(void) {}

static unsigned char *vm_mem;
static unsigned int  vm_reg[32];
static unsigned int  vm_pc;
static int           vm_halted;

// --- CHERI capability ---
#define CHERI_PERM_LOAD   0x01u
#define CHERI_PERM_STORE  0x02u
#define CHERI_PERM_EXEC   0x04u
#define CHERI_PERM_GLOBAL 0x08u

typedef struct {
    unsigned int  base;
    unsigned int  length;
    unsigned char perms;
    unsigned char tag;    // 1 = valid capability, 0 = untagged/freed
    unsigned char sealed; // 1 = sealed token, нельзя разыменовывать
    unsigned char _pad;
} Cap;

// --- MTE shadow ---
static unsigned char vm_tags[MTE_NGRANULES];       // тег каждой гранулы
static unsigned int  vm_alloc_ng[MTE_NGRANULES];   // кол-во гранул alloc от [i]
static unsigned int  vm_heap_ptr;
static unsigned int  mte_prng;

// --- CHERI capability register file (параллельно vm_reg) ---
static Cap cap_regs[32];

// fd table
#define VM_MAX_FDS 8
#define VM_FD_SCREEN (-2)
static int vm_fd[VM_MAX_FDS];

static void vm_fd_init(void) {
    for (int i = 0; i < VM_MAX_FDS; i++) vm_fd[i] = -1;
    vm_fd[0] = -1;
    vm_fd[1] = VM_FD_SCREEN;
    vm_fd[2] = VM_FD_SCREEN;
}

static unsigned int sext(unsigned int val, unsigned int top_bit) {
    if ((val >> top_bit) & 1u)
        val |= ~((1u << top_bit) - 1u);
    return val;
}

// --- вспомогательный вывод (нужен vm_mte_fault) ---
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

// --- MTE PRNG: xorshift32, никогда не возвращает 0 ---
static unsigned int mte_rand_tag(void) {
    mte_prng ^= mte_prng << 13;
    mte_prng ^= mte_prng >> 17;
    mte_prng ^= mte_prng << 5;
    unsigned int t = (mte_prng >> 8) & MTE_TAG_MASK;
    return t ? t : 1u;
}

static unsigned int mte_rand_tag_ne(unsigned int old) {
    unsigned int t;
    do { t = mte_rand_tag(); } while (t == old);
    return t;
}

// --- MTE fault: печатает диагностику и останавливает VM ---
static void vm_mte_fault(unsigned int ptr, int is_write) {
    unsigned int ptr_tag = (ptr >> MTE_SHIFT) & MTE_TAG_MASK;
    unsigned int real_a  = ptr & MTE_ADDR_MASK;
    unsigned int mem_tag = (real_a < VM_MEM_SIZE)
                         ? (unsigned int)vm_tags[real_a / MTE_GRANULE] : 0u;
    ax_print("\n\033[41;37m[MTE FAULT] ");
    ax_print(is_write ? "STORE" : "LOAD ");
    ax_print(" addr="); print_hex32(ptr);
    ax_print(" ptr_tag=0x"); print_hex8(ptr_tag);
    ax_print(" mem_tag=0x"); print_hex8(mem_tag);
    ax_print(" pc=");   print_hex32(vm_pc);
    ax_print("\033[0m\n");
    vm_halted = 1;
}

// --- CHERI fault и проверка ---
static void vm_cheri_fault(const char *kind, unsigned int ea,
                            unsigned int base, unsigned int length) {
    ax_print("\n\033[44;37m[CHERI FAULT] ");
    ax_print(kind);
    ax_print(" addr="); print_hex32(ea);
    if (length) {
        ax_print(" bounds=["); print_hex32(base);
        ax_print(","); print_hex32(base + length);
        ax_print(")");
    }
    ax_print(" pc="); print_hex32(vm_pc);
    ax_print("\033[0m\n");
    vm_halted = 1;
}

// Проверяет cap[10]; возвращает 1 если OK, 0 при fault.
static int cheri_check(const Cap *c, unsigned int offset, unsigned int size, int is_write) {
    if (!c->tag) {
        vm_cheri_fault("TAG: untagged capability", c->base + offset, 0, 0);
        return 0;
    }
    if (c->sealed) {
        vm_cheri_fault("SEALED: cannot deref sealed cap", c->base + offset, c->base, c->length);
        return 0;
    }
    unsigned char need = is_write ? CHERI_PERM_STORE : CHERI_PERM_LOAD;
    if (!(c->perms & need)) {
        vm_cheri_fault(is_write ? "PERM: no STORE permission" : "PERM: no LOAD permission",
                       c->base + offset, c->base, c->length);
        return 0;
    }
    if (offset >= c->length || size > c->length - offset) {
        vm_cheri_fault("BOUNDS: out of range", c->base + offset, c->base, c->length);
        return 0;
    }
    return 1;
}

// Возвращает 1 если проверка прошла. ptr_tag=0 → нетегированный, skip.
static int mte_check(unsigned int ptr, int is_write) {
    unsigned int ptr_tag = (ptr >> MTE_SHIFT) & MTE_TAG_MASK;
    if (ptr_tag == 0) return 1;
    unsigned int real_a = ptr & MTE_ADDR_MASK;
    if (real_a >= VM_MEM_SIZE) { vm_mte_fault(ptr, is_write); return 0; }
    if ((unsigned int)vm_tags[real_a / MTE_GRANULE] != ptr_tag) {
        vm_mte_fault(ptr, is_write);
        return 0;
    }
    return 1;
}

// --- Доступ к памяти VM с MTE-проверкой ---
static unsigned int mr8(unsigned int a) {
    if (!mte_check(a, 0)) return 0;
    unsigned int ra = a & MTE_ADDR_MASK;
    if (ra >= VM_MEM_SIZE) return 0;
    return vm_mem[ra];
}
static unsigned int mr16(unsigned int a) {
    if (!mte_check(a, 0)) return 0;
    unsigned int ra = a & MTE_ADDR_MASK;
    if (ra + 1 >= VM_MEM_SIZE) return 0;
    return (unsigned int)vm_mem[ra] | ((unsigned int)vm_mem[ra+1] << 8);
}
static unsigned int mr32(unsigned int a) {
    if (!mte_check(a, 0)) return 0;
    unsigned int ra = a & MTE_ADDR_MASK;
    if (ra + 3 >= VM_MEM_SIZE) return 0;
    return (unsigned int)vm_mem[ra]
         | ((unsigned int)vm_mem[ra+1] << 8)
         | ((unsigned int)vm_mem[ra+2] << 16)
         | ((unsigned int)vm_mem[ra+3] << 24);
}
static void mw8(unsigned int a, unsigned int v) {
    if (!mte_check(a, 1)) return;
    unsigned int ra = a & MTE_ADDR_MASK;
    if (ra < VM_MEM_SIZE) vm_mem[ra] = (unsigned char)v;
}
static void mw16(unsigned int a, unsigned int v) {
    if (!mte_check(a, 1)) return;
    unsigned int ra = a & MTE_ADDR_MASK;
    if (ra + 1 < VM_MEM_SIZE) { vm_mem[ra] = v & 0xFF; vm_mem[ra+1] = (v>>8) & 0xFF; }
}
static void mw32(unsigned int a, unsigned int v) {
    if (!mte_check(a, 1)) return;
    unsigned int ra = a & MTE_ADDR_MASK;
    if (ra + 3 < VM_MEM_SIZE) {
        vm_mem[ra]   =  v        & 0xFF;
        vm_mem[ra+1] = (v >>  8) & 0xFF;
        vm_mem[ra+2] = (v >> 16) & 0xFF;
        vm_mem[ra+3] = (v >> 24) & 0xFF;
    }
}

// Instruction fetch: обходит MTE (PC всегда нетегирован)
static unsigned int vm_ifetch(unsigned int pc) {
    unsigned int ra = pc & MTE_ADDR_MASK;
    if (ra + 3 >= VM_MEM_SIZE) return 0;
    return (unsigned int)vm_mem[ra]
         | ((unsigned int)vm_mem[ra+1] << 8)
         | ((unsigned int)vm_mem[ra+2] << 16)
         | ((unsigned int)vm_mem[ra+3] << 24);
}

static void vm_screen_write(unsigned int ptr, unsigned int count) {
    char buf[2] = {0, 0};
    for (unsigned int i = 0; i < count && ptr + i < VM_MEM_SIZE; i++) {
        buf[0] = (char)vm_mem[ptr + i];
        ax_print(buf);
    }
}

static void vm_copy_str(unsigned int vm_ptr, char* dst, unsigned int max) {
    unsigned int i = 0;
    while (i + 1 < max && vm_ptr + i < VM_MEM_SIZE && vm_mem[vm_ptr + i])
        dst[i] = (char)vm_mem[vm_ptr + i++];
    dst[i] = '\0';
}

static void vm_ecall(void) {
    unsigned int nr = vm_reg[17]; // a7
    unsigned int a0 = vm_reg[10];
    unsigned int a1 = vm_reg[11];
    unsigned int a2 = vm_reg[12];

    if (nr == 1) {
        char buf[2] = { (char)(a0 & 0xFF), 0 };
        ax_print(buf);
    } else if (nr == 4) {
        unsigned int p = a0 & MTE_ADDR_MASK;
        while (p < VM_MEM_SIZE && vm_mem[p]) {
            char buf[2] = { (char)vm_mem[p++], 0 };
            ax_print(buf);
        }
    } else if (nr == 10 || nr == 93) {
        vm_halted = 1;
    } else if (nr == 20) {
        // mte_malloc(size=a0) → tagged ptr в a0
        if (a0 == 0) { vm_reg[10] = 0; return; }
        unsigned int ng    = (a0 + MTE_GRANULE - 1) / MTE_GRANULE;
        unsigned int bytes = ng * MTE_GRANULE;
        unsigned int sp    = vm_reg[2] & MTE_ADDR_MASK;
        if (vm_heap_ptr + bytes > sp - 64u) { vm_reg[10] = 0; return; }
        unsigned int rptr = vm_heap_ptr;
        vm_heap_ptr += bytes;
        unsigned int tag = mte_rand_tag();
        for (unsigned int i = 0; i < ng; i++)
            vm_tags[rptr / MTE_GRANULE + i] = (unsigned char)tag;
        vm_alloc_ng[rptr / MTE_GRANULE] = ng;
        vm_reg[10] = ((tag << MTE_SHIFT) & 0xFF000000u) | rptr;
    } else if (nr == 21) {
        // mte_free(tagged_ptr=a0) — retag гранул, UAF поймается на след. mr/mw
        unsigned int ptr_tag = (a0 >> MTE_SHIFT) & MTE_TAG_MASK;
        if (ptr_tag == 0) return;
        unsigned int real_a = a0 & MTE_ADDR_MASK;
        if (real_a >= VM_MEM_SIZE) return;
        unsigned int gi = real_a / MTE_GRANULE;
        unsigned int ng = vm_alloc_ng[gi];
        if (ng == 0) return;
        unsigned int new_tag = mte_rand_tag_ne(ptr_tag);
        for (unsigned int i = 0; i < ng; i++)
            vm_tags[gi + i] = (unsigned char)new_tag;
        vm_alloc_ng[gi] = 0;
    } else if (nr == 22) {
        // mte_tag(ptr=a0, size=a1, tag=a2) — вручную тегировать регион
        unsigned int rptr = a0 & MTE_ADDR_MASK;
        unsigned int ng   = (a1 + MTE_GRANULE - 1) / MTE_GRANULE;
        unsigned int tag  = a2 & MTE_TAG_MASK;
        for (unsigned int i = 0; i < ng && (rptr / MTE_GRANULE + i) < MTE_NGRANULES; i++)
            vm_tags[rptr / MTE_GRANULE + i] = (unsigned char)tag;
    } else if (nr == 64) {
        unsigned int written = 0;
        if (a0 < VM_MAX_FDS && a1 < VM_MEM_SIZE) {
            unsigned int cnt = a2;
            if (a1 + cnt > VM_MEM_SIZE) cnt = VM_MEM_SIZE - a1;
            if (vm_fd[a0] == VM_FD_SCREEN) {
                vm_screen_write(a1, cnt);
                written = cnt;
            } else if (vm_fd[a0] >= 0) {
                int r = ax_fwrite(vm_fd[a0], vm_mem + a1, cnt);
                written = (r > 0) ? (unsigned int)r : 0;
            }
        }
        vm_reg[10] = written;
    } else if (nr == 63) {
        unsigned int got = 0;
        if (a0 < VM_MAX_FDS && a1 < VM_MEM_SIZE && vm_fd[a0] >= 0) {
            unsigned int cnt = a2;
            if (a1 + cnt > VM_MEM_SIZE) cnt = VM_MEM_SIZE - a1;
            int r = ax_fread(vm_fd[a0], vm_mem + a1, cnt);
            got = (r > 0) ? (unsigned int)r : 0;
        }
        vm_reg[10] = got;
    } else if (nr == 1024) {
        char name[24];
        vm_copy_str(a0, name, sizeof(name));
        int fd = -1;
        for (int i = 3; i < VM_MAX_FDS; i++) {
            if (vm_fd[i] == -1) {
                int hfd = ax_open(name, (int)a1);
                if (hfd >= 0) { vm_fd[i] = hfd; fd = i; }
                break;
            }
        }
        vm_reg[10] = (unsigned int)(int)fd;
    } else if (nr == 57) {
        if (a0 >= 3 && a0 < VM_MAX_FDS && vm_fd[a0] >= 0) {
            ax_close(vm_fd[a0]);
            vm_fd[a0] = -1;
        }
        vm_reg[10] = 0;
    // --- CHERI ecalls ---
    } else if (nr == 30) {
        // cap_malloc(size=a0) → cap_regs[10]
        unsigned int sz = a0;
        if (sz == 0) { cap_regs[10].tag = 0; return; }
        unsigned int aligned = (sz + 7u) & ~7u;
        if (vm_heap_ptr + aligned > (vm_reg[2] - 64u)) { cap_regs[10].tag = 0; return; }
        Cap c; c.base = vm_heap_ptr; c.length = sz;
        c.perms = CHERI_PERM_LOAD | CHERI_PERM_STORE;
        c.tag = 1; c.sealed = 0; c._pad = 0;
        cap_regs[10] = c;
        vm_heap_ptr += aligned;
        ax_print("[CHERI] cap_malloc("); print_hex32(sz);
        ax_print(") base="); print_hex32(c.base);
        ax_print(" len="); print_hex32(c.length);
        ax_print(" perms=R|W tag=1\n");
    } else if (nr == 31) {
        // cap_free: tag = 0 → следующий deref = TAG FAULT
        cap_regs[10].tag = 0;
    } else if (nr == 32) {
        // cap_restrict(new_perms=a0): монотонное сужение прав
        Cap *c = &cap_regs[10];
        if (!c->tag) { vm_cheri_fault("TAG: restrict on untagged cap", 0, 0, 0); return; }
        c->perms &= (unsigned char)(a0 & 0x0Fu);
        ax_print("[CHERI] perms restricted to 0x"); print_hex8(c->perms); ax_print("\n");
    } else if (nr == 33) {
        // cap_getbase → a0
        vm_reg[10] = cap_regs[10].base;
    } else if (nr == 34) {
        // cap_getlen → a0
        vm_reg[10] = cap_regs[10].length;
    } else if (nr == 35) {
        // cap_getperms → a0
        vm_reg[10] = cap_regs[10].perms;
    } else if (nr == 36) {
        // cap_seal: помечает capability как sealed
        Cap *c = &cap_regs[10];
        if (!c->tag) { vm_cheri_fault("TAG: seal on untagged cap", 0, 0, 0); return; }
        c->sealed = 1;
        ax_print("[CHERI] capability sealed\n");
    } else if (nr == 38) {
        // cap_load8(offset=a0) → a0
        Cap *c = &cap_regs[10];
        if (!cheri_check(c, a0, 1, 0)) return;
        unsigned int addr = c->base + a0;
        vm_reg[10] = (addr < VM_MEM_SIZE) ? vm_mem[addr] : 0u;
    } else if (nr == 39) {
        // cap_store8(offset=a0, value=a1)
        Cap *c = &cap_regs[10];
        if (!cheri_check(c, a0, 1, 1)) return;
        unsigned int addr = c->base + a0;
        if (addr < VM_MEM_SIZE) vm_mem[addr] = (unsigned char)a1;
    } else if (nr == 40) {
        // cap_load32(offset=a0) → a0
        Cap *c = &cap_regs[10];
        if (!cheri_check(c, a0, 4, 0)) return;
        unsigned int addr = c->base + a0;
        if (addr + 3 < VM_MEM_SIZE)
            vm_reg[10] = (unsigned int)vm_mem[addr]
                       | ((unsigned int)vm_mem[addr+1] << 8)
                       | ((unsigned int)vm_mem[addr+2] << 16)
                       | ((unsigned int)vm_mem[addr+3] << 24);
    } else if (nr == 41) {
        // cap_store32(offset=a0, value=a1)
        Cap *c = &cap_regs[10];
        if (!cheri_check(c, a0, 4, 1)) return;
        unsigned int addr = c->base + a0;
        if (addr + 3 < VM_MEM_SIZE) {
            vm_mem[addr]   = (unsigned char)a1;
            vm_mem[addr+1] = (unsigned char)(a1 >> 8);
            vm_mem[addr+2] = (unsigned char)(a1 >> 16);
            vm_mem[addr+3] = (unsigned char)(a1 >> 24);
        }
    }
}

static int vm_step(void) {
    unsigned int ins = vm_ifetch(vm_pc);
    if (vm_halted) return 1;

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
    case 0x37: res = imm_u; break;
    case 0x17: res = vm_pc + imm_u; break;
    case 0x6F:
        res = npc; npc = vm_pc + imm_j; break;
    case 0x67:
        res = npc; npc = (v1 + imm_i) & ~1u; break;
    case 0x63: {
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
    case 0x03:
        switch (f3) {
        case 0: res = sext(mr8(v1+imm_i),  7); break; // LB
        case 1: res = sext(mr16(v1+imm_i),15); break; // LH
        case 2: res = mr32(v1+imm_i);          break; // LW
        case 4: res = mr8(v1+imm_i);           break; // LBU
        case 5: res = mr16(v1+imm_i);          break; // LHU
        default: write_rd = 0; break;
        }
        break;
    case 0x23:
        switch (f3) {
        case 0: mw8( v1+imm_s, v2); break;
        case 1: mw16(v1+imm_s, v2); break;
        case 2: mw32(v1+imm_s, v2); break;
        }
        write_rd = 0; break;
    case 0x13: {
        unsigned int sh = rs2;
        switch (f3) {
        case 0: res = v1 + imm_i;                          break;
        case 1: res = v1 << sh;                            break;
        case 2: res = ((int)v1 < (int)imm_i) ? 1u : 0u;  break;
        case 3: res = (v1 < imm_i) ? 1u : 0u;             break;
        case 4: res = v1 ^ imm_i;                          break;
        case 5: res = (f7 & 0x20u) ? (unsigned int)((int)v1 >> sh) : (v1 >> sh); break;
        case 6: res = v1 | imm_i;                          break;
        case 7: res = v1 & imm_i;                          break;
        }
        break;
    }
    case 0x33:
        if (f7 == 0x01u) {                              // M extension
            switch (f3) {
            case 0: res = v1 * v2; break;
            case 1: { long long p = (long long)(int)v1 * (long long)(int)v2;
                      res = (unsigned int)(p >> 32); break; }
            case 2: { long long p = (long long)(int)v1 * (long long)(unsigned int)v2;
                      res = (unsigned int)(p >> 32); break; }
            case 3: { unsigned long long p = (unsigned long long)v1 * v2;
                      res = (unsigned int)(p >> 32); break; }
            case 4:
                if (v2 == 0) res = ~0u;
                else if (v1 == 0x80000000u && v2 == ~0u) res = 0x80000000u;
                else res = (unsigned int)((int)v1 / (int)v2);
                break;
            case 5: res = (v2 == 0) ? ~0u : v1 / v2; break;
            case 6:
                if (v2 == 0) res = v1;
                else if (v1 == 0x80000000u && v2 == ~0u) res = 0;
                else res = (unsigned int)((int)v1 % (int)v2);
                break;
            case 7: res = (v2 == 0) ? v1 : v1 % v2; break;
            }
        } else {
            switch (f3) {
            case 0: res = (f7 & 0x20u) ? (v1 - v2) : (v1 + v2); break;
            case 1: res = v1 << (v2 & 0x1Fu);                    break;
            case 2: res = ((int)v1 < (int)v2) ? 1u : 0u;        break;
            case 3: res = (v1 < v2) ? 1u : 0u;                  break;
            case 4: res = v1 ^ v2;                               break;
            case 5: res = (f7 & 0x20u) ? (unsigned int)((int)v1 >> (v2&31)) : (v1 >> (v2&31)); break;
            case 6: res = v1 | v2;                               break;
            case 7: res = v1 & v2;                               break;
            }
        }
        break;
    case 0x73:
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

// --- Встроенный hello-world (без MTE, нетегированные указатели, tag=0) ---
// auipc s0, 0 / addi s0, s0, 0x40 / lbu a0, 0(s0) / beq+ecall loop / exit
static const unsigned char builtin_hello[] = {
    0x17,0x04,0x00,0x00,
    0x13,0x04,0x04,0x04,
    0x03,0x45,0x04,0x00,
    0x63,0x0A,0x05,0x00,
    0x93,0x08,0x10,0x00,
    0x73,0x00,0x00,0x00,
    0x13,0x04,0x14,0x00,
    0x6F,0xF0,0xDF,0xFE,
    0x93,0x08,0xA0,0x00,
    0x73,0x00,0x00,0x00,
    0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
    'H','e','l','l','o',' ','f','r','o','m',' ',
    'R','V','3','2','I','!','\n',0
};

// --- Встроенный MTE-тест ---
// 1. mte_malloc(32)          → tagged ptr в s0
// 2. sb 0x55 → 0(s0)        VALID WRITE (tag совпадает)
// 3. print 'V', '\n'
// 4. mte_free(s0)            → гранулы retag-ованы новым тегом
// 5. print 'F', '\n'
// 6. sb 0x55 → 0(s0)        UAF → MTE FAULT (ptr_tag != new mem_tag)
//
// Encodings (все LE):
//   addi rd, x0, imm  = (imm<<20)|(rd<<7)|0x13
//   mv  d, s          = add d, s, x0 = (s<<15)|(d<<7)|0x33
//   sb  rs2, 0(rs1)   = (rs2<<20)|(rs1<<15)|0x23   [imm=0]
//   ecall             = 0x00000073
static const unsigned char builtin_mte_test[] = {
    // addi a7, x0, 20   (ecall vm_malloc)
    0x93,0x08,0x40,0x01,
    // addi a0, x0, 32   (size = 32 bytes)
    0x13,0x05,0x00,0x02,
    // ecall             → a0 = tagged ptr
    0x73,0x00,0x00,0x00,
    // mv s0, a0         (add s0, a0, x0: rs1=a0=10, rd=s0=8)
    0x33,0x04,0x05,0x00,
    // addi t0, x0, 0x55 (test byte)
    0x93,0x02,0x50,0x05,
    // sb t0, 0(s0)      VALID WRITE (ptr_tag == mem_tag → OK)
    0x23,0x00,0x54,0x00,
    // addi a0, x0, 'V'=86
    0x13,0x05,0x60,0x05,
    // addi a7, x0, 1    (print_char)
    0x93,0x08,0x10,0x00,
    // ecall
    0x73,0x00,0x00,0x00,
    // addi a0, x0, '\n'=10
    0x13,0x05,0xA0,0x00,
    // addi a7, x0, 1
    0x93,0x08,0x10,0x00,
    // ecall
    0x73,0x00,0x00,0x00,
    // mv a0, s0         (add a0, s0, x0: rs1=s0=8, rd=a0=10)
    0x33,0x05,0x04,0x00,
    // addi a7, x0, 21   (ecall vm_free)
    0x93,0x08,0x50,0x01,
    // ecall             → гранулы retag-ованы
    0x73,0x00,0x00,0x00,
    // addi a0, x0, 'F'=70
    0x13,0x05,0x60,0x04,
    // addi a7, x0, 1
    0x93,0x08,0x10,0x00,
    // ecall
    0x73,0x00,0x00,0x00,
    // addi a0, x0, '\n'=10
    0x13,0x05,0xA0,0x00,
    // addi a7, x0, 1
    0x93,0x08,0x10,0x00,
    // ecall
    0x73,0x00,0x00,0x00,
    // sb t0, 0(s0)      UAF → MTE FAULT (ptr_tag != new mem_tag)
    0x23,0x00,0x54,0x00,
    // addi a7, x0, 10   (exit — сюда не дойдёт)
    0x93,0x08,0xA0,0x00,
    // ecall
    0x73,0x00,0x00,0x00,
};

// --- Встроенный тест CHERI: bounds checking ---
// cap_malloc(16) → cap_regs[10]
// cap_store8(0,  0xAB) — valid (offset=0,  last=15)
// cap_store8(15, 0xCD) — valid (last byte)
// cap_store8(16, 0xFF) — BOUNDS FAULT (offset == length)
//
// ecall 30 = cap_malloc, ecall 39 = cap_store8(offset=a0, val=a1)
// addi rd, x0, imm : (imm<<20)|(rd<<7)|0x13
static const unsigned char builtin_cheri_test[] = {
    0x93,0x08,0xE0,0x01, // addi a7,x0,30   (cap_malloc)
    0x13,0x05,0x00,0x01, // addi a0,x0,16   (size)
    0x73,0x00,0x00,0x00, // ecall
    0x13,0x05,0x10,0x03, // addi a0,x0,'1'=49
    0x93,0x08,0x10,0x00, // addi a7,x0,1    (print_char)
    0x73,0x00,0x00,0x00, // ecall
    0x93,0x08,0x70,0x02, // addi a7,x0,39   (cap_store8)
    0x13,0x05,0x00,0x00, // addi a0,x0,0    (offset=0)
    0x93,0x05,0xB0,0x0A, // addi a1,x0,0xAB=171
    0x73,0x00,0x00,0x00, // ecall            valid write
    0x13,0x05,0x20,0x03, // addi a0,x0,'2'=50
    0x93,0x08,0x10,0x00, // addi a7,x0,1
    0x73,0x00,0x00,0x00, // ecall
    0x93,0x08,0x70,0x02, // addi a7,x0,39
    0x13,0x05,0xF0,0x00, // addi a0,x0,15   (offset=15, last byte)
    0x93,0x05,0xD0,0x0C, // addi a1,x0,0xCD=205
    0x73,0x00,0x00,0x00, // ecall            valid write
    0x13,0x05,0x30,0x03, // addi a0,x0,'3'=51
    0x93,0x08,0x10,0x00, // addi a7,x0,1
    0x73,0x00,0x00,0x00, // ecall
    0x93,0x08,0x70,0x02, // addi a7,x0,39
    0x13,0x05,0x00,0x01, // addi a0,x0,16   (offset=16 == length → OOB!)
    0x93,0x05,0xF0,0x0F, // addi a1,x0,0xFF=255
    0x73,0x00,0x00,0x00, // ecall            → BOUNDS FAULT
    0x93,0x08,0xA0,0x00, // addi a7,x0,10   (exit, never reached)
    0x73,0x00,0x00,0x00, // ecall
};

// --- Встроенный тест CHERI: use-after-free через cap_free ---
// cap_malloc(16) → cap_regs[10]
// cap_store8(0, 0x55) — valid write
// cap_free           → tag=0
// cap_store8(0, 0xFF) — TAG FAULT
//
// ecall 31 = cap_free
static const unsigned char builtin_cheri_uaf_test[] = {
    0x93,0x08,0xE0,0x01, // addi a7,x0,30   (cap_malloc)
    0x13,0x05,0x00,0x01, // addi a0,x0,16
    0x73,0x00,0x00,0x00, // ecall
    0x13,0x05,0xD0,0x04, // addi a0,x0,'M'=77
    0x93,0x08,0x10,0x00, // addi a7,x0,1
    0x73,0x00,0x00,0x00, // ecall
    0x93,0x08,0x70,0x02, // addi a7,x0,39   (cap_store8)
    0x13,0x05,0x00,0x00, // addi a0,x0,0
    0x93,0x05,0x50,0x05, // addi a1,x0,0x55=85
    0x73,0x00,0x00,0x00, // ecall            valid write
    0x13,0x05,0x70,0x05, // addi a0,x0,'W'=87
    0x93,0x08,0x10,0x00, // addi a7,x0,1
    0x73,0x00,0x00,0x00, // ecall
    0x93,0x08,0xF0,0x01, // addi a7,x0,31   (cap_free)
    0x73,0x00,0x00,0x00, // ecall            → tag=0
    0x13,0x05,0x60,0x04, // addi a0,x0,'F'=70
    0x93,0x08,0x10,0x00, // addi a7,x0,1
    0x73,0x00,0x00,0x00, // ecall
    0x93,0x08,0x70,0x02, // addi a7,x0,39   (cap_store8)
    0x13,0x05,0x00,0x00, // addi a0,x0,0
    0x93,0x05,0xF0,0x0F, // addi a1,x0,0xFF=255
    0x73,0x00,0x00,0x00, // ecall            → TAG FAULT
    0x93,0x08,0xA0,0x00, // addi a7,x0,10
    0x73,0x00,0x00,0x00, // ecall
};

// --- Тест CHERI: cap_restrict (monotone permission narrowing) ---
// cap_malloc(16) → R|W
// cap_store8(0, 0x55)       valid write
// cap_restrict(PERM_LOAD=1) → R only, STORE убран
// cap_store8(0, 0xFF)       → PERM FAULT: no STORE permission
//
// ecall 32 = cap_restrict(new_perms=a0)
static const unsigned char builtin_cheri_perm_test[] = {
    0x93,0x08,0xE0,0x01, // addi a7,x0,30   (cap_malloc)
    0x13,0x05,0x00,0x01, // addi a0,x0,16
    0x73,0x00,0x00,0x00, // ecall
    0x13,0x05,0xD0,0x04, // addi a0,x0,'M'=77
    0x93,0x08,0x10,0x00, // addi a7,x0,1
    0x73,0x00,0x00,0x00, // ecall  print 'M'
    0x93,0x08,0x70,0x02, // addi a7,x0,39   (cap_store8)
    0x13,0x05,0x00,0x00, // addi a0,x0,0    offset
    0x93,0x05,0x50,0x05, // addi a1,x0,0x55=85
    0x73,0x00,0x00,0x00, // ecall  valid write
    0x13,0x05,0x70,0x05, // addi a0,x0,'W'=87
    0x93,0x08,0x10,0x00, // addi a7,x0,1
    0x73,0x00,0x00,0x00, // ecall  print 'W'
    0x93,0x08,0x00,0x02, // addi a7,x0,32   (cap_restrict)
    0x13,0x05,0x10,0x00, // addi a0,x0,1    PERM_LOAD only
    0x73,0x00,0x00,0x00, // ecall  → perms=R, STORE removed
    0x13,0x05,0x20,0x05, // addi a0,x0,'R'=82
    0x93,0x08,0x10,0x00, // addi a7,x0,1
    0x73,0x00,0x00,0x00, // ecall  print 'R'
    0x93,0x08,0x70,0x02, // addi a7,x0,39   (cap_store8)
    0x13,0x05,0x00,0x00, // addi a0,x0,0
    0x93,0x05,0xF0,0x0F, // addi a1,x0,0xFF=255
    0x73,0x00,0x00,0x00, // ecall  → PERM FAULT
    0x93,0x08,0xA0,0x00, // addi a7,x0,10
    0x73,0x00,0x00,0x00, // ecall  exit
};

// --- Тест CHERI: cap_seal (unforgeable token, cannot deref) ---
// cap_malloc(16) → R|W
// cap_store8(0, 0x42)   valid write (до запечатывания)
// cap_seal              → sealed=1
// cap_store8(0, 0xFF)   → SEALED FAULT: cannot deref sealed cap
//
// ecall 36 = cap_seal (без аргументов, действует на cap_regs[10])
static const unsigned char builtin_cheri_seal_test[] = {
    0x93,0x08,0xE0,0x01, // addi a7,x0,30   (cap_malloc)
    0x13,0x05,0x00,0x01, // addi a0,x0,16
    0x73,0x00,0x00,0x00, // ecall
    0x13,0x05,0xD0,0x04, // addi a0,x0,'M'=77
    0x93,0x08,0x10,0x00, // addi a7,x0,1
    0x73,0x00,0x00,0x00, // ecall  print 'M'
    0x93,0x08,0x70,0x02, // addi a7,x0,39   (cap_store8)
    0x13,0x05,0x00,0x00, // addi a0,x0,0
    0x93,0x05,0x20,0x04, // addi a1,x0,0x42=66
    0x73,0x00,0x00,0x00, // ecall  valid write before seal
    0x13,0x05,0x70,0x05, // addi a0,x0,'W'=87
    0x93,0x08,0x10,0x00, // addi a7,x0,1
    0x73,0x00,0x00,0x00, // ecall  print 'W'
    0x93,0x08,0x40,0x02, // addi a7,x0,36   (cap_seal)
    0x73,0x00,0x00,0x00, // ecall  → sealed=1
    0x13,0x05,0x30,0x05, // addi a0,x0,'S'=83
    0x93,0x08,0x10,0x00, // addi a7,x0,1
    0x73,0x00,0x00,0x00, // ecall  print 'S'
    0x93,0x08,0x70,0x02, // addi a7,x0,39   (cap_store8)
    0x13,0x05,0x00,0x00, // addi a0,x0,0
    0x93,0x05,0xF0,0x0F, // addi a1,x0,0xFF=255
    0x73,0x00,0x00,0x00, // ecall  → SEALED FAULT
    0x93,0x08,0xA0,0x00, // addi a7,x0,10
    0x73,0x00,0x00,0x00, // ecall  exit
};

static int vm_str_eq(const char* a, const char* b) {
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}

int main(int argc, char** argv) {
    vm_mem = (unsigned char*)ax_malloc(VM_MEM_SIZE);
    if (!vm_mem) { ax_print("rv32i: out of memory\n"); return 1; }
    vm_fd_init();

    int is_mte_test = 0;
    unsigned int prog_size = 0;

    if (argc >= 2 && vm_str_eq(argv[1], "--mte-test")) {
        is_mte_test = 1;
        prog_size = sizeof(builtin_mte_test);
        for (unsigned int i = 0; i < prog_size; i++)
            vm_mem[i] = builtin_mte_test[i];
        ax_print("[RV32I+MTE] running built-in MTE test\n");
    } else if (argc >= 2 && vm_str_eq(argv[1], "--cheri-test")) {
        prog_size = sizeof(builtin_cheri_test);
        for (unsigned int i = 0; i < prog_size; i++)
            vm_mem[i] = builtin_cheri_test[i];
        ax_print("[RV32I+CHERI] running built-in bounds test\n");
    } else if (argc >= 2 && vm_str_eq(argv[1], "--cheri-uaf")) {
        prog_size = sizeof(builtin_cheri_uaf_test);
        for (unsigned int i = 0; i < prog_size; i++)
            vm_mem[i] = builtin_cheri_uaf_test[i];
        ax_print("[RV32I+CHERI] running built-in UAF test\n");
    } else if (argc >= 2 && vm_str_eq(argv[1], "--cheri-perm")) {
        prog_size = sizeof(builtin_cheri_perm_test);
        for (unsigned int i = 0; i < prog_size; i++)
            vm_mem[i] = builtin_cheri_perm_test[i];
        ax_print("[RV32I+CHERI] running built-in perm test\n");
    } else if (argc >= 2 && vm_str_eq(argv[1], "--cheri-seal")) {
        prog_size = sizeof(builtin_cheri_seal_test);
        for (unsigned int i = 0; i < prog_size; i++)
            vm_mem[i] = builtin_cheri_seal_test[i];
        ax_print("\033[H");  // курсор в начало — вывод виден до прокрутки
        ax_print("[RV32I+CHERI] running built-in seal test\n");
    } else if (argc >= 2) {
        prog_size = ax_readfile(argv[1], vm_mem, VM_MEM_SIZE);
        if (prog_size == 0) {
            ax_print("rv32i: cannot load '");
            ax_print(argv[1]);
            ax_print("'\n");
            return 1;
        }
        ax_print("[RV32I+MTE] loaded ");
        ax_print(argv[1]);
        ax_print("\n");
    } else {
        prog_size = sizeof(builtin_hello);
        for (unsigned int i = 0; i < prog_size; i++)
            vm_mem[i] = builtin_hello[i];
        ax_print("[RV32I] running built-in hello\n");
    }

    // Инициализация VM
    for (int i = 0; i < 32; i++) {
        vm_reg[i] = 0;
        Cap z; z.base=0; z.length=0; z.perms=0; z.tag=0; z.sealed=0; z._pad=0;
        cap_regs[i] = z;
    }
    vm_reg[2] = VM_MEM_SIZE - 16u; // sp
    vm_pc     = 0;
    vm_halted = 0;

    // Инициализация MTE shadow
    for (unsigned int i = 0; i < MTE_NGRANULES; i++) {
        vm_tags[i]    = 0; // tag=0 = нетегировано
        vm_alloc_ng[i] = 0;
    }
    // PRNG seed: XOR адреса vm_mem (ASLR хоста даёт разброс) с константой
    mte_prng = 0xDEADBEEFu ^ (unsigned int)(unsigned long)vm_mem;
    if (mte_prng == 0) mte_prng = 0xDEADBEEFu;

    // Куча VM: начинается сразу после кода, выровнена на гранулу, минимум 0x200
    vm_heap_ptr = (prog_size + MTE_GRANULE - 1) & ~(MTE_GRANULE - 1u);
    if (vm_heap_ptr < 0x200u) vm_heap_ptr = 0x200u;

    if (is_mte_test) {
        ax_print("[MTE] tag_bits=8  granule=16B  heap_base=");
        print_hex32(vm_heap_ptr);
        ax_print("\n");
    }

    unsigned int cycles = 0;
    while (!vm_halted && cycles < VM_MAX_CYCLES) {
        vm_step();
        cycles++;
    }

    if (!vm_halted && cycles >= VM_MAX_CYCLES) {
        ax_print("[RV32I] timeout after ");
        print_hex32(cycles);
        ax_print(" cycles\n");
    } else if (!is_mte_test) {
        ax_print("[RV32I] halted at pc=");
        print_hex32(vm_pc);
        ax_print(" after ");
        print_hex32(cycles);
        ax_print(" cycles\n");
    }
    return 0;
}
