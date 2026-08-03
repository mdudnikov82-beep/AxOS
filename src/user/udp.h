#ifndef AXOS_UDP_H
#define AXOS_UDP_H

// Минимальный UDP поверх IPv4/ARP (icmp.h - переиспользуем оттуда только
// ip_checksum()/MY_IP/arp_resolve_next_hop(), сам ICMP тут не нужен, но
// выносить его в отдельный header ради этого не стоит). Портирован с
// RISC-V стороны (src/user/rv64/udp.h) - тот же протокол, та же логика.

#include "icmp.h"

#define IP_PROTO_UDP 17

static unsigned char udp_tx[14 + 20 + 8 + 512];
static unsigned char udp_rx[600];

// ---- Общая сетевая случайность (TCP ISN, DNS query ID/source port) ----
// xorshift64, тот же алгоритм/константы, что уже используются для MTE
// тегов поколения (malloc.c) - переиспользовано вместо изобретения
// нового PRNG. Возвращает старшие 32 бита (лучше перемешаны, чем
// младшие, для xorshift-генераторов).
static unsigned long long __net_rand_state = 0;
static unsigned int net_rand32(void) {
    if (__net_rand_state == 0) {
        __net_rand_state = (unsigned long long)ax_get_ticks() ^ 0x9E3779B97F4A7C15ULL;
        if (__net_rand_state == 0) __net_rand_state = 1ULL;
    }
    __net_rand_state ^= __net_rand_state << 13;
    __net_rand_state ^= __net_rand_state >> 7;
    __net_rand_state ^= __net_rand_state << 17;
    return (unsigned int)(__net_rand_state >> 32);
}

// Собирает и шлёт одну UDP-датаграмму (макс. 512 байт payload). Поле
// UDP-чексуммы ставится в 0 - по RFC 768 чексумма над IPv4 ОПЦИОНАЛЬНА,
// 0 означает "не считалась", это не битый пакет, а легальный режим.
static int udp_send(unsigned int dst_ip, unsigned short dst_port, unsigned short src_port,
                     const void *payload, unsigned int len) {
    if (len > 512) return -1;

    unsigned char dst_mac[6], my_mac[6];
    if (!ax_net_mac(my_mac)) return -1;
    if (!arp_resolve_next_hop(dst_ip, dst_mac, 2000)) return -1;

    unsigned char *eth = udp_tx;
    for (int i = 0; i < 6; i++) eth[i] = dst_mac[i];
    for (int i = 0; i < 6; i++) eth[6 + i] = my_mac[i];
    arp__put16be(eth + 12, 0x0800);   // ethertype = IPv4

    unsigned char *ip = eth + 14;
    unsigned int udp_len = 8 + len;
    unsigned int ip_total = 20 + udp_len;
    ip[0] = 0x45; ip[1] = 0;
    arp__put16be(ip + 2, ip_total);
    arp__put16be(ip + 4, 0);          // identification
    arp__put16be(ip + 6, 0);          // flags/fragment offset
    ip[8] = 64;                       // TTL
    ip[9] = IP_PROTO_UDP;
    ip[10] = 0; ip[11] = 0;           // checksum - заполняется ниже
    unsigned int my_ip = MY_IP;
    ip[12] = (unsigned char)(my_ip >> 24); ip[13] = (unsigned char)(my_ip >> 16);
    ip[14] = (unsigned char)(my_ip >> 8);  ip[15] = (unsigned char)my_ip;
    ip[16] = (unsigned char)(dst_ip >> 24); ip[17] = (unsigned char)(dst_ip >> 16);
    ip[18] = (unsigned char)(dst_ip >> 8);  ip[19] = (unsigned char)dst_ip;
    arp__put16be(ip + 10, ip_checksum(ip, 20));

    unsigned char *udp = ip + 20;
    arp__put16be(udp + 0, src_port);
    arp__put16be(udp + 2, dst_port);
    arp__put16be(udp + 4, udp_len);
    udp[6] = 0; udp[7] = 0;   // checksum = 0 (не считаем, см. коммент выше)

    unsigned char *data = udp + 8;
    const unsigned char *src = (const unsigned char *)payload;
    for (unsigned int i = 0; i < len; i++) data[i] = src[i];

    return (ax_net_send(udp_tx, 14 + ip_total) == 0) ? 0 : -1;
}

// Неблокирующий приём одной UDP-датаграммы (poll). Если что-то пришло и
// это UDP, копирует payload в buf (обрезая по max_len), заполняет
// src_ip/src_port/dst_port (любой из указателей можно передать NULL) и
// возвращает длину скопированного payload. 0 - ничего/не UDP.
static unsigned int udp_recv(unsigned int *src_ip_out, unsigned short *src_port_out,
                              unsigned short *dst_port_out, void *buf, unsigned int max_len) {
    unsigned int n = ax_net_recv(udp_rx, sizeof(udp_rx));
    if (n < 14 + 20 + 8) return 0;
    if (udp_rx[12] != 0x08 || udp_rx[13] != 0x00) return 0;   // ethertype != IPv4

    unsigned char *ip = udp_rx + 14;
    if (ip[9] != IP_PROTO_UDP) return 0;
    unsigned int ihl = (unsigned int)(ip[0] & 0x0F) * 4;   // обычно 20, но не хардкодим
    // РЕАЛЬНЫЙ БАГ (найден при аудите, есть на обеих платформах - tcp.h/
    // icmp.h уже делают эту же проверку). ihl может быть больше 20
    // (IP-опции) - без этой проверки udp[4]/udp[5] читались бы за
    // пределами того, что n подтверждает, если пакет короче, чем
    // заявляет свой же IHL.
    if (n < 14 + ihl + 8) return 0;
    unsigned char *udp = ip + ihl;

    unsigned int udp_len = ((unsigned int)udp[4] << 8) | udp[5];
    unsigned int data_len = (udp_len > 8) ? (udp_len - 8) : 0;
    if (data_len > max_len) data_len = max_len;
    // Не доверяем udp_len сверх того, что n реально подтверждает - та же
    // защита, что уже есть в tcp_parse_segment()/icmp_maybe_respond().
    unsigned int avail = (n > 14 + ihl + 8) ? (n - (14 + ihl + 8)) : 0;
    if (data_len > avail) data_len = avail;

    unsigned char *data = udp + 8;
    unsigned char *dst = (unsigned char *)buf;
    for (unsigned int i = 0; i < data_len; i++) dst[i] = data[i];

    if (src_ip_out) *src_ip_out = ((unsigned int)ip[12] << 24) | ((unsigned int)ip[13] << 16) |
                                  ((unsigned int)ip[14] << 8)  |  (unsigned int)ip[15];
    if (src_port_out) *src_port_out = (unsigned short)(((unsigned int)udp[0] << 8) | udp[1]);
    if (dst_port_out) *dst_port_out = (unsigned short)(((unsigned int)udp[2] << 8) | udp[3]);
    return data_len;
}

#endif
