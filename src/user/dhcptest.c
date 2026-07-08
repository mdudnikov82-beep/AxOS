#include "axiom.h"
#include "dhcp.h"

// Проверка dhcp.h "от и до": полный DORA-обмен с настоящим DHCP-сервером
// QEMU SLIRP, затем - доказательство, что выданный адрес реально рабочий
// (не просто "сервер прислал ответ"), пингуя полученный router через уже
// проверенный icmp_ping(). Портирован с RISC-V стороны
// (src/user/rv64/dhcptest.c) - тот же протокол, тот же тест.

static void print_ip(unsigned int ip) {
    ax_printf("%u.%u.%u.%u", (ip >> 24) & 0xFF, (ip >> 16) & 0xFF,
              (ip >> 8) & 0xFF, ip & 0xFF);
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    unsigned char mac[6];
    if (!ax_net_mac(mac)) {
        ax_print("dhcp: no NIC found (need -device virtio-net-pci)\n");
        return 1;
    }

    ax_print("dhcp: static IP before lease: ");
    print_ip(MY_IP);
    ax_print("\ndhcp: starting DORA (Discover/Offer/Request/Ack)...\n");

    if (!dhcp_client(3000)) {
        ax_print("dhcp: FAILED (no offer/ack within timeout)\n");
        return 1;
    }

    ax_print("dhcp: lease OK - IP=");
    print_ip(MY_IP);
    ax_print(" mask=");
    print_ip(dhcp_subnet_mask);
    ax_print(" router=");
    print_ip(dhcp_router_ip);
    ax_print(" dns=");
    print_ip(dhcp_dns_ip);
    ax_print("\n");

    ax_print("dhcp: pinging DHCP-assigned router to prove the lease actually works...\n");
    unsigned long rtt;
    if (icmp_ping(dhcp_router_ip, 1, 2000, &rtt)) {
        ax_printf("dhcp: ALL OK - ping reply using DHCP-assigned identity, rtt=%ums\n",
                  (unsigned int)rtt);
        return 0;
    }

    ax_print("dhcp: lease obtained but ping failed\n");
    return 1;
}
