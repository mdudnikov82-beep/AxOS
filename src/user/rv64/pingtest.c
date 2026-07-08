#include "syscall.h"
#include "icmp.h"

// Проверка icmp.h "от и до": 4 ping'а на гейтвей QEMU SLIRP (10.0.2.2),
// как классический `ping -c 4`. Печатает round-trip время каждого ответа
// и итоговую статистику потерь.

static void print_udec(unsigned long v) {
    char buf[20]; int i = 0;
    if (!v) { write(1, "0", 1); return; }
    while (v) { buf[i++] = '0' + (v % 10); v /= 10; }
    for (int a = 0, b = i - 1; a < b; a++, b--) { char t = buf[a]; buf[a] = buf[b]; buf[b] = t; }
    write(1, buf, i);
}

int main(void) {
    unsigned char mac[6];
    if (!net_mac(mac)) {
        puts_rv("ping: no NIC found (need -device virtio-net-device)\r\n");
        exit(1);
    }

    unsigned int target = IP4(10, 0, 2, 2);
    puts_rv("PING 10.0.2.2 (gateway):\r\n");

    int sent = 0, received = 0;
    for (unsigned short seq = 1; seq <= 4; seq++) {
        sent++;
        unsigned long rtt;
        if (icmp_ping(target, seq, 2000, &rtt)) {
            received++;
            puts_rv("  reply seq=");
            print_udec(seq);
            puts_rv(" time=");
            print_udec(rtt);
            puts_rv("ms\r\n");
        } else {
            puts_rv("  seq=");
            print_udec(seq);
            puts_rv(" timeout\r\n");
        }
        sleep_ms(200);
    }

    puts_rv("--- statistics: ");
    print_udec((unsigned long)sent);
    puts_rv(" sent, ");
    print_udec((unsigned long)received);
    puts_rv(" received\r\n");

    exit(received > 0 ? 0 : 1);
    return 0;
}
