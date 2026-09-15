# Instructor manual attendance — findings and plan

Status: **blocked on the backend**, one untested client-side path left. 15 September 2026.

## Request

An instructor picks a training centre and class time, sees the class list, marks students
present and saves.

## What the current API allows

Production Swagger (69 routes) has one attendance write, `POST /Attendance/Add`
`{qrCode, attendanceType, tTimeId?}`. No `studentId`, no date, no bulk form.

Live probe, 12 August 2026, instructor token (userType 2, `isAllowAttendance: true`), test
student in that instructor's centre roster:

| Body (attendanceType 2) | Result |
| --- | --- |
| `ST-` student code, no class time | `-1 Invalid QR Code` |
| bare student id + class time | `-1 Invalid QR Code` |
| registration code + class time | `-1 Invalid QR Code` |

The same call with a student token answers "Invalid Instructor details", so the backend has an
instructor branch; it just does not accept any tried student identifier. `qrCode` is only
parsed as a centre code (`TC-` + id padded to 8). `/Reports/Attendance` returns 0 rows to an
instructor, so the app also cannot show who has checked in. No rows were created.

**Still untested:** `ST-` code *with* a class time under types 2/1/3/0, and the roster `value`
field with a class time. Probe: `flutter_app/tool/probe_manual_attendance.dart` (read-only by
default; `PROBE_WRITE=true` creates a real record on success, test student only).

The club already prints student QR posters (`/Utilities/StudentQRCode`, `ST-` codes), so some
scanner in the club system accepts them. It may use a route that is not in the mobile API.

## Backend request (if the probe finds nothing)

1. `POST /Attendance/MarkByInstructor` — instructor token, body
   `{tCenterId, tTimeId, attendanceDate, entries: [{studentId, attendanceTypeId}]}`.
   Validates each student belongs to the centre and the instructor may mark it. Idempotent per
   student + class time + date. Response lists the result per student.
2. `POST /Attendance/Undo` (or `attendanceTypeId` update) to correct a mistake.
3. `/Reports/Attendance` returns a centre's rows to an instructor for `tCenterId` + date +
   `tTimeId`, so the register shows who is already marked.
4. Attendance type list (Present / Absent / Leave ids) from `DropdownListByType` or the new
   route.

## App (Claude repo, implemented 15 September 2026)

Class Check-In has the register built against contract item 1:

- `lib/services/manual_attendance.dart` reads the server's Swagger route table once per session.
  The register appears only when `/Attendance/MarkByInstructor` is listed, so it goes live
  with the backend without an app update. A failed check is retried, never cached as "off".
- When live: tap students to tick them (Select all / Clear all), choose a training time (Save
  stays disabled until then), confirm, save. Each student shows the server's result; a student
  the response does not mention is shown as not confirmed, never assumed marked. Saved students
  are unticked. Results are dropped if the centre changed during the save.
- When not live: the class list and centre QR work as before, with a note that marking needs
  a backend update.
- `attendanceTypeId: 1` for Present is assumed from report rows; confirm with the backend.
- Tests: `test/manual_attendance_test.dart` (availability, body, per-student results, errors)
  and two Class Check-In widget tests in `test/react_native_parity_test.dart`.

**If the probe finds a working `/Attendance/Add` body:** swap `ManualAttendance.markPresent`
to post that body once per student and make `isAvailable` return true; the UI stays the same.
