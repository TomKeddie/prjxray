#!/usr/bin/env bash

# This script requires an XC7A50T family part

set -ex

source ${XRAY_DIR}/utils/environment.sh

export XRAY_PINCFG=${XRAY_PINCFG:-ARTY-A7-SWBUT}
export BUILD_DIR=${BUILD_DIR:-build}

# not part of the normal DB
# to generate:
cat >/dev/null <<EOF
pushd ${XRAY_DIR}
source minitests/roi_harness/basys3.sh
pushd fuzzers/001-part-yaml
make clean
make
make pushdb
popd
popd
EOF
stat ${XRAY_DIR}/database/artix7/${XRAY_PART}.yaml >/dev/null

# 6x by 18y CLBs (108)
if [ $SMALL = Y ] ; then
    echo "Design: small"
    export PITCH=1
    export DIN_N=8
    export DOUT_N=8
    export XRAY_ROI=SLICE_X12Y100:SLICE_X17Y117
# 16x by 50y CLBs (800)
else
    echo "Design: large"
    export PITCH=3
    export DIN_N=8
    export DOUT_N=8
    export XRAY_ROI=SLICE_X12Y100:SLICE_X27Y149
fi

mkdir -p $BUILD_DIR
pushd $BUILD_DIR

cat >defines.v <<EOF
\`ifndef DIN_N
\`define DIN_N $DIN_N
\`endif

\`ifndef DOUT_N
\`define DOUT_N $DOUT_N
\`endif
EOF

vivado -mode batch -source ../runme.tcl
test -z "$(fgrep CRITICAL vivado.log)"

${XRAY_BITREAD} -F $XRAY_ROI_FRAMES -o design.bits -z -y design.bit
${XRAY_SEGPRINT} -zd design.bits >design.segp
${XRAY_DIR}/tools/segprint2fasm.py design.segp design.fasm
${XRAY_DIR}/tools/fasm2frame.py design.fasm design.frm
# Hack to get around weird clock error related to clk net not found
# Remove following lines:
#set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk_IBUF]
#set_property FIXED_ROUTE { { CLK_BUFG_BUFGCTRL0_O CLK_BUFG_CK_GCLK0 ... CLK_L1 CLBLM_M_CLK }  } [get_nets clk_net]
if [ -f fixed.xdc ] ; then
    cat fixed.xdc |fgrep -v 'CLOCK_DEDICATED_ROUTE FALSE' |fgrep -v 'set_property FIXED_ROUTE { { CLK_BUFG_BUFGCTRL0_O' >fixed_noclk.xdc
fi
popd
