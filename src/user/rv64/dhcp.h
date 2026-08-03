#pragma once

// Минимальный DHCP-клиент (RFC 2131) поверх udp.h - только классический
// DORA-обмен (Discover -> Offer -> Request -> Ack) с одним сервером, без
// повторной аренды (renewal/rebinding), без DECLINE/RELEASE. При успехе
// перезаписывает g_my_ip (arp.h, макрос MY_IP) реально выданным адресом -
// до этого MY_IP была просто зашитая статика.
//
// DISCOVER/REQUEST оба идут широковещательно (dst MAC/IP = broadcast),
// потому что на момент их отправки своего IP у нас ещё нет - собираются
// напрямую (не через udp_send(), который сначала резолвил бы MAC через
// ARP - для 255.255.255.255 резолвить нечего).

#include "udp.h"

#define DHCP_SERVER_PORT 67
#define DHCP_CLIENT_PORT 68

#define DHCP_DISCOVER 1
#define DHCP_OFFER    2
#define DHCP_REQUEST  3
#define DHCP_ACK      5
#define DHCP_NAK      6

#define DHCP_OPT_SUBNET       1
#define DHCP_OPT_ROUTER       3
#define DHCP_OPT_DNS          6
#define DHCP_OPT_REQUESTED_IP 50
#define DHCP_OPT_MSG_TYPE     53
#define DHCP_OPT_SERVER_ID    54
#define DHCP_OPT_PARAM_LIST   55
#define DHCP_OPT_END          255

static unsigned char dhcp_tx[14 + 20 + 8 + 240 + 32];
static unsigned char dhcp_rx[600];

// Заполняются dhcp_client() при успехе - остальные параметры аренды,
// которые MY_IP сам по себе не несёт.
static unsigned int dhcp_subnet_mask = 0;
static unsigned int dhcp_router_ip   = 0;
static unsigned int dhcp_dns_ip      = 0;

// Собирает и шлёт один широковещательный DHCP-пакет. type - DHCP_DISCOVER
// или DHCP_REQUEST; requested_ip/server_ip нужны только для REQUEST (для
// DISCOVER передать 0/0).
static void dhcp_send(unsigned char type, unsigned int xid, const unsigned char my_mac[6],
                       unsigned int requested_ip, unsigned int server_ip) {
    unsigned char *eth = dhcp_tx;
    for (int i = 0; i < 6; i++) eth[i] = 0xFF;              // dst = broadcast
    for (int i = 0; i < 6; i++) eth[6 + i] = my_mac[i];
    arp__put16be(eth + 12, 0x0800);

    unsigned char *ip   = eth + 14;
    unsigned char *udp  = ip + 20;
    unsigned char *dhcp = udp + 8;

    dhcp[0] = 1; dhcp[1] = 1; dhcp[2] = 6; dhcp[3] = 0;   // op=BOOTREQUEST, htype=eth, hlen=6
    dhcp[4] = (unsigned char)(xid >> 24); dhcp[5] = (unsigned char)(xid >> 16);
    dhcp[6] = (unsigned char)(xid >> 8);  dhcp[7] = (unsigned char)xid;
    dhcp[8] = 0; dhcp[9] = 0;                              // secs
    dhcp[10] = 0x80; dhcp[11] = 0;                         // flags: broadcast bit
    for (int i = 12; i < 28; i++) dhcp[i] = 0;             // ciaddr/yiaddr/siaddr/giaddr
    for (int i = 0; i < 6; i++) dhcp[28 + i] = my_mac[i];  // chaddr (первые 6 из 16 байт)
    for (int i = 34; i < 236; i++) dhcp[i] = 0;            // остаток chaddr + sname + file
    dhcp[236] = 99; dhcp[237] = 130; dhcp[238] = 83; dhcp[239] = 99;   // magic cookie

    unsigned char *opt = dhcp + 240;
    int oi = 0;
    opt[oi++] = DHCP_OPT_MSG_TYPE; opt[oi++] = 1; opt[oi++] = (unsigned char)type;
    if (type == DHCP_REQUEST) {
        opt[oi++] = DHCP_OPT_REQUESTED_IP; opt[oi++] = 4;
        opt[oi++] = (unsigned char)(requested_ip >> 24); opt[oi++] = (unsigned char)(requested_ip >> 16);
        opt[oi++] = (unsigned char)(requested_ip >> 8);  opt[oi++] = (unsigned char)requested_ip;
        opt[oi++] = DHCP_OPT_SERVER_ID; opt[oi++] = 4;
        opt[oi++] = (unsigned char)(server_ip >> 24); opt[oi++] = (unsigned char)(server_ip >> 16);
        opt[oi++] = (unsigned char)(server_ip >> 8);  opt[oi++] = (unsigned char)server_ip;
    }
    opt[oi++] = DHCP_OPT_PARAM_LIST; opt[oi++] = 3;
    opt[oi++] = DHCP_OPT_SUBNET; opt[oi++] = DHCP_OPT_ROUTER; opt[oi++] = DHCP_OPT_DNS;
    opt[oi++] = DHCP_OPT_END;

    unsigned int dhcp_msg_len = 240 + (unsigned int)oi;
    unsigned int udp_len = 8 + dhcp_msg_len;
    unsigned int ip_total = 20 + udp_len;

    ip[0] = 0x45; ip[1] = 0;
    arp__put16be(ip + 2, ip_total);
    arp__put16be(ip + 4, 0);
    arp__put16be(ip + 6, 0);
    ip[8] = 64; ip[9] = IP_PROTO_UDP;
    ip[10] = 0; ip[11] = 0;
    ip[12] = 0; ip[13] = 0; ip[14] = 0; ip[15] = 0;              // src = 0.0.0.0 (нет IP ещё)
    ip[16] = 255; ip[17] = 255; ip[18] = 255; ip[19] = 255;      // dst = broadcast
    arp__put16be(ip + 10, ip_checksum(ip, 20));

    arp__put16be(udp + 0, DHCP_CLIENT_PORT);
    arp__put16be(udp + 2, DHCP_SERVER_PORT);
    arp__put16be(udp + 4, udp_len);
    udp[6] = 0; udp[7] = 0;   // checksum = 0 (опционально для IPv4/UDP)

    net_send(dhcp_tx, 14 + ip_total);
}

// Разбирает опции DHCP-сообщения (dhcp - указатель на его начало, n - его
// полная длина в байтах, включая BOOTP-заголовок). Проверяет xid и magic
// cookie. Заодно попутно обновляет dhcp_subnet_mask/router/dns, если эти
// опции присутствуют - независимо от типа сообщения (сервер обычно шлёт
// их и в OFFER, и в ACK одинаково).
static int dhcp_parse(const unsigned char *dhcp, unsigned int n, unsigned int xid,
                       unsigned char *msg_type_out, unsigned int *yiaddr_out,
                       unsigned int *server_id_out) {
    if (n < 240) return 0;
    unsigned int rxid = ((unsigned int)dhcp[4] << 24) | ((unsigned int)dhcp[5] << 16) |
                        ((unsigned int)dhcp[6] << 8)  |  (unsigned int)dhcp[7];
    if (rxid != xid) return 0;
    if (dhcp[236] != 99 || dhcp[237] != 130 || dhcp[238] != 83 || dhcp[239] != 99) return 0;

    *yiaddr_out = ((unsigned int)dhcp[16] << 24) | ((unsigned int)dhcp[17] << 16) |
                 ((unsigned int)dhcp[18] << 8)  |  (unsigned int)dhcp[19];

    unsigned char mtype = 0;
    unsigned int server_id = 0;
    unsigned int i = 240;
    while (i < n) {
        unsigned char code = dhcp[i++];
        if (code == 0) continue;            // pad
        if (code == DHCP_OPT_END) break;
        if (i >= n) break;
        unsigned char len = dhcp[i++];
        if (i + len > n) break;

        if (code == DHCP_OPT_MSG_TYPE && len >= 1) {
            mtype = dhcp[i];
        } else if (code == DHCP_OPT_SERVER_ID && len >= 4) {
            server_id = ((unsigned int)dhcp[i] << 24) | ((unsigned int)dhcp[i+1] << 16) |
                       ((unsigned int)dhcp[i+2] << 8)  |  (unsigned int)dhcp[i+3];
        } else if (code == DHCP_OPT_SUBNET && len >= 4) {
            dhcp_subnet_mask = ((unsigned int)dhcp[i] << 24) | ((unsigned int)dhcp[i+1] << 16) |
                              ((unsigned int)dhcp[i+2] << 8)  |  (unsigned int)dhcp[i+3];
        } else if (code == DHCP_OPT_ROUTER && len >= 4) {
            dhcp_router_ip = ((unsigned int)dhcp[i] << 24) | ((unsigned int)dhcp[i+1] << 16) |
                            ((unsigned int)dhcp[i+2] << 8)  |  (unsigned int)dhcp[i+3];
        } else if (code == DHCP_OPT_DNS && len >= 4) {
            dhcp_dns_ip = ((unsigned int)dhcp[i] << 24) | ((unsigned int)dhcp[i+1] << 16) |
                         ((unsigned int)dhcp[i+2] << 8)  |  (unsigned int)dhcp[i+3];
        }
        i += len;
    }
    *msg_type_out = mtype;
    if (server_id_out) *server_id_out = server_id;
    return 1;
}

// Поллит net_recv() до timeout_ms, ища DHCP-ответ типа want_type с нашим
// xid, адресованный DHCP_CLIENT_PORT. При успехе кладёт yiaddr/server_id
// (любой указатель можно передать NULL) и возвращает 1.
static int dhcp_wait_for(unsigned char want_type, unsigned int xid, unsigned int timeout_ms,
                          unsigned int *yiaddr_out, unsigned int *server_id_out) {
    unsigned int waited = 0;
    while (waited < timeout_ms) {
        unsigned int n = net_recv(dhcp_rx, sizeof(dhcp_rx));
        if (n >= 14 + 20 + 8 && dhcp_rx[12] == 0x08 && dhcp_rx[13] == 0x00) {
            unsigned char *ip = dhcp_rx + 14;
            if (ip[9] == IP_PROTO_UDP) {
                unsigned int ihl = (unsigned int)(ip[0] & 0x0F) * 4;
                // Тот же баг, что был в udp_recv() (см. project_udp_ihl_bounds_fix) -
                // независимая копия того же разбора: раньше udp[2]/udp[3]
                // читались ДО проверки n > 14+ihl+8, а не после - при
                // коротком, но заявляющем большой IHL пакете это читало
                // "чужие" байты от предыдущего net_recv() как порт назначения.
                if (n > 14 + ihl + 8) {
                    unsigned char *udp = ip + ihl;
                    unsigned int dport = ((unsigned int)udp[2] << 8) | udp[3];
                    if (dport == DHCP_CLIENT_PORT) {
                        unsigned char *dhcp = udp + 8;
                        unsigned int dhcp_len = n - (14 + ihl + 8);
                        unsigned char mtype = 0;
                        unsigned int yiaddr = 0, server_id = 0;
                        if (dhcp_parse(dhcp, dhcp_len, xid, &mtype, &yiaddr, &server_id) &&
                            mtype == want_type) {
                            if (yiaddr_out) *yiaddr_out = yiaddr;
                            if (server_id_out) *server_id_out = server_id;
                            return 1;
                        }
                    }
                }
            }
        }
        sleep_ms(20);
        waited += 20;
    }
    return 0;
}

// Полный DORA-обмен с одним таймаутом на каждый из двух шагов (Offer,
// потом Ack). При успехе перезаписывает g_my_ip (MY_IP) выданным адресом
// и заполняет dhcp_subnet_mask/router/dns. Возвращает 1/0.
static int dhcp_client(unsigned int timeout_ms) {
    unsigned char my_mac[6];
    if (!net_mac(my_mac)) return 0;

    unsigned int xid = 0x3903F326;   // один клиент - фиксированный xid, случайность не нужна

    dhcp_send(DHCP_DISCOVER, xid, my_mac, 0, 0);
    unsigned int offered_ip = 0, server_id = 0;
    if (!dhcp_wait_for(DHCP_OFFER, xid, timeout_ms, &offered_ip, &server_id)) return 0;

    dhcp_send(DHCP_REQUEST, xid, my_mac, offered_ip, server_id);
    unsigned int acked_ip = 0;
    if (!dhcp_wait_for(DHCP_ACK, xid, timeout_ms, &acked_ip, 0)) return 0;

    g_my_ip = acked_ip;
    // Так же обновляем g_subnet_mask/g_router_ip (arp.h) - без этого
    // arp_resolve_next_hop() продолжал бы считать подсеть/гейтвей теми же,
    // что были заданы статикой по умолчанию, даже если DHCP выдал другие.
    if (dhcp_subnet_mask) g_subnet_mask = dhcp_subnet_mask;
    if (dhcp_router_ip)   g_router_ip   = dhcp_router_ip;
    return 1;
}
