# MostlyText trademark and name search record

**Owner summary.** This is a log of name and figurative-mark searches for
"MostlyText" and the Slant M+T mark. It records what was searched, where, when
and what was found. **It draws no legal-risk conclusion.** Whether any finding
matters legally is for a qualified trademark professional. As of 2026-09-25 the
three register searches (WIPO, USPTO, IPOS) have **not yet been run**: those
systems can't be queried from the design lane's automated environment. The
exact queries to run are below, followed by a log of what was done.

## What to search

**Word marks**

| Query | Why |
|---|---|
| `MOSTLYTEXT` | The product name as one word |
| `MOSTLY TEXT`, `MOSTLY-TEXT` | Spaced and hyphenated forms |
| `MOSTLY*` in the classes below | Marks that start with the same word |
| `*TEXT` in the classes below, filtered for software | To catch close "…Text" editor names |
| `MARKTEXT`, `MARK TEXT` | An existing open-source Markdown editor with a similar name pattern |
| `MOSTLYTXT`, `MOSTLI TEXT` | Spelling and sound variants |

**Figurative mark:** the Slant M+T mark (`design/brand/slant/validation/slant-master.svg`,
exported as PNG for upload). Search it by image where the database supports
that, and by classification code:
- **Vienna classification** (WIPO, IPOS): category 27, "forms of writing".
  Choose the sections for letters in a special form and linked or overlapping
  letters in the database's own code picker when searching. They are not
  pre-selected here, to avoid recording an unchecked code.
- **USPTO design search codes:** category 27, "forms of writing"
  (https://tmdesigncodes.uspto.gov/category/27). Choose the stylised-letter and
  overlapping-letter sections in the manual when searching.
- Also search figuratively for single stylised **M** marks, to cover the
  BMW M perceptual neighbour noted in D-021.

**Classes (Nice classification):**
- **9:** downloadable computer software, text-editing software.
- **42:** software design and development, software as a service.
- Also record, without filtering to them, any hits in **35**, **38** and **41**
  that use the identical word.

## Databases

| Database | URL | Coverage | Status (2026-09-25) |
|---|---|---|---|
| WIPO Global Brand Database | https://branddb.wipo.int | Madrid international registrations plus many national offices; supports image search | **Not run.** Automated access hit a CAPTCHA page. Run manually. |
| USPTO Trademark Search | https://tmsearch.uspto.gov | United States | **Not run.** The search app is JavaScript-only and returned no results to automated access. Run manually. |
| IPOS Digital Hub | https://digitalhub.ipos.gov.sg (Similar Mark Search and Trade Mark search) | Singapore | **Not run.** An interactive e-service, not queried automatically. Run manually. |

## Search log

Add one row per query per database. Record **all** relevant hits, even ones
that look harmless. Assessment belongs to the reviewer, not the log.

| Date | Searcher | Database | Query / code | Filters (classes, status) | Results | Relevant hits (mark, owner, number, classes, status) |
|---|---|---|---|---|---|---|
| 2026-09-25 | Design lane (automated) | WIPO Global Brand Database | `mostlytext` (brand name) | none | Not retrieved: CAPTCHA | — |
| 2026-09-25 | Design lane (automated) | USPTO Trademark Search | `mostlytext` | none | Not retrieved: JavaScript-only app | — |
| | | IPOS Digital Hub | | | | |

## Web pre-screen (not a register search)

These are general web searches, recorded so they aren't repeated. They say
nothing about registered rights.

| Date | Query | Engine | Finding |
|---|---|---|---|
| 2026-09-25 | `MostlyText app` | Web search | No product or company named MostlyText in the results. Results were for similarly named apps (MightyText, Simpletext, SimpleText). |
| 2026-09-25 | `"MostlyText"` | Web search | No product or company named MostlyText. Unrelated uses of the phrase "mostly text" (a printer copy-quality setting, translation pages). |
| 2026-09-25 | `"Mostly Text" app OR software OR editor` | Web search | No product named "Mostly Text". General text editors only. |
| 2026-09-25 | `MarkText markdown editor logo icon` | Web search | MarkText exists: an open-source Markdown editor for Mac, Windows and Linux (github.com/marktext/marktext; marktext.me). The logo was not retrieved for visual comparison. |
| 2026-09-25 | Visual-neighbour screen (see the validation board, §3) | Web search | BMW M recorded as the strongest perceptual neighbour. Others: generic MT/TM stock monograms, Monzo, M&T Bank, Microsoft Teams, the Markdown mark. |

Domains held by the owner, per `planning/MIGRATION_PLAN.md` O1:
`mostlytext.app` and `mostlytext.dev`.

## Handing to a reviewer

Give the reviewer this file, `slant-master.svg`, the lockup specification
(D-015) and the intended classes. The reviewer's conclusion should be recorded
as a new decision in `design/DECISIONS.md`, not in this log.
