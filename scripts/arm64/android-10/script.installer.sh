#!/sbin/sh
#
##############################################################
# File name       : installer.sh
#
# Description     : Main installation script for BiTGApps
#
# Build Date      : Friday March 15 11:36:43 IST 2019
#
# Updated on      : Monday November 25 16:58:59 IST 2019
#
# GitHub          : TheHitMan7 <krtik.vrma@gmail.com>
#
# BiTGApps Author : TheHitMan @ xda-developers
#
# Copyright       : Copyright (C) 2019 TheHitMan7 (Kartik Verma)
#
# License         : SPDX-License-Identifier: GPL-3.0-or-later
#
# The BiTGApps scripts are free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# These scripts are distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
##############################################################

# Import OUTFD function
ui_print() {
  echo -n -e "ui_print $1\n" >> /proc/self/fd/$OUTFD
  echo -n -e "ui_print\n" >> /proc/self/fd/$OUTFD
}

# Unset predefined environmental variable
recovery_actions() {
  OLD_LD_LIB=$LD_LIBRARY_PATH
  OLD_LD_PRE=$LD_PRELOAD
  OLD_LD_CFG=$LD_CONFIG_FILE
  unset LD_LIBRARY_PATH
  unset LD_PRELOAD
  unset LD_CONFIG_FILE
}

# Restore predefined environmental variable
recovery_cleanup() {
  [ -z $OLD_LD_LIB ] || export LD_LIBRARY_PATH=$OLD_LD_LIB
  [ -z $OLD_LD_PRE ] || export LD_PRELOAD=$OLD_LD_PRE
  [ -z $OLD_LD_CFG ] || export LD_CONFIG_FILE=$OLD_LD_CFG
}

# selinux status
selinux_variable() {
  getenforce >> /cache/bitgapps/selinux.log;
}

if [ -n "$(cat /etc/fstab | grep /system_root)" ];
then
  SYSTEM=/system_root/system
else
  SYSTEM=/system
fi;

# Only support vendor that is outside the system or symlinked in root
vendor_fallback() {
  if [ -f /vendor/build.prop ];
    then
    device_vendorpartition=true
    VENDOR=/vendor
  else
    device_vendorpartition=false
  fi;
}

PROPFILES="$SYSTEM/build.prop /sdcard/config.txt";

get_file_prop() {
  grep -m1 "^$2=" "$1" | cut -d= -f2
}

get_prop() {
  #check known .prop files using get_file_prop
  for f in $PROPFILES; do
    if [ -e "$f" ]; then
      prop="$(get_file_prop "$f" "$1")"
      if [ -n "$prop" ]; then
        break #if an entry has been found, break out of the loop
      fi;
    fi;
  done
  #if prop is still empty; try to use recovery's built-in getprop method; otherwise output current result
  if [ -z "$prop" ]; then
    getprop "$1" | cut -c1-
  else
    printf "$prop"
  fi;
}

# insert_line <file> <if search string> <before|after> <line match string> <inserted line>
insert_line() {
  local offset line;
  if ! grep -q "$2" $1; then
    case $3 in
      before) offset=0;;
      after) offset=1;;
    esac;
    line=$((`grep -n "$4" $1 | head -n1 | cut -d: -f1` + offset));
    if [ -f $1 -a "$line" ] && [ "$(wc -l $1 | cut -d\  -f1)" -lt "$line" ]; then
      echo "$5" >> $1;
    else
      sed -i "${line}s;^;${5}\n;" $1;
    fi;
  fi;
}

# replace_line <file> <line replace string> <replacement line>
replace_line() {
  if grep -q "$2" $1; then
    local line=$(grep -n "$2" $1 | head -n1 | cut -d: -f1);
    sed -i "${line}s;.*;${3};" $1;
  fi;
}

# remove_line <file> <line match string>
remove_line() {
  if grep -q "$2" $1; then
    local line=$(grep -n "$2" $1 | head -n1 | cut -d: -f1);
    sed -i "${line}d" $1;
  fi;
}

grep_cmdline() {
  local REGEX="s/^$1=//p"
  cat /proc/cmdline | tr '[:space:]' '\n' | sed -n "$REGEX" 2>/dev/null;
}

# Set config file property
supported_config="$(get_prop "ro.config.setupwizard")";
supported_target="true";

# Set privileged app Whitelist property
android_flag="$(get_prop "ro.control_privapp_permissions")";
supported_flag_enforce="enforce";
supported_flag_disable="disable";
supported_flag_log="log";
PROPFLAG="ro.control_privapp_permissions";

# Set partition and boot slot property
system_as_root=`getprop ro.build.system_root_image`
active_slot=`getprop ro.boot.slot_suffix`

# Set default packages
ZIP="
  zip/core/priv_app_CarrierSetup.tar.gz
  zip/core/priv_app_ConfigUpdater.tar.gz
  zip/core/priv_app_GmsCoreSetupPrebuilt.tar.gz
  zip/core/priv_app_GoogleExtServices.tar.gz
  zip/core/priv_app_GoogleServicesFramework.tar.gz
  zip/core/priv_app_Phonesky.tar.gz
  zip/core/priv_app_PrebuiltGmsCore.tar.gz
  zip/sys/sys_app_GoogleCalendarSyncAdapter.tar.gz
  zip/sys/sys_app_GoogleContactsSyncAdapter.tar.gz
  zip/sys/sys_app_GoogleExtShared.tar.gz
  zip/sys/sys_app_SoundPickerPrebuilt.tar.gz
  zip/sys_addon.tar.gz
  zip/sys_Config_Permission.tar.gz
  zip/sys_Default_Permission.tar.gz
  zip/sys_Framework.tar.gz
  zip/sys_Lib.tar.gz
  zip/sys_Lib64.tar.gz
  zip/sys_Permissions.tar.gz
  zip/sys_Pref_Permission.tar.gz"

# Set config dependent packages
ZIP_INITIAL="
  zip/core/priv_app_GoogleBackupTransport.tar.gz
  zip/core/priv_app_GoogleRestore.tar.gz
  zip/core/priv_app_SetupWizard.tar.gz"

# Unpack system files
unpack_zip() {
  for f in $ZIP; do
    unzip -o "$ZIPFILE" "$f" -d "$TMP";
  done
}

# Unpack system files using config property
unpack_zip_initial() {
  for f in $ZIP_INITIAL; do
    unzip -o "$ZIPFILE" "$f" -d "$TMP";
  done
}

# Check whether config file present in device or not
get_config() {
  if [ -f /sdcard/config.txt ]; then
    build_config=true
  else
    build_config=false
  fi;
}

# Unpack config dependent packages
config_install() {
  if [ "$supported_config" = "$supported_target" ]; then
    unpack_zip_initial;
    # Remove SetupWizard components
    pre_installed_initial() {
      rm -rf $SYSTEM/product/app/ManagedProvisioning
      rm -rf $SYSTEM/product/app/Provision
      rm -rf $SYSTEM/product/priv-app/ManagedProvisioning
      rm -rf $SYSTEM/product/priv-app/Provision
      rm -rf $SYSTEM_APP/ManagedProvisioning
      rm -rf $SYSTEM_APP/Provision
      rm -rf $SYSTEM_PRIV_APP/GoogleBackupTransport
      rm -rf $SYSTEM_PRIV_APP/GoogleRestore
      rm -rf $SYSTEM_PRIV_APP/ManagedProvisioning
      rm -rf $SYSTEM_PRIV_APP/Provision
      rm -rf $SYSTEM_PRIV_APP/SetupWizard
    }
    # Unpack SetupWizard components
    extract_app_initial() {
      tar tvf $ZIP_FILE/core/priv_app_GoogleBackupTransport.tar.gz >> $config_log
      tar tvf $ZIP_FILE/core/priv_app_GoogleRestore.tar.gz >> $config_log
      tar tvf $ZIP_FILE/core/priv_app_SetupWizard.tar.gz >> $config_log
      tar -xz -f $ZIP_FILE/core/priv_app_GoogleBackupTransport.tar.gz -C $TMP_PRIV_SETUP
      tar -xz -f $ZIP_FILE/core/priv_app_GoogleRestore.tar.gz -C $TMP_PRIV_SETUP
      tar -xz -f $ZIP_FILE/core/priv_app_SetupWizard.tar.gz -C $TMP_PRIV_SETUP
      send_sparse_12;
    }
    # Selinux context for SetupWizard components
    selinux_context_sp2_initial() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleBackupTransport";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleRestore";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/SetupWizard";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleBackupTransport/GoogleBackupTransport.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleRestore/GoogleRestore.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/SetupWizard/SetupWizard.apk";
    }
    # Initiate SetupWizard components installation
    on_config_install() {
      pre_installed_initial;
      extract_app_initial;
      selinux_context_sp2_initial;
    }
    on_config_install;
  else
    build_configproperty=false
  fi;
}

# Detect A/B partition layout https://source.android.com/devices/tech/ota/ab_updates
# and system-as-root https://source.android.com/devices/bootloader/system-as-root
set_mount() {
  if [ "$system_as_root" == "true" ]; then
    if [ ! -z "$active_slot" ]; then
      device_abpartition=true
      SYSTEM_MOUNT=/system
    else
      device_abpartition=false
      SYSTEM_MOUNT=/system_root
    fi;
  else
    device_abpartition=false
    SYSTEM_MOUNT=/system
  fi;
}

androidboot="$TMP/boot_slot.log"
# Check A/B slot
boot_slot() {
  SLOT=`grep_cmdline androidboot.slot_suffix`
  if [ -z $SLOT ]; then
    SLOT=`grep_cmdline androidboot.slot`
    [ -z $SLOT ] || SLOT=_${SLOT}
  fi
  [ -z $SLOT ] || echo "Current boot slot: $SLOT" >> $androidboot
}

# Mount partition
mount_part() {
  mounts=""
  for p in "/cache" "/data" "$SYSTEM_MOUNT"; do
    if [ -d "$p" ] && grep -q "$p" "/etc/fstab" && ! mountpoint -q "$p"; then
      mounts="$mounts $p"
    fi;
  done
  for m in $mounts; do
    mount -o rw "$m"
  done
  # Add vendor backward comaptibility
  for i in "/vendor"; do
    if [ -d "$i" ] && grep -q "$p" "/etc/fstab" && ! mountpoint -q "$p"; then
      mounts="$mounts $i"
    fi;
  done
  for v in $mounts; do
    mount -o rw "$v"
  done
}
vendor_fallback;

# Remount $SYSTEM_MOUNT, if previous mount failed
remount_part() {
  mount -o remount,rw $SYSTEM_MOUNT
}

# Remount /system to /system_root if we have system-as-root
on_SAR() {
  if [ -f /system/init.rc ]; then
    system_as_root=true
    [ -L /system_root ] && rm -f /system_root
    mkdir /system_root 2>/dev/null;
    mount --move /system /system_root
    mount -o bind /system_root/system /system
  else
    grep ' / ' /proc/mounts | grep -qv 'rootfs' || grep -q ' /system_root ' /proc/mounts \
    && system_as_root=true || system_as_root=false
  fi;
}

cleanup() {
  rm -rf /tmp/unzip
  rm -rf /tmp/zip
}

clean_logs() {
  rm -rf /cache/bitgapps
}

# Generate a separate log file on abort
on_install_failed() {
  rm -rf /sdcard/bitgapps_debug_failed_logs.tar.gz
  rm -rf /cache/bitgapps
  mkdir /cache/bitgapps
  cd /cache/bitgapps
  cp -f $TMP/recovery.log /cache/bitgapps/recovery.log
  selinux_variable;
  cp -f $TMP/boot_slot.log /cache/bitgapps/boot_slot.log
  pre_install;
  cp -f $SYSTEM/build.prop /cache/bitgapps/build.prop
  cp -f $VENDOR/build.prop /cache/bitgapps/build2.prop
  cp -f /sdcard/config.txt /cache/bitgapps/config.txt
  tar -cz -f "$TMP/bitgapps_debug_failed_logs.tar.gz" *
  cp -f $TMP/bitgapps_debug_failed_logs.tar.gz /sdcard/bitgapps_debug_failed_logs.tar.gz
  # Checkout log path
  cd /
}

# log
on_install_complete() {
  rm -rf /sdcard/bitgapps_debug_complete_logs.tar.gz
  cd /cache/bitgapps
  cp -f $TMP/recovery.log /cache/bitgapps/recovery.log
  cp -f $TMP/boot_slot.log /cache/bitgapps/boot_slot.log
  cp -f $SYSTEM/build.prop /cache/bitgapps/build.prop
  cp -f $VENDOR/build.prop /cache/bitgapps/build2.prop
  cp -f /sdcard/config.txt /cache/bitgapps/config.txt
  tar -cz -f "$TMP/bitgapps_debug_complete_logs.tar.gz" *
  cp -f $TMP/bitgapps_debug_complete_logs.tar.gz /sdcard/bitgapps_debug_complete_logs.tar.gz
  # Checkout log path
  cd /
}

unmount_all() {
  ui_print " ";
  if [ "$device_abpartition" = "true" ]; then
    mount -o ro $SYSTEM_MOUNT
    mount -o ro $VENDOR
  else
    umount $SYSTEM_MOUNT
    umount $VENDOR
  fi
}

on_install() {
  selinux_variable;
  on_install_complete;
  clean_logs;
  cleanup;
  recovery_cleanup;
  unmount_all;
}

on_abort() {
  ui_print "$*";
  on_install_failed;
  clean_logs;
  cleanup;
  recovery_cleanup;
  unmount_all;
  exit 1;
}

# Set package defaults
TMP="/tmp"
ZIP_FILE="/tmp/zip"
# Create temporary unzip directory
mkdir /tmp/unzip
chmod 0755 /tmp/unzip
UNZIP_DIR="/tmp/unzip"
TMP_ADDON="$UNZIP_DIR/tmp_addon"
TMP_SYS="$UNZIP_DIR/tmp_sys"
TMP_SYS_ROOT="$UNZIP_DIR/tmp_sys_root"
TMP_PRIV="$UNZIP_DIR/tmp_priv"
TMP_PRIV_ROOT="$UNZIP_DIR/tmp_priv_root"
TMP_PRIV_SETUP="$UNZIP_DIR/tmp_priv_setup"
TMP_LIB="$UNZIP_DIR/tmp_lib"
TMP_LIB64="$UNZIP_DIR/tmp_lib64"
TMP_FRAMEWORK="$UNZIP_DIR/tmp_framework"
TMP_CONFIG="$UNZIP_DIR/tmp_config"
TMP_DEFAULT_PERM="$UNZIP_DIR/tmp_default"
TMP_G_PERM="$UNZIP_DIR/tmp_perm"
TMP_G_PREF="$UNZIP_DIR/tmp_pref"
TMP_PERM_ROOT="$UNZIP_DIR/tmp_perm_root"
SYSTEM_APP="$SYSTEM/app"
SYSTEM_PRIV_APP="$SYSTEM/priv-app"
SYSTEM_LIB="$SYSTEM/lib"
SYSTEM_LIB64="$SYSTEM/lib64"
SYSTEM_ADDOND="$SYSTEM/addon.d"
SYSTEM_FRAMEWORK="$SYSTEM/framework"
SYSTEM_ETC_CONFIG="$SYSTEM/etc/sysconfig"
SYSTEM_ETC_DEFAULT="$SYSTEM/etc"
SYSTEM_ETC_PERM="$SYSTEM/etc/permissions"
SYSTEM_ETC_PREF="$SYSTEM/etc"
# Set logging
LOG="/cache/bitgapps/installation.log"
config_log="/cache/bitgapps/config-installation.log"
whitelist="/cache/bitgapps/enforce.log";
EXTRA_LOG="/cache/bitgapps/extra.log"
SQLITE_LOG="/cache/bitgapps/sqlite.log"
SQLITE_TOOL="/tmp/sqlite3"
ZIPALIGN_LOG="/cache/bitgapps/zipalign.log"
ZIPALIGN_TOOL="/tmp/zipalign"
FILES="/cache/bitgapps/files.log"

# Create log dir
logd() {
  mkdir /cache/bitgapps
  chmod 0755 /cache/bitgapps
}

# Creating installation components
service_manager() {
  echo "-----------------------------------" >> $LOG
  echo " --- BiTGApps Installation Log --- " >> $LOG
  echo "             Start at              " >> $LOG
  echo "        $( date +"%m-%d-%Y %H:%M:%S" )" >> $LOG
  echo "-----------------------------------" >> $LOG
  echo " " >> $LOG
  echo "-----------------------------------" >> $LOG
  if [ -d /cache/bitgapps ]; then
    echo "- Log directory found in :" /cache >> $LOG
  else
    echo "- Log directory not found in :" /cache >> $LOG
  fi;
  echo "-----------------------------------" >> $LOG
  if [ -d "$UNZIP_DIR" ]; then
    echo "- Unzip directory found in :" $TMP >> $LOG
    echo "- Creating components in :" $TMP >> $LOG
    mkdir $UNZIP_DIR/tmp_addon
    mkdir $UNZIP_DIR/tmp_sys
    mkdir $UNZIP_DIR/tmp_sys_root
    mkdir $UNZIP_DIR/tmp_priv
    mkdir $UNZIP_DIR/tmp_priv_root
    mkdir $UNZIP_DIR/tmp_priv_setup
    mkdir $UNZIP_DIR/tmp_lib
    mkdir $UNZIP_DIR/tmp_lib64
    mkdir $UNZIP_DIR/tmp_framework
    mkdir $UNZIP_DIR/tmp_config
    mkdir $UNZIP_DIR/tmp_default
    mkdir $UNZIP_DIR/tmp_perm
    mkdir $UNZIP_DIR/tmp_pref
    mkdir $UNZIP_DIR/tmp_perm_root
    chmod 0755 $UNZIP_DIR
    chmod 0755 $UNZIP_DIR/tmp_addon
    chmod 0755 $UNZIP_DIR/tmp_sys
    chmod 0755 $UNZIP_DIR/tmp_sys_root
    chmod 0755 $UNZIP_DIR/tmp_priv
    chmod 0755 $UNZIP_DIR/tmp_priv_root
    chmod 0755 $UNZIP_DIR/tmp_priv_setup
    chmod 0755 $UNZIP_DIR/tmp_lib
    chmod 0755 $UNZIP_DIR/tmp_lib64
    chmod 0755 $UNZIP_DIR/tmp_framework
    chmod 0755 $UNZIP_DIR/tmp_config
    chmod 0755 $UNZIP_DIR/tmp_default
    chmod 0755 $UNZIP_DIR/tmp_perm
    chmod 0755 $UNZIP_DIR/tmp_pref
    chmod 0755 $UNZIP_DIR/tmp_perm_root
  else
    echo "- Unzip directory not found in :" $TMP >> $LOG
  fi;
}

# Removing pre-installed system files
pre_installed() {
  rm -rf $SYSTEM_APP/GoogleCalendarSyncAdapter
  rm -rf $SYSTEM_APP/GoogleContactsSyncAdapter
  rm -rf $SYSTEM_APP/ExtShared
  rm -rf $SYSTEM_APP/GoogleExtShared
  rm -rf $SYSTEM_APP/MarkupGoogle
  rm -rf $SYSTEM_APP/SoundPickerPrebuilt
  rm -rf $SYSTEM_PRIV_APP/AndroidPlatformServices
  rm -rf $SYSTEM_PRIV_APP/CarrierSetup
  rm -rf $SYSTEM_PRIV_APP/ConfigUpdater
  rm -rf $SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt
  rm -rf $SYSTEM_PRIV_APP/ExtServices
  rm -rf $SYSTEM_PRIV_APP/GoogleExtServices
  rm -rf $SYSTEM_PRIV_APP/GoogleServicesFramework
  rm -rf $SYSTEM_PRIV_APP/Phonesky
  rm -rf $SYSTEM_PRIV_APP/PrebuiltGmsCore
  rm -rf $SYSTEM_FRAMEWORK/com.google.android.dialer.support.jar
  rm -rf $SYSTEM_FRAMEWORK/com.google.android.maps.jar
  rm -rf $SYSTEM_FRAMEWORK/com.google.android.media.effects.jar
  rm -rf $SYSTEM_LIB/libsketchology_native.so
  rm -rf $SYSTEM_LIB64/libjni_latinimegoogle.so
  rm -rf $SYSTEM_LIB64/libsketchology_native.so
  rm -rf $SYSTEM_ETC_CONFIG/dialer_experience.xml
  rm -rf $SYSTEM_ETC_CONFIG/google.xml
  rm -rf $SYSTEM_ETC_CONFIG/google_build.xml
  rm -rf $SYSTEM_ETC_CONFIG/google_exclusives_enable.xml
  rm -rf $SYSTEM_ETC_CONFIG/google-hiddenapi-package-whitelist.xml
  rm -rf $SYSTEM_ETC_DEFAULT/default-permissions
  rm -rf $SYSTEM_ETC_PERM/com.google.android.dialer.support.xml
  rm -rf $SYSTEM_ETC_PERM/com.google.android.maps.xml
  rm -rf $SYSTEM_ETC_PERM/com.google.android.media.effects.xml
  rm -rf $SYSTEM_ETC_PERM/privapp-permissions-google.xml
  rm -rf $SYSTEM_ETC_PERM/split-permissions-google.xml
  rm -rf $SYSTEM_ETC_PREF/preferred-apps
  rm -rf $SYSTEM_ADDOND/90bit_gapps.sh
  rm -rf $SYSTEM/etc/g.prop
}

# Unpack system files
extract_app() {
  echo "-----------------------------------" >> $LOG
  echo "- Unpack SYS-APP Files" >> $LOG
  tar tvf $ZIP_FILE/sys/sys_app_GoogleCalendarSyncAdapter.tar.gz >> $LOG
  tar tvf $ZIP_FILE/sys/sys_app_GoogleContactsSyncAdapter.tar.gz >> $LOG
  tar tvf $ZIP_FILE/sys/sys_app_GoogleExtShared.tar.gz >> $LOG
  tar tvf $ZIP_FILE/sys/sys_app_SoundPickerPrebuilt.tar.gz >> $LOG
  tar -xz -f $ZIP_FILE/sys/sys_app_GoogleCalendarSyncAdapter.tar.gz -C $TMP_SYS
  tar -xz -f $ZIP_FILE/sys/sys_app_GoogleContactsSyncAdapter.tar.gz -C $TMP_SYS
  tar -xz -f $ZIP_FILE/sys/sys_app_GoogleExtShared.tar.gz -C $TMP_SYS
  tar -xz -f $ZIP_FILE/sys/sys_app_SoundPickerPrebuilt.tar.gz -C $TMP_SYS
  echo "- Done" >> $LOG
  echo "-----------------------------------" >> $LOG
  echo "- Unpack PRIV-APP Files" >> $LOG
  tar tvf $ZIP_FILE/core/priv_app_CarrierSetup.tar.gz >> $LOG
  tar tvf $ZIP_FILE/core/priv_app_ConfigUpdater.tar.gz >> $LOG
  tar tvf $ZIP_FILE/core/priv_app_GmsCoreSetupPrebuilt.tar.gz >> $LOG
  tar tvf $ZIP_FILE/core/priv_app_GoogleExtServices.tar.gz >> $LOG
  tar tvf $ZIP_FILE/core/priv_app_GoogleServicesFramework.tar.gz >> $LOG
  tar tvf $ZIP_FILE/core/priv_app_Phonesky.tar.gz >> $LOG
  tar tvf $ZIP_FILE/core/priv_app_PrebuiltGmsCore.tar.gz >> $LOG
  tar -xz -f $ZIP_FILE/core/priv_app_CarrierSetup.tar.gz -C $TMP_PRIV
  tar -xz -f $ZIP_FILE/core/priv_app_ConfigUpdater.tar.gz -C $TMP_PRIV
  tar -xz -f $ZIP_FILE/core/priv_app_GmsCoreSetupPrebuilt.tar.gz -C $TMP_PRIV
  tar -xz -f $ZIP_FILE/core/priv_app_GoogleExtServices.tar.gz -C $TMP_PRIV
  tar -xz -f $ZIP_FILE/core/priv_app_GoogleServicesFramework.tar.gz -C $TMP_PRIV
  tar -xz -f $ZIP_FILE/core/priv_app_Phonesky.tar.gz -C $TMP_PRIV
  tar -xz -f $ZIP_FILE/core/priv_app_PrebuiltGmsCore.tar.gz -C $TMP_PRIV
  echo "- Done" >> $LOG
  echo "-----------------------------------" >> $LOG
  echo "- Unpack Framework Files" >> $LOG
  tar tvf $ZIP_FILE/sys_Framework.tar.gz >> $LOG
  tar -xz -f $ZIP_FILE/sys_Framework.tar.gz -C $TMP_FRAMEWORK
  echo "- Done" >> $LOG
  echo "-----------------------------------" >> $LOG
  echo "- Unpack System Lib" >> $LOG
  tar tvf $ZIP_FILE/sys_Lib.tar.gz >> $LOG
  tar -xz -f $ZIP_FILE/sys_Lib.tar.gz -C $TMP_LIB
  echo "- Done" >> $LOG
  echo "-----------------------------------" >> $LOG
  echo "- Unpack System Lib64" >> $LOG
  tar tvf $ZIP_FILE/sys_Lib64.tar.gz >> $LOG
  tar -xz -f $ZIP_FILE/sys_Lib64.tar.gz -C $TMP_LIB64
  echo "- Done" >> $LOG
  echo "-----------------------------------" >> $LOG
  echo "- Unpack System Files" >> $LOG
  tar tvf $ZIP_FILE/sys_Config_Permission.tar.gz >> $LOG
  tar tvf $ZIP_FILE/sys_Default_Permission.tar.gz >> $LOG
  tar tvf $ZIP_FILE/sys_Permissions.tar.gz >> $LOG
  tar tvf $ZIP_FILE/sys_Pref_Permission.tar.gz >> $LOG
  tar -xz -f $ZIP_FILE/sys_Config_Permission.tar.gz -C $TMP_CONFIG
  tar -xz -f $ZIP_FILE/sys_Default_Permission.tar.gz -C $TMP_DEFAULT_PERM
  tar -xz -f $ZIP_FILE/sys_Permissions.tar.gz -C $TMP_G_PERM
  tar -xz -f $ZIP_FILE/sys_Pref_Permission.tar.gz -C $TMP_G_PREF
  echo "- Done" >> $LOG
  echo "-----------------------------------" >> $LOG
  echo "- Unpack Boot Script" >> $LOG
  tar tvf $ZIP_FILE/sys_addon.tar.gz >> $LOG
  tar -xz -f $ZIP_FILE/sys_addon.tar.gz -C $TMP_ADDON
  echo "- Done" >> $LOG
  echo "-----------------------------------" >> $LOG
  echo "- Installation Complete" >> $LOG
  echo "-----------------------------------" >> $LOG
  echo "Finish at $( date +"%m-%d-%Y %H:%M:%S" )" >> $LOG
  echo "-----------------------------------" >> $LOG
}

# Install packages in sparse format
send_sparse_1() {
  file_list="$(find "$TMP_SYS/" -mindepth 1 -type f | cut -d/ -f5-)"
  dir_list="$(find "$TMP_SYS/" -mindepth 1 -type d | cut -d/ -f5-)"
  for file in $file_list; do
      install -D "$TMP_SYS/${file}" "$SYSTEM_APP/${file}"
      chmod 0644 "$SYSTEM_APP/${file}";
  done
  for dir in $dir_list; do
      chmod 0755 "$SYSTEM_APP/${dir}";
  done
}

send_sparse_2() {
  file_list="$(find "$TMP_PRIV/" -mindepth 1 -type f | cut -d/ -f5-)"
  dir_list="$(find "$TMP_PRIV/" -mindepth 1 -type d | cut -d/ -f5-)"
  for file in $file_list; do
      install -D "$TMP_PRIV/${file}" "$SYSTEM_PRIV_APP/${file}"
      chmod 0644 "$SYSTEM_PRIV_APP/${file}";
  done
  for dir in $dir_list; do
      chmod 0755 "$SYSTEM_PRIV_APP/${dir}";
  done
}

send_sparse_3() {
  file_list="$(find "$TMP_FRAMEWORK/" -mindepth 1 -type f | cut -d/ -f5-)"
  dir_list="$(find "$TMP_FRAMEWORK/" -mindepth 1 -type d | cut -d/ -f5-)"
  for file in $file_list; do
      install -D "$TMP_FRAMEWORK/${file}" "$SYSTEM_FRAMEWORK/${file}"
      chmod 0644 "$SYSTEM_FRAMEWORK/${file}";
  done
  for dir in $dir_list; do
    chmod 0755 "$SYSTEM_FRAMEWORK/${dir}";
  done
}

send_sparse_4() {
  file_list="$(find "$TMP_LIB/" -mindepth 1 -type f | cut -d/ -f5-)"
  dir_list="$(find "$TMP_LIB/" -mindepth 1 -type d | cut -d/ -f5-)"
  for file in $file_list; do
      install -D "$TMP_LIB/${file}" "$SYSTEM_LIB/${file}"
      chmod 0644 "$SYSTEM_LIB/${file}";
  done
  for dir in $dir_list; do
    chmod 0755 "$SYSTEM_LIB/${dir}";
  done
}

send_sparse_5() {
  file_list="$(find "$TMP_LIB64/" -mindepth 1 -type f | cut -d/ -f5-)"
  dir_list="$(find "$TMP_LIB64/" -mindepth 1 -type d | cut -d/ -f5-)"
  for file in $file_list; do
      install -D "$TMP_LIB64/${file}" "$SYSTEM_LIB64/${file}"
      chmod 0644 "$SYSTEM_LIB64/${file}";
  done
  for dir in $dir_list; do
    chmod 0755 "$SYSTEM_LIB64/${dir}";
  done
}

send_sparse_6() {
  file_list="$(find "$TMP_CONFIG/" -mindepth 1 -type f | cut -d/ -f5-)"
  dir_list="$(find "$TMP_CONFIG/" -mindepth 1 -type d | cut -d/ -f5-)"
  for file in $file_list; do
      install -D "$TMP_CONFIG/${file}" "$SYSTEM_ETC_CONFIG/${file}"
      chmod 0644 "$SYSTEM_ETC_CONFIG/${file}";
  done
  for dir in $dir_list; do
    chmod 0755 "$SYSTEM_ETC_CONFIG/${dir}";
  done
}

send_sparse_7() {
  file_list="$(find "$TMP_DEFAULT_PERM/" -mindepth 1 -type f | cut -d/ -f5-)"
  dir_list="$(find "$TMP_DEFAULT_PERM/" -mindepth 1 -type d | cut -d/ -f5-)"
  for file in $file_list; do
      install -D "$TMP_DEFAULT_PERM/${file}" "$SYSTEM_ETC_DEFAULT/${file}"
      chmod 0644 "$SYSTEM_ETC_DEFAULT/${file}";
  done
  for dir in $dir_list; do
    chmod 0755 "$SYSTEM_ETC_DEFAULT/${dir}";
  done
}

send_sparse_8() {
  file_list="$(find "$TMP_G_PREF/" -mindepth 1 -type f | cut -d/ -f5-)"
  dir_list="$(find "$TMP_G_PREF/" -mindepth 1 -type d | cut -d/ -f5-)"
  for file in $file_list; do
      install -D "$TMP_G_PREF/${file}" "$SYSTEM_ETC_PREF/${file}"
      chmod 0644 "$SYSTEM_ETC_PREF/${file}";
  done
  for dir in $dir_list; do
    chmod 0755 "$SYSTEM_ETC_PREF/${dir}";
  done
}

send_sparse_9() {
  file_list="$(find "$TMP_G_PERM/" -mindepth 1 -type f | cut -d/ -f5-)"
  dir_list="$(find "$TMP_G_PERM/" -mindepth 1 -type d | cut -d/ -f5-)"
  for file in $file_list; do
      install -D "$TMP_G_PERM/${file}" "$SYSTEM_ETC_PERM/${file}"
      chmod 0644 "$SYSTEM_ETC_PERM/${file}";
  done
  for dir in $dir_list; do
    chmod 0755 "$SYSTEM_ETC_PERM/${dir}";
  done
}

send_sparse_10() {
  cp -f $TMP/g.prop $SYSTEM/etc/g.prop
  chmod 0644 $SYSTEM/etc/g.prop
}

send_sparse_11() {
  file_list="$(find "$TMP_ADDON/" -mindepth 1 -type f | cut -d/ -f5-)"
  dir_list="$(find "$TMP_ADDON/" -mindepth 1 -type d | cut -d/ -f5-)"
  for file in $file_list; do
      install -D "$TMP_ADDON/${file}" "$SYSTEM_ADDOND/${file}"
      chmod 0644 "$SYSTEM_ADDOND/${file}";
  done
  for dir in $dir_list; do
    chmod 0755 "$SYSTEM_ADDOND/${dir}";
  done
}

send_sparse_12() {
  file_list="$(find "$TMP_PRIV_SETUP/" -mindepth 1 -type f | cut -d/ -f5-)"
  dir_list="$(find "$TMP_PRIV_SETUP/" -mindepth 1 -type d | cut -d/ -f5-)"
  for file in $file_list; do
      install -D "$TMP_PRIV_SETUP/${file}" "$SYSTEM_PRIV_APP/${file}"
      chmod 0644 "$SYSTEM_PRIV_APP/${file}";
  done
  for dir in $dir_list; do
      chmod 0755 "$SYSTEM_PRIV_APP/${dir}";
  done
}

# end sparse method
  
# Set selinux context
selinux_context_s1() {
  chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleCalendarSyncAdapter";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleContactsSyncAdapter";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleExtShared";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/SoundPickerPrebuilt";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/SoundPickerPrebuilt/SoundPickerPrebuilt.apk";
}

selinux_context_sp2() {
  chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/CarrierSetup";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/ConfigUpdater";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleExtServices";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleServicesFramework";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/Phonesky";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/PrebuiltGmsCore";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/CarrierSetup/CarrierSetup.apk";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/Phonesky/Phonesky.apk";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/PrebuiltGmsCore/PrebuiltGmsCore.apk";
}

selinux_context_sf3() {
  chcon -h u:object_r:system_file:s0 "$SYSTEM_FRAMEWORK/com.google.android.dialer.support.jar";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_FRAMEWORK/com.google.android.maps.jar";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_FRAMEWORK/com.google.android.media.effects.jar";
}

selinux_context_sl4() {
  chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB/libsketchology_native.so";
}

selinux_context_sl5() {
  chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libjni_latinimegoogle.so";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libsketchology_native.so";
}

selinux_context_se6() {
  chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_DEFAULT/default-permissions";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_DEFAULT/default-permissions/default-permissions.xml";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_DEFAULT/default-permissions/opengapps-permissions.xml";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/com.google.android.dialer.support.xml";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/com.google.android.maps.xml";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/com.google.android.media.effects.xml";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/privapp-permissions-google.xml";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/split-permissions-google.xml";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PREF/preferred-apps";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PREF/preferred-apps/google.xml";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/dialer_experience.xml";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google.xml";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google_build.xml";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google_exclusives_enable.xml";
  chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google-hiddenapi-package-whitelist.xml";
  chcon -h u:object_r:system_file:s0 "$SYSTEM/etc/g.prop";
}

selinux_context_sb7() {
  chcon -h u:object_r:system_file:s0 "$SYSTEM_ADDOND/90bit_gapps.sh";
}

# end selinux method

# Enable Google Assistant
set_assistant() {
  insert_line $SYSTEM/build.prop "ro.opa.eligible_device=true" after 'net.bt.name=Android' 'ro.opa.eligible_device=true';
}

# Remove Privileged App Whitelist property with flag enforce
whitelist_permission() {
  if [ -f $SYSTEM/build.prop ]; then
    grep -v "$PROPFLAG" $SYSTEM/build.prop > /tmp/build.prop
    rm -rf $SYSTEM/build.prop
    cp -f /tmp/build.prop $SYSTEM/build.prop
    chmod 0600 $SYSTEM/build.prop
    rm -rf /tmp/build.prop
    insert_line $SYSTEM/build.prop "ro.control_privapp_permissions=disable" after 'DEVICE_PROVISIONED=1' 'ro.control_privapp_permissions=disable';
  fi;
  if [ -f /system_root/system/etc/prop.default ]; then
    echo "system_root: prop.default present in device" >> $whitelist
    grep -v "$PROPFLAG" /system_root/system/etc/prop.default > /tmp/prop.default
    rm -rf /system_root/system/etc/prop.default
    cp -f /tmp/prop.default /system_root/system/etc/prop.default
    chmod 0600 /system_root/system/etc/prop.default
    ln -sfnv /system_root/system/etc/prop.default /system_root/default.prop
    rm -rf /tmp/prop.default
    insert_line /system_root/system/etc/prop.default "ro.control_privapp_permissions=disable" after 'ro.allow.mock.location=0' 'ro.control_privapp_permissions=disable';
  else
    echo "system_root: unable to find prop.default" >> $whitelist
  fi;
  if [ -f $VENDOR/build.prop ]; then
    grep -v "$PROPFLAG" $VENDOR/build.prop > /tmp/build.prop
    rm -rf $VENDOR/build.prop
    cp -f /tmp/build.prop $VENDOR/build.prop
    chmod 0600 $VENDOR/build.prop
    rm -rf /tmp/build.prop
    insert_line $VENDOR/build.prop "ro.control_privapp_permissions=disable" after 'ro.carrier=unknown' 'ro.control_privapp_permissions=disable';
  fi;
}

ui_print "Mount Partitions";

# These set of functions should be executed before any other install function
function pre_install() {
  set_mount;
  boot_slot;
  mount_part;
  remount_part;
  on_SAR;
}
pre_install;

ui_print " ";

# Set version check property
android_sdk="$(get_prop "ro.build.version.sdk")";
supported_sdk="29";
android_version="$(get_prop "ro.build.version.release")";
supported_version="10";

ui_print "Checking Android SDK version";
if [ "$android_sdk" = "$supported_sdk" ]; then
    ui_print "$android_sdk";
    ui_print " ";
else
    ui_print " ";
    on_abort "Unsupported Android SDK version. Aborting...";
    ui_print " ";
fi;

ui_print "Checking Android version";
if [ "$android_version" = "$supported_version" ]; then
    ui_print "$android_version";
    ui_print " ";
else
    ui_print " ";
    on_abort "Unsupported Android version. Aborting...";
    ui_print " ";
fi;

# Check to make certain that user device matches the architecture
device_architecture="$(get_prop "ro.product.cpu.abilist")"
# If the recommended field is empty, fall back to the deprecated one
if [ -z "$device_architecture" ]; then
  device_architecture="$(get_prop "ro.product.cpu.abi")"
fi

case "$device_architecture" in
  *x86_64*) arch="x86_64";;
  *x86*) arch="x86";;
  *arm64*) arch="arm64";;
  *armeabi*) arch="arm";;
  *) arch="unknown";;
esac

ui_print "Checking Android ARCH";
for targetarch in arm64; do
  if [ "$arch" = "$targetarch" ]; then
    ui_print "$arch";
    ui_print " ";
  else
    ui_print " ";
    on_abort "Unsupported Android ARCH. Aborting...";
    ui_print " ";
  fi;
done

ui_print "Installing";

# Do not merge 'pre_install' functions here
# Begin installation
function post_install() {
  clean_logs;
  logd;
  recovery_actions;
  unpack_zip;
  service_manager;
  pre_installed;
  extract_app;
  send_sparse_1;
  send_sparse_2;
  send_sparse_3;
  send_sparse_4;
  send_sparse_5;
  send_sparse_6;
  send_sparse_7;
  send_sparse_8;
  send_sparse_9;
  send_sparse_10;
  send_sparse_11;
  selinux_context_s1;
  selinux_context_sp2;
  selinux_context_sf3;
  selinux_context_sl4;
  selinux_context_sl5;
  selinux_context_se6;
  selinux_context_sb7;
  config_install;
  set_assistant;
  whitelist_permission;
  on_install;
  recovery_cleanup;
}
post_install; # end installation

# end method