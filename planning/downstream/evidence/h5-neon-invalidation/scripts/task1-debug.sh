#!/bin/bash
C=${C:?}
$C/run.sh debug c1-stock full200-stock "NeonBufferedInvalidationTests" MACDOWN_NEON_INVALIDATION_TRIAL=1 MACDOWN_NEON_INV_RESIDUALS=1
$C/run.sh debug c1-invalidation-buffer full200-patch "NeonBufferedInvalidationTests" MACDOWN_NEON_INVALIDATION_TRIAL=1 MACDOWN_NEON_INV_RESIDUALS=1
$C/run.sh release c12-both widened50-c12 "NeonBufferedInvalidationTests/randomWidened" MACDOWN_NEON_INVALIDATION_TRIAL=1 MACDOWN_NEON_INV_WIDENED=1 MACDOWN_NEON_INV_SEQUENCES=50
$C/run.sh release c1-stock widened50-stock "NeonBufferedInvalidationTests/randomWidened" MACDOWN_NEON_INVALIDATION_TRIAL=1 MACDOWN_NEON_INV_WIDENED=1 MACDOWN_NEON_INV_SEQUENCES=50
