#!/bin/bash
cd $C
R="MACDOWN_NEON_RESOLVE_TRIAL=1 MACDOWN_NEON_RES_RANDOM=0"
NEON_BRANCH=c2-diag ./.run-c.sh c2 debug det-default NeonSublayerResolveTests $R > logs/sum-det-default.txt 2>&1
./.run-c.sh c2 debug det-drop NeonSublayerResolveTests $R STS_DROP_STALE=1 STS_SKIP_SAME=1 > logs/sum-det-drop.txt 2>&1
./.run-c.sh c2 debug det-drop-fresh NeonSublayerResolveTests $R STS_DROP_STALE=1 STS_SKIP_SAME=1 STS_FRESH_REPARSE=1 > logs/sum-det-drop-fresh.txt 2>&1
./.run-c.sh c2 debug det-stockflush NeonSublayerResolveTests $R NEON_FLUSH=stock STS_DROP_STALE=1 STS_SKIP_SAME=1 STS_FRESH_REPARSE=1 > logs/sum-det-stockflush.txt 2>&1
./.run-c.sh c2 debug det-resolveoff NeonSublayerResolveTests $R NEON_RESOLVE=off > logs/sum-det-resolveoff.txt 2>&1
echo done
