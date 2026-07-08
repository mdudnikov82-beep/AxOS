#pragma once

// Минимальный IPv4 + ICMP echo (ping) поверх arp.h/virtio-net. Только то,
// что нужно для одного ping-запроса/ответа - ни фрагментации, ни опций IP,
// ни других типов ICMP. Как и arp.h - header-only, static-состояние, своя
// копия на программу.

#include "arp.h"

#define ICMP_ECHO_REQUEST 8
#define ICMP_ECHO_REPLY   0
#define ICMP_ID           0x4158        // 'AX' - идентификатор нашего "ping"
#define PING_PAYLOAD_LEN  32
#define IP_PROTO_ICMP     1

static unsigned char icmp_tx[14 + 20 + 8 + PING_PAYLOAD_LEN];
static unsigned char icmp_rx[128];

// Стандартная интернет-контрольная сумма (RFC 1071): дополнение до
// единицы суммы 16-битных слов. len — в байтах; нечётный хвостовой байт
// дополняется нулём справа.
static unsigned short ip_checksum(const void *data, unsigned int len) {
    const unsigned char *p = (const unsigned char *)data;
    unsigned long sum = 0;
    while (len > 1) {
        sum += ((unsigned int)p[0] << 8) | p[1];
        p += 2; len -= 2;
    }
    if (len == 1) sum += (unsigned int)p[0] << 8;
    while (sum >> 16) sum = (sum & 0xFFFFUL) + (sum >> 16);
    return (unsigned short)(~sum & 0xFFFFUL);
}

// Проверяет входящий кадр на ICMP echo request к НАШЕМУ MY_IP; если да -
// шлёт echo reply (тот же payload/identifier/sequence, type=0 вместо 8) и
// возвращает 1. Учитывает IHL заголовка IP (на случай опций, хотя мы сами
// их не используем) и обрезает payload по вместимости icmp_tx (74Б=
// 14+20+8+PING_PAYLOAD_LEN) и по факту реально принятых байт - не читает
// за пределами того, что n подтверждает.
static int icmp_maybe_respond(const unsigned char *rx, unsigned int n) {
    if (n < 14 + 20 + 8) return 0;
    if (rx[12] != 0x08 || rx[13] != 0x00) return 0;   // ethertype != IPv4

    const unsigned char *ip = rx + 14;
    unsigned int ihl = (unsigned int)(ip[0] & 0x0F) * 4;
    if (ip[9] != IP_PROTO_ICMP) return 0;
    if (n < 14 + ihl + 8) return 0;

    unsigned int dst_ip = ((unsigned int)ip[16] << 24) | ((unsigned int)ip[17] << 16) |
                          ((unsigned int)ip[18] << 8)  |  (unsigned int)ip[19];
    if (dst_ip != MY_IP) return 0;   // не нам

    const unsigned char *req_icmp = ip + ihl;
    if (req_icmp[0] != ICMP_ECHO_REQUEST) return 0;

    unsigned int ip_total   = ((unsigned int)ip[2] << 8) | ip[3];
    unsigned int icmp_len   = (ip_total > ihl) ? (ip_total - ihl) : 0;
    unsigned int payload_len = (icmp_len > 8) ? (icmp_len - 8) : 0;
    if (payload_len > PING_PAYLOAD_LEN) payload_len = PING_PAYLOAD_LEN;
    unsigned int avail = (n > 14 + ihl + 8) ? (n - (14 + ihl + 8)) : 0;
    if (payload_len > avail) payload_len = avail;

    unsigned int src_ip = ((unsigned int)ip[12] << 24) | ((unsigned int)ip[13] << 16) |
                          ((unsigned int)ip[14] << 8)  |  (unsigned int)ip[15];

    unsigned char my_mac[6];
    if (!net_mac(my_mac)) return 0;

    unsigned char *eth = icmp_tx;
    for (int i = 0; i < 6; i++) eth[i]     = rx[6 + i];   // dst = src запросившего кадра
    for (int i = 0; i < 6; i++) eth[6 + i] = my_mac[i];
    arp__put16be(eth + 12, 0x0800);

    unsigned char *rip = eth + 14;
    unsigned int reply_icmp_len = 8 + payload_len;
    unsigned int reply_ip_total = 20 + reply_icmp_len;
    rip[0] = 0x45; rip[1] = 0;
    arp__put16be(rip + 2, reply_ip_total);
    arp__put16be(rip + 4, 0);
    arp__put16be(rip + 6, 0);
    rip[8] = 64;
    rip[9] = IP_PROTO_ICMP;
    rip[10] = 0; rip[11] = 0;
    unsigned int my_ip = MY_IP;
    rip[12] = (unsigned char)(my_ip >> 24); rip[13] = (unsigned char)(my_ip >> 16);
    rip[14] = (unsigned char)(my_ip >> 8);  rip[15] = (unsigned char)my_ip;
    rip[16] = (unsigned char)(src_ip >> 24); rip[17] = (unsigned char)(src_ip >> 16);
    rip[18] = (unsigned char)(src_ip >> 8);  rip[19] = (unsigned char)src_ip;
    arp__put16be(rip + 10, ip_checksum(rip, 20));

    unsigned char *ricmp = rip + 20;
    ricmp[0] = ICMP_ECHO_REPLY; ricmp[1] = 0;
    ricmp[2] = 0; ricmp[3] = 0;
    ricmp[4] = req_icmp[4]; ricmp[5] = req_icmp[5];   // тот же identifier
    ricmp[6] = req_icmp[6]; ricmp[7] = req_icmp[7];   // тот же sequence
    for (unsigned int i = 0; i < payload_len; i++) ricmp[8 + i] = req_icmp[8 + i];
    arp__put16be(ricmp + 2, ip_checksum(ricmp, reply_icmp_len));

    net_send(icmp_tx, 14 + reply_ip_total);
    return 1;
}

// Собирает и шлёт один ICMP echo request на dst_ip (резолвя MAC через ARP),
// ждёт ответ до timeout_ms (поллинг net_recv() каждые 10мс). При успехе
// возвращает 1 и кладёт время round-trip (мс) в *rtt_ms_out.
static int icmp_ping(unsigned int dst_ip, unsigned short seq,
                      unsigned int timeout_ms, unsigned long *rtt_ms_out) {
    unsigned char dst_mac[6], my_mac[6];
    if (!net_mac(my_mac)) return 0;
    if (!arp_resolve(dst_ip, dst_mac, 2000)) return 0;

    unsigned char *eth = icmp_tx;
    for (int i = 0; i < 6; i++) eth[i] = dst_mac[i];
    for (int i = 0; i < 6; i++) eth[6 + i] = my_mac[i];
    arp__put16be(eth + 12, 0x0800);   // ethertype = IPv4

    unsigned char *ip = eth + 14;
    unsigned int icmp_len = 8 + PING_PAYLOAD_LEN;
    unsigned int ip_total = 20 + icmp_len;
    ip[0] = 0x45; ip[1] = 0;                 // version=4, IHL=5, TOS=0
    arp__put16be(ip + 2, ip_total);
    arp__put16be(ip + 4, seq);               // identification (переиспользуем seq)
    arp__put16be(ip + 6, 0);                 // flags/fragment offset
    ip[8] = 64;                              // TTL
    ip[9] = IP_PROTO_ICMP;
    ip[10] = 0; ip[11] = 0;                  // checksum - заполняется ниже
    unsigned int my_ip = MY_IP;
    ip[12] = (unsigned char)(my_ip >> 24); ip[13] = (unsigned char)(my_ip >> 16);
    ip[14] = (unsigned char)(my_ip >> 8);  ip[15] = (unsigned char)my_ip;
    ip[16] = (unsigned char)(dst_ip >> 24); ip[17] = (unsigned char)(dst_ip >> 16);
    ip[18] = (unsigned char)(dst_ip >> 8);  ip[19] = (unsigned char)dst_ip;
    arp__put16be(ip + 10, ip_checksum(ip, 20));

    unsigned char *icmp = ip + 20;
    icmp[0] = ICMP_ECHO_REQUEST; icmp[1] = 0;
    icmp[2] = 0; icmp[3] = 0;                // checksum - заполняется ниже
    arp__put16be(icmp + 4, ICMP_ID);
    arp__put16be(icmp + 6, seq);
    for (int i = 0; i < PING_PAYLOAD_LEN; i++) icmp[8 + i] = (unsigned char)('a' + (i % 23));
    arp__put16be(icmp + 2, ip_checksum(icmp, icmp_len));

    unsigned long t0 = (unsigned long)gettime();
    net_send(icmp_tx, 14 + ip_total);

    unsigned int waited = 0;
    while (waited < timeout_ms) {
        unsigned int n = net_recv(icmp_rx, sizeof(icmp_rx));
        if (n >= 14 + 20 + 8) {
            unsigned char *rip   = icmp_rx + 14;
            unsigned char *ricmp = icmp_rx + 14 + 20;
            if (icmp_rx[12] == 0x08 && icmp_rx[13] == 0x00 &&   // ethertype IPv4
                rip[9] == IP_PROTO_ICMP && ricmp[0] == ICMP_ECHO_REPLY) {
                unsigned int rid  = ((unsigned int)ricmp[4] << 8) | ricmp[5];
                unsigned int rseq = ((unsigned int)ricmp[6] << 8) | ricmp[7];
                if (rid == ICMP_ID && rseq == seq) {
                    if (rtt_ms_out) *rtt_ms_out = ((unsigned long)gettime() - t0) / 10000UL;
                    return 1;
                }
            }
            icmp_maybe_respond(icmp_rx, n);   // заодно отвечаем, если нас саму пингуют
        }
        sleep_ms(10);
        waited += 10;
    }
    return 0;
}
