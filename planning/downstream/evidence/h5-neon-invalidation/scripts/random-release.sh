#!/bin/bash
C=${C:?}
$C/run.sh release c1-stock random200-stock "NeonBufferedInvalidationTests/random" MACDOWN_NEON_INVALIDATION_TRIAL=1
$C/run.sh release c1-invalidation-buffer random200-patch "NeonBufferedInvalidationTests/random" MACDOWN_NEON_INVALIDATION_TRIAL=1
$C/run.sh release c1-diag-toggles random200-patch+resolve "NeonBufferedInvalidationTests/random" MACDOWN_NEON_INVALIDATION_TRIAL=1 DIAG_NEON_FIX=1
