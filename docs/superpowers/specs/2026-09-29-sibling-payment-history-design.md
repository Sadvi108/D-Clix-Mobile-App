# Sibling payments in Payment History — design

2026-09-29 · Approved in session.

## Problem

A student who pays a sibling's invoice sees no record of it. The payment itself works:
`BoostPayment.confirm` reconciles every account in the cart, and the Pay tab reloads the
sibling's dues. The receipt is what goes missing.

- The Pay tab has its own account chips (`_activeAccount` in `payments_screen.dart`), but
  History ignores them. History filters with `session.scopedRows` (`payments_screen.dart:462`),
  and with no sibling selected app-wide that falls to `scopeToSelf`, which drops every receipt
  that names someone else. The sibling's receipt names the sibling.
- The sibling's receipts show only after switching the whole app to that sibling (Home or
  Profile switcher). The Pay tab does not follow that switch (`_accountId` ignores
  `activeStudentId`), so Pay and History can show two different children at once.
- History cards never say whose receipt they are.

## Decision

One account chip for the whole Payments screen, shared by Pay and History. Rejected:

- Per-child server fetch (`/Reports/Receipts` with `sourceKeyId`): unverified for a student
  token, and one extra request per child.
- Chips that switch the app-wide student: re-scopes Home, Progress and the rest as a side effect.

## Behaviour

- The chip row shows above both Pay and History. One selection; switching tabs keeps it.
- History lists only the selected child's receipts.
- The chip starts on the app-wide selected student (`session.activeStudentId`) when that is
  one of the chips, otherwise on the signed-in student. Both sides carry `/Listing/MySiblings`
  ids, so they match by id.
- After paying for a sibling, the screen stays on that sibling's chip, so the receipt shows as
  soon as History reloads.
- Advance Payment keeps its own multi-select of accounts; it is not changed.

## Data flow

- Receipts are fetched exactly as today (`RnApi.receipts`, one request).
- History narrows them with `scopeStudentRows` (`lib/utils/progress_stats.dart`), the rule the
  Progress screens already use: for the signed-in student, rows that match them by name or IC
  plus rows that name nobody; for a sibling, only rows positively matched by name.
- The signed-in student's identity is the auth record's `name` and `icNo`; a sibling's is the
  `text` of its `/Listing/MySiblings` row.

## Privacy

`/Reports/Receipts` returns the whole branch to a student token. A sibling chip therefore
shows only receipts positively matched to that sibling, never unattributed or other students'
rows. The server-side scoping of that route is out of scope here and belongs with the backend
asks.

## Empty states

- Receipts exist, none for the selected child: "No receipts for {name} yet."
- No receipts at all: "No receipts found." (unchanged)

## Testing (written first, each seen failing)

1. After paying for sibling B, History on B's chip lists B's receipt.
2. The signed-in student's chip never lists B's or an unrelated student's receipt.
3. The chip starts on the app-wide selected sibling.
4. Pay and History stay on the same child when switching tabs.

## Assumption and fallback

This relies on `/Reports/Receipts` returning the sibling's receipt to the payer's token, as
documented for student tokens. If the sibling's receipt still does not appear on their chip
after this ships, the server is not sending it; fall back to the per-child fetch above.
