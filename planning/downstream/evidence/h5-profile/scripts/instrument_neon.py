#!/usr/bin/env python3
"""SCRATCH-ONLY: instrument Neon's TextLayoutManagerSystemInterface.applyStyles (H5 profile).
instrument_neon.py <Neon checkout>. Logs `H5NEON` per call when H5PROF_TS is set.
EXPERIMENT E3 (env H5PROF_E3=<n>): drain an autorelease pool every n tokens."""
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / 'Sources' / 'Neon' / 'TextViewSystemInterface.swift'
s = p.read_text()
old = '''	public func applyStyles(for application: TokenApplication) {
		if let range = application.range {
			setAttributes([:], in: range)
		}

		for token in application.tokens {
			let attrs = attributeProvider(token)
			setAttributes(attrs, in: token.range)
		}
	}

	public var content: NSTextContentManager {'''
new = '''	public func applyStyles(for application: TokenApplication) {
		let h5 = ProcessInfo.processInfo.environment["H5PROF_TS"] != nil
		let e3 = Int(ProcessInfo.processInfo.environment["H5PROF_E3"] ?? "") ?? 0
		let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
		if let range = application.range {
			setAttributes([:], in: range)
		}
		let t1 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

		if e3 > 0 {
			var index = 0
			let tokens = application.tokens
			while index < tokens.count {
				autoreleasepool {
					for token in tokens[index ..< min(index + e3, tokens.count)] {
						setAttributes(attributeProvider(token), in: token.range)
					}
				}
				index += e3
			}
		} else {
			for token in application.tokens {
				let attrs = attributeProvider(token)
				setAttributes(attrs, in: token.range)
			}
		}
		if h5 {
			let t2 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
			FileHandle.standardError.write("H5NEON applyStyles range=\\(application.range.map { "\\($0.location)+\\($0.length)" } ?? "nil") tokens=\\(application.tokens.count) clear_ms=\\(Double(t1 - t0) / 1e6) tokens_ms=\\(Double(t2 - t1) / 1e6) e3=\\(e3)\\n".data(using: .utf8)!)
		}
	}

	public var content: NSTextContentManager {'''
assert s.count(old) == 1, 'pattern'
p.write_text(s.replace(old, new))
print('instrumented', p)
