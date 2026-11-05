/* SPDX-License-Identifier: MIT */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define K1_BT_PROTOCOL_VERSION 1
#define K1_BT_STATUS_SIZE 24
#define K1_BT_OP_DEBOUNCE 1
#define K1_BT_OP_PROFILE 2
#define K1_BT_OP_CUSTOM 3

enum k1_bt_profile {
    K1_BT_STOCK = 0,
    K1_BT_RESPONSIVE = 1,
    K1_BT_FAST = 2,
    K1_BT_CUSTOM = 3,
};

struct k1_bt_parameters {
    uint16_t min_interval;
    uint16_t max_interval;
    uint16_t latency;
    uint16_t timeout;
};

static inline uint16_t k1_bt_get_le16(const uint8_t *p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static inline bool k1_bt_parameters_valid(const struct k1_bt_parameters *p) {
    /* A deliberately bounded tuning range, with the Core supervision constraint.
     * Intervals: 1.25 ms units. Timeout: 10 ms units. */
    return p->min_interval >= 6 && p->max_interval <= 40 &&
           p->min_interval <= p->max_interval && p->latency <= 30 &&
           p->timeout >= 200 && p->timeout <= 600 &&
           (uint32_t)p->timeout * 8 >
               (uint32_t)p->max_interval * (p->latency + 1) * 2;
}

static inline struct k1_bt_parameters k1_bt_profile_parameters(uint8_t profile, bool mac) {
    struct k1_bt_parameters p = {6, 6, 30, 400};
    if (profile == K1_BT_STOCK && mac) {
        p.min_interval = p.max_interval = 12;
    } else if (profile == K1_BT_RESPONSIVE) {
        p.min_interval = mac ? 9 : 6;
        p.max_interval = mac ? 12 : 9;
        p.latency = 0;
    } else if (profile == K1_BT_FAST) {
        p.latency = 0;
    }
    return p;
}

static inline bool k1_bt_write_valid(const uint8_t *data, size_t len) {
    if (len < 2 || data[0] != K1_BT_PROTOCOL_VERSION) {
        return false;
    }
    switch (data[1]) {
    case K1_BT_OP_DEBOUNCE:
        return len == 4 && data[2] <= 50 && data[3] >= 1 && data[3] <= 50;
    case K1_BT_OP_PROFILE:
        return len == 3 && data[2] <= K1_BT_FAST;
    case K1_BT_OP_CUSTOM:
        if (len == 10) {
            struct k1_bt_parameters p = {
                k1_bt_get_le16(data + 2), k1_bt_get_le16(data + 4),
                k1_bt_get_le16(data + 6), k1_bt_get_le16(data + 8)};
            return k1_bt_parameters_valid(&p);
        }
        return false;
    default:
        return false;
    }
}
