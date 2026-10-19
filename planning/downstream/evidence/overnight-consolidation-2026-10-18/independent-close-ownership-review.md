# Follow-on ownership trace

Question: removing the unused strong coordinator binding from the two close-sheet callbacks leaves a weak-reference presence check across awaits. Does this interact with normal window/benchmark teardown?

Independent disposition: no established lifetime regression; retain the warning fix. Production AppDelegate strongly owns the coordinator throughout app lifetime (AppDelegate.swift:12), and each hosted root receives it in the environment (WindowController.swift:104). Removing a controller removes the coordinator-to-window edge, not the AppDelegate-to-coordinator edge. The eventual close operation independently binds a strong coordinator and validates the retired document (WindowController+Close.swift:167). Benchmark teardown directly closes its fixture rather than entering a sheet callback; its functional regression retains its coordinator explicitly.

A non-nil weak-reference check is not a lifetime guarantee across await. The old unused local must not be treated as protection for the broader unproved externally-dismantled-window/pending-sheet race. This trace justifies no additional source change and is not an executed lifetime regression test. Review was read-only.
