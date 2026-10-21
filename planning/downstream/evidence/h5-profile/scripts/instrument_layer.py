#!/usr/bin/env python3
"""SCRATCH-ONLY timing instrumentation of SwiftTreeSitterLayer/LanguageLayer.swift (H5 profile).
instrument_layer.py <SwiftTreeSitter dir>. Prints `H5LL ...` lines to stderr when H5PROF_TS=1."""
import sys, pathlib

p = pathlib.Path(sys.argv[1]) / 'Sources' / 'SwiftTreeSitterLayer' / 'LanguageLayer.swift'
s = p.read_text()


def rep(old, new):
    global s
    if old not in s:
        raise SystemExit('not found: ' + old[:70])
    s = s.replace(old, new, 1)


rep('''public enum LanguageLayerError''', '''enum H5LL {
	static let on = ProcessInfo.processInfo.environment["H5PROF_TS"] != nil
	@inline(__always) static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
	static func log(_ s: @autoclosure () -> String) {
		guard on else { return }
		FileHandle.standardError.write(("H5LL " + s() + "\\n").data(using: .utf8)!)
	}
	static func ms(_ t0: UInt64) -> String { String(format: "%.3f", Double(now() - t0) / 1e6) }
}

public enum LanguageLayerError''')

rep('''	private func parse(with content: Content) -> IndexSet {
		let newState = parser.parse(state: state, readHandler: content.readHandler)

		let oldState = state

		self.state = newState

		var invalidations = oldState.changedSet(for: newState)
''', '''	private func parse(with content: Content) -> IndexSet {
		let t0 = H5LL.now()
		let newState = parser.parse(state: state, readHandler: content.readHandler)
		let t1 = H5LL.now()

		let oldState = state

		self.state = newState

		var invalidations = oldState.changedSet(for: newState)
		H5LL.log("op=parse lang=\\(languageName) depth=\\(depth) parse_ms=\\(String(format: "%.3f", Double(t1 - t0) / 1e6)) changedSet_ms=\\(H5LL.ms(t1)) invalidated=\\(invalidations.count)")
''')

rep('''		// injections must be shallow
		let injections = try executeShallowQuery(.injections, in: set).injections(with: content.textProvider)
		let groupedInjections = Dictionary(grouping: injections, by: { $0.name })
		var invalidations = IndexSet()
''', '''		// injections must be shallow
		let r0 = H5LL.now()
		let injections = try executeShallowQuery(.injections, in: set).injections(with: content.textProvider)
		let groupedInjections = Dictionary(grouping: injections, by: { $0.name })
		var invalidations = IndexSet()
		H5LL.log("op=resolve-query lang=\\(languageName) set=\\(set.count) setRanges=\\(set.rangeView.count) injections=\\(injections.count) ms=\\(H5LL.ms(r0))")
		defer { H5LL.log("op=resolve-total lang=\\(languageName) ms=\\(H5LL.ms(r0))") }
''')

rep('''		var allRanges = includedRanges
		var invalidation = IndexSet()
''', '''		let e0 = H5LL.now()
		var allRanges = includedRanges
		var invalidation = IndexSet()
		defer { H5LL.log("op=encorporate lang=\\(languageName) new=\\(tsRanges.count) existing=\\(includedRanges.count) total=\\(allRanges.count) ms=\\(H5LL.ms(e0))") }
''')
p.write_text(s)
print('instrumented', p)
