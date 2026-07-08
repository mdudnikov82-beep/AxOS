#pragma once

// Минимальный ARP поверх virtio-net (см. virtio_net.c/SYS_NET_*): резолв
// "IPv4 -> MAC" исходящими запросами (arp_resolve) и ответ на входящие
// запросы, адресованные нашему собственному IP (arp_maybe_respond) - раз
// гость теперь честно "владеет" MY_IP (см. ниже), отвечать на "кто держит
// MY_IP?" правильно и обязательно, а не просто вежливо.
//
// Header-only библиотека в стиле malloc.h/gfx_ui.h этого же каталога:
// подключается в один .c-файл, который линкуется в отдельный ELF - каждая
// программа получает свою собственную копию кэша/буферов, коллизий между
// программами нет (это не общая библиотека в разделяемой памяти).
//
// RX-буфер и кэш - static (не в стеке): RV64 user-стек - ОДНА страница 4КБ
// на весь call chain, arp_rx_buf/arp_cache_tbl тут заведомо большие.

#include "syscall.h"

#define IP4(a, b, c, d) \
    (((unsigned int)(a) << 24) | ((unsigned int)(b) << 16) | \
     ((unsigned int)(c) << 8)  |  (unsigned int)(d))

// IP гостя. По умолчанию - статика (тот же 10.0.2.0/24, что и гейтвей
// 10.0.2.2/DNS 10.0.2.3, которые QEMU SLIRP готов маршрутизировать), но
// теперь это переменная, а не константа - dhcp.h (если подключить и
// вызвать dhcp_client()) перезаписывает её реальным выданным адресом
// после успешного DORA-обмена. MY_IP - это ВСЕГДА g_my_ip, просто
// удобное имя для всех вызывающих (arp.h/icmp.h/udp.h), которые были
// написаны до dhcp.h и ожидают MY_IP как значение, а не переменную.
static unsigned int g_my_ip = IP4(10, 0, 2, 15);
#define MY_IP g_my_ip

// Маска подсети и гейтвей - умолчания совпадают с тем, что реально
// раздаёт QEMU SLIRP; dhcp.h (dhcp_client()) перезаписывает их настоящими
// значениями из ACK, как и g_my_ip. Нужны исключительно для
// arp_resolve_next_hop() ниже - без них нет способа отличить "адрес в
// нашей локальной сети" от "адрес где-то в интернете".
static unsigned int g_subnet_mask = IP4(255, 255, 255, 0);
static unsigned int g_router_ip   = IP4(10, 0, 2, 2);

#define ARP_CACHE_SIZE 8

typedef struct {
    unsigned int  ip;
    unsigned char mac[6];
    int           valid;
} arp_entry_t;

static arp_entry_t   arp_cache_tbl[ARP_CACHE_SIZE];
static unsigned char arp_my_mac[6];
static int            arp_my_mac_ok = 0;
static unsigned char  arp_rx_buf[128];

static void arp__put16be(unsigned char *p, unsigned int v) {
    p[0] = (unsigned char)(v >> 8);
    p[1] = (unsigned char)v;
}

static void arp_cache_put(unsigned int ip, const unsigned char mac[6]) {
    int slot = -1;
    for (int i = 0; i < ARP_CACHE_SIZE; i++) {
        if (arp_cache_tbl[i].valid && arp_cache_tbl[i].ip == ip) { slot = i; break; }
    }
    if (slot < 0) {
        for (int i = 0; i < ARP_CACHE_SIZE; i++) {
            if (!arp_cache_tbl[i].valid) { slot = i; break; }
        }
    }
    if (slot < 0) slot = 0;   // кэш полон - вытесняем первый слот (LRU тут излишен)

    arp_cache_tbl[slot].ip = ip;
    for (int j = 0; j < 6; j++) arp_cache_tbl[slot].mac[j] = mac[j];
    arp_cache_tbl[slot].valid = 1;
}

static int arp_cache_get(unsigned int ip, unsigned char mac_out[6]) {
    for (int i = 0; i < ARP_CACHE_SIZE; i++) {
        if (arp_cache_tbl[i].valid && arp_cache_tbl[i].ip == ip) {
            for (int j = 0; j < 6; j++) mac_out[j] = arp_cache_tbl[i].mac[j];
            return 1;
        }
    }
    return 0;
}

// Шлёт широковещательный ARP-запрос "кто держит ip?".
static void arp_send_request(unsigned int ip) {
    if (!arp_my_mac_ok) arp_my_mac_ok = net_mac(arp_my_mac);

    unsigned char f[42];
    for (int i = 0; i < 6; i++) f[i] = 0xFF;              // dst = broadcast
    for (int i = 0; i < 6; i++) f[6 + i] = arp_my_mac[i]; // src = наш MAC
    arp__put16be(f + 12, 0x0806);                          // ethertype = ARP

    unsigned char *a = f + 14;
    arp__put16be(a + 0, 1);        // htype = Ethernet
    arp__put16be(a + 2, 0x0800);   // ptype = IPv4
    a[4] = 6; a[5] = 4;            // hlen/plen
    arp__put16be(a + 6, 1);        // oper = request
    for (int i = 0; i < 6; i++) a[8 + i] = arp_my_mac[i];
    unsigned int my_ip = MY_IP;
    a[14] = (unsigned char)(my_ip >> 24); a[15] = (unsigned char)(my_ip >> 16);
    a[16] = (unsigned char)(my_ip >> 8);  a[17] = (unsigned char)my_ip;
    for (int i = 0; i < 6; i++) a[18 + i] = 0;   // target MAC (неизвестен)
    a[24] = (unsigned char)(ip >> 24); a[25] = (unsigned char)(ip >> 16);
    a[26] = (unsigned char)(ip >> 8);  a[27] = (unsigned char)ip;

    net_send(f, sizeof(f));
}

// Разбирает один принятый кадр; если это ARP-ответ - кладёт отправителя в
// кэш (заодно, даже если это не тот IP, который мы ждали - "подслушанное"
// сообщение всё равно полезно). Возвращает 1, если это был ответ именно от
// wanted_ip (mac_out заполнен).
static int arp_handle_frame(const unsigned char *rx, unsigned int n,
                             unsigned int wanted_ip, unsigned char mac_out[6]) {
    if (n < 42) return 0;
    if (rx[12] != 0x08 || rx[13] != 0x06) return 0;   // ethertype != ARP
    if (rx[20] != 0x00 || rx[21] != 0x02) return 0;   // oper != reply

    unsigned int sender_ip = ((unsigned int)rx[28] << 24) | ((unsigned int)rx[29] << 16) |
                             ((unsigned int)rx[30] << 8)  |  (unsigned int)rx[31];
    arp_cache_put(sender_ip, rx + 22);

    if (sender_ip == wanted_ip) {
        for (int j = 0; j < 6; j++) mac_out[j] = rx[22 + j];
        return 1;
    }
    return 0;
}

// Проверяет, не входящий ли это ARP-запрос НАШЕГО MY_IP - и если да, шлёт
// корректный ARP-ответ (unicast запросившему, а не broadcast). Возвращает
// 1, если ответили (кадр обработан), 0 если это был не такой запрос (кадр
// не наш - вызывающий может проверить его на что-то другое).
static int arp_maybe_respond(const unsigned char *rx, unsigned int n) {
    if (n < 42) return 0;
    if (rx[12] != 0x08 || rx[13] != 0x06) return 0;   // ethertype != ARP
    if (rx[20] != 0x00 || rx[21] != 0x01) return 0;   // oper != request

    // ARP-payload с offset 14: htype(14-15) ptype(16-17) hlen(18) plen(19)
    // oper(20-21) sha(22-27) spa(28-31) tha(32-37) tpa(38-41) - tpa (target
    // IP), а НЕ 24-27 (это середина sha соседнего запроса).
    unsigned int target_ip = ((unsigned int)rx[38] << 24) | ((unsigned int)rx[39] << 16) |
                             ((unsigned int)rx[40] << 8)  |  (unsigned int)rx[41];
    if (target_ip != MY_IP) return 0;   // не про нас

    if (!arp_my_mac_ok) arp_my_mac_ok = net_mac(arp_my_mac);

    unsigned char reply[42];
    for (int i = 0; i < 6; i++) reply[i]     = rx[22 + i];    // dst = запросивший
    for (int i = 0; i < 6; i++) reply[6 + i] = arp_my_mac[i]; // src = мы
    arp__put16be(reply + 12, 0x0806);

    unsigned char *a = reply + 14;
    arp__put16be(a + 0, 1); arp__put16be(a + 2, 0x0800);
    a[4] = 6; a[5] = 4;
    arp__put16be(a + 6, 2);   // oper = reply
    for (int i = 0; i < 6; i++) a[8 + i] = arp_my_mac[i];
    unsigned int my_ip = MY_IP;
    a[14] = (unsigned char)(my_ip >> 24); a[15] = (unsigned char)(my_ip >> 16);
    a[16] = (unsigned char)(my_ip >> 8);  a[17] = (unsigned char)my_ip;
    for (int i = 0; i < 6; i++) a[18 + i] = rx[22 + i];   // target MAC = запросивший (его sha)
    a[24] = rx[28]; a[25] = rx[29]; a[26] = rx[30]; a[27] = rx[31]; // target IP = его spa (sender IP)

    net_send(reply, sizeof(reply));
    return 1;
}

// Резолвит ip -> MAC. Сначала смотрит в кэше; если нет - шлёт запрос и ждёт
// до timeout_ms (поллинг net_recv() каждые 20мс). Возвращает 1/0.
static int arp_resolve(unsigned int ip, unsigned char mac_out[6], unsigned int timeout_ms) {
    if (arp_cache_get(ip, mac_out)) return 1;

    arp_send_request(ip);

    unsigned int waited = 0;
    while (waited < timeout_ms) {
        unsigned int n = net_recv(arp_rx_buf, sizeof(arp_rx_buf));
        if (n > 0) {
            if (arp_handle_frame(arp_rx_buf, n, ip, mac_out)) return 1;
            arp_maybe_respond(arp_rx_buf, n);   // заодно отвечаем, если это спрашивали НАС
        }
        sleep_ms(20);
        waited += 20;
    }
    return 0;
}

// Резолвит MAC для ОТПРАВКИ пакета на dst_ip: если dst_ip лежит в нашей
// локальной подсети - резолвит его напрямую (как раньше); иначе резолвит
// гейтвей (g_router_ip) - Ethernet-кадр идёт до гейтвея, а IP-заголовок
// внутри всё равно адресован настоящему dst_ip, гейтвей сам разберётся,
// куда слать дальше. Без этого шага ЛЮБОЙ реальный интернет-адрес был бы
// недостижим - ARP на адрес за пределами локального сегмента никто и
// никогда не ответит (гейтвей отвечает только за СВОЙ адрес, а настоящий
// интернет-хост физически не увидит наш L2-broadcast). Все более ранние
// ICMP/UDP-тесты этой сети везло - и гейтвей (10.0.2.2), и DNS (10.0.2.3)
// сами лежат в локальной подсети, так что резолвились напрямую без
// маршрутизации - этот пробел не проявлялся, пока не появился первый
// тест на настоящий адрес в интернете (см. tcp.h/httpget.c).
static int arp_resolve_next_hop(unsigned int dst_ip, unsigned char mac_out[6],
                                 unsigned int timeout_ms) {
    unsigned int local = ((dst_ip & g_subnet_mask) == (MY_IP & g_subnet_mask));
    unsigned int next_hop = local ? dst_ip : g_router_ip;
    return arp_resolve(next_hop, mac_out, timeout_ms);
}
