#!/usr/bin/bash

SE_LINUX=${SE_LINUX:-no}
SRC_DIR=$(dirname $0)
BUILD_DIR="$SRC_DIR/build"
PREFIX=${PREFIX:-/usr/local}

clean() {
    rm -rf $BUILD_DIR
}

build() {
    set -e

    mkdir -p $BUILD_DIR
    checkmodule -M -m -o $BUILD_DIR/gitlab-ssh.mod $SRC_DIR/gitlab-ssh.te
    semodule_package -o $BUILD_DIR/gitlab-ssh.pp -m $BUILD_DIR/gitlab-ssh.mod

    test -n "$SUDO_UID" && chown -R $SUDO_UID:$SUDO_GID $BUILD_DIR

    set +e
}

install_pkg() {
    set -e

    install $SRC_DIR/gitlab-keys-check $PREFIX/bin
    install $SRC_DIR/gitlab-shell-proxy $PREFIX/bin

    if [[ $SE_LINUX != "no" ]]; then
        test ! -e $BUILD_DIR/gitlab-ssh.pp && build
        semodule -i $BUILD_DIR/gitlab-ssh.pp
    fi

    set +e
}

remove() {
    test -e $PREFIX/bin/gitlab-keys-check && rm $PREFIX/bin/gitlab-keys-check
    test -e $PREFIX/bin/gitlab-shell-proxy && rm $PREFIX/bin/gitlab-shell-proxy
    ( semodule -l | grep gitlab-ssh > /dev/null ) && semodule -r gitlab-ssh
}

show_help() {
    cat <<EOD
GitLab SSH Proxy

Usage:
  ./setup.sh [commands]...

Available Commands:
  build   Build SELinux policy module package in ./build
  clean   Remove ./build directory
  install Copy scripts to /usr/local/bin and install SE Linux module package
  remove  Remove scripts and SE Linux module package
  help    Show available commands
EOD
}

if [[ $# -lt 1 ]]; then
    show_help
    exit 0
fi

for cmd in "$@"
do
    case "$cmd" in
        build)
            build
            ;;

        clean)
            clean
            ;;

        install)
            install_pkg
            ;;

        remove)
            remove
            ;;

        help)
            show_help
            ;;

        *)
            echo "Error: unsupported command '${cmd}'" >&2
            echo "Use '$0 help' for supported commands" >&2
            exit 1
            ;;
    esac
done
