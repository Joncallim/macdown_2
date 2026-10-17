#!/bin/bash
C=${C:?}
for cfg in debug release; do for b in c1-stock c2-pending-limit; do
  for t in insertThenDelete twoInserts deletingTheLast control; do
    $C/run.sh $cfg $b t2-$b-$t "NeonPendingEditLimitTests/$t" MACDOWN_NEON_PENDING_TRIAL=1
  done
  $C/run.sh $cfg $b t2-$b-strictWidened "NeonReplacementEditStrictTests/widened" MACDOWN_STRICT_WIDENED_DEBUG=1
done; done
