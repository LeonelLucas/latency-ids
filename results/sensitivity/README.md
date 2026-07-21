# Sensitivity executions

`host-sw-earlier` is an independent execution on the same physical Host-SW
used for the final paper run. Its timing protocol and definitive configuration
are identical to the final run. Runner version `2026-07-19.4` predates only the
export of validation/test score arrays added in version `2026-07-20.1`; the
timing implementation and fitted-model hashes are unchanged.

Across the 288 matched classifier/call-size/composition conditions, the median
absolute difference between condition medians is 0.41%, and the Spearman rank
correlation is 0.9998. This execution is retained as a test-retest sensitivity
check, not as a third physical host or a primary confirmatory result.
