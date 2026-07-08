#include "syscall.h"

// Проверка драйвера virtio-net "от и до": берём MAC, шлём широковещательный
// ARP-запрос ("кто держит 10.0.2.2?" — стандартный gateway QEMU SLIRP при
// `-netdev user`), и слушаем ответ. Если он приходит — и отправка, и приём
// у драйвера реально работают через настоящую сетевую эмуляцию QEMU, а не
// просто "не упало при вызове". Никакого стека ARP/IP тут нет — только
// один захардкоженный пакет для проверки.

// Большие буферы - в .bss, не на стеке (стек RV64-процесса - одна страница
// 4КБ на весь стек вызовов, см. память проекта).
static unsigned char mac[6];
static unsigned char tx_frame[42];
static unsigned char rx_buf[1514];

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

static void put16be(unsigned char *p, unsigned int v) { p[0] = (v >> 8) & 0xFF; p[1] = v & 0xFF; }

int main(void) {
    if (!net_mac(mac)) {
        puts_rv("net: no NIC found (need -device virtio-net-device)\r\n");
        exit(1);
    }

    puts_rv("net: MAC = ");
    print_mac(mac);
    puts_rv("\r\n");

    // Ethernet-заголовок: широковещательный ARP-запрос.
    for (int i = 0; i < 6; i++) tx_frame[i] = 0xFF;               // dst = broadcast
    for (int i = 0; i < 6; i++) tx_frame[6 + i] = mac[i];         // src = наш MAC
    put16be(tx_frame + 12, 0x0806);                               // ethertype = ARP

    // ARP-запрос (28 байт): "кто держит 10.0.2.2?" — гейтвей QEMU SLIRP по
    // умолчанию при `-netdev user`. sender IP не обязан быть "настоящим" —
    // сам факт ответа уже доказывает, что TX/RX работают.
    unsigned char *arp = tx_frame + 14;
    put16be(arp + 0, 1);        // htype = Ethernet
    put16be(arp + 2, 0x0800);   // ptype = IPv4
    arp[4] = 6;                 // hlen
    arp[5] = 4;                 // plen
    put16be(arp + 6, 1);        // oper = request
    for (int i = 0; i < 6; i++) arp[8 + i] = mac[i];   // sender MAC
    arp[14] = 10; arp[15] = 0; arp[16] = 2; arp[17] = 15;  // sender IP 10.0.2.15
    for (int i = 0; i < 6; i++) arp[18 + i] = 0;       // target MAC (unknown)
    arp[24] = 10; arp[25] = 0; arp[26] = 2; arp[27] = 2;   // target IP 10.0.2.2

    if (net_send(tx_frame, sizeof(tx_frame)) != 0) {
        puts_rv("net: send failed\r\n");
        exit(1);
    }
    puts_rv("net: ARP request sent, listening for a reply (5s)...\r\n");

    for (int tries = 0; tries < 50; tries++) {
        unsigned int n = net_recv(rx_buf, sizeof(rx_buf));
        if (n > 0) {
            puts_rv("net: got ");
            char dec[12]; int di = 0; unsigned int v = n;
            if (!v) dec[di++] = '0';
            while (v) { dec[di++] = (char)('0' + v % 10); v /= 10; }
            for (int a = 0, b = di - 1; a < b; a++, b--) { char t = dec[a]; dec[a] = dec[b]; dec[b] = t; }
            write(1, dec, di);
            puts_rv(" byte frame, first bytes: ");
            unsigned int dump = (n < 32) ? n : 32;
            for (unsigned int i = 0; i < dump; i++) { print_hex_byte(rx_buf[i]); write(1, " ", 1); }
            puts_rv("\r\n");

            if (n >= 42 && rx_buf[12] == 0x08 && rx_buf[13] == 0x06 && rx_buf[21] == 2) {
                puts_rv("net: ARP reply! Sender MAC = ");
                print_mac(rx_buf + 22);
                puts_rv(" -- TX and RX both confirmed working.\r\n");
            }
            exit(0);
        }
        sleep_ms(100);
    }

    puts_rv("net: no reply in 5s (check `-netdev user,id=net0 -device virtio-net-device,netdev=net0`)\r\n");
    exit(1);
    return 0;
}
