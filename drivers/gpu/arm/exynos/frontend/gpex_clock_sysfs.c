/* SPDX-License-Identifier: GPL-2.0 */

/*
 * (C) COPYRIGHT 2021 Samsung Electronics Inc. All rights reserved.
 *
 * This program is free software and is provided to you under the terms of the
 * GNU General Public License version 2 as published by the Free Software
 * Foundation, and any use by you of this program is subject to the terms
 * of such GNU licence.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, you can access it online at
 * http://www.gnu.org/licenses/gpl-2.0.html.
 */

#include <gpex_clock.h>
#include <gpex_pm.h>
#include <gpex_dvfs.h>
#include <gpex_utils.h>
#include <gpex_clboost.h>

#include <linux/regulator/consumer.h>

#include "gpex_clock_internal.h"

static struct _clock_info *clk_info;
static struct regulator *g3d_regulator;

#define GPU_UNLOCKED_FREQ 1209000
#define GPU_NORMAL_FREQ 897000
int gpu_unlock = 1;

/*************************************
 * sysfs node functions
 *************************************/
GPEX_STATIC ssize_t show_clock(char *buf)
{
	ssize_t len = 0;
	int clock = 0;

	gpex_pm_lock();
	if (gpex_pm_get_status(false))
		clock = gpex_clock_get_clock_slow();
	gpex_pm_unlock();

	len += snprintf(buf + len, PAGE_SIZE - len, "%d", clock);

	return gpex_utils_sysfs_endbuf(buf, len);
}
CREATE_SYSFS_DEVICE_READ_FUNCTION(show_clock)
CREATE_SYSFS_KOBJECT_READ_FUNCTION(show_clock)

GPEX_STATIC ssize_t set_clock(const char *buf, size_t count)
{
	unsigned int clk = 0;
	int ret;

	ret = kstrtoint(buf, 0, &clk);
	if (ret) {
		GPU_LOG(MALI_EXYNOS_WARNING, "%s: invalid value\n", __func__);
		return -ENOENT;
	}

	if (clk == 0) {
		gpex_dvfs_enable();
	} else {
		gpex_dvfs_disable();
		gpex_clock_set(clk);
	}

	return count;
}
CREATE_SYSFS_DEVICE_WRITE_FUNCTION(set_clock)

GPEX_STATIC int gpu_get_asv_table(char *buf, size_t buf_size)
{
	int i = 0;
	int len = 0;
	int min_clock_idx = 0;

	if (buf == NULL)
		return 0;

	len += snprintf(buf + len, buf_size - len, "GPU, vol\n");

	min_clock_idx = gpex_clock_get_table_idx(clk_info->gpu_min_clock);

	for (i = gpex_clock_get_table_idx(clk_info->gpu_max_clock); i <= min_clock_idx; i++) {
		len += snprintf(buf + len, buf_size - len, "%d, %7d\n", clk_info->table[i].clock,
				clk_info->table[i].voltage);
	}

	return len;
}

GPEX_STATIC ssize_t show_asv_table(char *buf)
{
	ssize_t ret = 0;

	ret += gpu_get_asv_table(buf + ret, (size_t)PAGE_SIZE - ret);

	if (ret < PAGE_SIZE - 1) {
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "\n");
	} else {
		buf[PAGE_SIZE - 2] = '\n';
		buf[PAGE_SIZE - 1] = '\0';
		ret = PAGE_SIZE - 1;
	}

	return ret;
}
CREATE_SYSFS_DEVICE_READ_FUNCTION(show_asv_table)

GPEX_STATIC ssize_t show_time_in_state(char *buf)
{
	ssize_t ret = 0;
	int i;

	gpex_clock_update_time_in_state(gpex_pm_get_status(true) * clk_info->cur_clock);

	for (i = gpex_clock_get_table_idx(clk_info->gpu_min_clock);
	     i >= gpex_clock_get_table_idx(clk_info->gpu_max_clock); i--) {
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "%d %llu %llu\n",
				clk_info->table[i].clock, clk_info->table[i].time,
				clk_info->table[i].time_busy / 100);
	}

	if (ret >= PAGE_SIZE - 1) {
		buf[PAGE_SIZE - 2] = '\n';
		buf[PAGE_SIZE - 1] = '\0';
		ret = PAGE_SIZE - 1;
	}

	return ret;
}
CREATE_SYSFS_DEVICE_READ_FUNCTION(show_time_in_state)

GPEX_STATIC ssize_t reset_time_in_state(const char *buf, size_t count)
{
	gpex_clock_init_time_in_state();

	return count;
}
CREATE_SYSFS_DEVICE_WRITE_FUNCTION(reset_time_in_state)

void set_max_lock_dvfs(int clock) {
	int ret;

	clk_info->user_max_lock_input = clock;

	clock = gpex_get_valid_gpu_clock(clock, false);

	ret = gpex_clock_get_table_idx(clock);
	if ((ret < gpex_clock_get_table_idx(gpex_clock_get_max_clock())) ||
	    (ret > gpex_clock_get_table_idx(gpex_clock_get_min_clock()))) {
		return;
	}

	if (clock == gpex_clock_get_max_clock()) {
		gpex_clock_lock_clock(GPU_CLOCK_MAX_UNLOCK, SYSFS_LOCK, 0);
	} else {
		gpex_clock_lock_clock(GPU_CLOCK_MAX_LOCK, SYSFS_LOCK, clock);
	}
}

GPEX_STATIC ssize_t set_gpu_unlock(const char *buf, size_t count)
{
	if (sysfs_streq("0", buf) || sysfs_streq("1", buf)) {
		gpu_unlock = sysfs_streq("1", buf);
		set_max_lock_dvfs(gpu_unlock ? GPU_UNLOCKED_FREQ : GPU_NORMAL_FREQ);
	} else {
		return -EINVAL;
	}

	return count;
}

CREATE_SYSFS_KOBJECT_WRITE_FUNCTION(set_gpu_unlock)

GPEX_STATIC ssize_t get_gpu_unlock(char *buf)
{
	return snprintf(buf, PAGE_SIZE, "%d\n", gpu_unlock);
}
CREATE_SYSFS_KOBJECT_READ_FUNCTION(get_gpu_unlock)

GPEX_STATIC ssize_t show_max_lock_dvfs(char *buf)
{
	ssize_t ret = 0;
	unsigned long flags;
	int locked_clock = -1;
	int user_locked_clock = -1;

	gpex_dvfs_spin_lock(&flags);
	locked_clock = clk_info->max_lock;
	user_locked_clock = clk_info->user_max_lock_input;
	gpex_dvfs_spin_unlock(&flags);

	if (locked_clock > 0)
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "%d / %d", locked_clock,
				user_locked_clock);
	else
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "-1");

	if (ret < PAGE_SIZE - 1) {
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "\n");
	} else {
		buf[PAGE_SIZE - 2] = '\n';
		buf[PAGE_SIZE - 1] = '\0';
		ret = PAGE_SIZE - 1;
	}

	return ret;
}
CREATE_SYSFS_DEVICE_READ_FUNCTION(show_max_lock_dvfs)

GPEX_STATIC ssize_t show_max_lock_dvfs_kobj(char *buf)
{
	ssize_t ret = 0;
	unsigned long flags;
	int locked_clock = -1;

	gpex_dvfs_spin_lock(&flags);
	locked_clock = clk_info->max_lock;
	gpex_dvfs_spin_unlock(&flags);

	if (locked_clock > 0)
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "%d", locked_clock);
	else
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "%d", clk_info->gpu_max_clock);

	if (ret < PAGE_SIZE - 1) {
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "\n");
	} else {
		buf[PAGE_SIZE - 2] = '\n';
		buf[PAGE_SIZE - 1] = '\0';
		ret = PAGE_SIZE - 1;
	}

	return ret;
}
CREATE_SYSFS_KOBJECT_READ_FUNCTION(show_max_lock_dvfs_kobj)

GPEX_STATIC ssize_t show_min_lock_dvfs(char *buf)
{
	ssize_t ret = 0;
	unsigned long flags;
	int locked_clock = -1;
	int user_locked_clock = -1;

	gpex_dvfs_spin_lock(&flags);
	locked_clock = clk_info->min_lock;
	user_locked_clock = clk_info->user_min_lock_input;
	gpex_dvfs_spin_unlock(&flags);

	if (locked_clock > 0)
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "%d / %d", locked_clock,
				user_locked_clock);
	else
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "-1");

	if (ret < PAGE_SIZE - 1) {
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "\n");
	} else {
		buf[PAGE_SIZE - 2] = '\n';
		buf[PAGE_SIZE - 1] = '\0';
		ret = PAGE_SIZE - 1;
	}

	return ret;
}
CREATE_SYSFS_DEVICE_READ_FUNCTION(show_min_lock_dvfs)

GPEX_STATIC ssize_t show_min_lock_dvfs_kobj(char *buf)
{
	ssize_t ret = 0;
	unsigned long flags;
	int locked_clock = -1;

	gpex_dvfs_spin_lock(&flags);
	locked_clock = clk_info->min_lock;
	gpex_dvfs_spin_unlock(&flags);

	if (locked_clock > 0)
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "%d", locked_clock);
	else
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "%d", clk_info->gpu_min_clock);

	if (ret < PAGE_SIZE - 1) {
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "\n");
	} else {
		buf[PAGE_SIZE - 2] = '\n';
		buf[PAGE_SIZE - 1] = '\0';
		ret = PAGE_SIZE - 1;
	}

	return ret;
}
CREATE_SYSFS_KOBJECT_READ_FUNCTION(show_min_lock_dvfs_kobj)

GPEX_STATIC ssize_t set_mm_min_lock_dvfs(const char *buf, size_t count)
{
	int ret, clock = 0;

	if (sysfs_streq("0", buf)) {
		gpex_clock_lock_clock(GPU_CLOCK_MIN_UNLOCK, MM_LOCK, 0);
	} else {
		ret = kstrtoint(buf, 0, &clock);
		if (ret) {
			GPU_LOG(MALI_EXYNOS_WARNING, "%s: invalid value\n", __func__);
			return -ENOENT;
		}

		clock = gpex_get_valid_gpu_clock(clock, true);

		ret = gpex_clock_get_table_idx(clock);
		if ((ret < gpex_clock_get_table_idx(gpex_clock_get_max_clock())) ||
		    (ret > gpex_clock_get_table_idx(gpex_clock_get_min_clock()))) {
			GPU_LOG(MALI_EXYNOS_WARNING, "%s: invalid clock value (%d)\n", __func__,
				clock);
			return -ENOENT;
		}

		if (clock > gpex_clock_get_max_clock_limit())
			clock = gpex_clock_get_max_clock_limit();

		gpex_clboost_set_state(CLBOOST_DISABLE);

		if (clock == gpex_clock_get_min_clock())
			gpex_clock_lock_clock(GPU_CLOCK_MIN_UNLOCK, MM_LOCK, 0);
		else
			gpex_clock_lock_clock(GPU_CLOCK_MIN_LOCK, MM_LOCK, clock);
	}

	return count;
}
CREATE_SYSFS_KOBJECT_WRITE_FUNCTION(set_mm_min_lock_dvfs)

GPEX_STATIC ssize_t show_mm_min_lock_dvfs(char *buf)
{
	ssize_t ret = 0;
	unsigned long flags;
	int locked_clock = -1;

	gpex_dvfs_spin_lock(&flags);
	locked_clock = clk_info->min_lock;
	gpex_dvfs_spin_unlock(&flags);

	if (locked_clock > 0)
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "%d", locked_clock);
	else
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "%d", gpex_clock_get_min_clock());

	if (ret < PAGE_SIZE - 1) {
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "\n");
	} else {
		buf[PAGE_SIZE - 2] = '\n';
		buf[PAGE_SIZE - 1] = '\0';
		ret = PAGE_SIZE - 1;
	}

	return ret;
}
CREATE_SYSFS_KOBJECT_READ_FUNCTION(show_mm_min_lock_dvfs)

GPEX_STATIC ssize_t show_max_lock_status(char *buf)
{
	ssize_t ret = 0;
	unsigned long flags;
	int i;
	int max_lock_status[NUMBER_LOCK];

	gpex_dvfs_spin_lock(&flags);
	for (i = 0; i < NUMBER_LOCK; i++)
		max_lock_status[i] = clk_info->user_max_lock[i];
	gpex_dvfs_spin_unlock(&flags);

	for (i = 0; i < NUMBER_LOCK; i++)
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "[%d:%d]", i, max_lock_status[i]);

	if (ret < PAGE_SIZE - 1) {
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "\n");
	} else {
		buf[PAGE_SIZE - 2] = '\n';
		buf[PAGE_SIZE - 1] = '\0';
		ret = PAGE_SIZE - 1;
	}

	return ret;
}
CREATE_SYSFS_DEVICE_READ_FUNCTION(show_max_lock_status)

GPEX_STATIC ssize_t show_min_lock_status(char *buf)
{
	ssize_t ret = 0;
	unsigned long flags;
	int i;
	int min_lock_status[NUMBER_LOCK];

	gpex_dvfs_spin_lock(&flags);
	for (i = 0; i < NUMBER_LOCK; i++)
		min_lock_status[i] = clk_info->user_min_lock[i];
	gpex_dvfs_spin_unlock(&flags);

	for (i = 0; i < NUMBER_LOCK; i++)
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "[%d:%d]", i, min_lock_status[i]);

	if (ret < PAGE_SIZE - 1) {
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "\n");
	} else {
		buf[PAGE_SIZE - 2] = '\n';
		buf[PAGE_SIZE - 1] = '\0';
		ret = PAGE_SIZE - 1;
	}

	return ret;
}
CREATE_SYSFS_DEVICE_READ_FUNCTION(show_min_lock_status)

GPEX_STATIC ssize_t show_gpu_freq_table(char *buf)
{
	ssize_t ret = 0;
	int i = 0;

	/* TODO: find a better way to make sure this table is initialized...
	 * May be freq table should be initializesd even if DVFS is disabled?
	 * */
	if (!clk_info->table)
		return ret;

	for (i = gpex_clock_get_table_idx(clk_info->gpu_min_clock);
	     i >= gpex_clock_get_table_idx(clk_info->gpu_max_clock); i--) {
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "%d ", clk_info->table[i].clock);
	}

	if (ret < PAGE_SIZE - 1) {
		ret += snprintf(buf + ret, PAGE_SIZE - ret, "\n");
	} else {
		buf[PAGE_SIZE - 2] = '\n';
		buf[PAGE_SIZE - 1] = '\0';
		ret = PAGE_SIZE - 1;
	}

	return ret;
}
CREATE_SYSFS_KOBJECT_READ_FUNCTION(show_gpu_freq_table)

GPEX_STATIC ssize_t show_volt(char *buf)
{
	ssize_t len = 0;
	int volt = 0;

	gpex_pm_lock();
	if (g3d_regulator)
		volt = regulator_get_voltage(g3d_regulator);
	else if (gpex_pm_get_status(false))
		volt = clk_info->table[gpex_clock_get_table_idx(gpex_clock_get_clock_slow())].voltage;
	gpex_pm_unlock();

	if (volt < 0)
		volt = 0;

	len += snprintf(buf + len, PAGE_SIZE - len, "%d", volt);

	return gpex_utils_sysfs_endbuf(buf, len);
}
CREATE_SYSFS_DEVICE_READ_FUNCTION(show_volt)
CREATE_SYSFS_KOBJECT_READ_FUNCTION(show_volt)

int gpex_clock_sysfs_init(struct _clock_info *_clk_info)
{
	clk_info = _clk_info;
	g3d_regulator = regulator_get(NULL, "vdd_g3d");

	if (IS_ERR(g3d_regulator))
		g3d_regulator = NULL;

	GPEX_UTILS_SYSFS_DEVICE_FILE_ADD(clock, show_clock, set_clock);
	GPEX_UTILS_SYSFS_DEVICE_FILE_ADD_RO(asv_table, show_asv_table);
	GPEX_UTILS_SYSFS_DEVICE_FILE_ADD(time_in_state, show_time_in_state, reset_time_in_state);
	GPEX_UTILS_SYSFS_DEVICE_FILE_ADD_RO(dvfs_max_lock, show_max_lock_dvfs);
	GPEX_UTILS_SYSFS_DEVICE_FILE_ADD_RO(dvfs_min_lock, show_min_lock_dvfs);
	GPEX_UTILS_SYSFS_DEVICE_FILE_ADD_RO(dvfs_max_lock_status, show_max_lock_status);
	GPEX_UTILS_SYSFS_DEVICE_FILE_ADD_RO(dvfs_min_lock_status, show_min_lock_status);
	GPEX_UTILS_SYSFS_DEVICE_FILE_ADD_RO(volt, show_volt);

	GPEX_UTILS_SYSFS_KOBJECT_FILE_ADD_RO(gpu_max_clock, show_max_lock_dvfs_kobj);
	GPEX_UTILS_SYSFS_KOBJECT_FILE_ADD_RO(gpu_min_clock, show_min_lock_dvfs_kobj);
	GPEX_UTILS_SYSFS_KOBJECT_FILE_ADD(gpu_mm_min_clock, show_mm_min_lock_dvfs,
					  set_mm_min_lock_dvfs);
	GPEX_UTILS_SYSFS_KOBJECT_FILE_ADD_RO(gpu_clock, show_clock);
	GPEX_UTILS_SYSFS_KOBJECT_FILE_ADD_RO(gpu_freq_table, show_gpu_freq_table);
	GPEX_UTILS_SYSFS_KOBJECT_FILE_ADD(gpu_unlock, get_gpu_unlock, set_gpu_unlock);
	GPEX_UTILS_SYSFS_KOBJECT_FILE_ADD_RO(gpu_volt, show_volt);

	return 0;
}
