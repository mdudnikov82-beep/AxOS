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
        }
        sleep_ms(10);
        waited += 10;
    }
    return 0;
}
