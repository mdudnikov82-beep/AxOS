#include "axiom.h"
#include "udp.h"

// Проверка udp.h "от и до" на настоящем сервисе: шлёт DNS-запрос A-записи
// для "example.com" на встроенный DNS-прокси QEMU SLIRP (10.0.2.3:53) и
// разбирает достаточно ответа, чтобы убедиться, что это осмысленный
// DNS-ответ именно на наш запрос. Портирован с RISC-V стороны
// (src/user/rv64/dnstest.c) - тот же протокол, тот же тест.

static const unsigned char dns_query[] = {
    0x12, 0x34,             // ID = 0x1234
    0x01, 0x00,             // flags: стандартный запрос, recursion desired
    0x00, 0x01,             // QDCOUNT = 1
    0x00, 0x00,             // ANCOUNT = 0
    0x00, 0x00,             // NSCOUNT = 0
    0x00, 0x00,             // ARCOUNT = 0
    7, 'e','x','a','m','p','l','e',
    3, 'c','o','m',
    0,
    0x00, 0x01,              // QTYPE = A
    0x00, 0x01               // QCLASS = IN
};

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    unsigned char mac[6];
    if (!ax_net_mac(mac)) {
        ax_print("dns: no NIC found (need -device virtio-net-pci)\n");
        return 1;
    }

    unsigned int dns_ip = IP4(10, 0, 2, 3);
    ax_print("dns: sending A query for example.com to 10.0.2.3:53...\n");
    if (udp_send(dns_ip, 53, 5353, dns_query, sizeof(dns_query)) != 0) {
        ax_print("dns: udp_send failed\n");
        return 1;
    }

    static unsigned char resp[512];
    for (int tries = 0; tries < 300; tries++) {
        unsigned int src_ip; unsigned short src_port, dst_port;
        unsigned int n = udp_recv(&src_ip, &src_port, &dst_port, resp, sizeof(resp));
        if (n >= 12 && dst_port == 5353) {
            unsigned int id      = ((unsigned int)resp[0] << 8) | resp[1];
            unsigned int flags   = ((unsigned int)resp[2] << 8) | resp[3];
            unsigned int ancount = ((unsigned int)resp[6] << 8) | resp[7];

            ax_printf("dns: got %u byte reply, id=0x%04x, QR=%u, answers=%u\n",
                      n, id, (flags >> 15) & 1, ancount);

            if (id == 0x1234 && (flags & 0x8000)) {
                ax_print("dns: ALL OK (valid response to our query, UDP TX+RX both work)\n");
                return 0;
            }
        }
        ax_sleep_ms(10);
    }

    ax_print("dns: no valid reply in 3s (needs host internet access via QEMU SLIRP)\n");
    return 1;
}
