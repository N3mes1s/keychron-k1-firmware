/* SPDX-License-Identifier: MIT */
#include <assert.h>
#include <stdio.h>
#include <zmk/ble_tuning_protocol.h>

int main(void) {
    for (int mac = 0; mac < 2; mac++) {
        for (int profile = 0; profile <= K1_BT_FAST; profile++) {
            struct k1_bt_parameters p = k1_bt_profile_parameters(profile, mac);
            assert(k1_bt_parameters_valid(&p));
            if (profile != K1_BT_STOCK) {
                assert(p.latency == 0);
            }
        }
    }
    uint8_t packet[20] = {1, K1_BT_OP_DEBOUNCE, 0, 10};
    assert(k1_bt_write_valid(packet, 4));
    for (size_t len = 0; len <= sizeof(packet); len++) {
        if (len != 4) {
            assert(!k1_bt_write_valid(packet, len));
        }
    }
    for (unsigned press = 0; press < 256; press++) {
        for (unsigned release = 0; release < 256; release++) {
            packet[2] = press;
            packet[3] = release;
            assert(k1_bt_write_valid(packet, 4) ==
                (press <= 50 && release >= 1 && release <= 50));
        }
    }
    packet[1] = K1_BT_OP_PROFILE;
    for (unsigned profile = 0; profile < 256; profile++) {
        packet[2] = profile;
        assert(k1_bt_write_valid(packet, 3) == (profile <= K1_BT_FAST));
    }
    const uint8_t valid_custom[] = {1, 3, 6, 0, 12, 0, 0, 0, 0x90, 1};
    assert(k1_bt_write_valid(valid_custom, sizeof(valid_custom)));
    struct k1_bt_parameters bad[] = {
        {5, 12, 0, 400}, {6, 41, 0, 400}, {12, 6, 0, 400},
        {6, 12, 31, 400}, {6, 12, 0, 199}, {6, 12, 0, 601},
        {40, 40, 30, 200}, /* supervision timeout too short */
    };
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); i++) {
        assert(!k1_bt_parameters_valid(&bad[i]));
    }
    packet[0] = 2;
    assert(!k1_bt_write_valid(packet, 3));
    packet[0] = 1;
    packet[1] = 255;
    assert(!k1_bt_write_valid(packet, 3));
    puts("Bluetooth protocol boundary checks passed (65,536 debounce combinations).");
}
