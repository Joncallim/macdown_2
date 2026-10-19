"""Corruption controls for diagnostic evidence, not product correctness tests."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("restore_collect", Path(__file__).with_name("collect.py"))
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def fixture(label):
    observed, reference = "0+3:c333333,f", "0+3:c173691,fi"
    events = [
        {"event": "session.start"},
        {"event": "client.bind", "client": "edited-client", "role": "edited"},
        {"event": "client.bind", "client": "fresh-client", "role": "fresh"},
        {"event": "query.begin", "queryID": "1"},
        {"event": "query.namedRanges", "queryID": "1", "namedRanges": "text:{0,3}"},
        {"event": "query.application", "queryID": "1", "queryClient": "edited-client",
         "currentVersion": "1", "admittedVersion": "1", "textSHA256": digest("synthetic")},
        {"event": "paint.before", "queryID": "1", "renderingAvailable": "true",
         "renderedRuns": "", "renderedSHA256": digest("")},
        {"event": "paint.begin", "queryID": "1", "currentVersion": "1",
         "admittedVersion": "1", "textSHA256": digest("synthetic")},
        {"event": "paint.set.returned", "queryID": "1", "queryClient": "edited-client",
         "requestedRange": "{0,3}", "clampedRange": "{0,3}", "attributes": "c333333,f", "contentLength": "3"},
        {"event": "paint.end", "queryID": "1", "currentVersion": "1",
         "admittedVersion": "1", "textSHA256": digest("synthetic")},
        {"event": "paint.after", "queryID": "1", "renderingAvailable": "true",
         "renderedRuns": observed, "renderedSHA256": digest(observed)},
        {"event": "query.applied", "queryID": "1"},
        {"event": "query.end", "queryID": "1"},
        {"event": "styler.validate.returned", "action": "none"},
    ]
    run = {"event": "fixture.runs", "stage": "oracle", "originalComparisonMatches": "false",
           "readOrder": "afterPrimaryAssertion", "observed": observed, "reference": reference,
           "observedSHA256": digest(observed), "referenceSHA256": digest(reference),
           "initialReferenceSHA256": digest(reference)}
    events.append(run)
    for row in events:
        if row["event"] == "client.bind":
            row.update(tree=row["client"] + "-tree", generation="1", view=row["role"] + "-view", callbackContext=row["role"] + "-callback")
        if row.get("queryID") and row["event"] != "query.begin":
            row["queryClient"] = "edited-client"
        if row["event"] == "query.namedRanges":
            row.update(namedRangesSHA256=digest(row["namedRanges"]), range="{0,3}", clientVersion="1")
        if row["event"] == "query.application":
            row.update(tokens="text:{0,3}", tokensSHA256=digest("text:{0,3}"), tokenCount="1", action="replace", clearRange="{0,3}")
    setter_index = next(i for i, e in enumerate(events) if e["event"] == "paint.set.returned")
    events.insert(setter_index, {**events[setter_index], "attributes": ""})
    events.extend({"event": "fixture.state", "stage": stage} for stage in [
        "invalidate.call.begin", "invalidate.call.returned", "discard.call.begin", "discard.call.returned",
        "rebuild.call.begin", "rebuild.call.returned",
    ])
    events.extend({**run, "stage": stage, "originalComparisonMatches": "notPrimary"}
                  for stage in ["after2s", "afterInvalidation", "afterRebuild"])
    events.append({"event": "session.finish"})
    trace = {"schema": 2, "processID": 444, "session": label, "label": label, "events": events,
             "droppedEvents": 0, "collectionEnded": True, "quiescenceAsserted": False, "pendingObservedWork": []}
    recount(trace)
    return trace


def recount(trace):
    for index, event in enumerate(trace["events"]):
        event["sequence"] = str(index + 1)
    trace["payloadBytes"] = sum(len(k.encode()) + len(v.encode()) for row in trace["events"] for k, v in row.items())


class TraceIntegrityTests(unittest.TestCase):
    def validate(self, mutate=None):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for label in sorted(collector.EXPECTED_TRACE_LABELS):
                trace = fixture(label)
                if mutate:
                    mutate(trace)
                recount(trace)
                (root / (label + ".json")).write_text(json.dumps(trace))
            return collector.validate_traces(root, {444})

    def test_complete_evidence_can_retain_a_failed_primary_comparison(self):
        result = self.validate()
        self.assertEqual(result["outcome"], "passed")
        self.assertTrue(all(s["attribution"]["primary_matches"] == "false" for s in result["sessions"]))

    def test_wrong_process_is_not_same_process_evidence(self):
        with self.assertRaises(collector.DiagnosticFailure):
            self.validate(lambda t: t.update(processID=445))

    def test_corrupt_style_hash_is_rejected(self):
        def mutate(t):
            next(e for e in t["events"] if e["event"] == "paint.after")["renderedSHA256"] = "0" * 64
        with self.assertRaises(collector.DiagnosticFailure):
            self.validate(mutate)

    def test_missing_application_boundary_is_rejected(self):
        with self.assertRaises(collector.DiagnosticFailure):
            self.validate(lambda t: t.update(events=[e for e in t["events"] if e["event"] != "paint.after"]))

    def test_setter_from_another_client_is_rejected(self):
        def mutate(t):
            next(e for e in t["events"] if e["event"] == "paint.set.returned")["queryClient"] = "fresh-client"
        with self.assertRaises(collector.DiagnosticFailure):
            self.validate(mutate)

    def test_setter_outside_application_is_rejected(self):
        def mutate(t):
            row = next(e for e in t["events"] if e["event"] == "paint.set.returned")
            t["events"].remove(row)
            t["events"].insert(-1, row)
        with self.assertRaises(collector.DiagnosticFailure):
            self.validate(mutate)

    def test_changed_primary_reference_identity_is_rejected(self):
        def mutate(t):
            next(e for e in t["events"] if e.get("stage") == "afterInvalidation")["initialReferenceSHA256"] = digest("changed")
        with self.assertRaises(collector.DiagnosticFailure):
            self.validate(mutate)

    def test_dropped_events_are_not_complete_evidence(self):
        with self.assertRaises(collector.DiagnosticFailure):
            self.validate(lambda t: t.update(droppedEvents=1))

    def test_missing_failure_probe_boundary_is_rejected(self):
        with self.assertRaises(collector.DiagnosticFailure):
            self.validate(lambda t: t.update(events=[e for e in t["events"] if e.get("stage") != "invalidate.call.begin"]))

    def test_missing_provider_output_is_rejected(self):
        with self.assertRaises(collector.DiagnosticFailure):
            self.validate(lambda t: t.update(events=[e for e in t["events"] if e["event"] != "query.namedRanges"]))

    def test_required_causal_payload_deletions_are_rejected(self):
        cases = {
            "client.bind": ["tree", "generation", "callbackContext"],
            "query.application": ["tokens", "tokensSHA256", "tokenCount", "action", "clearRange"],
            "query.namedRanges": ["namedRanges", "namedRangesSHA256", "range", "clientVersion"],
            "paint.before": ["renderedRuns", "renderedSHA256"],
            "paint.after": ["renderedRuns", "renderedSHA256"],
            "paint.set.returned": ["requestedRange", "clampedRange", "attributes"],
        }
        for event, fields in cases.items():
            for field in fields:
                def mutate(t):
                    next(e for e in t["events"] if e["event"] == event).pop(field)
                with self.subTest(event=event, field=field), self.assertRaises(collector.DiagnosticFailure):
                    self.validate(mutate)

    def test_missing_one_setter_is_rejected_even_if_others_exist(self):
        def mutate(t):
            t["events"].remove(next(e for e in t["events"] if e["event"] == "paint.set.returned"))
        with self.assertRaises(collector.DiagnosticFailure):
            self.validate(mutate)

    def test_ordered_duplicate_tokens_and_setters_are_preserved(self):
        def mutate(t):
            app = next(e for e in t["events"] if e["event"] == "query.application")
            app.update(tokens="text:{0,3}|text:{0,3}", tokensSHA256=digest("text:{0,3}|text:{0,3}"), tokenCount="2")
            index = max(i for i, e in enumerate(t["events"]) if e["event"] == "paint.set.returned")
            t["events"].insert(index + 1, copy.deepcopy(t["events"][index]))
        self.assertEqual(self.validate(mutate)["outcome"], "passed")


if __name__ == "__main__":
    unittest.main()
