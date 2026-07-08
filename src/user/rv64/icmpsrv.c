#include "syscall.h"
#include "icmp.h"

// Слушает входящие ICMP echo request к MY_IP и отвечает на них
// (icmp_maybe_respond, см. icmp.h) в течение ~15 секунд, печатая каждый
// такой запрос. Проверка "нас реально можно пинговать" - в отличие от
// pingtest.c, который проверяет, что МЫ можем пинговать других.

static void print_ip(unsigned int ip) {
    unsigned char o[4] = { (unsigned char)(ip>>24), (unsigned char)(ip>>16),
                           (unsigned char)(ip>>8), (unsigned char)ip };
    for (int i = 0; i < 4; i++) {
        char dec[4]; int di = 0; unsigned int v = o[i];
        if (!v) dec[di++] = '0';
        while (v) { dec[di++] = (char)('0' + v % 10); v /= 10; }
        for (int a = 0, b = di - 1; a < b; a++, b--) { char t = dec[a]; dec[a] = dec[b]; dec[b] = t; }
        write(1, dec, di);
        if (i < 3) write(1, ".", 1);
    }
}

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
        puts_rv("icmpsrv: no NIC found (need -device virtio-net-device)\r\n");
        exit(1);
    }

    puts_rv("icmpsrv: listening for ICMP echo requests to MY_IP=");
    print_ip(MY_IP);
    puts_rv(" (15s)...\r\n");

    static unsigned char rx[128];
    int answered = 0;
    for (int tries = 0; tries < 1500; tries++) {
        unsigned int n = net_recv(rx, sizeof(rx));
        if (n >= 14 + 20 + 8 && rx[12] == 0x08 && rx[13] == 0x00) {
            unsigned char *ip = rx + 14;
            unsigned int ihl = (unsigned int)(ip[0] & 0x0F) * 4;
            if (ip[9] == IP_PROTO_ICMP && n >= 14 + ihl + 8 && ip[ihl] == ICMP_ECHO_REQUEST) {
                unsigned int src_ip = ((unsigned int)ip[12] << 24) | ((unsigned int)ip[13] << 16) |
                                     ((unsigned int)ip[14] << 8)  |  (unsigned int)ip[15];
                unsigned int seq = ((unsigned int)ip[ihl + 6] << 8) | ip[ihl + 7];

                puts_rv("icmpsrv: echo request from ");
                print_ip(src_ip);
                puts_rv(" seq=");
                print_udec(seq);

                if (icmp_maybe_respond(rx, n)) {
                    answered++;
                    puts_rv(" -- answered!\r\n");
                } else {
                    puts_rv(" -- not us, ignored\r\n");
                }
            }
        }
        sleep_ms(10);
    }

    puts_rv("icmpsrv: done, answered ");
    print_udec((unsigned long)answered);
    puts_rv(" request(s)\r\n");

    exit(0);
    return 0;
}
