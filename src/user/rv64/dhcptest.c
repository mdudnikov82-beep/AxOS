#include "syscall.h"
#include "dhcp.h"

// Проверка dhcp.h "от и до": полный DORA-обмен с настоящим DHCP-сервером
// QEMU SLIRP, затем - доказательство, что выданный адрес реально рабочий
// (не просто "сервер прислал ответ"), пингуя полученный router через уже
// проверенный icmp_ping().

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
        puts_rv("dhcp: no NIC found (need -device virtio-net-device)\r\n");
        exit(1);
    }

    puts_rv("dhcp: static IP before lease: ");
    print_ip(MY_IP);
    puts_rv("\r\ndhcp: starting DORA (Discover/Offer/Request/Ack)...\r\n");

    if (!dhcp_client(3000)) {
        puts_rv("dhcp: FAILED (no offer/ack within timeout)\r\n");
        exit(1);
    }

    puts_rv("dhcp: lease OK - IP=");
    print_ip(MY_IP);
    puts_rv(" mask=");
    print_ip(dhcp_subnet_mask);
    puts_rv(" router=");
    print_ip(dhcp_router_ip);
    puts_rv(" dns=");
    print_ip(dhcp_dns_ip);
    puts_rv("\r\n");

    puts_rv("dhcp: pinging DHCP-assigned router to prove the lease actually works...\r\n");
    unsigned long rtt;
    if (icmp_ping(dhcp_router_ip, 1, 2000, &rtt)) {
        puts_rv("dhcp: ALL OK - ping reply using DHCP-assigned identity, rtt=");
        print_udec(rtt);
        puts_rv("ms\r\n");
        exit(0);
    }

    puts_rv("dhcp: lease obtained but ping failed\r\n");
    exit(1);
    return 0;
}
