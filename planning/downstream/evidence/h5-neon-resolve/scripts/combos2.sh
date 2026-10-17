#!/bin/bash
cd $C
R="MACDOWN_NEON_RESOLVE_TRIAL=1 MACDOWN_NEON_RES_RANDOM=0"
./.run-c.sh c2 debug det-expand NeonSublayer $R STS_EXPAND=1 STS_DROP_STALE=1 STS_SKIP_SAME=1 > logs/sum-det-expand.txt 2>&1
./.run-c.sh c2 debug det-expand-fresh NeonSublayer $R STS_EXPAND=1 STS_DROP_STALE=1 STS_SKIP_SAME=1 STS_FRESH_REPARSE=1 > logs/sum-det-expand-fresh.txt 2>&1
./.run-c.sh c2 debug det-layer-stock NeonSublayerLayerLevel $R > logs/sum-det-layer-stock.txt 2>&1
echo done
