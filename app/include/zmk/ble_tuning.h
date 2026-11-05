/* SPDX-License-Identifier: MIT */
#pragma once

#include <zephyr/bluetooth/conn.h>

int zmk_ble_tuning_init(void);
void zmk_ble_tuning_parameters(struct bt_le_conn_param *parameters, bool mac);
void zmk_ble_tuning_request_result(int result);
void zmk_ble_request_parameter_update(void);
