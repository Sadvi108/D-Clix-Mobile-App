# Tournament — findings, app change and backend request

15 September 2026.

## Findings

- Production Swagger (69 routes) and UAT (73) have one tournament route:
  `POST /Reports/TournamentSummary`.
- It is a **medal summary, not a tournament list**. Rows carry `id`, `name`, `gender`,
  `playerCount`, `medalGold`, `medalSilver`, `medalBronze` (live checks 10 Aug and 15 Sep).
  `name` is often empty (rows grouped by gender). No date, venue, status or registration.
- Dates in the request are ignored: an unfiltered request, 1–2 Jan 2019 and 1–2 Jan 2030
  returned identical rows for an instructor. `reportType` must be numeric or it answers 400.
- Test accounts: student A 1 row, student B 0 rows, instructor 2 rows.

The Expo "Competition" screen (and the Flutter port) showed Upcoming / Past tabs that did
not filter anything; every card was stamped UPCOMING or COMPLETED by the selected tab. The
instructor reports listed "Tournaments (Past)" and "Upcoming Tournaments" with identical rows.

## App change

- Student: **Tournament** (Home and More, route `/tournament`; `/competition` redirects).
  Medal and player totals, one card per summary row with category / age group / gender tags,
  filter pills only when rows carry more than one real tournament name. Empty state says no
  results were returned for the account. A note explains dates and registration are not in
  the club system yet. No tabs, no status badge.
- Instructor: one **Tournament Summary** report (reports list and home tile, route
  `/instructor/reports/tournament-summary`). The old past / upcoming / generic tournament
  routes redirect to it.

## Backend request

1. `GET /Tournament/List?status=upcoming|ongoing|past` — for the member's club/branch:
   `tournamentId`, `name`, `startDate`, `endDate`, `timezone`, `venue`, `status`,
   `registrationClosingDate`, `categories` / `ageGroups`, `fee`, `posterUrl`, and for the
   token holder `eligible` and `registrationStatus`. Upcoming/past must use real dates.
2. `GET /Tournament/MyResults` — per student: `tournamentId`, tournament name and date,
   `category`, `ageGroup`, `placement` / `medal`. Guardians: include `studentId` + name per row.
3. `/Reports/TournamentSummary` rows should include `tournamentId` and a non-empty `name`
   so results can be tied to a tournament.
4. Optional: `POST /Tournament/Register` `{tournamentId, studentId, category}` with the
   registration status in the response.

Once 1 exists, the Tournament screen gets real Upcoming / Past tabs from dates; 2 replaces the
summary cards with per-event results.
