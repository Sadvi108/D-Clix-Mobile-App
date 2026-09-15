# Progress Report, Belt / Rank and Grading — agreed spec

Agreed 15 September 2026 by Claude (`~/Projects/Dclix`, repo `D-Clix-Mobile-App`) and Codex
(`~/Desktop/Club-Management-Mobile-app-main`, repo `Club-Management-Mobile-app`). Both repos
implement this same spec independently. It replaces both agents' first versions.

## Why the first versions were not enough

| First version | Problem |
| --- | --- |
| Claude | Substring status match counted "Not present" as present; unknown statuses counted as missed; `defaultRange()` ends next year so future rows counted; hero showed 0% with no data; an empty grade fell back to a stale cached grade; selected sibling fell back to all rows; belt journey implied a next rank and completed belts the API cannot prove. |
| Codex | Attendance kept a row only when its name equalled `displayName`; live rows are not shown to carry a name, so real members could see an empty report. Belt / Rank hid the grade unless `MyInfo.name` equalled `displayName`. Material chips off the app's look; history list duplicated Attendance. |

## Identity and scoping (shared by all three screens)

Sibling switching is a client-side filter (`UserSession.activeStudentName`); the token stays
the guardian's, and `/Profile/MyInfo` always describes the token's student.

- **Identity match:** `icNo` equal, or names equal after trim, whitespace collapse and case fold.
  No fuzzy matching.
- **Self** (no sibling selected, or the selected sibling is the token's own student): keep rows
  with no name/`icNo` (anonymous — the endpoint ran with the member's token) and rows that
  match self. Reject every row that names someone else, even when only one other person
  appears.
- **Selected sibling:** keep only positive matches. Anonymous or non-matching rows are never
  shown; the screen says the data is not available for the selected student.
- Anonymous rows belonging to self is an endpoint assumption pending the live check below.

## `/progress` — Progress Report

1. Selected student's name.
2. Period chips **30 / 90 / 365 days**, default **90**, exact dates shown. Chips drive only the
   hero rate and the Present / Absent / Other counts.
3. Hero: `Present / (Present + Absent)` rounded; `—` when that denominator is 0. Status match
   is exact after trim + case fold (`present`, `absent`); anything else is Other.
4. **Recent activity** (fixed, labelled independent of the period): this month's Present count,
   last month's Present count, consecutive Monday-start weeks with a Present session (an
   unfinished current week does not break it; a streak reaching the fetch boundary reads
   "at least N weeks"), latest Present date.
5. **Last 6 months** chart including the current month: Present and Absent per month; Other
   is not drawn as missed.
6. Links to Attendance and Belt / Rank. No duplicated history list.
7. Fetch from the earlier of 12 calendar months ago or 364 days before today, through the end
   of today. Locally drop future and invalid dates; say how many invalid-date rows were
   excluded.

## `/belt-rank` — Belt / Rank

- Exact `currentGrade` as the main content; sub-ranks kept (`Grade 5 (Green 2)`).
- Colour accent only when exactly one belt colour word matches; otherwise neutral.
- Training centre and instructor from the same `MyInfo` when present.
- Note: ask your instructor about the next rank and requirements.
- Link to Progress Report.
- No belt journey, next rank, checkmarks or "top belt".
- A successful `MyInfo` with an empty grade clears any cached grade. Cached self data may show
  only while the first request is pending or failed, never for a selected sibling.
- Selected sibling: grade shown only when `MyInfo` positively matches that student.

## `/grading` — Grading Schedule

- Student More tile removed in both repos. The Codex repo keeps its `/grading` route; the
  Claude repo never had one. Instructor Grading Schedule / Grade Completed reports unchanged.
- Code comments say the report "returned empty for the test student accounts", not "always".

## States

- Initial load: spinner. Initial failure: retry, no metrics.
- Refresh failure with data from the same identity: keep data, show a stale notice.
- Empty result and identity-unavailable are different messages.
- `rn_kit` styling, pull-to-refresh, `LiveRefreshMixin`.

## Shared test cases

Anonymous self rows; single other named person rejected; sibling no-match; name spacing/case;
`icNo` match; cleared grade; unknown status; future and invalid dates; month and year
boundaries; streak across weeks, unfinished current week, boundary "at least"; rate `—`
with no Present/Absent; colour accent ambiguous vs single.

## Open: live check (Codex Desktop agent, holds the test accounts)

Report field **names only** (no values) from `/Reports/Attendance` and `/Profile/MyInfo` for a
student account and a guardian account with siblings: does each attendance row carry
`studentName`, `name` or `icNo`? Does `MyInfo` carry `name` / `icNo`? If attendance rows
carry no identity field for a guardian with siblings, sibling Progress Report stays
"not available" until the backend adds one.
