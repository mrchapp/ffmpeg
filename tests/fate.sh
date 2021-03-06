#! /bin/sh

config=$1

die(){
    echo "$@"
    exit 1
}

test -r "$config"  || die "usage: fate.sh <config>"

workdir=$(dirname $config)
make=make

. "$config"

test -n "$slot"    || die "slot not specified"
test -n "$repo"    || die "repo not specified"
test -d "$samples" || die "samples location not specified"

lock(){
    lock=$1/fate.lock
    (set -C; exec >$lock) 2>/dev/null || return
    trap 'rm $lock' EXIT
}

checkout(){
    case "$repo" in
        file:*|/*) src="${repo#file:}"      ;;
        git:*)     git clone "$repo" "$src" ;;
        svn:*)     svn co    "$repo" "$src" ;;
    esac
}

update()(
    cd ${src} || return
    case "$repo" in
        git:*) git pull ;;
        svn:*) svn up   ;;
    esac
)

configure()(
    cd ${build} || return
    ${src}/configure                                                    \
        --prefix="${inst}"                                              \
        --samples="${samples}"                                          \
        ${arch:+--arch=$arch}                                           \
        ${cpu:+--cpu="$cpu"}                                            \
        ${cross_prefix:+--cross-prefix="$cross_prefix"}                 \
        ${cc:+--cc="$cc"}                                               \
        ${target_os:+--target-os="$target_os"}                          \
        ${sysroot:+--sysroot="$sysroot"}                                \
        ${target_exec:+--target-exec="$target_exec"}                    \
        ${target_path:+--target-path="$target_path"}                    \
        ${extra_cflags:+--extra-cflags="$extra_cflags"}                 \
        ${extra_ldflags:+--extra-ldflags="$extra_ldflags"}              \
        ${extra_libs:+--extra-libs="$extra_libs"}                       \
        ${extra_conf}
)

compile()(
    cd ${build} || return
    ${make} ${makeopts} && ${make} install
)

fate()(
    cd ${build} || return
    ${make} ${makeopts} -k fate
)

clean(){
    rm -r ${build} ${inst}
}

report(){
    date=$(date -u +%Y%m%d%H%M%S)
    echo "fate:0:${date}:${slot}:${version}:$1:$2" >report
    cat ${build}/config.fate ${build}/tests/data/fate/*.rep >>report
    test -n "$fate_recv" && tar cz report *.log | $fate_recv
}

fail(){
    report "$@"
    clean
    exit
}

mkdir -p ${workdir} || die "Error creating ${workdir}"
lock ${workdir}     || die "${workdir} locked"
cd ${workdir}       || die "cd ${workdir} failed"

src=${workdir}/src
build=${workdir}/build
inst=${workdir}/install
report=tests/data/fate/report

test -d "$src" && update || checkout || die "Error fetching source"

cd ${workdir}

version=$(${src}/version.sh ${src})
test "$version" = "$(cat version 2>/dev/null)" && exit 0
echo ${version} >version

rm -rf "${build}"
mkdir -p ${build}

configure >configure.log 2>&1 || fail $? "error configuring"
compile   >compile.log   2>&1 || fail $? "error compiling"
fate      >test.log      2>&1 || fail $? "error testing"
report 0 success
clean
