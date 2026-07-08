#include "syscall.h"
#include "udp.h"

// Проверка udp.h "от и до" на настоящем сервисе: шлёт DNS-запрос A-записи
// для "example.com" на встроенный DNS-прокси QEMU SLIRP (10.0.2.3:53) и
// разбирает достаточно ответа, чтобы убедиться, что это осмысленный DNS-
// ответ именно на наш запрос (не полноценный DNS-клиент - парсим только
// заголовок).

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
        puts_rv("dns: no NIC found (need -device virtio-net-device)\r\n");
        exit(1);
    }

    unsigned int dns_ip = IP4(10, 0, 2, 3);
    puts_rv("dns: sending A query for example.com to 10.0.2.3:53...\r\n");
    if (udp_send(dns_ip, 53, 5353, dns_query, sizeof(dns_query)) != 0) {
        puts_rv("dns: udp_send failed\r\n");
        exit(1);
    }

    static unsigned char resp[512];
    for (int tries = 0; tries < 300; tries++) {
        unsigned int src_ip; unsigned short src_port, dst_port;
        unsigned int n = udp_recv(&src_ip, &src_port, &dst_port, resp, sizeof(resp));
        if (n >= 12 && dst_port == 5353) {
            unsigned int id      = ((unsigned int)resp[0] << 8) | resp[1];
            unsigned int flags   = ((unsigned int)resp[2] << 8) | resp[3];
            unsigned int ancount = ((unsigned int)resp[6] << 8) | resp[7];

            puts_rv("dns: got "); print_udec(n); puts_rv(" byte reply, id=0x");
            char h[4] = { "0123456789abcdef"[(id>>12)&0xF], "0123456789abcdef"[(id>>8)&0xF],
                          "0123456789abcdef"[(id>>4)&0xF],  "0123456789abcdef"[id&0xF] };
            write(1, h, 4);
            puts_rv(", QR="); print_udec((flags >> 15) & 1);
            puts_rv(", answers="); print_udec(ancount);
            puts_rv("\r\n");

            if (id == 0x1234 && (flags & 0x8000)) {
                puts_rv("dns: ALL OK (valid response to our query, UDP TX+RX both work)\r\n");
                exit(0);
            }
        }
        sleep_ms(10);
    }

    puts_rv("dns: no valid reply in 3s (needs host internet access via QEMU SLIRP)\r\n");
    exit(1);
    return 0;
}
