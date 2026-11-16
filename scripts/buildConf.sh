#!/bin/bash
# Generates the rsync daemon and lsyncd configuration of the File Synchronization add-on.
#
# Usage:
#   buildConf.sh conf <baseDir> <syncPaths> <syncTargets> <delay> <uid>
#   buildConf.sh dirs <baseDir> <syncPaths>
#
#   conf - writes <baseDir>lsyncd/etc/rsync.conf and <baseDir>lsyncd/etc/lsyncd.conf
#   dirs - creates the lsyncd_tmp directory in every synced directory
#
# baseDir     - webroot of the node (or /data for storage), the add-on lives in <baseDir>lsyncd/
# syncPaths   - comma-separated paths relative to baseDir, "/" or an empty value means baseDir itself
# syncTargets - comma-separated hosts that receive the changes of this node:
#               the mirror node and, optionally, a node of the second environment
#
# Every sync path gets its own rsync module: the first one keeps the historical
# name "syncmodule", the next ones are "syncmodule_2", "syncmodule_3", and so on.
# The same paths in the same order must be configured on all synchronized nodes.

set -e

ACTION=$1
baseDir=${2%/}/
IFS=',' read -r -a paths <<< "$3"
[ ${#paths[@]} -gt 0 ] || paths=("")
installDir=${baseDir}lsyncd/

# Keeps the historical module name for the first path, so a second environment
# with an older version of the add-on still receives it.
module_name() {
    if [ "$1" -eq 0 ]; then
        echo syncmodule
    else
        echo "syncmodule_$(($1 + 1))"
    fi
}

source_dir() {
    local p=${1#/}
    p=${p%/}
    if [ -n "$p" ]; then
        echo "${baseDir}${p}/"
    else
        echo "$baseDir"
    fi
}

# Prints one lsyncd sync block: $1 - source directory, $2 - target host, $3 - rsync module.
sync_block() {
    cat <<EOF

sync {
	default.rsync,
	source = "$1",
	target = "rsync://admin@$2/$3",
	delay = ${delay},
	delete = 'running',
	exclude = {
		"lsyncd/",
		"lsyncd_tmp/"
	},
	rsync = {
		archive = true,
		compress = true,
		update = true,
		_extra = {
			"--port=7755", "--password-file=${installDir}etc/rsyncd.pass", "--temp-dir=/lsyncd_tmp"
		},
	}
}
EOF
}

build_conf() {
    local uid=${3:-jelastic} targets i src ip
    IFS=',' read -r -a targets <<< "$1"
    delay=$2
    [[ "$delay" =~ ^[0-9]+$ ]] || delay=10

    {
        cat <<EOF
uid = ${uid}
max connections = 128
pid file = ${installDir}var/run/rsyncd.pid
log file = ${installDir}var/rsync.log
lock file = ${installDir}var/rsync.lock
use chroot = no
EOF
        for i in "${!paths[@]}"; do
            cat <<EOF

[$(module_name "$i")]
	path = $(source_dir "${paths[$i]}")
	comment = Content sync
	auth users = admin
	secrets file = ${installDir}etc/rsyncd.secrets
	list = yes
	read only = no
	munge symlinks = no
EOF
        done
    } > "${installDir}etc/rsync.conf"

    {
        cat <<EOF
settings {
	logfile = "${installDir}var/log/lsyncd.log",
	statusFile = "${installDir}var/log/lsyncd.status",
	insist = 1
}
EOF
        for i in "${!paths[@]}"; do
            src=$(source_dir "${paths[$i]}")
            for ip in "${targets[@]}"; do
                if [ -n "$ip" ]; then
                    sync_block "$src" "$ip" "$(module_name "$i")"
                fi
            done
        done
    } > "${installDir}etc/lsyncd.conf"
}

# With "use chroot = no" the rsync daemon resolves --temp-dir=/lsyncd_tmp relative
# to the module path, so every synced directory needs its own lsyncd_tmp.
build_dirs() {
    local i
    for i in "${!paths[@]}"; do
        mkdir -p "$(source_dir "${paths[$i]}")lsyncd_tmp"
    done
    # Kept for compatibility with older versions, points to the first path as before.
    rm -rf /tmp/lsyncd_tmp
    ln -s "$(source_dir "${paths[0]}")lsyncd_tmp/" /tmp/
}

case "$ACTION" in
    conf)
        build_conf "$4" "$5" "$6"
        ;;
    dirs)
        build_dirs
        ;;
    *)
        echo "Usage: $0 conf <baseDir> <syncPaths> <syncTargets> <delay> <uid> | dirs <baseDir> <syncPaths>" >&2
        exit 2
        ;;
esac
