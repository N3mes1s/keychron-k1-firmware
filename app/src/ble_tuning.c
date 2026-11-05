/* SPDX-License-Identifier: MIT
 * Local Bluetooth settings for the K1 Ultra. No key reports or arbitrary
 * Launcher/DFU commands are exposed through this service.
 */
#include <errno.h>
#include <string.h>
#include <zephyr/kernel.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/settings/settings.h>
#include <zephyr/sys/byteorder.h>
#include <zmk/ble.h>
#include <zmk/ble_tuning.h>
#include <zmk/ble_tuning_protocol.h>
#include "launcher/launcher.h"

#define TUNING_SERVICE_UUID BT_UUID_128_ENCODE(0x8b7f9b20, 0x6f06, 0x4e8c, 0xbc17, 0x41f136c1a100)
#define TUNING_CONTROL_UUID BT_UUID_128_ENCODE(0x8b7f9b20, 0x6f06, 0x4e8c, 0xbc17, 0x41f136c1a101)

static struct bt_uuid_128 service_uuid = BT_UUID_INIT_128(TUNING_SERVICE_UUID);
static struct bt_uuid_128 control_uuid = BT_UUID_INIT_128(TUNING_CONTROL_UUID);
static struct k_spinlock state_lock;
static uint8_t selected_profile = K1_BT_STOCK;
static struct k1_bt_parameters custom_parameters = {6, 12, 0, 400};
static int16_t request_result = -ENODATA;
static int16_t save_result;
static bool save_pending;
static uint32_t generation;

extern bool settings_enabled_dlps;
uint8_t get_os_type(void);

struct bond_match {
    const bt_addr_le_t *peer;
    bool found;
};

static void find_bond(const struct bt_bond_info *bond, void *user_data) {
    struct bond_match *match = user_data;
    match->found |= bt_addr_le_cmp(&bond->addr, match->peer) == 0;
}

static bool active_secure_host(struct bt_conn *conn) {
    struct bt_conn_info info;
    if (!conn || bt_conn_get_security(conn) < BT_SECURITY_L2 ||
        bt_conn_get_info(conn, &info) != 0 || info.type != BT_CONN_TYPE_LE ||
        info.role != BT_CONN_ROLE_PERIPHERAL ||
        info.id != zmk_ble_active_profile_btid() ||
        bt_addr_le_cmp(bt_conn_get_dst(conn), zmk_ble_active_profile_addr()) != 0) {
        return false;
    }
    struct bond_match match = {.peer = bt_conn_get_dst(conn), .found = false};
    bt_foreach_bond(info.id, find_bond, &match);
    return match.found;
}

static void encode_saved(uint8_t data[10]) {
    data[0] = K1_BT_PROTOCOL_VERSION;
    data[1] = selected_profile;
    sys_put_le16(custom_parameters.min_interval, data + 2);
    sys_put_le16(custom_parameters.max_interval, data + 4);
    sys_put_le16(custom_parameters.latency, data + 6);
    sys_put_le16(custom_parameters.timeout, data + 8);
}

static void save_worker(struct k_work *work) {
    uint8_t data[10];
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    uint32_t saving_generation = generation;
    encode_saved(data);
    k_spin_unlock(&state_lock, key);
    /* Use the same power-management gate as the existing Launcher storage. */
    bool previous_gate = settings_enabled_dlps;
    settings_enabled_dlps = false;
    int result = settings_save_one("ble_tuning/config", data, sizeof(data));
    settings_enabled_dlps = previous_gate;
    key = k_spin_lock(&state_lock);
    if (generation == saving_generation) {
        save_pending = false;
        save_result = result;
    }
    k_spin_unlock(&state_lock, key);
}

K_WORK_DELAYABLE_DEFINE(save_work, save_worker);

static int settings_set(const char *name, size_t len, settings_read_cb read_cb, void *cb_arg) {
    uint8_t data[10];
    if (strcmp(name, "config") != 0) {
        return -ENOENT;
    }
    if (len != sizeof(data)) {
        return -EINVAL;
    }
    int result = read_cb(cb_arg, data, sizeof(data));
    if (result < 0) {
        return result;
    }
    if (result != sizeof(data) || data[0] != K1_BT_PROTOCOL_VERSION ||
        data[1] > K1_BT_CUSTOM) {
        return -EINVAL;
    }
    struct k1_bt_parameters parameters = {
        sys_get_le16(data + 2), sys_get_le16(data + 4),
        sys_get_le16(data + 6), sys_get_le16(data + 8)};
    if (!k1_bt_parameters_valid(&parameters)) {
        return -EINVAL;
    }
    selected_profile = data[1];
    custom_parameters = parameters;
    return 0;
}

static struct settings_handler tuning_handler = {
    .name = "ble_tuning", .h_set = settings_set,
};

int zmk_ble_tuning_init(void) {
    int result = settings_register(&tuning_handler);
    return result ? result : settings_load_subtree("ble_tuning");
}

void zmk_ble_tuning_parameters(struct bt_le_conn_param *parameters, bool mac) {
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    struct k1_bt_parameters p = selected_profile == K1_BT_CUSTOM ? custom_parameters :
        k1_bt_profile_parameters(selected_profile, mac);
    k_spin_unlock(&state_lock, key);
    parameters->interval_min = p.min_interval;
    parameters->interval_max = p.max_interval;
    parameters->latency = p.latency;
    parameters->timeout = p.timeout;
}

void zmk_ble_tuning_request_result(int result) {
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    request_result = result;
    k_spin_unlock(&state_lock, key);
}

static ssize_t read_status(struct bt_conn *conn, const struct bt_gatt_attr *attr,
                           void *buf, uint16_t len, uint16_t offset) {
    if (!active_secure_host(conn)) {
        return BT_GATT_ERR(BT_ATT_ERR_AUTHORIZATION);
    }
    struct bt_conn_info info;
    if (bt_conn_get_info(conn, &info) != 0) {
        return BT_GATT_ERR(BT_ATT_ERR_UNLIKELY);
    }
    uint8_t status[K1_BT_STATUS_SIZE] = {K1_BT_PROTOCOL_VERSION, 0x03};
    launcher_get_debounce(status + 2, status + 3);
    struct bt_le_conn_param parameters;
    zmk_ble_tuning_parameters(&parameters, get_os_type() != 0);
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    status[4] = selected_profile;
    status[5] = 0x03 | (save_pending ? 0x04 : 0);
    sys_put_le16((uint16_t)request_result, status + 20);
    sys_put_le16((uint16_t)save_result, status + 22);
    k_spin_unlock(&state_lock, key);
    bool matches = info.le.interval >= parameters.interval_min &&
                   info.le.interval <= parameters.interval_max &&
                   info.le.latency == parameters.latency &&
                   info.le.timeout == parameters.timeout;
    if (matches) {
        status[5] |= 0x08;
    }
    sys_put_le16(parameters.interval_min, status + 6);
    sys_put_le16(parameters.interval_max, status + 8);
    sys_put_le16(parameters.latency, status + 10);
    sys_put_le16(parameters.timeout, status + 12);
    sys_put_le16(info.le.interval, status + 14);
    sys_put_le16(info.le.latency, status + 16);
    sys_put_le16(info.le.timeout, status + 18);
    return bt_gatt_attr_read(conn, attr, buf, len, offset, status, sizeof(status));
}

static ssize_t write_control(struct bt_conn *conn, const struct bt_gatt_attr *attr,
                             const void *buf, uint16_t len, uint16_t offset, uint8_t flags) {
    if (!active_secure_host(conn)) {
        return BT_GATT_ERR(BT_ATT_ERR_AUTHORIZATION);
    }
    if (offset != 0 || flags != 0) {
        return BT_GATT_ERR(BT_ATT_ERR_INVALID_OFFSET);
    }
    const uint8_t *data = buf;
    if (!k1_bt_write_valid(data, len)) {
        return BT_GATT_ERR(BT_ATT_ERR_VALUE_NOT_ALLOWED);
    }
    if (data[1] == K1_BT_OP_DEBOUNCE) {
        return launcher_set_debounce(data[2], data[3]) == 0 ? len :
            BT_GATT_ERR(BT_ATT_ERR_VALUE_NOT_ALLOWED);
    }
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    if (data[1] == K1_BT_OP_PROFILE) {
        selected_profile = data[2];
    } else {
        selected_profile = K1_BT_CUSTOM;
        custom_parameters = (struct k1_bt_parameters){
            sys_get_le16(data + 2), sys_get_le16(data + 4),
            sys_get_le16(data + 6), sys_get_le16(data + 8)};
    }
    generation++;
    save_pending = true;
    request_result = -EINPROGRESS;
    k_spin_unlock(&state_lock, key);
    k_work_reschedule(&save_work, K_MSEC(500));
    zmk_ble_request_parameter_update();
    return len;
}

BT_GATT_SERVICE_DEFINE(k1_tuning_svc,
    BT_GATT_PRIMARY_SERVICE(&service_uuid.uuid),
    BT_GATT_CHARACTERISTIC(&control_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_WRITE,
        BT_GATT_PERM_READ_ENCRYPT | BT_GATT_PERM_WRITE_ENCRYPT,
        read_status, write_control, NULL));
