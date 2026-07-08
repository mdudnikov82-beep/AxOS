#include "syscall.h"
#include "arp.h"

// Проверка arp.h "от и до": резолвит два реальных адреса QEMU SLIRP (гейтвей
// 10.0.2.2 и DNS 10.0.2.3), затем резолвит гейтвей ПОВТОРНО, чтобы показать
// попадание в кэш (второй вызов не должен слать новый запрос/ждать).

static void print_hex_byte(unsigned char b) {
    char h[2] = { "0123456789abcdef"[b >> 4], "0123456789abcdef"[b & 0xF] };
    write(1, h, 2);
}

static void print_mac(const unsigned char m[6]) {
    for (int i = 0; i < 6; i++) {
        print_hex_byte(m[i]);
        if (i < 5) write(1, ":", 1);
    }
}

static int resolve_and_print(const char *label, unsigned int ip) {
    unsigned char mac[6];
    unsigned long t0 = (unsigned long)gettime();
    int ok = arp_resolve(ip, mac, 3000);
    unsigned long t1 = (unsigned long)gettime();
    unsigned long ms = (t1 - t0) / 10000UL;   // CLINT time тикает на 10МГц

    puts_rv(label);
    if (!ok) { puts_rv(" -- FAIL (no reply in 3s)\r\n"); return 0; }

    puts_rv(" -> ");
    print_mac(mac);
    puts_rv(" (");
    char dec[12]; int di = 0; unsigned long v = ms;
    if (!v) dec[di++] = '0';
    while (v) { dec[di++] = (char)('0' + v % 10); v /= 10; }
    for (int a = 0, b = di - 1; a < b; a++, b--) { char t = dec[a]; dec[a] = dec[b]; dec[b] = t; }
    write(1, dec, di);
    puts_rv("ms)\r\n");
    return 1;
}

int main(void) {
    unsigned char mac[6];
    if (!net_mac(mac)) {
        puts_rv("arp: no NIC found (need -device virtio-net-device)\r\n");
        exit(1);
    }

    int ok1 = resolve_and_print("arp: resolve 10.0.2.2 (gateway)", IP4(10, 0, 2, 2));
    int ok2 = resolve_and_print("arp: resolve 10.0.2.3 (dns)    ", IP4(10, 0, 2, 3));
    int ok3 = resolve_and_print("arp: resolve 10.0.2.2 (cached) ", IP4(10, 0, 2, 2));

    if (ok1 && ok2 && ok3) {
        puts_rv("arp: ALL OK\r\n");
        exit(0);
    }
    puts_rv("arp: FAILED\r\n");
    exit(1);
    return 0;
}
