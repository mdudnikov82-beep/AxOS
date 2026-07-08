#include "axiom.h"

// Проверка драйвера virtio-net на x86 "от и до": берёт MAC, шлёт
// широковещательный ARP-запрос ("кто держит 10.0.2.2?" - гейтвей QEMU
// SLIRP по умолчанию при `-netdev user`), слушает ответ. Если он приходит
// - и отправка, и приём у драйвера реально работают через настоящую
// сетевую эмуляцию QEMU. Один в один со своим RISC-V аналогом
// (src/user/rv64/nettest.c) - тот же протокол, тот же метод проверки.

static void put16be(unsigned char* p, unsigned int v) {
    p[0] = (unsigned char)(v >> 8);
    p[1] = (unsigned char)v;
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    unsigned char mac[6];
    if (!ax_net_mac(mac)) {
        ax_print("net: no NIC found (need -device virtio-net-pci)\n");
        return 1;
    }

    ax_printf("net: MAC = %02x:%02x:%02x:%02x:%02x:%02x\n",
              mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

    unsigned char frame[42];
    for (int i = 0; i < 6; i++) frame[i] = 0xFF;            // dst = broadcast
    for (int i = 0; i < 6; i++) frame[6 + i] = mac[i];       // src = наш MAC
    put16be(frame + 12, 0x0806);                             // ethertype = ARP

    unsigned char* arp = frame + 14;
    put16be(arp + 0, 1);        // htype = Ethernet
    put16be(arp + 2, 0x0800);   // ptype = IPv4
    arp[4] = 6; arp[5] = 4;     // hlen/plen
    put16be(arp + 6, 1);        // oper = request
    for (int i = 0; i < 6; i++) arp[8 + i] = mac[i];   // sender MAC
    arp[14] = 10; arp[15] = 0; arp[16] = 2; arp[17] = 15;  // sender IP 10.0.2.15
    for (int i = 0; i < 6; i++) arp[18 + i] = 0;       // target MAC (unknown)
    arp[24] = 10; arp[25] = 0; arp[26] = 2; arp[27] = 2;   // target IP 10.0.2.2

    if (ax_net_send(frame, sizeof(frame)) != 0) {
        ax_print("net: send failed\n");
        return 1;
    }
    ax_print("net: ARP request sent, listening for a reply (5s)...\n");

    unsigned char rx[1514];
    for (int tries = 0; tries < 50; tries++) {
        unsigned int n = ax_net_recv(rx, sizeof(rx));
        if (n > 0) {
            ax_printf("net: got %u byte frame\n", n);
            if (n >= 42 && rx[12] == 0x08 && rx[13] == 0x06 && rx[21] == 2) {
                ax_printf("net: ARP reply! Sender MAC = %02x:%02x:%02x:%02x:%02x:%02x -- TX and RX both confirmed working.\n",
                          rx[22], rx[23], rx[24], rx[25], rx[26], rx[27]);
            }
            return 0;
        }
        ax_sleep_ms(100);
    }

    ax_print("net: no reply in 5s (check `-netdev user,id=net0 -device virtio-net-pci,netdev=net0`)\n");
    return 1;
}
