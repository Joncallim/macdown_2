#!/bin/bash
# Stage C2 correctness runs (sequential). C must be set.
cd $C; cp run.sh .run-k.sh
T="MACDOWN_NEON_RESOLVE_TRIAL=1 MACDOWN_NEON_RES_WIDENED=1"
for cfg in debug release; do
  ./.run-k.sh final $cfg resolve "NeonSublayer" $T > logs/sum-final-$cfg-resolve.txt 2>&1
  ./.run-k.sh final $cfg regress "NeonBufferedInvalidationTests|NeonPendingEditLimitTests|NeonReplacementEditTests" MACDOWN_NEON_INVALIDATION_TRIAL=1 MACDOWN_NEON_PENDING_TRIAL=1 MACDOWN_NEON_INV_RESIDUALS=1 > logs/sum-final-$cfg-regress.txt 2>&1
done
# before: stock stack. Debug aborts on background-path tests (C1 task 2), so those run one by one.
./.run-k.sh base debug det "NeonSublayerResolveTests/(?!large)" MACDOWN_NEON_RESOLVE_TRIAL=1 MACDOWN_NEON_RES_RANDOM=0 > logs/sum-base-debug-det.txt 2>&1
for t in largePasteThenEditsInTheSameTurn largeDeletionThenEditsWhileTheParseIsInFlight largeReplacementRemovingMarkupThenEdits largePasteOfAFenceThenEdits; do
  ./.run-k.sh base debug det-$t "NeonSublayerResolveTests/$t" MACDOWN_NEON_RESOLVE_TRIAL=1 > logs/sum-base-debug-det-$t.txt 2>&1
done
./.run-k.sh base release det "NeonSublayer" MACDOWN_NEON_RESOLVE_TRIAL=1 MACDOWN_NEON_RES_WIDENED=1 > logs/sum-base-release-resolve.txt 2>&1
# flush variant (rejected re-entrancy change), same STS/Neon behaviour as final via diag toggles
NEON_BRANCH=c2-diag ./.run-k.sh c2 release flush-idle "NeonSublayerResolveTests" MACDOWN_NEON_RESOLVE_TRIAL=1 STS_EXPAND=1 STS_DROP_STALE=1 STS_SKIP_SAME=1 NEON_RESOLVE=span NEON_FLUSH=idle-first > logs/sum-c2-release-flush-idle.txt 2>&1
echo ALLDONE
