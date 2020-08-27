#!/bin/bash
# generate-speccpu.sh - Generate SPECcpu configuration file
#
# Does what it says on the tin, generates a SPEC configuration file using
# gcc as a compiler. It can also be used to auto-generate some informationo
# about the machine itself
set ${MMTESTS_SH_DEBUG:-+x}

# Exit codes
EXIT_SUCCESS=0
EXIT_FAILURE=-1

# Default
GCC_VERSION=
BITNESS=32
ARCH=`uname -m`
HUGEPAGES="no"

if [ "$SAMPLE_CYCLE_FACTOR" = "" ]; then
	export SAMPLE_CYCLE_FACTOR=36
fi
if [ "$SAMPLE_EVENT_FACTOR" = "" ]; then
	export SAMPLE_EVENT_FACTOR=4
fi

##
# usage - Print usage
usage() {
	echo "
generate-speccpu.sh (c) Mel Gorman 2008

Usage: generate-speccpu.sh [options]
  -h, --help   Print this usage message
  --gcc        GCC version (Default: default)
  --conf file  Read default configuration values from file
  --bitness    32/64 bitness (Default: $BITNESS)
  --emit-conf  Print detected values for later use by --conf
  --hugepages-heaponly   Use hugepages in the configuration
  --hugepages-oldrelink  Use hugepages in the configuration
  --hugepages-newrelink  Use hugepages in the configuration
"
	exit $1
}

##
# warning - Print a warning
# die - Exit with error message
warning() {
	echo "WARNING: $@"
}

die() {
	echo "FATAL: $@"
	exit $EXIT_FAILURE
}

##
# Read a configuration file. Expectation is that it contains SPEC
# variables only
read_conf() {
	if [ "$1" = "" ]; then
		return
	fi
	
	if [ ! -f "$1" ]; then
		die Configuration file \'$1\' is not a file
	fi

	. $1
}

##
# emit_header - Emit header
emit_header() {
	echo "# Autogenerated by generate-speccpu.sh"
	echo
}

##
# detect_base - Detect base configuration
# emit_base - Emit the base SPEC configuration
detect_base() {
	ignore_errors=no
	tune=base
	output_format="asc, pdf, Screen"
	ext=$ARCH-m$BITNESS-gcc`echo $GCC_VERSION | sed -e 's/\.//g'`
	reportable=1
	teeout=yes
	teerunout=yes
	env_vars=1
}

emit_base () {
	echo "## Base configuration"
	echo "ignore_errors      = $ignore_errors"
	echo "tune               = $tune"
	echo "ext                = $ext"
	echo "output_format      = $output_format"
	echo "reportable         = $reportable"
	echo "teeout             = $teeout"
	echo "teerunout          = yes"
	echo "hw_avail           = $hw_avail"
	echo "license_num        = $license_num"
	echo "test_sponsor       = $test_sponsor"
	echo "prepared_by        = $prepared_by"
	echo "tester             = $tester"

	if [ "$HUGEPAGES" != "no" ]; then
		echo "env_vars           = $env_vars"
	fi
	echo
}

##
# emit_compiler - Print the compiler configuration
emit_compiler() {
	if [ "`which gcc$GCC_VERSION`" = "" ]; then die No gcc$GCC_VERSION; fi
	if [ "`which g++$GCC_VERSION`" = "" ]; then die No g++$GCC_VERSION; fi
	if [ "`which gfortran$GCC_VERSION`" = "" ]; then die No gfortran$GCC_VERSION; fi
	echo "## Compiler"
	echo "CC                 = gcc$GCC_VERSION"
	echo "CXX                = g++$GCC_VERSION"
	echo "FC                 = gfortran$GCC_VERSION"
	echo
}

##
# cpuinfo_val - Output the given value of a cpuinfo field
cpuinfo_val() {
	grep "^$1" /proc/cpuinfo | awk -F": " '{print $2}' | head -1
}

##
# detect_mconf - Detect machine configuration
# emit_mconf - Emit machine HW configuration
# emit_onlymconf - Emit mconf and exit
detect_mconf() {
	# Common to all arches
	# Lookup primary cache information
	cache=/sys/devices/system/cpu/cpu0/cache
	pcache=
	for index in `ls /sys/devices/system/cpu/cpu0/cache`; do
		if [ "$pcache" != "" ]; then
			pcache="$pcache + "
		fi
		pcache="$pcache`cat $cache/$index/size`"
		pcache="$pcache `cat $cache/$index/type | head -c1`"
	done
	hw_memory=`free -m | grep ^Mem: | awk '{print $2}'`MB
	hw_cpus=`grep processor /proc/cpuinfo | wc -l`

	case "$ARCH" in
		i?86|x86_64|ia64)

			if [ "`which dmidecode`" = "" ]; then
				warning dmidecode is not in path, very limited info
			fi

			hw_manu=`dmidecode -s baseboard-manufacturer`
			hw_prod=`dmidecode -s baseboard-product-name`
			hw_vers=`dmidecode -s baseboard-version`

			hw_model="$hw_manu $hw_prod $hw_vers"
			hw_cpu_name=`cpuinfo_val "model name"`
			hw_cpu_mhz=`cpuinfo_val "cpu MHz"`
			hw_ncoresperchip=`cpuinfo_val "cpu cores"`
			hw_nchips=$(($hw_cpus/$hw_ncoresperchip))
			hw_ncores=$(($hw_cpus/$hw_nchips))
			hw_pcache=$pcache

			;;
		ppc64)
			hw_cpu_name=`cpuinfo_val cpu`
			hw_cpu_mhz=`cpuinfo_val "clock"`
			hw_pcache=$pcache
			;;
	esac
}

emit_mconf() {
	echo "## HW config"
	echo "hw_model           = $hw_model"
	echo "hw_cpu_name        = $hw_cpu_name"
	echo "hw_cpu_char        = $hw_cpu_char"
	echo "hw_cpu_mhz         = $hw_cpu_mhz"
	echo "hw_fpu             = $hw_fpu"
	echo "hw_nchips          = $hw_nchips"
	echo "hw_ncores          = $hw_ncores"
	echo "hw_ncoresperchip   = $hw_ncoresperchip"
	echo "hw_nthreadspercore = $hw_nthreadspercore"
	echo "hw_ncpuorder       = $hw_ncpuorder"
	echo "hw_pcache          = $hw_pcache"
	echo "hw_scache          = $hw_scache"
	echo "hw_tcache          = $hw_tcache"
	echo "hw_ocache          = $hw_ocache"
	echo "hw_memory          = $hw_memory"
	echo "hw_disk            = $hw_disk"
	echo "hw_vendor          = $hw_vendor"
	echo

}

##
# detect_sconf - Detect machine configuration
# emit_sconf - Emit machine HW configuration
# emit_onlysconf - Emit mconf and exit
RELEASE_FILES="
debian_version \
debian_release \
redhat-release \
redhat_version \
SuSE-release \
lsb-release"
 
OS=`uname -s| tr 'A-Z' 'a-z'`
RELEASE=
VERSION=
DISTRO=

detect_sconf() {
	# Get the distribution major name
	for RELEASE_FILE in $RELEASE_FILES; do
		if [ "$DISTRO" = "" -a -r /etc/$RELEASE_FILE ] ; then
			DISTRO=`echo $RELEASE_FILE | tr 'A-Z' 'a-z' | sed -e 's/[_-]\(release\|version\)$//'`
			if [ "$DISTRO" = "lsb" ]; then
				if [ "`grep Ubuntu /etc/$RELEASE_FILE`" != "" ] ; then
					DISTRO=ubuntu
				else
					DISTRO=unrecognised
				fi
			fi
		fi
	done

	# Get the distribution release name
	case "$DISTRO" in
		suse)
			TEST=`grep Enterprise /etc/SuSE-release`
			if [ "$TEST" != "" ]; then
				RELEASE=SLES
				VERSION=`grep 'VERSION' /etc/SuSE-release | sed -e 's/ *VERSION *= *//'`
				VERSION=$VERSION-pl
				VERSION=$VERSION`grep 'PATCHLEVEL' /etc/SuSE-release | sed -e 's/ *PATCHLEVEL *= *//'`
			else
				RELEASE=SuSE
				VERSION=`egrep 'VERSION' /etc/SuSE-release | sed -e 's/ *VERSION *= *//'`
			fi
			;;
		redhat)
			RELEASE=`sed -e 's/ release.*$//' /etc/redhat-release | sed -e 's/[^A-Z]//g'`
			VERSION=`sed -e 's/^.* release//' /etc/redhat-release | \
				sed -e 's/[^0-9]//g' | \
				sed -e 's/\([0-9]\)\([0-9]\)/\1.\2/g'`
			;;
		debian)
			RELEASE=$(sed -e 's/\/.*//' /etc/debian_version)
			;;
		ubuntu)
			RELEASE=$(egrep 'RELEASE' /etc/lsb-release | sed -e 's/DISTRIB_RELEASE=//')
			;;
	esac


	DISTRO=`echo $DISTRO | sed 's/\([a-z]\)\([a-zA-Z0-9]*\)/\u\1\2/g'`
	RELEASE=`echo $RELEASE | sed 's/\([a-z]\)\([a-zA-Z0-9]*\)/\u\1\2/g'`
	sw_os="$DISTRO $RELEASE for $ARCH"
	sw_file=`stat -f . -c %T`
	sw_other="Kernel `uname -r`"
	sw_base_ptrsize="$BITNESS-bit"
	sw_peak_ptrsize="Not Applicable"
	sw_state="Runlevel `cat /proc/1/cmdline | awk '{print $2}'`"
	sw_compiler="gcc, g++ & gfortran $GCC_VERSION for $ARCH"
}

emit_sconf() {
	echo "## SW config"
	echo "sw_os              = $sw_os"
	echo "sw_file            = $sw_file"
	echo "sw_state           = $sw_state"
	echo "sw_compiler        = $sw_compiler"
	echo "sw_avail           = $sw_avail"
	echo "sw_other           = $sw_other"
	echo "sw_base_ptrsize    = $sw_base_ptrsize"
	echo "sw_peak_ptrsize    = $sw_peak_ptrsize"

	# Required because of the patching of gamess
	echo "strict_rundir_verify = 0"
	echo

	if [ "$HUGEPAGES" = "no" ]; then
		return
	fi

	echo "## libhugetlbfs relinking"
	echo "%define LHBDT   -B /usr/share/libhugetlbfs -Wl,--hugetlbfs-link=BDT"
	echo "%define LHB     -B /usr/share/libhugetlbfs -Wl,--hugetlbfs-link=B"
	echo "%define LHALIGN -B /usr/share/libhugetlbfs -Wl,--hugetlbfs-align"
	if [ "$HUGEPAGES" = "old-relink" ]; then
		echo "%define LHRELINK %{LHBDT}"
	fi
	if [ "$HUGEPAGES" = "new-relink" ]; then
		echo "%define LHRELINK %{LHALIGN}"
	fi
	if [ "$HUGEPAGES" = "heaponly" ]; then
		echo "%define LHRELINK"
	fi

	LIBHUGEPATH=
	if [ -e /usr/lib/x86_64-linux-gnu/ ]; then
		LIBHUGEPATH=-L/usr/lib/x86_64-linux-gnu/
	fi
	echo "%define LHLIB $LIBHUGEPATH -lhugetlbfs"
	echo
	echo "# Commented out as reportable runs ignore them, set env externally"
	echo "## ENV_HUGETLB_MORECORE = yes"
	echo "## ENV_HUGETLB_ELFMAP = RW"
	echo
}

##
# emit_optimization - Emit compiler optimizations and notes
emit_optimization() {
	echo "## Optimisation"
	echo "makeflags          = -j$hw_cpus"
	echo "COPTIMIZE          = $GCC_OPTIMIZE -m$BITNESS"
	echo "CXXOPTIMIZE        = $GCC_OPTIMIZE -m$BITNESS"
	echo "FOPTIMIZE          = $GCC_OPTIMIZE -m$BITNESS"
	if [ "$HUGEPAGES" != "no" ]; then
		echo "EXTRA_LIBS         = %{LHRELINK} %{LHLIB}"
	fi

	echo
	echo "notes0100= C base flags: \$[COPTIMIZE]"
	echo "notes0110= C++ base flags: \$[CXXOPTIMIZE]"
	echo "notes0120= Fortran base flags: \$[FOPTIMIZE]"
	echo
}

##
# detect_portability - detect portability flags
# emit_portall - Emit portability flags for all
# emit_portint - Emit portability flags for integer tests
# emit_portflt - Emit portability flags for flotaing-point tests
detect_portability() {
	port_os=SPEC_CPU_LINUX

	case "$BITNESS" in
		64)
			port_pointer=SPEC_CPU_LP64
			port_all=SPEC_CPU_LP64
			;;
		32)
			port_pointer=
	esac

	case "$ARCH" in
		i?86|x86_64|ia64)
			if [ $BITNESS -eq 32 ]; then
				port_osarch=SPEC_CPU_LINUX_IA32
			else
				port_osarch=SPEC_CPU_LINUX_X64
			fi
			;;
		ppc64)
			port_osarch=SPEC_CPU_LINUX_PPC
			port_cfort=yes
			;;
	esac
}

emit_portall() {
	echo "## Portability flags - all"
	echo "default=base=default=default:"
	if [ "$port_all" != "" ]; then
		echo "notes35            = PORTABILITY=-D$port_all is applied to all benchmarks"
		echo "PORTABILITY        = -D$port_all"
	fi
	echo
}

emit_portint() {
	PERLBENCH_EXTRA=
	echo "## Portability flags - int"
	echo "400.perlbench=default=default=default:"
	if [ "`uname -m`" = "x86_64" ]; then
		PERLBENCH_EXTRA="-fno-strict-aliasing"
	fi
	echo "CPORTABILITY       = -D$port_osarch $PERLBENCH_EXTRA"
	echo "notes35            = 400.perlbench: -D$port_osarch"
	echo

	echo "462.libquantum=default=default=default:"
	echo "CPORTABILITY       = -D$port_os"
	echo "notes60            = 462.libquantum: -D$port_os"
	echo

	echo "483.xalancbmk=default=default=default:"
	echo "CXXPORTABILITY       = -D$port_os"
	echo

	H264_EXTRA=
	if [[ "`uname -m`" =~ i.86 ]]; then
		H264_EXTRA="$H264_EXTRA -fno-strict-aliasing"
	fi
	if [[ "`uname -m`" = "x86_64" ]]; then
		H264_EXTRA="$H264_EXTRA -fno-strict-aliasing"
	fi
	if [ "$port_cfort" = "yes" ]; then
		H264_EXTRA="$H264_EXTRA -fsigned-char"
	fi

	if [ "$H264_EXTRA" != "" ]; then
		echo "464.h264ref=default=default=default:"
		echo "CPORTABILITY = $H264_EXTRA"
		echo
	fi
}

emit_portflt() {
	echo "## Portability flags - flt"

	if [ "$port_cfort" != "yes" ]; then
		echo "481.wrf=default=default=default:"
		echo "CPORTABILITY      = -DSPEC_CPU_CASE_FLAG -D$port_os"
		echo

		return
	fi

	echo "481.wrf=default=default=default:"
	echo "CPORTABILITY        = -DNOUNDERSCORE"
	echo "FOPTIMIZE           = $GCC_OPTIMIZE -m$BITNESS -fno-underscoring"
	echo

	echo "482.sphinx3=default=default=default:"
	echo "CPORTABILITY = -fsigned-char"
	echo

}

##
# emit_footer - Print the end
emit_footer() {
	echo "__MD5__"
}

##
# emit_conf
# Instead of emitting a SPEC configuration file, emit every value
# as a shell script that is suitable for import by --conf. This
# allows a user to have machine-specific configuration files with
# values filled in that are detected incorrectly
emit_conf() {
	if [ "$EMIT_CONF" != "yes" ]; then
		return
	fi
	IFS="
"
	for LINE in `emit_base` \
			`emit_mconf` \
			`emit_sconf`; do
		echo $LINE | grep ^\# > /dev/null
		if [ $? -eq 0 ]; then
			echo
			echo $LINE
		else
			KEY=`echo $LINE | awk -F = '{print $1}' | sed -e 's/ //g'`
			VAL=`echo $LINE | awk -F "= " '{print $2}'`
			echo $KEY=\"$VAL\"
		fi
	done
	exit $EXIT_SUCCESS
}


# Parse the arguments
OPTARGS=`getopt -o h --long help,gcc,emit-conf,bitness:,conf:,monitor:,hugepages-heaponly,hugepages-oldrelink,hugepages-newrelink -n generate-speccpu.sh -- "$@"`
eval set -- "$OPTARGS"
while [ "$1" != "" ] && [ "$1" != "--" ]; do
	case "$1" in
		-h|--help)
			usage $EXIT_SUCCESS;
			;;
		--gcc)
			GCC_VERSION=$2
			shift 2
			;;
		--conf)
			CONFFILE=$2
			shift 2
			;;
		--emit-conf)
			EMIT_CONF=yes
			shift
			;;
		--bitness)
			BITNESS=$2
			shift 2
			;;
		--monitor)
			EVENTS=`echo $2 | tr , ' '`
			shift 2
			;;
		--hugepages-heaponly)
			HUGEPAGES=heaponly
			shift
			;;
		--hugepages-oldrelink)
			HUGEPAGES=old-relink
			shift
			;;
		--hugepages-newrelink)
			HUGEPAGES=new-relink
			shift
			;;
	esac
done

# Automatic detection
detect_base
detect_mconf
detect_sconf
detect_portability

# Read/write conf files
read_conf $CONFFILE
emit_conf

# Generate a spec file
emit_header
emit_base
emit_compiler
emit_mconf
emit_sconf
emit_optimization
emit_portall
emit_portint
emit_portflt
emit_footer
