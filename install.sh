#!/usr/bin/env bash
# shellcheck disable=SC1090

#########################################################
# ARCH LINUX INSTALLER | Automated Arch Linux Installer TUI
#########################################################


# AUTOR:    Snaplyze
# ORIGIN:   Russia
# LICENCE:  GPL 2.0

# CONFIG
set -o pipefail # A pipeline error results in the error status of the entire pipeline
set -e          # Terminate if any command exits with a non-zero
set -E          # ERR trap inherited by shell functions (errtrace)

# ENVIRONMENT
: "${DEBUG:=false}" # DEBUG=true ./installer.sh
: "${GUM:=./gum}"   # GUM=/usr/bin/gum ./installer.sh
: "${FORCE:=false}" # FORCE=true ./installer.sh

# SCRIPT
VERSION='1.1.0'

# GUM
GUM_VERSION="0.13.0"

# ENVIRONMENT
SCRIPT_CONFIG="./installer.conf"
SCRIPT_LOG="./installer.log"

# INIT
INIT_FILENAME="initialize"

# TEMP
SCRIPT_TMP_DIR="$(mktemp -d "./.tmp.XXXXX")"
ERROR_MSG="${SCRIPT_TMP_DIR}/installer.err"
PROCESS_LOG="${SCRIPT_TMP_DIR}/process.log"
PROCESS_RET="${SCRIPT_TMP_DIR}/process.ret"

# COLORS
COLOR_WHITE=251
COLOR_GREEN=36
COLOR_PURPLE=212
COLOR_YELLOW=221
COLOR_RED=9

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# MAIN
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main() {

    # Clear logfile
    [ -f "$SCRIPT_LOG" ] && mv -f "$SCRIPT_LOG" "${SCRIPT_LOG}.old"

    # Check gum binary or download
    gum_init

    # Traps (error & exit)
    trap 'trap_exit' EXIT
    trap 'trap_error ${FUNCNAME} ${LINENO}' ERR

    # Print version to logfile
    log_info "Arch Linux ${VERSION}"

    # Start recovery
    [[ "$1" = "--recovery"* ]] && {
        start_recovery
        exit $? # Exit after recovery
    }

    # ---------------------------------------------------------------------------------------------------

    # Loop properties step to update screen if user edit properties
    while (true); do

        print_header "Arch Linux Installer" # Show landig page
        gum_white 'Please make sure you have:' && echo
        gum_white '• Backed up your important data'
        gum_white '• A stable internet connection'
        gum_white '• Secure Boot disabled'
        gum_white '• Boot Mode set to UEFI'

        # Ask for load & remove existing config file
        if [ "$FORCE" = "false" ] && [ -f "$SCRIPT_CONFIG" ] && ! gum_confirm "Load existing installer.conf?"; then
            gum_confirm "Remove existing installer.conf?" || trap_gum_exit # If not want remove config > exit script
            echo && gum_title "Properties File"
            mv -f "$SCRIPT_CONFIG" "${SCRIPT_CONFIG}.old" && gum_info "installer.conf was moved to installer.conf.old"
            gum_warn "Please restart Arch Linux Installer..."
            echo && exit 0
        fi

        echo # Print new line

        # Source installer.conf if exists or select preset
        until properties_preset_source; do :; done

        # Selectors
        echo && gum_title "Core Setup"
        until select_hostname; do :; done             # <-- Добавлен вызов
        until select_username; do :; done
        until select_password; do :; done
        until select_timezone; do :; done
        until select_language; do :; done
        until select_keyboard; do :; done
        until select_disk; do :; done
        until select_filesystem; do :; done           # <-- Добавлен вызов
        echo && gum_title "Desktop Setup"
        until select_enable_desktop_environment; do :; done
        until select_enable_desktop_driver; do :; done
        until select_enable_desktop_slim; do :; done
        until select_enable_desktop_keyboard; do :; done
        echo && gum_title "Feature Setup"
        until select_enable_encryption; do :; done
        until select_enable_core_tweaks; do :; done
        until select_enable_bootsplash; do :; done
        until select_enable_multilib; do :; done
        until select_enable_aur; do :; done
        until select_reflector_countries; do :; done # <-- Добавлен вызов
        until select_enable_housekeeping; do :; done

        # Print success
        echo && gum_title "Properties"

        # Open Advanced Properties?
        if [ "$FORCE" = "false" ] && gum_confirm --negative="Skip" "Open Advanced Setup?"; then
            local header_txt="• Advanced Setup | Save with CTRL + D or ESC and cancel with CTRL + C"
            if gum_write --show-line-numbers --prompt "" --height=12 --width=180 --header="${header_txt}" --value="$(cat "$SCRIPT_CONFIG")" >"${SCRIPT_CONFIG}.new"; then
                mv "${SCRIPT_CONFIG}.new" "${SCRIPT_CONFIG}" && properties_source
                gum_info "Properties successfully saved"
                gum_confirm "Change Password?" && until select_password --change && properties_source; do :; done
                echo && ! gum_spin --title="Reload Properties in 3 seconds..." -- sleep 3 && trap_gum_exit
                continue # Restart properties step to refresh properties screen
            else
                rm -f "${SCRIPT_CONFIG}.new" # Remove tmp properties
                gum_warn "Advanced Setup canceled"
            fi
        fi

        # Finish
        gum_info "Successfully initialized"

        ######################################################
        break # Exit properties step and continue installation
        ######################################################
    done

    # ---------------------------------------------------------------------------------------------------

    # Start installation in 5 seconds?
    if [ "$FORCE" = "false" ]; then
        gum_confirm "Start Arch Linux Installation?" || trap_gum_exit
    fi
    local spin_title="Arch Linux Installation starts in 5 seconds. Press CTRL + C to cancel..."
    echo && ! gum_spin --title="$spin_title" -- sleep 5 && trap_gum_exit # CTRL + C pressed
    gum_title "Arch Linux Installation"

    SECONDS=0 # Messure execution time of installation

    # Executors
    exec_init_installation
    exec_prepare_disk
    exec_pacstrap_core
    exec_enable_multilib
    exec_install_aur_helper
    exec_install_bootsplash
    exec_install_housekeeping
    exec_install_desktop
    exec_install_graphics_driver
    exec_install_vm_support
    exec_finalize_arch_linux
    exec_cleanup_installation

    # Calc installation duration
    duration=$SECONDS # This is set before install starts
    duration_min="$((duration / 60))"
    duration_sec="$((duration % 60))"

    # Print duration time info
    local finish_txt="Installation successful in ${duration_min} minutes and ${duration_sec} seconds"
    echo && gum_green --bold "$finish_txt"
    log_info "$finish_txt"

    # Copy installer files to users home
    if [ "$DEBUG" = "false" ]; then
        cp -f "$SCRIPT_CONFIG" "/mnt/home/${ARCH_LINUX_USERNAME}/installer.conf"
        sed -i "1i\# Arch Linux Version: ${VERSION}" "/mnt/home/${ARCH_LINUX_USERNAME}/installer.conf"
        cp -f "$SCRIPT_LOG" "/mnt/home/${ARCH_LINUX_USERNAME}/installer.log"
        arch-chroot /mnt chown -R "$ARCH_LINUX_USERNAME":"$ARCH_LINUX_USERNAME" "/home/${ARCH_LINUX_USERNAME}/installer.conf"
        arch-chroot /mnt chown -R "$ARCH_LINUX_USERNAME":"$ARCH_LINUX_USERNAME" "/home/${ARCH_LINUX_USERNAME}/installer.log"
    fi

    wait # Wait for sub processes

    # ---------------------------------------------------------------------------------------------------

    # Show reboot & unmount promt
    local do_reboot do_unmount do_chroot

    # Default values
    do_reboot="false"
    do_chroot="false"
    do_unmount="false"

    # Force values
    if [ "$FORCE" = "true" ]; then
        do_reboot="false"
        do_chroot="false"
        do_unmount="true"
    fi

    # Reboot promt
    [ "$FORCE" = "false" ] && gum_confirm "Reboot to Arch Linux now?" && do_reboot="true" && do_unmount="true"

    # Unmount
    [ "$FORCE" = "false" ] && [ "$do_reboot" = "false" ] && gum_confirm "Unmount Arch Linux from /mnt?" && do_unmount="true"
    [ "$do_unmount" = "true" ] && echo && gum_warn "Unmounting Arch Linux from /mnt..."
    if [ "$DEBUG" = "false" ] && [ "$do_unmount" = "true" ]; then
        swapoff -a
        umount -A -R /mnt
        [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && cryptsetup close cryptroot
    fi

    # Do reboot
    [ "$FORCE" = "false" ] && [ "$do_reboot" = "true" ] && gum_warn "Rebooting to Arch Linux..." && [ "$DEBUG" = "false" ] && reboot

    # Chroot
    [ "$FORCE" = "false" ] && [ "$do_unmount" = "false" ] && gum_confirm "Chroot to new Arch Linux?" && do_chroot="true"
    if [ "$do_chroot" = "true" ] && echo && gum_warn "Chrooting Arch Linux at /mnt..."; then
        gum_warn "!! YOUR ARE NOW ON YOUR NEW Arch Linux SYSTEM !!"
        gum_warn ">> Leave with command 'exit'"
        if [ "$DEBUG" = "false" ]; then
            arch-chroot /mnt </dev/tty || true
        fi
        wait # Wait for subprocesses
        gum_warn "Please reboot manually..."
    fi

    # Print warning
    [ "$do_unmount" = "false" ] && [ "$do_chroot" = "false" ] && echo && gum_warn "Arch Linux is still mounted at /mnt"

    gum_info "Exit" && exit 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# RECOVERY
# ////////////////////////////////////////////////////////////////////////////////////////////////////

start_recovery() {
    print_header "Arch Linux Recovery"
    local recovery_boot_partition recovery_root_partition user_input items options
    local recovery_mount_dir="/mnt/recovery"
    local recovery_crypt_label="cryptrecovery"

    recovery_unmount() {
        set +e
        swapoff -a &>/dev/null
        umount -A -R "$recovery_mount_dir" &>/dev/null
        cryptsetup close "$recovery_crypt_label" &>/dev/null
        set -e
    }

    # Select disk
    mapfile -t items < <(lsblk -I 8,259,254 -d -o KNAME,SIZE -n)
    # size: $(lsblk -d -n -o SIZE "/dev/${item}")
    options=() && for item in "${items[@]}"; do options+=("/dev/${item}"); done
    user_input=$(gum_choose --header "+ Select Arch Linux Disk" "${options[@]}") || exit 130
    gum_title "Recovery"
    [ -z "$user_input" ] && log_fail "Disk is empty" && exit 1 # Check if new value is null
    user_input=$(echo "$user_input" | awk -F' ' '{print $1}')  # Remove size from input
    [ ! -e "$user_input" ] && log_fail "Disk does not exists" && exit 130

    [[ "$user_input" = "/dev/nvm"* ]] && recovery_boot_partition="${user_input}p1" || recovery_boot_partition="${user_input}1"
    [[ "$user_input" = "/dev/nvm"* ]] && recovery_root_partition="${user_input}p2" || recovery_root_partition="${user_input}2"

    # Check encryption
    if lsblk -ndo FSTYPE "$recovery_root_partition" 2>/dev/null | grep -q "crypto_LUKS"; then
        recovery_encryption_enabled="true"
        gum_warn "The disk $user_input is encrypted with LUKS"
    else
        recovery_encryption_enabled="false"
        gum_info "The disk $user_input is not encrypted"
    fi

    # Check archiso
    [ "$(cat /proc/sys/kernel/hostname)" != "archiso" ] && gum_fail "You must execute the Recovery from Arch ISO!" && exit 130

    # Make sure everything is unmounted
    recovery_unmount

    # Create mount dir
    mkdir -p "$recovery_mount_dir"
    mkdir -p "$recovery_mount_dir/boot"

    # Mount disk
    if [ "$recovery_encryption_enabled" = "true" ]; then

        # Encryption password
        recovery_encryption_password=$(gum_input --password --header "+ Enter Encryption Password") || exit 130

        # Open encrypted Disk
        echo -n "$recovery_encryption_password" | cryptsetup open "$recovery_root_partition" "$recovery_crypt_label" &>/dev/null || {
            gum_fail "Wrong encryption password"
            exit 130
        }

        # Mount encrypted disk
        mount "/dev/mapper/${recovery_crypt_label}" "$recovery_mount_dir"
        mount "$recovery_boot_partition" "$recovery_mount_dir/boot"
    else
        # Mount unencrypted disk
        mount "$recovery_root_partition" "$recovery_mount_dir"
        mount "$recovery_boot_partition" "$recovery_mount_dir/boot"
    fi

    # Chroot
    gum_green "!! YOUR ARE NOW ON YOUR RECOVERY SYSTEM !!"
    gum_yellow ">> Leave with command 'exit'"
    arch-chroot "$recovery_mount_dir" </dev/tty
    wait && recovery_unmount
    gum_green ">> Exit Recovery"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PROPERTIES
# ////////////////////////////////////////////////////////////////////////////////////////////////////

properties_source() {
    [ ! -f "$SCRIPT_CONFIG" ] && return 1
    set -a # Load properties file and auto export variables
    source "$SCRIPT_CONFIG"
    set +a
    return 0
}

properties_generate() {
    { # Write properties to installer.conf
        echo "ARCH_LINUX_HOSTNAME='${ARCH_LINUX_HOSTNAME}'"
        echo "ARCH_LINUX_USERNAME='${ARCH_LINUX_USERNAME}'"
        echo "ARCH_LINUX_DISK='${ARCH_LINUX_DISK}'"
        echo "ARCH_LINUX_BOOT_PARTITION='${ARCH_LINUX_BOOT_PARTITION}'"
        echo "ARCH_LINUX_ROOT_PARTITION='${ARCH_LINUX_ROOT_PARTITION}'"
        echo "ARCH_LINUX_FILESYSTEM='${ARCH_LINUX_FILESYSTEM}'" # <-- ДОБАВЛЕНО
        echo "ARCH_LINUX_ENCRYPTION_ENABLED='${ARCH_LINUX_ENCRYPTION_ENABLED}'"
        echo "ARCH_LINUX_TIMEZONE='${ARCH_LINUX_TIMEZONE}'"
        echo "ARCH_LINUX_LOCALE_LANG='${ARCH_LINUX_LOCALE_LANG}'"
        echo "ARCH_LINUX_LOCALE_GEN_LIST=(${ARCH_LINUX_LOCALE_GEN_LIST[*]@Q})"
        echo "ARCH_LINUX_REFLECTOR_COUNTRY='${ARCH_LINUX_REFLECTOR_COUNTRY}'" # <-- Теперь может быть список через запятую или пустой
        echo "ARCH_LINUX_VCONSOLE_KEYMAP='${ARCH_LINUX_VCONSOLE_KEYMAP}'"
        echo "ARCH_LINUX_VCONSOLE_FONT='${ARCH_LINUX_VCONSOLE_FONT}'"
        echo "ARCH_LINUX_KERNEL='${ARCH_LINUX_KERNEL}'"
        echo "ARCH_LINUX_MICROCODE='${ARCH_LINUX_MICROCODE}'"
        echo "ARCH_LINUX_CORE_TWEAKS_ENABLED='${ARCH_LINUX_CORE_TWEAKS_ENABLED}'"
        echo "ARCH_LINUX_MULTILIB_ENABLED='${ARCH_LINUX_MULTILIB_ENABLED}'"
        echo "ARCH_LINUX_AUR_HELPER='${ARCH_LINUX_AUR_HELPER}'"
        echo "ARCH_LINUX_BOOTSPLASH_ENABLED='${ARCH_LINUX_BOOTSPLASH_ENABLED}'"
        echo "ARCH_LINUX_HOUSEKEEPING_ENABLED='${ARCH_LINUX_HOUSEKEEPING_ENABLED}'"
        echo "ARCH_LINUX_DESKTOP_ENABLED='${ARCH_LINUX_DESKTOP_ENABLED}'"
        echo "ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER='${ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER}'"
        echo "ARCH_LINUX_DESKTOP_EXTRAS_ENABLED='${ARCH_LINUX_DESKTOP_EXTRAS_ENABLED}'"
        echo "ARCH_LINUX_DESKTOP_SLIM_ENABLED='${ARCH_LINUX_DESKTOP_SLIM_ENABLED}'"
        echo "ARCH_LINUX_DESKTOP_KEYBOARD_MODEL='${ARCH_LINUX_DESKTOP_KEYBOARD_MODEL}'"
        echo "ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT='${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT}'"
        echo "ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT='${ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT}'"
        echo "ARCH_LINUX_VM_SUPPORT_ENABLED='${ARCH_LINUX_VM_SUPPORT_ENABLED}'"
        echo "ARCH_LINUX_ECN_ENABLED='${ARCH_LINUX_ECN_ENABLED}'"
    } >"$SCRIPT_CONFIG" # Write properties to file
}

properties_preset_source() {

    # Default presets that are not filesystem/hostname dependent
    [ -z "$ARCH_LINUX_KERNEL" ] && ARCH_LINUX_KERNEL="linux-zen"
    [ -z "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" ] && ARCH_LINUX_DESKTOP_EXTRAS_ENABLED='true'
    [ -z "$ARCH_LINUX_VM_SUPPORT_ENABLED" ] && ARCH_LINUX_VM_SUPPORT_ENABLED="true"
    [ -z "$ARCH_LINUX_ECN_ENABLED" ] && ARCH_LINUX_ECN_ENABLED="true"
    [ -z "$ARCH_LINUX_DESKTOP_KEYBOARD_MODEL" ] && ARCH_LINUX_DESKTOP_KEYBOARD_MODEL="pc105"
    # Default filesystem if not set
    [ -z "$ARCH_LINUX_FILESYSTEM" ] && ARCH_LINUX_FILESYSTEM="ext4"

    # Set microcode
    [ -z "$ARCH_LINUX_MICROCODE" ] && grep -E "GenuineIntel" &>/dev/null <<<"$(lscpu)" && ARCH_LINUX_MICROCODE="intel-ucode"
    [ -z "$ARCH_LINUX_MICROCODE" ] && grep -E "AuthenticAMD" &>/dev/null <<<"$(lscpu)" && ARCH_LINUX_MICROCODE="amd-ucode"

    # Load properties or select preset
    if [ -f "$SCRIPT_CONFIG" ]; then
        properties_source
        gum join "$(gum_green --bold "• ")" "$(gum_white "Setup preset loaded from: ")" "$(gum_white --bold "installer.conf")"
    else
        # Select preset
        local preset options
        options=("desktop - GNOME Desktop Environment (default)" "core    - Minimal Arch Linux TTY Environment" "none    - No pre-selection")
        preset=$(gum_choose --header "+ Choose Setup Preset" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$preset" ] && return 1 # Check if new value is null
        preset="$(echo "$preset" | awk '{print $1}')"

        # Core preset
        if [[ $preset == core* ]]; then
            ARCH_LINUX_DESKTOP_ENABLED='false'
            ARCH_LINUX_MULTILIB_ENABLED='false'
            ARCH_LINUX_HOUSEKEEPING_ENABLED='false'
            ARCH_LINUX_BOOTSPLASH_ENABLED='false'
            ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER="none"
            ARCH_LINUX_AUR_HELPER='none'
        fi

        # Desktop preset
        if [[ $preset == desktop* ]]; then
            ARCH_LINUX_DESKTOP_EXTRAS_ENABLED='true'
            ARCH_LINUX_CORE_TWEAKS_ENABLED="true"
            ARCH_LINUX_BOOTSPLASH_ENABLED='true'
            ARCH_LINUX_DESKTOP_ENABLED='true'
            ARCH_LINUX_MULTILIB_ENABLED='true'
            ARCH_LINUX_HOUSEKEEPING_ENABLED='true'
            ARCH_LINUX_AUR_HELPER='paru'
        fi

        # Write properties (generate an initial file based on presets)
        properties_generate # Generate file AFTER applying preset logic
        properties_source   # Source the newly generated file
        gum join "$(gum_green --bold "• ")" "$(gum_white "Setup preset loaded for: ")" "$(gum_white --bold "$preset")"
    fi
    return 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# SELECTORS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

select_hostname() {
    if [ -z "$ARCH_LINUX_HOSTNAME" ]; then
        local user_input
        # Предлагаем дефолт, но позволяем изменить
        user_input=$(gum_input --header "+ Enter Hostname" --value "archlinux") || trap_gum_exit_confirm
        # Простая валидация (не пустое, без пробелов, без кавычек)
        if [ -z "$user_input" ] || [[ "$user_input" =~ \ |\'|\" ]]; then
             gum_confirm --affirmative="Ok" --negative="" "Invalid hostname: '${user_input}'. Cannot be empty or contain spaces/quotes."
             return 1
        fi
        ARCH_LINUX_HOSTNAME="$user_input" && properties_generate
    fi
    gum_property "Hostname" "$ARCH_LINUX_HOSTNAME"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_username() {
    if [ -z "$ARCH_LINUX_USERNAME" ]; then
        local user_input
        user_input=$(gum_input --header "+ Enter Username") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                      # Check if new value is null
        ARCH_LINUX_USERNAME="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Username" "$ARCH_LINUX_USERNAME"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_password() { # --change
    if [ "$1" = "--change" ] || [ -z "$ARCH_LINUX_PASSWORD" ]; then
        local user_password user_password_check
        user_password=$(gum_input --password --header "+ Enter Password") || trap_gum_exit_confirm
        [ -z "$user_password" ] && return 1 # Check if new value is null
        user_password_check=$(gum_input --password --header "+ Enter Password again") || trap_gum_exit_confirm
        [ -z "$user_password_check" ] && return 1 # Check if new value is null
        if [ "$user_password" != "$user_password_check" ]; then
            gum_confirm --affirmative="Ok" --negative="" "The passwords are not identical"
            return 1
        fi
        ARCH_LINUX_PASSWORD="$user_password" && properties_generate # Set value and generate properties file
    fi
    [ "$1" = "--change" ] && gum_info "Password successfully changed"
    [ "$1" != "--change" ] && gum_property "Password" "*******"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_timezone() {
    if [ -z "$ARCH_LINUX_TIMEZONE" ]; then
        local tz_auto user_input
        tz_auto="$(curl -s http://ip-api.com/line?fields=timezone)"
        user_input=$(gum_input --header "+ Enter Timezone (auto-detected)" --value "$tz_auto") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1 # Check if new value is null
        if [ ! -f "/usr/share/zoneinfo/${user_input}" ]; then
            gum_confirm --affirmative="Ok" --negative="" "Timezone '${user_input}' is not supported"
            return 1
        fi
        ARCH_LINUX_TIMEZONE="$user_input" && properties_generate # Set property and generate properties file
    fi
    gum_property "Timezone" "$ARCH_LINUX_TIMEZONE"
    return 0
}

# ---------------------------------------------------------------------------------------------------

# shellcheck disable=SC2001
select_language() {
    if [ -z "$ARCH_LINUX_LOCALE_LANG" ] || [ -z "${ARCH_LINUX_LOCALE_GEN_LIST[*]}" ]; then
        local user_input items options filter
        # Fetch available options (list all from /usr/share/i18n/locales and check if entry exists in /etc/locale.gen)
        mapfile -t items < <(basename -a /usr/share/i18n/locales/* | grep -v "@") # Create array without @ files
        # Add only available locales (!!! intense command !!!)
        options=() && for item in "${items[@]}"; do grep -q -e "^$item" -e "^#$item" /etc/locale.gen && options+=("$item"); done
        # shellcheck disable=SC2002
        [ -r /root/.zsh_history ] && filter=$(cat /root/.zsh_history | grep 'loadkeys' | head -n 2 | tail -n 1 | cut -d';' -f2 | cut -d' ' -f2 | cut -d'-' -f1)
        # Select locale
        user_input=$(gum_filter --value="$filter" --header "+ Choose Language" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1  # Check if new value is null
        ARCH_LINUX_LOCALE_LANG="$user_input" # Set property
        # Set locale.gen properties (auto generate ARCH_LINUX_LOCALE_GEN_LIST)
        ARCH_LINUX_LOCALE_GEN_LIST=() && while read -r locale_entry; do
            ARCH_LINUX_LOCALE_GEN_LIST+=("$locale_entry")
            # Remove leading # from matched lang in /etc/locale.gen and add entry to array
        done < <(sed "/^#${ARCH_LINUX_LOCALE_LANG}/s/^#//" /etc/locale.gen | grep "$ARCH_LINUX_LOCALE_LANG")
        # Add en_US fallback (every language) if not already exists in list
        [[ "${ARCH_LINUX_LOCALE_GEN_LIST[*]}" != *'en_US.UTF-8 UTF-8'* ]] && ARCH_LINUX_LOCALE_GEN_LIST+=('en_US.UTF-8 UTF-8')
        properties_generate # Generate properties file (for ARCH_LINUX_LOCALE_LANG & ARCH_LINUX_LOCALE_GEN_LIST)
    fi
    gum_property "Language" "$ARCH_LINUX_LOCALE_LANG"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_keyboard() {
    if [ -z "$ARCH_LINUX_VCONSOLE_KEYMAP" ]; then
        local user_input items options filter
        mapfile -t items < <(command localectl list-keymaps)
        options=() && for item in "${items[@]}"; do options+=("$item"); done
        # shellcheck disable=SC2002
        [ -r /root/.zsh_history ] && filter=$(cat /root/.zsh_history | grep 'loadkeys' | head -n 2 | tail -n 1 | cut -d';' -f2 | cut -d' ' -f2 | cut -d'-' -f1)
        user_input=$(gum_filter --value="$filter" --header "+ Choose Keyboard" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                             # Check if new value is null
        ARCH_LINUX_VCONSOLE_KEYMAP="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Keyboard" "$ARCH_LINUX_VCONSOLE_KEYMAP"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_disk() {
    if [ -z "$ARCH_LINUX_DISK" ] || [ -z "$ARCH_LINUX_BOOT_PARTITION" ] || [ -z "$ARCH_LINUX_ROOT_PARTITION" ]; then
        local user_input items options
        mapfile -t items < <(lsblk -I 8,259,254 -d -o KNAME,SIZE -n)
        # size: $(lsblk -d -n -o SIZE "/dev/${item}")
        options=() && for item in "${items[@]}"; do options+=("/dev/${item}"); done
        user_input=$(gum_choose --header "+ Choose Disk" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                          # Check if new value is null
        user_input=$(echo "$user_input" | awk -F' ' '{print $1}') # Remove size from input
        [ ! -e "$user_input" ] && log_fail "Disk does not exists" && return 1
        ARCH_LINUX_DISK="$user_input" # Set property
        [[ "$ARCH_LINUX_DISK" = "/dev/nvm"* ]] && ARCH_LINUX_BOOT_PARTITION="${ARCH_LINUX_DISK}p1" || ARCH_LINUX_BOOT_PARTITION="${ARCH_LINUX_DISK}1"
        [[ "$ARCH_LINUX_DISK" = "/dev/nvm"* ]] && ARCH_LINUX_ROOT_PARTITION="${ARCH_LINUX_DISK}p2" || ARCH_LINUX_ROOT_PARTITION="${ARCH_LINUX_DISK}2"
        properties_generate # Generate properties file
    fi
    gum_property "Disk" "$ARCH_LINUX_DISK"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_filesystem() {
    if [ -z "$ARCH_LINUX_FILESYSTEM" ]; then
        local options=("ext4 (default)" "btrfs (with subvolumes)")
        local user_input
        user_input=$(gum_choose --header "+ Choose Filesystem" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1 # User cancelled
        user_input="$(echo "$user_input" | awk '{print $1}')" # Получаем только имя ФС (ext4 или btrfs)
        ARCH_LINUX_FILESYSTEM="$user_input" && properties_generate
    fi
    gum_property "Filesystem" "$ARCH_LINUX_FILESYSTEM"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_reflector_countries() {
    # Если значение уже задано в installer.conf, просто показываем его
    if [ -n "$ARCH_LINUX_REFLECTOR_COUNTRY" ]; then
        gum_property "Reflector Countries" "$ARCH_LINUX_REFLECTOR_COUNTRY"
        return 0
    fi

    # Получаем список стран от reflector
    local countries_list=()
    local country_item
    gum_spin --title "Fetching country list from reflector..." -- mapfile -t countries_list < <(reflector --list-countries 2>/dev/null)

    if [ ${#countries_list[@]} -eq 0 ]; then
        log_warn "Could not fetch country list from reflector. Skipping selection."
        gum_warn "Could not fetch country list from reflector. Using global mirrors."
        ARCH_LINUX_REFLECTOR_COUNTRY="" # Оставляем пустым для глобального поиска
        properties_generate # Сохраняем пустую переменную
        gum_property "Reflector Countries" "(Global)"
        return 0
    fi

    # Используем gum filter для выбора одной или нескольких стран
    local selected_countries_array=()
    local header_txt="+ Choose Mirror Countries (Space to select, Enter to confirm)"
    # Сортируем список стран для удобства
    mapfile -t sorted_countries_list < <(printf "%s\n" "${countries_list[@]}" | sort)
    mapfile -t selected_countries_array < <(gum filter --no-limit --height 15 --header "$header_txt" "${sorted_countries_list[@]}") || trap_gum_exit_confirm

    # Проверяем, выбрал ли пользователь что-то
    if [ ${#selected_countries_array[@]} -eq 0 ]; then
         # Предлагаем использовать глобальные зеркала или попробовать снова
        if gum_confirm "No countries selected. Use global mirrors (recommended) or try again?" --affirmative="Use Global" --negative="Try Again"; then
            ARCH_LINUX_REFLECTOR_COUNTRY="" && properties_generate
            gum_property "Reflector Countries" "(Global)"
            return 0 # Выбор сделан (глобальный)
        else
            return 1 # Возвращаем ошибку, чтобы until в main сработал и выбор повторился
        fi
    fi

    # Преобразуем массив выбранных стран в строку, разделенную запятыми
    local selected_countries_string
    selected_countries_string=$(printf "%s," "${selected_countries_array[@]}")
    selected_countries_string=${selected_countries_string%,} # Убираем последнюю запятую

    # Сохраняем результат
    ARCH_LINUX_REFLECTOR_COUNTRY="$selected_countries_string" && properties_generate

    gum_property "Reflector Countries" "$ARCH_LINUX_REFLECTOR_COUNTRY"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_encryption() {
    if [ -z "$ARCH_LINUX_ENCRYPTION_ENABLED" ]; then
        gum_confirm "Enable Disk Encryption?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_ENCRYPTION_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Disk Encryption" "$ARCH_LINUX_ENCRYPTION_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_core_tweaks() {
    if [ -z "$ARCH_LINUX_CORE_TWEAKS_ENABLED" ]; then
        gum_confirm "Enable Core Tweaks?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_CORE_TWEAKS_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Core Tweaks" "$ARCH_LINUX_CORE_TWEAKS_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_bootsplash() {
    if [ -z "$ARCH_LINUX_BOOTSPLASH_ENABLED" ]; then
        gum_confirm "Enable Bootsplash?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_BOOTSPLASH_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Bootsplash" "$ARCH_LINUX_BOOTSPLASH_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_desktop_environment() {
    if [ -z "$ARCH_LINUX_DESKTOP_ENABLED" ]; then
        local user_input
        gum_confirm "Enable GNOME Desktop Environment?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_DESKTOP_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Desktop Environment" "$ARCH_LINUX_DESKTOP_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_desktop_slim() {
    if [ "$ARCH_LINUX_DESKTOP_ENABLED" = "true" ]; then
        if [ -z "$ARCH_LINUX_DESKTOP_SLIM_ENABLED" ]; then
            local user_input
            gum_confirm "Enable Desktop Slim Mode? (GNOME Core Apps only)" --affirmative="No (default)" --negative="Yes"
            local user_confirm=$?
            [ $user_confirm = 130 ] && {
                trap_gum_exit_confirm
                return 1
            }
            [ $user_confirm = 1 ] && user_input="true"
            [ $user_confirm = 0 ] && user_input="false"
            ARCH_LINUX_DESKTOP_SLIM_ENABLED="$user_input" && properties_generate # Set value and generate properties file
        fi
        gum_property "Desktop Slim Mode" "$ARCH_LINUX_DESKTOP_SLIM_ENABLED"
    fi
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_desktop_keyboard() {
    if [ "$ARCH_LINUX_DESKTOP_ENABLED" = "true" ]; then
        if [ -z "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT" ]; then
            local user_input user_input2
            user_input=$(gum_input --header "+ Enter Desktop Keyboard Layout" --placeholder "e.g. 'us' or 'de'...") || trap_gum_exit_confirm
            [ -z "$user_input" ] && return 1 # Check if new value is null
            ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT="$user_input"
            gum_property "Desktop Keyboard" "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT"
            user_input2=$(gum_input --header "+ Enter Desktop Keyboard Variant (optional)" --placeholder "e.g. 'nodeadkeys' or leave empty...") || trap_gum_exit_confirm
            ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT="$user_input2"
            properties_generate
        else
            gum_property "Desktop Keyboard" "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT"
        fi
        [ -n "$ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT" ] && gum_property "Desktop Keyboard Variant" "$ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT"
    fi
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_desktop_driver() {
    if [ "$ARCH_LINUX_DESKTOP_ENABLED" = "true" ]; then
        if [ -z "$ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER" ] || [ "$ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER" = "none" ]; then
            local user_input options
            options=("mesa" "intel_i915" "nvidia" "amd" "ati")
            user_input=$(gum_choose --header "+ Choose Desktop Graphics Driver (default: mesa)" "${options[@]}") || trap_gum_exit_confirm
            [ -z "$user_input" ] && return 1                                     # Check if new value is null
            ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER="$user_input" && properties_generate # Set value and generate properties file
        fi
        gum_property "Desktop Graphics Driver" "$ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER"
    fi
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_aur() {
    if [ -z "$ARCH_LINUX_AUR_HELPER" ]; then
        local user_input options
        options=("paru" "paru-bin" "paru-git" "none")
        user_input=$(gum_choose --header "+ Choose AUR Helper (default: paru)" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                        # Check if new value is null
        ARCH_LINUX_AUR_HELPER="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "AUR Helper" "$ARCH_LINUX_AUR_HELPER"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_multilib() {
    if [ -z "$ARCH_LINUX_MULTILIB_ENABLED" ]; then
        gum_confirm "Enable 32 Bit Support?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_MULTILIB_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "32 Bit Support" "$ARCH_LINUX_MULTILIB_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_housekeeping() {
    if [ -z "$ARCH_LINUX_HOUSEKEEPING_ENABLED" ]; then
        gum_confirm "Enable Housekeeping?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_HOUSEKEEPING_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Housekeeping" "$ARCH_LINUX_HOUSEKEEPING_ENABLED"
    return 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# EXECUTORS (SUB PROCESSES)
# ////////////////////////////////////////////////////////////////////////////////////////////////////

exec_init_installation() {
    local process_name="Initialize Installation"
    process_init "$process_name"
    (
        [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return
        # Check installation prerequisites
        [ ! -d /sys/firmware/efi ] && log_fail "BIOS not supported! Please set your boot mode to UEFI." && exit 1
        log_info "UEFI detected"
        bootctl status | grep "Secure Boot" | grep -q "disabled" || { log_fail "You must disable Secure Boot in UEFI to continue installation" && exit 1; }
        log_info "Secure Boot: disabled"
        [ "$(cat /proc/sys/kernel/hostname)" != "archiso" ] && log_fail "You must execute the Installer from Arch ISO!" && exit 1
        log_info "Arch ISO detected"
        log_info "Waiting for Reflector from Arch ISO..."
        # This mirrorlist will copied to new Arch system during installation
        while timeout 180 tail --pid=$(pgrep reflector) -f /dev/null &>/dev/null; do sleep 1; done
        pgrep reflector &>/dev/null && log_fail "Reflector timeout after 180 seconds" && exit 1
        rm -f /var/lib/pacman/db.lck # Remove pacman lock file if exists
        timedatectl set-ntp true     # Set time
        # Make sure everything is unmounted before start install
        swapoff -a || true
        if [[ "$(umount -f -A -R /mnt 2>&1)" == *"target is busy"* ]]; then
            # If umount is busy execute fuser
            fuser -km /mnt || true
            umount -f -A -R /mnt || true
        fi
        wait # Wait for sub process
        cryptsetup close cryptroot || true
        vgchange -an || true
        # Temporarily disable ECN (prevent traffic problems with some old routers)
        [ "$ARCH_LINUX_ECN_ENABLED" = "false" ] && sysctl net.ipv4.tcp_ecn=0
        pacman -Sy --noconfirm archlinux-keyring # Update keyring
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_capture $! "$process_name"
}

# ---------------------------------------------------------------------------------------------------

exec_prepare_disk() {
    local process_name="Prepare Disk"
    process_init "$process_name"
    (
        [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return

        # Wipe and create partitions (Standard EFI + Root)
        log_info "Wiping disk ${ARCH_LINUX_DISK}..."
        wipefs -af "$ARCH_LINUX_DISK" || { log_fail "wipefs failed"; exit 1; }
        sgdisk --zap-all "$ARCH_LINUX_DISK" || { log_fail "sgdisk --zap-all failed"; exit 1; }
        log_info "Creating GPT partitions on ${ARCH_LINUX_DISK}..."
        sgdisk -o "$ARCH_LINUX_DISK" || { log_fail "sgdisk -o failed"; exit 1; }
        # Partition 1: EFI System Partition (ESP)
        sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot --align-end "$ARCH_LINUX_DISK" || { log_fail "sgdisk create boot failed"; exit 1; }
        # Partition 2: Linux Root
        sgdisk -n 2:0:0 -t 2:8300 -c 2:root --align-end "$ARCH_LINUX_DISK" || { log_fail "sgdisk create root failed"; exit 1; }
        partprobe "$ARCH_LINUX_DISK" || { log_warn "partprobe failed, continuing..."; }
        sleep 2 # Give kernel time to recognize partitions

        # Verify partitions exist
        [ ! -b "$ARCH_LINUX_BOOT_PARTITION" ] && { log_fail "Boot partition $ARCH_LINUX_BOOT_PARTITION not found"; exit 1; }
        [ ! -b "$ARCH_LINUX_ROOT_PARTITION" ] && { log_fail "Root partition $ARCH_LINUX_ROOT_PARTITION not found"; exit 1; }

        # Disk encryption setup
        local root_device="$ARCH_LINUX_ROOT_PARTITION" # Device to format/mount as root
        if [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ]; then
            log_info "Setting up LUKS encryption on ${ARCH_LINUX_ROOT_PARTITION}..."
            echo -n "$ARCH_LINUX_PASSWORD" | cryptsetup luksFormat "$ARCH_LINUX_ROOT_PARTITION" -q || { log_fail "cryptsetup luksFormat failed"; exit 1; }
            echo -n "$ARCH_LINUX_PASSWORD" | cryptsetup open "$ARCH_LINUX_ROOT_PARTITION" cryptroot -q || { log_fail "cryptsetup open failed"; exit 1; }
            root_device="/dev/mapper/cryptroot"
            log_info "LUKS device opened at ${root_device}"
        fi

        # Format EFI partition
        log_info "Formatting EFI partition ${ARCH_LINUX_BOOT_PARTITION} as FAT32..."
        mkfs.fat -F 32 -n BOOT "$ARCH_LINUX_BOOT_PARTITION" || { log_fail "mkfs.fat failed"; exit 1; }

        # --- Filesystem Specific Formatting and Mounting ---
        if [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ]; then
            log_info "Formatting ${root_device} with Btrfs..."
            mkfs.btrfs -f -L ROOT "$root_device" || { log_fail "mkfs.btrfs failed"; exit 1; }

            log_info "Mounting Btrfs top-level volume to create subvolumes..."
            local btrfs_mount_opts="rw,noatime,compress=zstd:3,ssd,space_cache=v2,discard=async" # Common options
            mount -t btrfs -o "${btrfs_mount_opts}" "$root_device" /mnt || { log_fail "Initial Btrfs mount failed"; exit 1; }

            log_info "Creating Btrfs subvolumes..."
            btrfs subvolume create /mnt/@ || { log_fail "Failed creating subvolume @"; exit 1; }
            btrfs subvolume create /mnt/@home || { log_fail "Failed creating subvolume @home"; exit 1; }
            btrfs subvolume create /mnt/@var_log || { log_fail "Failed creating subvolume @var_log"; exit 1; }
            btrfs subvolume create /mnt/@pkg || { log_fail "Failed creating subvolume @pkg"; exit 1; } # Pacman cache
            btrfs subvolume create /mnt/@snapshots || { log_fail "Failed creating subvolume @snapshots"; exit 1; } # For snapper/timeshift

            log_info "Unmounting Btrfs top-level volume..."
            umount /mnt || { log_fail "Unmounting Btrfs top-level failed"; exit 1; }

            log_info "Mounting Btrfs subvolumes..."
            mount -t btrfs -o "${btrfs_mount_opts},subvol=@" "$root_device" /mnt || { log_fail "Mounting @ failed"; exit 1; }
            # Create mount points for other subvolumes within the root subvolume mount
            mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,.snapshots} || { log_fail "Failed creating subvolume mountpoints"; exit 1; }
            mount -t btrfs -o "${btrfs_mount_opts},subvol=@home" "$root_device" /mnt/home || { log_fail "Mounting @home failed"; exit 1; }
            mount -t btrfs -o "${btrfs_mount_opts},subvol=@var_log" "$root_device" /mnt/var/log || { log_fail "Mounting @var_log failed"; exit 1; }
            mount -t btrfs -o "${btrfs_mount_opts},subvol=@pkg" "$root_device" /mnt/var/cache/pacman/pkg || { log_fail "Mounting @pkg failed"; exit 1; }
            mount -t btrfs -o "${btrfs_mount_opts},subvol=@snapshots" "$root_device" /mnt/.snapshots || { log_fail "Mounting @snapshots failed"; exit 1; }

            # Mount EFI partition inside the root mount
            mount "$ARCH_LINUX_BOOT_PARTITION" /mnt/boot || { log_fail "Mounting EFI partition failed"; exit 1; }
            log_info "Btrfs subvolumes mounted successfully."

        else # Default to ext4
            log_info "Formatting ${root_device} with Ext4..."
            mkfs.ext4 -F -L ROOT "$root_device" || { log_fail "mkfs.ext4 failed"; exit 1; }
            log_info "Mounting Ext4 volume..."
            mount "$root_device" /mnt || { log_fail "Mounting ext4 root failed"; exit 1; }
            mkdir -p /mnt/boot || { log_fail "Creating /mnt/boot failed"; exit 1; }
            mount "$ARCH_LINUX_BOOT_PARTITION" /mnt/boot || { log_fail "Mounting EFI partition failed"; exit 1; }
            log_info "Ext4 volume mounted successfully."
        fi
        # --- End Filesystem Specific ---

        # Return success
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_capture $! "$process_name"
}

# ---------------------------------------------------------------------------------------------------

exec_pacstrap_core() {
    local process_name="Pacstrap Arch Linux Core"
    process_init "$process_name"
    (
        [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return

        # Core packages (btrfs-progs is usually in base, but ensuring it)
        local packages=("$ARCH_LINUX_KERNEL" base sudo linux-firmware zram-generator networkmanager)
        [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && packages+=(btrfs-progs) # Ensure btrfs tools are installed

        # Add microcode package
        [ -n "$ARCH_LINUX_MICROCODE" ] && [ "$ARCH_LINUX_MICROCODE" != "none" ] && packages+=("$ARCH_LINUX_MICROCODE")

        # Install core packages and initialize an empty pacman keyring in the target
        log_info "Running pacstrap with packages: ${packages[*]}"
        pacstrap -K /mnt "${packages[@]}" || { log_fail "Pacstrap failed"; exit 1; }

        # Generate /etc/fstab (should work correctly for btrfs subvolumes now)
        log_info "Generating fstab..."
        genfstab -U /mnt >>/mnt/etc/fstab || { log_fail "genfstab failed"; exit 1; }
        # Optional: Add 'autodefrag' for Btrfs on non-SSD mounts if desired (careful with SSDs)
        # if [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ]; then
        #    sed -i '/btrfs/s/defaults/defaults,autodefrag/' /mnt/etc/fstab
        # fi

        # Set timezone & system clock
        log_info "Setting timezone and clock..."
        arch-chroot /mnt ln -sf "/usr/share/zoneinfo/${ARCH_LINUX_TIMEZONE}" /etc/localtime || { log_fail "Failed to set timezone link"; exit 1; }
        arch-chroot /mnt hwclock --systohc || { log_warn "hwclock --systohc failed"; } # Usually not critical

        # Create swap (zram-generator with zstd compression)
        log_info "Configuring zram..."
        {
            echo '[zram0]'
            echo 'zram-size = min(ram / 2, 4096)' # Consider making this configurable or smarter
            echo 'compression-algorithm = zstd'
        } >/mnt/etc/systemd/zram-generator.conf || { log_fail "Failed writing zram config"; exit 1; }
        { # Optimize swap on zram
            echo 'vm.swappiness = 180'
            echo 'vm.watermark_boost_factor = 0'
            echo 'vm.watermark_scale_factor = 125'
            echo 'vm.page-cluster = 0'
        } >/mnt/etc/sysctl.d/99-vm-zram-parameters.conf || { log_fail "Failed writing zram sysctl params"; exit 1; }

        # Set console keymap in /etc/vconsole.conf
        log_info "Setting vconsole keymap..."
        echo "KEYMAP=$ARCH_LINUX_VCONSOLE_KEYMAP" >/mnt/etc/vconsole.conf || { log_fail "Failed writing vconsole.conf"; exit 1; }
        [ -n "$ARCH_LINUX_VCONSOLE_FONT" ] && echo "FONT=$ARCH_LINUX_VCONSOLE_FONT" >>/mnt/etc/vconsole.conf

        # Set & Generate Locale
        log_info "Setting and generating locale..."
        echo "LANG=${ARCH_LINUX_LOCALE_LANG}.UTF-8" >/mnt/etc/locale.conf || { log_fail "Failed writing locale.conf"; exit 1; }
        for ((i = 0; i < ${#ARCH_LINUX_LOCALE_GEN_LIST[@]}; i++)); do
             sed -i "s/^#\(${ARCH_LINUX_LOCALE_GEN_LIST[$i]}\)/\1/g" "/mnt/etc/locale.gen" || log_warn "Failed to uncomment locale ${ARCH_LINUX_LOCALE_GEN_LIST[$i]}"
        done
        arch-chroot /mnt locale-gen || { log_fail "locale-gen failed"; exit 1; }

        # Set hostname & hosts
        log_info "Setting hostname and hosts file..."
        echo "$ARCH_LINUX_HOSTNAME" >/mnt/etc/hostname || { log_fail "Failed writing hostname"; exit 1; }
        {
            echo '# <ip>     <hostname.domain.org>  <hostname>'
            echo '127.0.0.1  localhost.localdomain  localhost'
            echo '::1        localhost.localdomain  localhost'
            # Add the new hostname
            echo "127.0.1.1  ${ARCH_LINUX_HOSTNAME}.localdomain ${ARCH_LINUX_HOSTNAME}"
        } >/mnt/etc/hosts || { log_fail "Failed writing hosts file"; exit 1; }

        # --- mkinitcpio HOOKS Setup ---
        # Base hooks common to both ext4 and btrfs
        local mkinitcpio_hooks="base systemd keyboard autodetect modconf block filesystems fsck"
        # Add sd-vconsole if console font is set
        [ -n "$ARCH_LINUX_VCONSOLE_FONT" ] && mkinitcpio_hooks="base systemd keyboard autodetect sd-vconsole modconf block filesystems fsck"
        # Add encryption hook if enabled
        [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && mkinitcpio_hooks="base systemd keyboard autodetect modconf block sd-encrypt filesystems fsck"
        [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && [ -n "$ARCH_LINUX_VCONSOLE_FONT" ] && mkinitcpio_hooks="base systemd keyboard autodetect sd-vconsole modconf block sd-encrypt filesystems fsck"
        # Add microcode hook (always)
        mkinitcpio_hooks=$(echo "$mkinitcpio_hooks" | sed 's/autodetect/autodetect microcode/')
        # Note: Plymouth hook is added later in exec_install_bootsplash if enabled

        log_info "Setting mkinitcpio HOOKS: $mkinitcpio_hooks"
        sed -i "s/^HOOKS=(.*)$/HOOKS=($mkinitcpio_hooks)/" /mnt/etc/mkinitcpio.conf || { log_fail "Failed to set mkinitcpio hooks"; exit 1; }
        # --- End mkinitcpio HOOKS Setup ---

        # Create initial ramdisk (Plymouth will trigger another rebuild later if enabled)
        log_info "Generating initial ramdisk (mkinitcpio -P)..."
        arch-chroot /mnt mkinitcpio -P || { log_fail "mkinitcpio -P failed"; exit 1; }

        # Install Bootloader to /boot (systemdboot)
        log_info "Installing systemd-boot..."
        arch-chroot /mnt bootctl --esp-path=/boot install || { log_fail "bootctl install failed"; exit 1; }

        # --- Kernel args ---
        log_info "Configuring bootloader entries..."
        local kernel_args=()
        # Root device definition
        if [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ]; then
            local luks_uuid
            luks_uuid=$(blkid -s UUID -o value "${ARCH_LINUX_ROOT_PARTITION}") || { log_fail "Failed getting LUKS UUID"; exit 1; }
            kernel_args+=("rd.luks.name=${luks_uuid}=cryptroot" "root=/dev/mapper/cryptroot")
        else
             local part_uuid
             part_uuid=$(blkid -s PARTUUID -o value "${ARCH_LINUX_ROOT_PARTITION}") || { log_fail "Failed getting PARTUUID"; exit 1; }
             kernel_args+=("root=PARTUUID=${part_uuid}")
        fi
        # Filesystem specific root flags
        [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && kernel_args+=("rootflags=subvol=@") # For btrfs root subvolume
        # Common options
        kernel_args+=('rw' 'init=/usr/lib/systemd/systemd' 'zswap.enabled=0') # Disable zswap when using zram
        # Nvidia Early KMS flag
        [ "$ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER" = "nvidia" ] && kernel_args+=("nvidia_drm.modeset=1")
        # Tweaks and silent boot options
        [ "$ARCH_LINUX_CORE_TWEAKS_ENABLED" = "true" ] && kernel_args+=('nowatchdog')
        [ "$ARCH_LINUX_BOOTSPLASH_ENABLED" = "true" ] || [ "$ARCH_LINUX_CORE_TWEAKS_ENABLED" = "true" ] && kernel_args+=('quiet' 'splash' 'vt.global_cursor_default=0')
        log_info "Kernel parameters: ${kernel_args[*]}"
        # --- End Kernel args ---

        # Create Bootloader config
        {
            echo 'default arch.conf'
            echo 'console-mode auto'
            echo 'timeout 3' # Slightly increased timeout
            echo 'editor yes'
        } >/mnt/boot/loader/loader.conf || { log_fail "Failed writing loader.conf"; exit 1; }

        # Create default boot entry
        {
            echo 'title   Arch Linux'
            echo "linux   /vmlinuz-${ARCH_LINUX_KERNEL}"
            [ -n "$ARCH_LINUX_MICROCODE" ] && [ "$ARCH_LINUX_MICROCODE" != "none" ] && echo "initrd  /${ARCH_LINUX_MICROCODE}.img"
            echo "initrd  /initramfs-${ARCH_LINUX_KERNEL}.img"
            echo "options ${kernel_args[*]}"
        } >/mnt/boot/loader/entries/arch.conf || { log_fail "Failed writing arch.conf"; exit 1; }

        # Create fallback boot entry
        {
            echo 'title   Arch Linux (Fallback)'
            echo "linux   /vmlinuz-${ARCH_LINUX_KERNEL}"
             [ -n "$ARCH_LINUX_MICROCODE" ] && [ "$ARCH_LINUX_MICROCODE" != "none" ] && echo "initrd  /${ARCH_LINUX_MICROCODE}.img"
            echo "initrd  /initramfs-${ARCH_LINUX_KERNEL}-fallback.img"
            echo "options ${kernel_args[*]}"
        } >/mnt/boot/loader/entries/arch-fallback.conf || { log_fail "Failed writing arch-fallback.conf"; exit 1; }

        # Create new user
        log_info "Creating user ${ARCH_LINUX_USERNAME}..."
        arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$ARCH_LINUX_USERNAME" || { log_fail "useradd failed"; exit 1; }

        # Create user dirs (redundant with useradd -m, but ensures .config/.local exist)
        mkdir -p "/mnt/home/${ARCH_LINUX_USERNAME}/.config"
        mkdir -p "/mnt/home/${ARCH_LINUX_USERNAME}/.local/share"
        arch-chroot /mnt chown -R "$ARCH_LINUX_USERNAME":"$ARCH_LINUX_USERNAME" "/home/${ARCH_LINUX_USERNAME}"

        # Allow users in group wheel to use sudo
        log_info "Configuring sudo..."
        sed -i 's/^# \(%wheel ALL=(ALL:ALL) ALL\)/\1/' /mnt/etc/sudoers || log_warn "Failed to uncomment wheel group in sudoers"

        # Change passwords
        log_info "Setting passwords..."
        printf "%s\n%s" "${ARCH_LINUX_PASSWORD}" "${ARCH_LINUX_PASSWORD}" | arch-chroot /mnt passwd root || { log_fail "Failed setting root password"; exit 1; }
        printf "%s\n%s" "${ARCH_LINUX_PASSWORD}" "${ARCH_LINUX_PASSWORD}" | arch-chroot /mnt passwd "$ARCH_LINUX_USERNAME" || { log_fail "Failed setting user password"; exit 1; }

        # Enable services
        log_info "Enabling core system services..."
        arch-chroot /mnt systemctl enable NetworkManager.service || log_warn "Failed enabling NetworkManager"
        arch-chroot /mnt systemctl enable fstrim.timer || log_warn "Failed enabling fstrim.timer" # Only relevant for SSDs
        arch-chroot /mnt systemctl enable systemd-zram-setup@zram0.service || log_warn "Failed enabling zram"
        arch-chroot /mnt systemctl enable systemd-oomd.service || log_warn "Failed enabling oomd" # Requires swap
        arch-chroot /mnt systemctl enable systemd-boot-update.service || log_warn "Failed enabling boot-update"
        arch-chroot /mnt systemctl enable systemd-timesyncd.service || log_warn "Failed enabling timesyncd"

        # Make some Arch Linux tweaks
        if [ "$ARCH_LINUX_CORE_TWEAKS_ENABLED" = "true" ]; then
            log_info "Applying core tweaks..."
            # Add password feedback
            grep -q "Defaults pwfeedback" /mnt/etc/sudoers || echo -e "\n## Enable sudo password feedback\nDefaults pwfeedback" >>/mnt/etc/sudoers
            # Configure pacman parallel downloads, colors, eyecandy
            sed -i 's/^#\(ParallelDownloads\)/\1/' /mnt/etc/pacman.conf
            grep -q "ILoveCandy" /mnt/etc/pacman.conf || sed -i '/^#Color/a ILoveCandy' /mnt/etc/pacman.conf
            sed -i 's/^#\(Color\)/\1/' /mnt/etc/pacman.conf
            # Disable watchdog modules
            mkdir -p /mnt/etc/modprobe.d/
            echo 'blacklist sp5100_tco' >>/mnt/etc/modprobe.d/blacklist-watchdog.conf
            echo 'blacklist iTCO_wdt' >>/mnt/etc/modprobe.d/blacklist-watchdog.conf
            # Disable debug packages when using makepkg
            sed -i '/^OPTIONS=/s/debug/!debug/' /mnt/etc/makepkg.conf
            # Reduce shutdown timeout (Optional, can be aggressive)
            # sed -i "s/^\s*#\s*DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=10s/" /mnt/etc/systemd/system.conf
        fi

        # Return success
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_capture $! "$process_name"
}
# ---------------------------------------------------------------------------------------------------

exec_install_desktop() {
    local process_name="GNOME Desktop"
    if [ "$ARCH_LINUX_DESKTOP_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return

            local packages=()

            # GNOME base packages
            packages+=(gnome git)

            # GNOME desktop extras
            if [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ]; then

                # GNOME base extras (buggy: power-profiles-daemon)
                packages+=(gnome-browser-connector gnome-themes-extra tuned-ppd rygel cups gnome-epub-thumbnailer)

                # GNOME wayland screensharing, flatpak & pipewire support
                packages+=(xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome flatpak-xdg-utils)

                # Audio (Pipewire replacements + session manager): https://wiki.archlinux.org/title/PipeWire#Installation
                packages+=(pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-pipewire lib32-pipewire-jack)

                # Disabled because hardware-specific
                #packages+=(sof-firmware) # Need for intel i5 audio

                # Networking & Access
                packages+=(samba rsync gvfs gvfs-mtp gvfs-smb gvfs-nfs gvfs-afc gvfs-goa gvfs-gphoto2 gvfs-google gvfs-dnssd gvfs-wsdd)
                packages+=(modemmanager network-manager-sstp networkmanager-l2tp networkmanager-vpnc networkmanager-pptp networkmanager-openvpn networkmanager-openconnect networkmanager-strongswan)

                # Kernel headers
                packages+=("${ARCH_LINUX_KERNEL}-headers")

                # Utils (https://wiki.archlinux.org/title/File_systems)
                packages+=(base-devel archlinux-contrib pacutils fwupd bash-completion dhcp net-tools inetutils nfs-utils e2fsprogs f2fs-tools udftools dosfstools ntfs-3g exfat-utils btrfs-progs xfsprogs p7zip zip unzip unrar tar wget curl)
                packages+=(nautilus-image-converter)

                # Runtimes, Builder & Helper
                packages+=(gdb python go rust nodejs npm lua cmake jq zenity gum fzf)

                # Certificates
                packages+=(ca-certificates)

                # Codecs (https://wiki.archlinux.org/title/Codecs_and_containers)
                packages+=(ffmpeg ffmpegthumbnailer gstreamer gst-libav gst-plugin-pipewire gst-plugins-good gst-plugins-bad gst-plugins-ugly libdvdcss libheif webp-pixbuf-loader opus speex libvpx libwebp)
                packages+=(a52dec faac faad2 flac jasper lame libdca libdv libmad libmpeg2 libtheora libvorbis libxv wavpack x264 xvidcore libdvdnav libdvdread openh264)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-gstreamer lib32-gst-plugins-good lib32-libvpx lib32-libwebp)

                # Optimization
                packages+=(gamemode sdl_image)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-gamemode lib32-sdl_image)

            fi

            # Installing packages together (preventing conflicts e.g.: jack2 and piepwire-jack)
            chroot_pacman_install "${packages[@]}"

            # Force remove gnome packages
            if [ "$ARCH_LINUX_DESKTOP_SLIM_ENABLED" = "true" ]; then
                chroot_pacman_remove gnome-calendar || true
                chroot_pacman_remove gnome-maps || true
                chroot_pacman_remove gnome-contacts || true
                chroot_pacman_remove gnome-font-viewer || true
                chroot_pacman_remove gnome-characters || true
                chroot_pacman_remove gnome-clocks || true
                chroot_pacman_remove gnome-connections || true
                chroot_pacman_remove gnome-music || true
                chroot_pacman_remove gnome-weather || true
                chroot_pacman_remove gnome-calculator || true
                chroot_pacman_remove gnome-logs || true
                chroot_pacman_remove gnome-text-editor || true
                chroot_pacman_remove gnome-disk-utility || true
                chroot_pacman_remove simple-scan || true
                chroot_pacman_remove baobab || true
                chroot_pacman_remove totem || true
                chroot_pacman_remove snapshot || true
                chroot_pacman_remove epiphany || true
                chroot_pacman_remove loupe || true
                chroot_pacman_remove decibels || true
                #chroot_pacman_remove evince || true # Need for sushi
            fi

            # Add user to other useful groups (https://wiki.archlinux.org/title/Users_and_groups#User_groups)
            arch-chroot /mnt groupadd -f plugdev
            arch-chroot /mnt usermod -aG adm,audio,video,optical,input,tty,plugdev "$ARCH_LINUX_USERNAME"

            # Add user to gamemode group
            [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ] && arch-chroot /mnt gpasswd -a "$ARCH_LINUX_USERNAME" gamemode

            # Enable GNOME auto login
            mkdir -p /mnt/etc/gdm
            # grep -qrnw /mnt/etc/gdm/custom.conf -e "AutomaticLoginEnable" || sed -i "s/^\[security\]/AutomaticLoginEnable=True\nAutomaticLogin=${ARCH_LINUX_USERNAME}\n\n\[security\]/g" /mnt/etc/gdm/custom.conf
            {
                echo "[daemon]"
                echo "WaylandEnable=True"
                echo ""
                echo "AutomaticLoginEnable=True"
                echo "AutomaticLogin=${ARCH_LINUX_USERNAME}"
                echo ""
                echo "[debug]"
                echo "Enable=False"
            } >/mnt/etc/gdm/custom.conf

            # Set git-credential-libsecret in ~/.gitconfig
            arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- git config --global credential.helper /usr/lib/git-core/git-credential-libsecret

            # GnuPG integration (https://wiki.archlinux.org/title/GNOME/Keyring#GnuPG_integration)
            mkdir -p "/mnt/home/${ARCH_LINUX_USERNAME}/.gnupg"
            echo 'pinentry-program /usr/bin/pinentry-gnome3' >"/mnt/home/${ARCH_LINUX_USERNAME}/.gnupg/gpg-agent.conf"

            # Set environment
            mkdir -p "/mnt/home/${ARCH_LINUX_USERNAME}/.config/environment.d/"
            # shellcheck disable=SC2016
            {
                echo '# SSH AGENT'
                echo 'SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/gcr/ssh' # Set gcr sock (https://wiki.archlinux.org/title/GNOME/Keyring#Setup_gcr)
                echo ''
                echo '# PATH'
                echo 'PATH="${PATH}:${HOME}/.local/bin"'
                echo ''
                echo '# XDG'
                echo 'XDG_CONFIG_HOME="${HOME}/.config"'
                echo 'XDG_DATA_HOME="${HOME}/.local/share"'
                echo 'XDG_STATE_HOME="${HOME}/.local/state"'
                echo 'XDG_CACHE_HOME="${HOME}/.cache"                '
            } >"/mnt/home/${ARCH_LINUX_USERNAME}/.config/environment.d/00-arch.conf"

            # shellcheck disable=SC2016
            {
                echo '# Workaround for Flatpak aliases'
                echo 'PATH="${PATH}:/var/lib/flatpak/exports/bin"'
            } >"/mnt/home/${ARCH_LINUX_USERNAME}/.config/environment.d/99-flatpak.conf"
         
            # Set X11 keyboard layout in /etc/X11/xorg.conf.d/00-keyboard.conf
            mkdir -p /mnt/etc/X11/xorg.conf.d/
            {
                echo 'Section "InputClass"'
                echo '    Identifier "system-keyboard"'
                echo '    MatchIsKeyboard "yes"'
                echo '    Option "XkbLayout" "'"${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT}"'"'
                echo '    Option "XkbModel" "'"${ARCH_LINUX_DESKTOP_KEYBOARD_MODEL}"'"'
                echo '    Option "XkbVariant" "'"${ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT}"'"'
                echo 'EndSection'
            } >/mnt/etc/X11/xorg.conf.d/00-keyboard.conf

            # Enable Arch Linux Desktop services
            arch-chroot /mnt systemctl enable gdm.service       # GNOME
            arch-chroot /mnt systemctl enable bluetooth.service # Bluetooth
            arch-chroot /mnt systemctl enable avahi-daemon      # Network browsing service
            arch-chroot /mnt systemctl enable gpm.service       # TTY Mouse Support

            # Extra services
            if [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
                arch-chroot /mnt systemctl enable tuned       # Power daemon
                arch-chroot /mnt systemctl enable tuned-ppd   # Power daemon
                arch-chroot /mnt systemctl enable cups.socket # Printer
            fi

            # User services (Not working: Failed to connect to user scope bus via local transport: Permission denied)
            # arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- systemctl enable --user pipewire.service       # Pipewire
            # arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- systemctl enable --user pipewire-pulse.service # Pipewire
            # arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- systemctl enable --user wireplumber.service    # Pipewire
            # arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- systemctl enable --user gcr-ssh-agent.socket   # GCR ssh-agent

            # Workaround: Manual creation of user service symlinks
            arch-chroot /mnt mkdir -p "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/default.target.wants"
            arch-chroot /mnt ln -s "/usr/lib/systemd/user/pipewire.service" "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/default.target.wants/pipewire.service"
            arch-chroot /mnt ln -s "/usr/lib/systemd/user/pipewire-pulse.service" "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/default.target.wants/pipewire-pulse.service"
            arch-chroot /mnt mkdir -p "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/sockets.target.wants"
            arch-chroot /mnt ln -s "/usr/lib/systemd/user/pipewire.socket" "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/sockets.target.wants/pipewire.socket"
            arch-chroot /mnt ln -s "/usr/lib/systemd/user/pipewire-pulse.socket" "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/sockets.target.wants/pipewire-pulse.socket"
            arch-chroot /mnt ln -s "/usr/lib/systemd/user/gcr-ssh-agent.socket" "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/sockets.target.wants/gcr-ssh-agent.socket"
            arch-chroot /mnt mkdir -p "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/pipewire.service.wants"
            arch-chroot /mnt ln -s "/usr/lib/systemd/user/wireplumber.service" "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/pipewire-session-manager.service"
            arch-chroot /mnt ln -s "/usr/lib/systemd/user/wireplumber.service" "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/pipewire.service.wants/wireplumber.service"
            arch-chroot /mnt chown -R "$ARCH_LINUX_USERNAME":"$ARCH_LINUX_USERNAME" "/home/${ARCH_LINUX_USERNAME}/.config/systemd/"

            # Enhance PAM (fix keyring issue for relogin): add try_first_pass
            sed -i 's/auth\s\+optional\s\+pam_gnome_keyring\.so$/& try_first_pass/' /mnt/etc/pam.d/gdm-password /mnt/etc/pam.d/gdm-autologin

            # Create users applications dir
            mkdir -p "/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications"

            # Create UEFI Boot desktop entry
            # {
            #    echo '[Desktop Entry]'
            #    echo 'Name=Reboot to UEFI'
            #    echo 'Icon=system-reboot'
            #    echo 'Exec=systemctl reboot --firmware-setup'
            #    echo 'Type=Application'
            #    echo 'Terminal=false'
            # } >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/systemctl-reboot-firmware.desktop"

            # Hide aplications desktop icons
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/bssh.desktop"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/bvnc.desktop"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/avahi-discover.desktop"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/qv4l2.desktop"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/qvidcap.desktop"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/lstopo.desktop"

            # Hide aplications (extra) desktop icons
            if [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
                echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/stoken-gui.desktop"       # networkmanager-openconnect
                echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/stoken-gui-small.desktop" # networkmanager-openconnect
                echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/cups.desktop"
                echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/tuned-gui.desktop"
                echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/cmake-gui.desktop"
            fi

            # Add Init script
            if [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
                {
                    echo "# exec_install_desktop | Favorite apps"
                    echo "gsettings set org.gnome.shell favorite-apps \"['org.gnome.Console.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Software.desktop', 'org.gnome.Settings.desktop']\""
                    echo "# exec_install_desktop | Reset app-folders"
                    echo "dconf reset -f /org/gnome/desktop/app-folders/"
                    echo "# exec_install_desktop | Show all input sources"
                    echo "gsettings set org.gnome.desktop.input-sources show-all-sources true"
                    echo "# exec_install_desktop | Mutter settings"
                    echo "gsettings set org.gnome.mutter center-new-windows true"
                    echo "# exec_install_desktop | File chooser settings"
                    echo "gsettings set org.gtk.Settings.FileChooser sort-directories-first true"
                    echo "gsettings set org.gtk.gtk4.Settings.FileChooser sort-directories-first true"
                } >>"/mnt/home/${ARCH_LINUX_USERNAME}/${INIT_FILENAME}.sh"
            fi

            # Set correct permissions
            arch-chroot /mnt chown -R "$ARCH_LINUX_USERNAME":"$ARCH_LINUX_USERNAME" "/home/${ARCH_LINUX_USERNAME}"

            # Return
            process_return 0
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_graphics_driver() {
    local process_name="Desktop Driver"
    if [ -n "$ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER" ] && [ "$ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER" != "none" ]; then
        process_init "$process_name"
        (
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return
            case "${ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER}" in
            "mesa") # https://wiki.archlinux.org/title/OpenGL#Installation
                local packages=(mesa mesa-utils vkd3d vulkan-tools)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-mesa lib32-mesa-utils lib32-vkd3d)
                chroot_pacman_install "${packages[@]}"
                ;;
            "intel_i915") # https://wiki.archlinux.org/title/Intel_graphics#Installation
                local packages=(vulkan-intel vkd3d libva-intel-driver vulkan-tools)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-vulkan-intel lib32-vkd3d lib32-libva-intel-driver)
                chroot_pacman_install "${packages[@]}"
                sed -i "s/^MODULES=(.*)/MODULES=(i915)/g" /mnt/etc/mkinitcpio.conf
                arch-chroot /mnt mkinitcpio -P
                ;;
            "nvidia") # https://wiki.archlinux.org/title/NVIDIA#Installation
                local packages=("${ARCH_LINUX_KERNEL}-headers" nvidia-dkms nvidia-settings nvidia-utils opencl-nvidia vkd3d vulkan-tools)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-nvidia-utils lib32-opencl-nvidia lib32-vkd3d)
                chroot_pacman_install "${packages[@]}"
                # https://wiki.archlinux.org/title/NVIDIA#DRM_kernel_mode_setting
                # Alternative (slow boot, bios logo twice, but correct plymouth resolution):
                #sed -i "s/systemd zswap.enabled=0/systemd nvidia_drm.modeset=1 nvidia_drm.fbdev=1 zswap.enabled=0/g" /mnt/boot/loader/entries/arch.conf
                mkdir -p /mnt/etc/modprobe.d/ && echo -e 'options nvidia_drm modeset=1 fbdev=1' >/mnt/etc/modprobe.d/nvidia.conf
                sed -i "s/^MODULES=(.*)/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/g" /mnt/etc/mkinitcpio.conf
                # https://wiki.archlinux.org/title/NVIDIA#pacman_hook
                mkdir -p /mnt/etc/pacman.d/hooks/
                {
                    echo "[Trigger]"
                    echo "Operation=Install"
                    echo "Operation=Upgrade"
                    echo "Operation=Remove"
                    echo "Type=Package"
                    echo "Target=nvidia"
                    echo "Target=${ARCH_LINUX_KERNEL}"
                    echo "# Change the linux part above if a different kernel is used"
                    echo ""
                    echo "[Action]"
                    echo "Description=Update NVIDIA module in initcpio"
                    echo "Depends=mkinitcpio"
                    echo "When=PostTransaction"
                    echo "NeedsTargets"
                    echo "Exec=/bin/sh -c 'while read -r trg; do case \$trg in linux*) exit 0; esac; done; /usr/bin/mkinitcpio -P'"
                } >/mnt/etc/pacman.d/hooks/nvidia.hook
                # Enable Wayland Support (https://wiki.archlinux.org/title/GDM#Wayland_and_the_proprietary_NVIDIA_driver)
                [ ! -f /mnt/etc/udev/rules.d/61-gdm.rules ] && mkdir -p /mnt/etc/udev/rules.d/ && ln -s /dev/null /mnt/etc/udev/rules.d/61-gdm.rules
                # Rebuild initial ram disk
                arch-chroot /mnt mkinitcpio -P
                ;;
            "amd") # https://wiki.archlinux.org/title/AMDGPU#Installation
                # Deprecated: libva-mesa-driver lib32-libva-mesa-driver mesa-vdpau lib32-mesa-vdpau
                local packages=(mesa mesa-utils xf86-video-amdgpu vulkan-radeon vkd3d vulkan-tools)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-mesa lib32-vulkan-radeon lib32-vkd3d)
                chroot_pacman_install "${packages[@]}"
                # Must be discussed: https://wiki.archlinux.org/title/AMDGPU#Disable_loading_radeon_completely_at_boot
                sed -i "s/^MODULES=(.*)/MODULES=(amdgpu)/g" /mnt/etc/mkinitcpio.conf
                arch-chroot /mnt mkinitcpio -P
                ;;
            "ati") # https://wiki.archlinux.org/title/ATI#Installation
                # Deprecated: libva-mesa-driver lib32-libva-mesa-driver mesa-vdpau lib32-mesa-vdpau
                local packages=(mesa mesa-utils xf86-video-ati vkd3d vulkan-tools)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-mesa lib32-vkd3d)
                chroot_pacman_install "${packages[@]}"
                sed -i "s/^MODULES=(.*)/MODULES=(radeon)/g" /mnt/etc/mkinitcpio.conf
                arch-chroot /mnt mkinitcpio -P
                ;;
            esac
            process_return 0
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_enable_multilib() {
    local process_name="Enable Multilib"
    if [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return
            sed -i '/\[multilib\]/,/Include/s/^#//' /mnt/etc/pacman.conf
            arch-chroot /mnt pacman -Syyu --noconfirm
            process_return 0
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_bootsplash() {
    local process_name="Bootsplash"
    if [ "$ARCH_LINUX_BOOTSPLASH_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0
            log_info "Installing Plymouth packages..."
            chroot_pacman_install plymouth git base-devel || { log_fail "Failed to install plymouth packages"; exit 1; }

            # --- Более надежное добавление хука plymouth ---
            log_info "Adding plymouth hook to mkinitcpio.conf..."
            local mkinitcpio_conf="/mnt/etc/mkinitcpio.conf"
            local current_hooks_line
            current_hooks_line=$(grep '^HOOKS=' "$mkinitcpio_conf") || { log_fail "Could not find HOOKS line in $mkinitcpio_conf"; exit 1; }
            local current_hooks
            current_hooks=$(echo "$current_hooks_line" | sed 's/HOOKS=(\(.*\))/\1/')

            # Определить, после какого хука вставить plymouth
            local insert_after="block"
            # Если есть sd-encrypt, вставляем после него
            [[ $current_hooks == *"sd-encrypt"* ]] && insert_after="sd-encrypt"

            # Сформировать новые хуки, если plymouth еще не добавлен
            local new_hooks="$current_hooks"
            if [[ $current_hooks != *"plymouth"* ]]; then
                # Используем awk для вставки после нужного хука
                 new_hooks=$(echo "$current_hooks" | awk -v hook_to_add="plymouth" -v after_hook="$insert_after" '{
                    output="";
                    for (i=1; i<=NF; i++) {
                        output = output $i " ";
                        if ($i == after_hook) {
                            output = output hook_to_add " ";
                        }
                    }
                    # Убираем лишний пробел в конце
                    sub(/ $/, "", output);
                    print output;
                }')
                log_info "New hooks string: $new_hooks"
                 # Заменить старую строку HOOKS на новую
                sed -i "s/^HOOKS=.*/HOOKS=($new_hooks)/" "$mkinitcpio_conf" || { log_fail "Failed to update HOOKS in $mkinitcpio_conf"; exit 1; }
                log_info "Successfully added plymouth hook after $insert_after."
            else
                 log_warn "Plymouth hook already present in $mkinitcpio_conf."
            fi
            # --- Конец надежного добавления хука ---

            # Установить тему и пересобрать initramfs (флаг -R делает это)
            log_info "Setting Plymouth theme to bgrt and rebuilding initramfs..."
            arch-chroot /mnt plymouth-set-default-theme -R bgrt || { log_fail "Failed to set Plymouth theme or rebuild initramfs"; exit 1; }

            process_return 0
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_aur_helper() {
    local process_name="AUR Helper"
    if [ -n "$ARCH_LINUX_AUR_HELPER" ] && [ "$ARCH_LINUX_AUR_HELPER" != "none" ]; then
        process_init "$process_name"
        (
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return
            chroot_pacman_install git base-devel                 # Install packages
            chroot_aur_install "$ARCH_LINUX_AUR_HELPER"             # Install AUR helper
            # Paru config
            if [ "$ARCH_LINUX_AUR_HELPER" = "paru" ] || [ "$ARCH_LINUX_AUR_HELPER" = "paru-bin" ] || [ "$ARCH_LINUX_AUR_HELPER" = "paru-git" ]; then
                sed -i 's/^#BottomUp/BottomUp/g' /mnt/etc/paru.conf
                sed -i 's/^#SudoLoop/SudoLoop/g' /mnt/etc/paru.conf
            fi
            process_return 0 # Return
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_housekeeping() {
    local process_name="Housekeeping"
    if [ "$ARCH_LINUX_HOUSEKEEPING_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0
            log_info "Installing housekeeping packages..."
            chroot_pacman_install pacman-contrib reflector pkgfile smartmontools irqbalance || { log_fail "Failed installing housekeeping packages"; exit 1; }

            log_info "Configuring reflector..."
            mkdir -p /mnt/etc/xdg/reflector # Ensure directory exists
            {
                echo "# Reflector configuration generated by Archlyze installer"
                echo "# Documentation: man reflector"
                echo ""
                echo "# --save: Path where the mirrorlist will be saved"
                echo "--save /etc/pacman.d/mirrorlist"
                echo ""
                # Use selected countries (comma-separated) or global if empty
                if [ -n "$ARCH_LINUX_REFLECTOR_COUNTRY" ]; then
                    echo "# --country: Restrict mirrors to selected countries"
                    echo "--country ${ARCH_LINUX_REFLECTOR_COUNTRY}"
                else
                    echo "# --country: Not specified, using global mirrors"
                fi
                echo ""
                echo "# --protocol: Specify protocols (https is recommended)"
                echo "--protocol https"
                echo ""
                echo "# --age: Maximum age of mirrors in hours"
                echo "--age 12"
                echo ""
                echo "# --latest: Number of recently synchronized mirrors to select"
                echo "--latest 20" # <-- Увеличено до 20
                echo ""
                echo "# --sort: Sort mirrors by 'rate', 'age', 'score', etc."
                echo "--sort rate"
                # echo ""
                # echo "# Optional: Add download speed test (--download-timeout, --fastest)"
                # echo "--download-timeout 5"
                # echo "--fastest 10" # Select 10 fastest from the initially sorted list
            } >/mnt/etc/xdg/reflector/reflector.conf || { log_fail "Failed writing reflector config"; exit 1; }

            log_info "Enabling housekeeping services/timers..."
            # Enable reflector timer (recommended over service)
            arch-chroot /mnt systemctl enable reflector.timer || log_warn "Failed enabling reflector.timer"
            # Enable paccache timer for cleaning package cache
            arch-chroot /mnt systemctl enable paccache.timer || log_warn "Failed enabling paccache.timer"
            # Enable pkgfile timer for updating pkgfile database
            arch-chroot /mnt systemctl enable pkgfile-update.timer || log_warn "Failed enabling pkgfile-update.timer"
            # Enable SMART monitoring daemon
            arch-chroot /mnt systemctl enable smartd.service || log_warn "Failed enabling smartd.service"
            # Enable IRQ balancing daemon
            arch-chroot /mnt systemctl enable irqbalance.service || log_warn "Failed enabling irqbalance.service"

            process_return 0
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_vm_support() {
    local process_name="VM Support"
    if [ "$ARCH_LINUX_VM_SUPPORT_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return
            case $(systemd-detect-virt || true) in
            kvm)
                log_info "KVM detected"
                chroot_pacman_install spice spice-vdagent spice-protocol spice-gtk qemu-guest-agent
                arch-chroot /mnt systemctl enable qemu-guest-agent
                ;;
            vmware)
                log_info "VMWare Workstation/ESXi detected"
                chroot_pacman_install open-vm-tools
                arch-chroot /mnt systemctl enable vmtoolsd
                arch-chroot /mnt systemctl enable vmware-vmblock-fuse
                ;;
            oracle)
                log_info "VirtualBox detected"
                chroot_pacman_install virtualbox-guest-utils
                arch-chroot /mnt systemctl enable vboxservice
                ;;
            microsoft)
                log_info "Hyper-V detected"
                chroot_pacman_install hyperv
                arch-chroot /mnt systemctl enable hv_fcopy_daemon
                arch-chroot /mnt systemctl enable hv_kvp_daemon
                arch-chroot /mnt systemctl enable hv_vss_daemon
                ;;
            *) log_info "No VM detected" ;; # Do nothing
            esac
            process_return 0 # Return
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

# shellcheck disable=SC2016
exec_finalize_arch_linux() {
    local process_name="Finalize Arch Linux"
    local init_script_path="/mnt/home/${ARCH_LINUX_USERNAME}/${INIT_FILENAME}.sh"
    # Используем имя хоста для создания уникального каталога инициализации
    # Добавляем . и _init для скрытия и ясности назначения
    local init_dir_name=".${ARCH_LINUX_HOSTNAME}_init"
    local init_dir_path="/mnt/home/${ARCH_LINUX_USERNAME}/${init_dir_name}"
    local target_script_path="${init_dir_path}/${INIT_FILENAME}.sh"
    local target_log_path="${init_dir_path}/${INIT_FILENAME}.log"
    local autostart_dir="/mnt/home/${ARCH_LINUX_USERNAME}/.config/autostart"
    local autostart_file="${autostart_dir}/${INIT_FILENAME}.desktop"

    # Проверяем, существует ли исходный скрипт инициализации
    if [ -s "$init_script_path" ]; then
        process_init "$process_name"
        (
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return

            log_info "Creating initialization directory: ${init_dir_path}"
            mkdir -p "${init_dir_path}" || { log_fail "Failed creating init directory ${init_dir_path}"; exit 1; }
            log_info "Creating autostart directory: ${autostart_dir}"
            mkdir -p "${autostart_dir}" || { log_fail "Failed creating autostart directory ${autostart_dir}"; exit 1; }

            log_info "Moving initialization script to ${target_script_path}"
            mv "$init_script_path" "$target_script_path" || { log_fail "Failed moving init script"; exit 1; }

            # Modify the target script
            log_info "Modifying initialization script..."
            # Add version env
            sed -i "1i\ARCH_LINUX_VERSION=${VERSION}" "$target_script_path" || log_warn "Failed adding version to init script"
            # Add shebang
            sed -i '1i\#!/usr/bin/env bash' "$target_script_path" || log_warn "Failed adding shebang to init script"
            # Add autostart-remove command (referencing the correct autostart file path)
            {
                echo "" # Add newline for clarity
                echo "# exec_finalize_arch_linux | Remove autostart init file after execution"
                # Use quotes for the path in case hostname contains special chars
                echo "rm -f \"${autostart_file}\""
            } >>"$target_script_path" || log_warn "Failed adding autostart removal to init script"
            # Add Print initialized info command
            {
                echo "" # Add newline for clarity
                echo "# exec_finalize_arch_linux | Print initialized info to log"
                echo "echo \"\$(date '+%Y-%m-%d %H:%M:%S') | Arch Linux \${ARCH_LINUX_VERSION} | Post-install script executed successfully.\""
            } >>"$target_script_path" || log_warn "Failed adding final log message to init script"

            log_info "Setting execute permission on init script..."
            arch-chroot /mnt chmod +x "/home/${ARCH_LINUX_USERNAME}/${init_dir_name}/${INIT_FILENAME}.sh" || { log_fail "Failed chmod on init script"; exit 1; }

            # Create autostart desktop entry
            log_info "Creating autostart entry: ${autostart_file}"
            {
                echo "[Desktop Entry]"
                echo "Type=Application"
                echo "Name=Arch Linux Post-Install Setup" # More descriptive name
                echo "Icon=preferences-system"
                # Execute script and redirect output to its log file inside the specific directory
                # Use quotes for paths
                echo "Exec=bash -c '\"/home/${ARCH_LINUX_USERNAME}/${init_dir_name}/${INIT_FILENAME}.sh\" > \"/home/${ARCH_LINUX_USERNAME}/${init_dir_name}/${INIT_FILENAME}.log\" 2>&1'"
                echo "Terminal=false"
                echo "Hidden=false" # Should not be hidden initially
                echo "NoDisplay=true" # Hide from application menus, but allow autostart
                echo "X-GNOME-Autostart-enabled=true"
            } >"$autostart_file" || { log_fail "Failed creating autostart file"; exit 1; }

            # Set correct ownership for the user's home directory content we created/modified
            log_info "Setting final ownership for user's home directory..."
            arch-chroot /mnt chown -R "$ARCH_LINUX_USERNAME":"$ARCH_LINUX_USERNAME" "/home/${ARCH_LINUX_USERNAME}/${init_dir_name}" "/home/${ARCH_LINUX_USERNAME}/.config" || { log_fail "Final chown failed"; exit 1; }

            process_return 0 # Return success
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    else
        log_info "No initialization script found at ${init_script_path}, skipping finalization step."
    fi
}

# ---------------------------------------------------------------------------------------------------

# shellcheck disable=SC2016
exec_cleanup_installation() {
    local process_name="Cleanup Installation"
    process_init "$process_name"
    (
        [ "$DEBUG" = "true" ] && sleep 1 && process_return 0                                                  # If debug mode then return
        arch-chroot /mnt chown -R "$ARCH_LINUX_USERNAME":"$ARCH_LINUX_USERNAME" "/home/${ARCH_LINUX_USERNAME}"         # Set correct home permissions
        arch-chroot /mnt bash -c 'pacman -Qtd &>/dev/null && pacman -Rns --noconfirm $(pacman -Qtdq) || true' # Remove orphans and force return true
        process_return 0                                                                                      # Return
    ) &>"$PROCESS_LOG" &
    process_capture $! "$process_name"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# CHROOT HELPER
# ////////////////////////////////////////////////////////////////////////////////////////////////////

chroot_pacman_install() {
    local packages=("$@")
    local pacman_failed="true"
    # Retry installing packages 5 times (in case of connection issues)
    for ((i = 1; i < 6; i++)); do
        # Print log if greather than first try
        [ "$i" -gt 1 ] && log_warn "${i}. Retry Pacman installation..."
        # Try installing packages
        # if ! arch-chroot /mnt bash -c "yes | LC_ALL=en_US.UTF-8 pacman -S --needed --disable-download-timeout ${packages[*]}"; then
        if ! arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout "${packages[@]}"; then
            sleep 10 && continue # Wait 10 seconds & try again
        else
            pacman_failed="false" && break # Success: break loop
        fi
    done
    # Result
    [ "$pacman_failed" = "true" ] && return 1  # Failed after 5 retries
    [ "$pacman_failed" = "false" ] && return 0 # Success
}

chroot_aur_install() {

    # Vars
    local repo repo_url repo_tmp_dir aur_failed
    repo="$1" && repo_url="https://aur.archlinux.org/${repo}.git"

    # Disable sudo needs no password rights
    sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /mnt/etc/sudoers

    # Temp dir
    repo_tmp_dir=$(mktemp -u "/home/${ARCH_LINUX_USERNAME}/.tmp-aur-${repo}.XXXX")

    # Retry installing AUR 5 times (in case of connection issues)
    aur_failed="true"
    for ((i = 1; i < 6; i++)); do

        # Print log if greather than first try
        [ "$i" -gt 1 ] && log_warn "${i}. Retry AUR installation..."

        #  Try cloning AUR repo
        ! arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- bash -c "rm -rf ${repo_tmp_dir}; git clone ${repo_url} ${repo_tmp_dir}" && sleep 10 && continue

        # Add '!debug' option to PKGBUILD
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- bash -c "cd ${repo_tmp_dir} && echo -e \"\noptions=('!debug')\" >>PKGBUILD"

        # Try installing AUR
        if ! arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- bash -c "cd ${repo_tmp_dir} && makepkg -si --noconfirm --needed"; then
            sleep 10 && continue # Wait 10 seconds & try again
        else
            aur_failed="false" && break # Success: break loop
        fi
    done

    # Remove tmp dir
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- rm -rf "$repo_tmp_dir"

    # Enable sudo needs no password rights
    sed -i 's/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /mnt/etc/sudoers

    # Result
    [ "$aur_failed" = "true" ] && return 1  # Failed after 5 retries
    [ "$aur_failed" = "false" ] && return 0 # Success
}

chroot_pacman_remove() { arch-chroot /mnt pacman -Rn --noconfirm "$@" || return 1; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# TRAP FUNCTIONS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# shellcheck disable=SC2317
trap_error() {
    # If process calls this trap, write error to file to use in exit trap
    echo "Command '${BASH_COMMAND}' failed with exit code $? in function '${1}' (line ${2})" >"$ERROR_MSG"
}

# shellcheck disable=SC2317
trap_exit() {
    local result_code="$?"

    # Read error msg from file (written in error trap)
    local error && [ -f "$ERROR_MSG" ] && error="$(<"$ERROR_MSG")" && rm -f "$ERROR_MSG"

    # Cleanup
    unset ARCH_LINUX_PASSWORD
    rm -rf "$SCRIPT_TMP_DIR"

    # When ctrl + c pressed exit without other stuff below
    [ "$result_code" = "130" ] && gum_warn "Exit..." && {
        exit 1
    }

    # Check if failed and print error
    if [ "$result_code" -gt "0" ]; then
        [ -n "$error" ] && gum_fail "$error"            # Print error message (if exists)
        [ -z "$error" ] && gum_fail "An Error occurred" # Otherwise pint default error message
        gum_warn "See ${SCRIPT_LOG} for more information..."
        gum_confirm "Show Logs?" && gum pager --show-line-numbers <"$SCRIPT_LOG" # Ask for show logs?
    fi

    exit "$result_code" # Exit installer.sh
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PROCESS FUNCTIONS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

process_init() {
    [ -f "$PROCESS_RET" ] && gum_fail "${PROCESS_RET} already exists" && exit 1
    echo 1 >"$PROCESS_RET" # Init result with 1
    log_proc "${1}..."     # Log starting
}

process_capture() {
    local pid="$1"              # Set process pid
    local process_name="$2"     # Set process name
    local user_canceled="false" # Will set to true if user press ctrl + c

    # Show gum spinner until pid is not exists anymore and set user_canceled to true on failure
    gum_spin --title "${process_name}..." -- bash -c "while kill -0 $pid &> /dev/null; do sleep 1; done" || user_canceled="true"
    cat "$PROCESS_LOG" >>"$SCRIPT_LOG" # Write process log to logfile

    # When user press ctrl + c while process is running
    if [ "$user_canceled" = "true" ]; then
        kill -0 "$pid" &>/dev/null && pkill -P "$pid" &>/dev/null              # Kill process if running
        gum_fail "Process with PID ${pid} was killed by user" && trap_gum_exit # Exit with 130
    fi

    # Handle error while executing process
    [ ! -f "$PROCESS_RET" ] && gum_fail "${PROCESS_RET} not found (do not init process?)" && exit 1
    [ "$(<"$PROCESS_RET")" != "0" ] && gum_fail "${process_name} failed" && exit 1 # If process failed (result code 0 was not write in the end)

    # Finish
    rm -f "$PROCESS_RET"                 # Remove process result file
    gum_proc "${process_name}" "success" # Print process success
}

process_return() {
    # 1. Write from sub process 0 to file when succeed (at the end of the script part)
    # 2. Rread from parent process after sub process finished (0=success 1=failed)
    echo "$1" >"$PROCESS_RET"
    exit "$1"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# HELPER FUNCTIONS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

print_header() {
    local title="$1"
    clear && gum_purple '
 █████  ██████   ██████ ██   ██      ██████  ███████ 
██   ██ ██   ██ ██      ██   ██     ██    ██ ██      
███████ ██████  ██      ███████     ██    ██ ███████ 
██   ██ ██   ██ ██      ██   ██     ██    ██      ██ 
██   ██ ██   ██  ██████ ██   ██      ██████  ███████'
    local header_version="               v. ${VERSION}"
    [ "$DEBUG" = "true" ] && header_version="               d. ${VERSION}"
    gum_white --margin "1 0" --align left --bold "Welcome to ${title} ${header_version}"
    [ "$FORCE" = "true" ] && gum_red --bold "CAUTION: Force mode enabled. Cancel with: Ctrl + c" && echo
    return 0
}

print_filled_space() {
    local total="$1" && local text="$2" && local length="${#text}"
    [ "$length" -ge "$total" ] && echo "$text" && return 0
    local padding=$((total - length)) && printf '%s%*s\n' "$text" "$padding" ""
}

gum_init() {
    if [ ! -x ./gum ]; then
        clear && echo "Loading Arch Linux Installer..." # Loading
        local gum_url gum_path                       # Prepare URL with version os and arch
        # https://github.com/charmbracelet/gum/releases
        gum_url="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_$(uname -s)_$(uname -m).tar.gz"
        if ! curl -Lsf "$gum_url" >"${SCRIPT_TMP_DIR}/gum.tar.gz"; then echo "Error downloading ${gum_url}" && exit 1; fi
        if ! tar -xf "${SCRIPT_TMP_DIR}/gum.tar.gz" --directory "$SCRIPT_TMP_DIR"; then echo "Error extracting ${SCRIPT_TMP_DIR}/gum.tar.gz" && exit 1; fi
        gum_path=$(find "${SCRIPT_TMP_DIR}" -type f -executable -name "gum" -print -quit)
        [ -z "$gum_path" ] && echo "Error: 'gum' binary not found in '${SCRIPT_TMP_DIR}'" && exit 1
        if ! mv "$gum_path" ./gum; then echo "Error moving ${gum_path} to ./gum" && exit 1; fi
        if ! chmod +x ./gum; then echo "Error chmod +x ./gum" && exit 1; fi
    fi
}

gum() {
    if [ -n "$GUM" ] && [ -x "$GUM" ]; then
        "$GUM" "$@"
    else
        echo "Error: GUM='${GUM}' is not found or executable" >&2
        exit 1
    fi
}

trap_gum_exit() { exit 130; }
trap_gum_exit_confirm() { gum_confirm "Exit Installation?" && trap_gum_exit; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# GUM WRAPPER
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# Gum colors (https://github.com/muesli/termenv?tab=readme-ov-file#color-chart)
gum_white() { gum_style --foreground "$COLOR_WHITE" "${@}"; }
gum_purple() { gum_style --foreground "$COLOR_PURPLE" "${@}"; }
gum_yellow() { gum_style --foreground "$COLOR_YELLOW" "${@}"; }
gum_red() { gum_style --foreground "$COLOR_RED" "${@}"; }
gum_green() { gum_style --foreground "$COLOR_GREEN" "${@}"; }

# Gum prints
gum_title() { log_head "${*}" && gum join "$(gum_purple --bold "+ ")" "$(gum_purple --bold "${*}")"; }
gum_info() { log_info "$*" && gum join "$(gum_green --bold "• ")" "$(gum_white "${*}")"; }
gum_warn() { log_warn "$*" && gum join "$(gum_yellow --bold "• ")" "$(gum_white "${*}")"; }
gum_fail() { log_fail "$*" && gum join "$(gum_red --bold "• ")" "$(gum_white "${*}")"; }

# Gum wrapper
gum_style() { gum style "${@}"; }
gum_confirm() { gum confirm --prompt.foreground "$COLOR_PURPLE" "${@}"; }
gum_input() { gum input --placeholder "..." --prompt "> " --prompt.foreground "$COLOR_PURPLE" --header.foreground "$COLOR_PURPLE" "${@}"; }
gum_write() { gum write --prompt "> " --header.foreground "$COLOR_PURPLE" --show-cursor-line --char-limit 0 "${@}"; }
gum_choose() { gum choose --cursor "> " --header.foreground "$COLOR_PURPLE" --cursor.foreground "$COLOR_PURPLE" "${@}"; }
gum_filter() { gum filter --prompt "> " --indicator ">" --placeholder "Type to filter..." --height 8 --header.foreground "$COLOR_PURPLE" "${@}"; }
gum_spin() { gum spin --spinner line --title.foreground "$COLOR_PURPLE" --spinner.foreground "$COLOR_PURPLE" "${@}"; }

# Gum key & value
gum_proc() { log_proc "$*" && gum join "$(gum_green --bold "• ")" "$(gum_white --bold "$(print_filled_space 24 "${1}")")" "$(gum_white "  >  ")" "$(gum_green "${2}")"; }
gum_property() { log_prop "$*" && gum join "$(gum_green --bold "• ")" "$(gum_white "$(print_filled_space 24 "${1}")")" "$(gum_green --bold "  >  ")" "$(gum_white --bold "${2}")"; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# LOGGING WRAPPER
# ////////////////////////////////////////////////////////////////////////////////////////////////////

write_log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') | archlyze | ${*}" >>"$SCRIPT_LOG"; }
log_info() { write_log "INFO | ${*}"; }
log_warn() { write_log "WARN | ${*}"; }
log_fail() { write_log "FAIL | ${*}"; }
log_head() { write_log "HEAD | ${*}"; }
log_proc() { write_log "PROC | ${*}"; }
log_prop() { write_log "PROP | ${*}"; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# START MAIN
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main "$@"
