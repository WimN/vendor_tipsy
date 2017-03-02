# tipsy functions that extend build/envsetup.sh
function __print_tipsy_functions_help() {
cat <<EOF
Additional TipsyRoms functions:
- cout:            Changes directory to out.
- mmp:             Builds all of the modules in the current directory and pushes them to the device.
- mmap:            Builds all of the modules in the current directory and its dependencies, then pushes the package to the device.
- mmmp:            Builds all of the modules in the supplied directories and pushes them to the device.
- mms:             Short circuit builder. Quickly re-build the kernel, rootfs, boot and system images
                   without deep dependencies. Requires the full build to have run before.
- cmremote:        Add git remote pointing to the cm github repository.
- aospremote:      Add git remote for matching AOSP repository.
- cafremote:       Add git remote for matching CodeAurora repository.
- mka:             Builds using SCHED_BATCH on all processors.
- mkap:            Builds the module(s) using mka and pushes them to the device.
- cmka:            Cleans and builds using mka.
- repodiff:        Diff 2 different branches or tags within the same repo
- repolastsync:    Prints date and time of last repo sync.
- reposync:        Parallel repo sync using ionice and SCHED_BATCH.
- repopick:        Utility to fetch changes from Gerrit.
- installboot:     Installs a boot.img to the connected device.
- installrecovery: Installs a recovery.img to the connected device.
EOF
}

function tipsy_device_combos()
{
    local T list_file variant device

    T="$(gettop)"
    list_file="${T}/vendor/tipsy/tipsy.devices"
    variant="userdebug"

    if [[ $1 ]]
    then
        if [[ $2 ]]
        then
            list_file="$1"
            variant="$2"
        else
            if [[ ${VARIANT_CHOICES[@]} =~ (^| )$1($| ) ]]
            then
                variant="$1"
            else
                list_file="$1"
            fi
        fi
    fi

    if [[ ! -f "${list_file}" ]]
    then
        echo "unable to find device list: ${list_file}"
        list_file="${T}/vendor/tipsy/tipsy.devices"
        echo "defaulting device list file to: ${list_file}"
    fi

    while IFS= read -r device
    do
        add_lunch_combo "tipsy_${device}-${variant}"
    done < "${list_file}"
}

function tipsy_rename_function()
{
    eval "original_tipsy_$(declare -f ${1})"
}

function _tipsy_build_hmm() #hidden
{
    printf "%-8s %s" "${1}:" "${2}"
}

function tipsy_append_hmm()
{
    HMM_DESCRIPTIVE=("${HMM_DESCRIPTIVE[@]}" "$(_tipsy_build_hmm "$1" "$2")")
}

function tipsy_add_hmm_entry()
{
    for c in ${!HMM_DESCRIPTIVE[*]}
    do
        if [[ "${1}" == $(echo "${HMM_DESCRIPTIVE[$c]}" | cut -f1 -d":") ]]
        then
            HMM_DESCRIPTIVE[${c}]="$(_tipsy_build_hmm "$1" "$2")"
            return
        fi
    done
    tipsy_append_hmm "$1" "$2"
}

function tipsyremote()
{
    local proj pfx project

    if ! git rev-parse &> /dev/null
    then
        echo "Not in a git directory. Please run this from an Android repository you wish to set up."
        return
    fi
    git remote rm tipsy 2> /dev/null

    proj="$(pwd -P | sed "s#$ANDROID_BUILD_TOP/##g")"

    if (echo "$proj" | egrep -q 'external|system|build|bionic|art|libcore|prebuilt|dalvik') ; then
        pfx="android_"
    fi

    project="${proj//\//_}"

    git remote add tipsy "git@github.com:TipsyOs/$pfx$project"
    echo "Remote 'tipsy' created"
}

function cmremote()
{
    local proj pfx project

    if ! git rev-parse &> /dev/null
    then
        echo "Not in a git directory. Please run this from an Android repository you wish to set up."
        return
    fi
    git remote rm cm 2> /dev/null

    proj="$(pwd -P | sed "s#$ANDROID_BUILD_TOP/##g")"
    pfx="android_"
    project="${proj//\//_}"

    if (echo "$project" | egrep -q 'display-caf|audio-caf|media-caf|ril-caf|wlan-caf|bt-caf') ; then
    project=${project%-caf*}
    fi

    git remote add cm "git@github.com:CyanogenMod/$pfx$project"
    echo "Remote 'cm' created"
}

function aospremote()
{
    local pfx project

    if ! git rev-parse &> /dev/null
    then
        echo "Not in a git directory. Please run this from an Android repository you wish to set up."
        return
    fi
    git remote rm aosp 2> /dev/null

    project="$(pwd -P | sed "s#$ANDROID_BUILD_TOP/##g")"
    if [[ "$project" != device* ]]
    then
        pfx="platform/"
    fi
    git remote add aosp "https://android.googlesource.com/$pfx$project"
    echo "Remote 'aosp' created"
}

function cafremote()
{
    local pfx project

    if ! git rev-parse &> /dev/null
    then
        echo "Not in a git directory. Please run this from an Android repository you wish to set up."
    fi
    git remote rm caf 2> /dev/null

    project="$(pwd -P | sed "s#$ANDROID_BUILD_TOP/##g")"
    if [[ "$project" != device* ]]
    then
        pfx="platform/"
    fi
    git remote add caf "git://codeaurora.org/$pfx$project"
    echo "Remote 'caf' created"
}


tipsy_rename_function hmm
function hmm() #hidden
{
    local i T
    T="$(gettop)"
    original_tipsy_hmm
    echo

    echo "vendor/tipsy extended functions. The complete list is:"
    for i in $(grep -P '^function .*$' "$T/vendor/tipsy/build/envsetup.sh" | grep -v "#hidden" | sed 's/function \([a-z_]*\).*/\1/' | sort | uniq); do
        echo "$i"
    done |column
}

function brunch()
{
    breakfast $*
    if [ $? -eq 0 ]; then
        mka bacon
    else
        echo "No such item in brunch menu. Try 'breakfast'"
        return 1
    fi
    return $?
}

function breakfast()
{
    target=$1
    local variant=$2
    TIPSY_DEVICES_ONLY="true"
    unset LUNCH_MENU_CHOICES
    add_lunch_combo full-eng
    for f in `/bin/ls vendor/tipsy/vendorsetup.sh 2> /dev/null`
        do
            echo "including $f"
            . $f
        done
    unset f

    if [ $# -eq 0 ]; then
        # No arguments, so let's have the full menu
        lunch
    else
        echo "z$target" | grep -q "-"
        if [ $? -eq 0 ]; then
            # A buildtype was specified, assume a full device name
            lunch $target
        else
            # This is probably just the TIPSY model name
            if [ -z "$variant" ]; then
                variant="userdebug"
            fi
            lunch tipsy_$target-$variant
        fi
    fi
    return $?
}

alias bib=breakfast

function eat()
{
    if [ "$OUT" ] ; then
        MODVERSION=$(get_build_var TIPSY_VERSION)
        ZIPFILE=tipsy-$MODVERSION.zip
        ZIPPATH=$OUT/$ZIPFILE
        if [ ! -f $ZIPPATH ] ; then
            echo "Nothing to eat"
            return 1
        fi
        adb start-server # Prevent unexpected starting server message from adb get-state in the next line
        if [ $(adb get-state) != device -a $(adb shell test -e /sbin/recovery 2> /dev/null; echo $?) != 0 ] ; then
            echo "No device is online. Waiting for one..."
            echo "Please connect USB and/or enable USB debugging"
            until [ $(adb get-state) = device -o $(adb shell test -e /sbin/recovery 2> /dev/null; echo $?) = 0 ];do
                sleep 1
            done
            echo "Device Found.."
        fi
    if (adb shell getprop ro.tipsy.device | grep -q "$TIPSY_BUILD");
    then
        # if adbd isn't root we can't write to /cache/recovery/
        adb root
        sleep 1
        adb wait-for-device
        cat << EOF > /tmp/command
--sideload_auto_reboot
EOF
        if adb push /tmp/command /cache/recovery/ ; then
            echo "Rebooting into recovery for sideload installation"
            adb reboot recovery
            adb wait-for-sideload
            adb sideload $ZIPPATH
        fi
        rm /tmp/command
    else
        echo "Nothing to eat"
        return 1
    fi
    return $?
    else
        echo "The connected device does not appear to be $TIPSY_BUILD, run away!"
    fi
}

function omnom()
{
    brunch $*
    eat
}

function cout()
{
    if [  "$OUT" ]; then
        cd $OUT
    else
        echo "Couldn't locate out directory.  Try setting OUT."
    fi
}

function dddclient()
{
   local OUT_ROOT=$(get_abs_build_var PRODUCT_OUT)
   local OUT_SYMBOLS=$(get_abs_build_var TARGET_OUT_UNSTRIPPED)
   local OUT_SO_SYMBOLS=$(get_abs_build_var TARGET_OUT_SHARED_LIBRARIES_UNSTRIPPED)
   local OUT_VENDOR_SO_SYMBOLS=$(get_abs_build_var TARGET_OUT_VENDOR_SHARED_LIBRARIES_UNSTRIPPED)
   local OUT_EXE_SYMBOLS=$(get_symbols_directory)
   local PREBUILTS=$(get_abs_build_var ANDROID_PREBUILTS)
   local ARCH=$(get_build_var TARGET_ARCH)
   local GDB
   case "$ARCH" in
       arm) GDB=arm-linux-androideabi-gdb;;
       arm64) GDB=arm-linux-androideabi-gdb; GDB64=aarch64-linux-android-gdb;;
       mips|mips64) GDB=mips64el-linux-android-gdb;;
       x86) GDB=x86_64-linux-android-gdb;;
       x86_64) GDB=x86_64-linux-android-gdb;;
       *) echo "Unknown arch $ARCH"; return 1;;
   esac

   if [ "$OUT_ROOT" -a "$PREBUILTS" ]; then
       local EXE="$1"
       if [ "$EXE" ] ; then
           EXE=$1
           if [[ $EXE =~ ^[^/].* ]] ; then
               EXE="system/bin/"$EXE
           fi
       else
           EXE="app_process"
       fi

       local PORT="$2"
       if [ "$PORT" ] ; then
           PORT=$2
       else
           PORT=":5039"
       fi

       local PID="$3"
       if [ "$PID" ] ; then
           if [[ ! "$PID" =~ ^[0-9]+$ ]] ; then
               PID=`pid $3`
               if [[ ! "$PID" =~ ^[0-9]+$ ]] ; then
                   # that likely didn't work because of returning multiple processes
                   # try again, filtering by root processes (don't contain colon)
                   PID=`adb shell ps | \grep $3 | \grep -v ":" | awk '{print $2}'`
                   if [[ ! "$PID" =~ ^[0-9]+$ ]]
                   then
                       echo "Couldn't resolve '$3' to single PID"
                       return 1
                   else
                       echo ""
                       echo "WARNING: multiple processes matching '$3' observed, using root process"
                       echo ""
                   fi
               fi
           fi
           adb forward "tcp$PORT" "tcp$PORT"
           local USE64BIT="$(is64bit $PID)"
           adb shell gdbserver$USE64BIT $PORT --attach $PID &
           sleep 2
       else
               echo ""
               echo "If you haven't done so already, do this first on the device:"
               echo "    gdbserver $PORT /system/bin/$EXE"
                   echo " or"
               echo "    gdbserver $PORT --attach <PID>"
               echo ""
       fi

       OUT_SO_SYMBOLS=$OUT_SO_SYMBOLS$USE64BIT
       OUT_VENDOR_SO_SYMBOLS=$OUT_VENDOR_SO_SYMBOLS$USE64BIT

       echo >|"$OUT_ROOT/gdbclient.cmds" "set solib-absolute-prefix $OUT_SYMBOLS"
       echo >>"$OUT_ROOT/gdbclient.cmds" "set solib-search-path $OUT_SO_SYMBOLS:$OUT_SO_SYMBOLS/hw:$OUT_SO_SYMBOLS/ssl/engines:$OUT_SO_SYMBOLS/drm:$OUT_SO_SYMBOLS/egl:$OUT_SO_SYMBOLS/soundfx:$OUT_VENDOR_SO_SYMBOLS:$OUT_VENDOR_SO_SYMBOLS/hw:$OUT_VENDOR_SO_SYMBOLS/egl"
       echo >>"$OUT_ROOT/gdbclient.cmds" "source $ANDROID_BUILD_TOP/development/scripts/gdb/dalvik.gdb"
       echo >>"$OUT_ROOT/gdbclient.cmds" "target remote $PORT"
       # Enable special debugging for ART processes.
       if [[ $EXE =~ (^|/)(app_process|dalvikvm)(|32|64)$ ]]; then
          echo >> "$OUT_ROOT/gdbclient.cmds" "art-on"
       fi
       echo >>"$OUT_ROOT/gdbclient.cmds" ""

       local WHICH_GDB=
       # 64-bit exe found
       if [ "$USE64BIT" != "" ] ; then
           WHICH_GDB=$ANDROID_TOOLCHAIN/$GDB64
       # 32-bit exe / 32-bit platform
       elif [ "$(get_build_var TARGET_2ND_ARCH)" = "" ]; then
           WHICH_GDB=$ANDROID_TOOLCHAIN/$GDB
       # 32-bit exe / 64-bit platform
       else
           WHICH_GDB=$ANDROID_TOOLCHAIN_2ND_ARCH/$GDB
       fi

       ddd --debugger $WHICH_GDB -x "$OUT_ROOT/gdbclient.cmds" "$OUT_EXE_SYMBOLS/$EXE"
  else
       echo "Unable to determine build system output dir."
   fi
}

function installboot()
{
    if [ ! -e "$OUT/recovery/root/etc/recovery.fstab" ];
    then
        echo "No recovery.fstab found. Build recovery first."
        return 1
    fi
    if [ ! -e "$OUT/boot.img" ];
    then
        echo "No boot.img found. Run make bootimage first."
        return 1
    fi
    PARTITION=`grep "^\/boot" $OUT/recovery/root/etc/recovery.fstab | awk {'print $3'}`
    if [ -z "$PARTITION" ];
    then
        # Try for RECOVERY_FSTAB_VERSION = 2
        PARTITION=`grep "[[:space:]]\/boot[[:space:]]" $OUT/recovery/root/etc/recovery.fstab | awk {'print $1'}`
        PARTITION_TYPE=`grep "[[:space:]]\/boot[[:space:]]" $OUT/recovery/root/etc/recovery.fstab | awk {'print $3'}`
        if [ -z "$PARTITION" ];
        then
            echo "Unable to determine boot partition."
            return 1
        fi
    fi
    adb start-server
    adb wait-for-online
    adb root
    sleep 1
    adb wait-for-online shell mount /system 2>&1 > /dev/null
    adb wait-for-online remount
    if (adb shell getprop ro.tipsy.device | grep -q "$TIPSY_BUILD");
    then
        adb push $OUT/boot.img /cache/
        for i in $OUT/system/lib/modules/*;
        do
            adb push $i /system/lib/modules/
        done
        adb shell dd if=/cache/boot.img of=$PARTITION
        adb shell chmod 644 /system/lib/modules/*
        echo "Installation complete."
    else
        echo "The connected device does not appear to be $TIPSY_BUILD, run away!"
    fi
}

function installrecovery()
{
    if [ ! -e "$OUT/recovery/root/etc/recovery.fstab" ];
    then
        echo "No recovery.fstab found. Build recovery first."
        return 1
    fi
    if [ ! -e "$OUT/recovery.img" ];
    then
        echo "No recovery.img found. Run make recoveryimage first."
        return 1
    fi
    PARTITION=`grep "^\/recovery" $OUT/recovery/root/etc/recovery.fstab | awk {'print $3'}`
    if [ -z "$PARTITION" ];
    then
        # Try for RECOVERY_FSTAB_VERSION = 2
        PARTITION=`grep "[[:space:]]\/recovery[[:space:]]" $OUT/recovery/root/etc/recovery.fstab | awk {'print $1'}`
        PARTITION_TYPE=`grep "[[:space:]]\/recovery[[:space:]]" $OUT/recovery/root/etc/recovery.fstab | awk {'print $3'}`
        if [ -z "$PARTITION" ];
        then
            echo "Unable to determine recovery partition."
            return 1
        fi
    fi
    adb start-server
    adb wait-for-online
    adb root
    sleep 1
    adb wait-for-online shell mount /system 2>&1 >> /dev/null
    adb wait-for-online remount
    if (adb shell getprop ro.tipsy.device | grep -q "$TIPSY_BUILD");
    then
        adb push $OUT/recovery.img /cache/
        adb shell dd if=/cache/recovery.img of=$PARTITION
        echo "Installation complete."
    else
        echo "The connected device does not appear to be $TIPSY_BUILD, run away!"
    fi
}

function makerecipe() {
    if [ -z "$1" ]
    then
        echo "No branch name provided."
        return 1
    fi
    cd android
    sed -i s/'default revision=.*'/'default revision="refs\/heads\/'$1'"'/ default.xml
    git commit -a -m "$1"
    cd ..

    repo forall -c '

    if [ "$REPO_REMOTE" = "github" ]
    then
        pwd
        slimremote
        git push slim HEAD:refs/heads/'$1'
    fi
    '
}

function mka() {
    local T=$(gettop)
    if [ "$T" ]; then
        case `uname -s` in
            Darwin)
                make -C $T -j `sysctl hw.ncpu|cut -d" " -f2` "$@"
                ;;
            *)
                mk_timer schedtool -B -n 10 -e ionice -n 7 make -C $T -j$(grep "^processor" /proc/cpuinfo | wc -l) "$@"
                ;;
        esac

    else
        echo "Couldn't locate the top of the tree.  Try setting TOP."
    fi
}

function cmka() {
    if [ ! -z "$1" ]; then
        for i in "$@"; do
            case $i in
                bacon|otapackage|systemimage)
                    mka installclean
                    mka $i
                    ;;
                *)
                    mka clean-$i
                    mka $i
                    ;;
            esac
        done
    else
        mka clean
        mka
    fi
}

function mms() {
    local T=$(gettop)
    if [ -z "$T" ]
    then
        echo "Couldn't locate the top of the tree.  Try setting TOP."
        return 1
    fi

    case `uname -s` in
        Darwin)
            local NUM_CPUS=$(sysctl hw.ncpu|cut -d" " -f2)
            ONE_SHOT_MAKEFILE="__none__" \
                make -C $T -j $NUM_CPUS "$@"
            ;;
        *)
            local NUM_CPUS=$(grep "^processor" /proc/cpuinfo | wc -l)
            ONE_SHOT_MAKEFILE="__none__" \
                mk_timer schedtool -B -n 1 -e ionice -n 1 \
                make -C $T -j $NUM_CPUS "$@"
            ;;
    esac
}

function repolastsync() {
    RLSPATH="$ANDROID_BUILD_TOP/.repo/.repo_fetchtimes.json"
    RLSLOCAL=$(date -d "$(stat -c %z $RLSPATH)" +"%e %b %Y, %T %Z")
    RLSUTC=$(date -d "$(stat -c %z $RLSPATH)" -u +"%e %b %Y, %T %Z")
    echo "Last repo sync: $RLSLOCAL / $RLSUTC"
}

function reposync() {
    case `uname -s` in
        Darwin)
            repo sync -j 4 "$@"
            ;;
        *)
            schedtool -B -n 1 -e ionice -n 1 `which repo` sync -j 4 "$@"
            ;;
    esac
}

function repodiff() {
    if [ -z "$*" ]; then
        echo "Usage: repodiff <ref-from> [[ref-to] [--numstat]]"
        return
    fi
    diffopts=$* repo forall -c \
      'echo "$REPO_PATH ($REPO_REMOTE)"; git diff ${diffopts} 2>/dev/null ;'
}

# Return success if adb is up and not in recovery
function _adb_connected {
    {
        if [[ "$(adb get-state)" == device &&
              "$(adb shell test -e /sbin/recovery; echo $?)" == 1 ]]
        then
            return 0
        fi
    } 2>/dev/null

    return 1
};

function dopush()
{
    local func=$1
    shift

    adb start-server # Prevent unexpected starting server message from adb get-state in the next line
    if ! _adb_connected; then
        echo "No device is online. Waiting for one..."
        echo "Please connect USB and/or enable USB debugging"
        until _adb_connected; do
            sleep 1
        done
        echo "Device Found."
    fi

    if (adb shell getprop ro.tipsy.device | grep -q "$TIPSY_BUILD") || [ "$FORCE_PUSH" = "true" ];
    then
    # retrieve IP and PORT info if we're using a TCP connection
    TCPIPPORT=$(adb devices | egrep '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+[^0-9]+' \
        | head -1 | awk '{print $1}')
    adb root &> /dev/null
    sleep 0.3
    if [ -n "$TCPIPPORT" ]
    then
        # adb root just killed our connection
        # so reconnect...
        adb connect "$TCPIPPORT"
    fi
    adb wait-for-device &> /dev/null
    sleep 0.3
    adb remount &> /dev/null

    $func $*
    if [ $? -ne 0 ]; then
        return $?
    fi

    NINJA_DIR=$(pwd -P | sed "s#$ANDROID_BUILD_TOP\/##" | sed "s/\//_/g")
    NINJA_MAKEFILE=$(gettop)/out/build-${TARGET_PRODUCT}-mmm-${NINJA_DIR}_Android.mk.ninja

    # Install: <file>
    LOC="$(grep '^ description = Install:' $NINJA_MAKEFILE | cut -d ':' -f 2)"

    # If any files are going to /data, push an octal file permissions reader to device
    if [ -n "$(echo $LOC | egrep '(^|\s)/data')" ]; then
        CHKPERM="/data/local/tmp/chkfileperm.sh"
(
cat <<'EOF'
#!/system/xbin/sh
FILE=$@
if [ -e $FILE ]; then
    ls -l $FILE | awk '{k=0;for(i=0;i<=8;i++)k+=((substr($1,i+2,1)~/[rwx]/)*2^(8-i));if(k)printf("%0o ",k);print}' | cut -d ' ' -f1
fi
EOF
) > $OUT/.chkfileperm.sh
        echo "Pushing file permissions checker to device"
        adb push $OUT/.chkfileperm.sh $CHKPERM
        adb shell chmod 755 $CHKPERM
        rm -f $OUT/.chkfileperm.sh
    fi

    stop_n_start=false
    for FILE in $(echo $LOC | tr " " "\n"); do
        # Make sure file is in $OUT/system or $OUT/data
        case $FILE in
            $OUT/system/*|$OUT/data/*)
                # Get target file name (i.e. /system/bin/adb)
                TARGET=$(echo $FILE | sed "s#$OUT##")
            ;;
            *) continue ;;
        esac

        case $TARGET in
            /data/*)
                # fs_config only sets permissions and se labels for files pushed to /system
                if [ -n "$CHKPERM" ]; then
                    OLDPERM=$(adb shell $CHKPERM $TARGET)
                    OLDPERM=$(echo $OLDPERM | tr -d '\r' | tr -d '\n')
                    OLDOWN=$(adb shell ls -al $TARGET | awk '{print $2}')
                    OLDGRP=$(adb shell ls -al $TARGET | awk '{print $3}')
                fi
                echo "Pushing: $TARGET"
                adb push $FILE $TARGET
                if [ -n "$OLDPERM" ]; then
                    echo "Setting file permissions: $OLDPERM, $OLDOWN":"$OLDGRP"
                    adb shell chown "$OLDOWN":"$OLDGRP" $TARGET
                    adb shell chmod "$OLDPERM" $TARGET
                else
                    echo "$TARGET did not exist previously, you should set file permissions manually"
                fi
                adb shell restorecon "$TARGET"
            ;;
            /system/priv-app/SystemUI/SystemUI.apk|/system/framework/*)
                # Only need to stop services once
                if ! $stop_n_start; then
                    adb shell stop
                    stop_n_start=true
                fi
                echo "Pushing: $TARGET"
                adb push $FILE $TARGET
            ;;
            *)
                echo "Pushing: $TARGET"
                adb push $FILE $TARGET
            ;;
        esac
    done
    if [ -n "$CHKPERM" ]; then
        adb shell rm $CHKPERM
    fi
    if $stop_n_start; then
        adb shell start
    fi
    return 0
    else
        echo "The connected device does not appear to be $TIPSY_BUILD, run away!"
    fi
}

alias mmp='dopush mm'
alias mmmp='dopush mmm'
alias mmap='dopush mma'
alias mkap='dopush mka'
alias cmkap='dopush cmka'

function repopick() {
    T=$(gettop)
    $T/vendor/tipsy/build/tools/repopick.py $@
}

function fixup_common_out_dir() {
    common_out_dir=$(get_build_var OUT_DIR)/target/common
    target_device=$(get_build_var TARGET_DEVICE)
    if [ ! -z $TIPSY_FIXUP_COMMON_OUT ]; then
        if [ -d ${common_out_dir} ] && [ ! -L ${common_out_dir} ]; then
            mv ${common_out_dir} ${common_out_dir}-${target_device}
            ln -s ${common_out_dir}-${target_device} ${common_out_dir}
        else
            [ -L ${common_out_dir} ] && rm ${common_out_dir}
            mkdir -p ${common_out_dir}-${target_device}
            ln -s ${common_out_dir}-${target_device} ${common_out_dir}
        fi
    else
        [ -L ${common_out_dir} ] && rm ${common_out_dir}
        mkdir -p ${common_out_dir}
    fi
}

# Enable SD-LLVM if available
if [ -d $(gettop)/prebuilts/snapdragon-llvm/toolchains ]; then
    case `uname -s` in
        Darwin)
            # Darwin is not supported yet
            ;;
        *)
            export SDCLANG=true
            export SDCLANG_PATH=$(gettop)/prebuilts/snapdragon-llvm/toolchains/llvm-Snapdragon_LLVM_for_Android_3.8/prebuilt/linux-x86_64/bin
            export SDCLANG_LTO_DEFS=$(gettop)/device/qcom/common/sdllvm-lto-defs.mk
            ;;
    esac
fi
