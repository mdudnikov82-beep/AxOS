#include "syscall.h"
#include "arp.h"

// Слушает входящие ARP-запросы MY_IP и отвечает на них (arp_maybe_respond,
// см. arp.h) в течение ~15 секунд, печатая каждый такой запрос. Проверка
// "нас реально можно найти по ARP" - в отличие от arptest.c/pingtest.c,
// которые проверяют, что МЫ можем резолвить/пинговать других.

static void print_hex_byte(unsigned char b) {
    char h[2] = { "0123456789abcdef"[b >> 4], "0123456789abcdef"[b & 0xF] };
    write(1, h, 2);
}

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

int main(void) {
    unsigned char mac[6];
    if (!net_mac(mac)) {
        puts_rv("arpserve: no NIC found (need -device virtio-net-device)\r\n");
        exit(1);
    }

    puts_rv("arpserve: listening for ARP requests for MY_IP=");
    print_ip(MY_IP);
    puts_rv(" (15s)...\r\n");

    static unsigned char rx[128];
    int answered = 0;
    for (int tries = 0; tries < 1500; tries++) {
        unsigned int n = net_recv(rx, sizeof(rx));
        if (n >= 42 && rx[12] == 0x08 && rx[13] == 0x06 && rx[21] == 0x01) {
            unsigned int target_ip = ((unsigned int)rx[38] << 24) | ((unsigned int)rx[39] << 16) |
                                     ((unsigned int)rx[40] << 8)  |  (unsigned int)rx[41];
            unsigned int sender_ip = ((unsigned int)rx[28] << 24) | ((unsigned int)rx[29] << 16) |
                                     ((unsigned int)rx[30] << 8)  |  (unsigned int)rx[31];
            puts_rv("arpserve: ARP request from ");
            print_ip(sender_ip);
            puts_rv(" (mac ");
            for (int i = 0; i < 6; i++) { print_hex_byte(rx[22+i]); if (i<5) write(1,":",1); }
            puts_rv(") asking for ");
            print_ip(target_ip);

            if (arp_maybe_respond(rx, n)) {
                answered++;
                puts_rv(" -- answered!\r\n");
            } else {
                puts_rv(" -- not us, ignored\r\n");
            }
        }
        sleep_ms(10);
    }

    puts_rv("arpserve: done, answered ");
    char dec[8]; int di = 0; unsigned int v = (unsigned int)answered;
    if (!v) dec[di++] = '0';
    while (v) { dec[di++] = (char)('0' + v % 10); v /= 10; }
    for (int a = 0, b = di - 1; a < b; a++, b--) { char t = dec[a]; dec[a] = dec[b]; dec[b] = t; }
    write(1, dec, di);
    puts_rv(" request(s)\r\n");

    exit(0);
    return 0;
}
