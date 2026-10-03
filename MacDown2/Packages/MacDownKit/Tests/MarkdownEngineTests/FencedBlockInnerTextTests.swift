@testable import MarkdownEngine
import Testing

/// Preview shows a diagram while the author is still typing its fence: a missing closing line must not
/// cost the last content line (the old code removed the last physical line whatever it was).
struct FencedBlockInnerTextTests {
    @Test func aTerminatedFenceLosesBothDelimiters() {
        #expect("```mermaid\ngraph TD\nA-->B\n```".fencedBlockInnerText() == "graph TD\nA-->B")
    }

    @Test func anUnterminatedFenceKeepsItsLastContentLine() {
        #expect("```mermaid\ngraph TD\nA-->B\n".fencedBlockInnerText() == "graph TD\nA-->B")
        #expect("```mermaid\ngraph TD\nA-->B".fencedBlockInnerText() == "graph TD\nA-->B")
    }

    @Test func tildeLongerAndIndentedClosingFencesAreRecognised() {
        #expect("~~~d2\nx -> y\n~~~".fencedBlockInnerText() == "x -> y")
        #expect("````dot\ndigraph {}\n````".fencedBlockInnerText() == "digraph {}")
        #expect("  ```dot\n  digraph {}\n  ```  ".fencedBlockInnerText() == "  digraph {}")
    }

    @Test func aContentLineThatMerelyStartsWithBackticksIsNotAClosingFence() {
        #expect("```mermaid\ngraph TD\n`x`".fencedBlockInnerText() == "graph TD\n`x`")
    }

    @Test func aLoneOpeningLineHasNoContent() {
        #expect("```mermaid".fencedBlockInnerText() == "")
    }

    @Test func aShorterOrDifferentFenceLineInsideTheBlockIsContentNotACloser() {
        #expect("````dot\na\n```".fencedBlockInnerText() == "a\n```")
        #expect("```dot\na\n~~~".fencedBlockInnerText() == "a\n~~~")
        #expect("~~~dot\na\n~~~~".fencedBlockInnerText() == "a")
    }
}
