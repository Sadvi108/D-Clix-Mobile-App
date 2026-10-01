// A fake Club.Api for screenshot capture.
//
// Uses package:http's MockClient through the injectable [ApiService.client]. The previous
// attempt intercepted dart:io with HttpOverrides, which meant hand-implementing HttpClient,
// HttpClientRequest and HttpClientResponse — requests arrived and responses silently never
// came back. Injecting one client is a fraction of the surface and cannot drift from what
// package:http actually expects.
//
// EVERY VALUE HERE IS INVENTED. The Expo guide once shipped screenshots containing a real
// member's name, phone number and member QR. Keeping the fixture in source means a capture
// physically cannot contain anyone's record.
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:qr/qr.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Wrap the API's `{status, meta, data}` envelope around a payload.
Map<String, dynamic> _env(dynamic data) => {
      'status': true,
      'meta': {'message': 'ok'},
      'data': data,
    };

const _member = {
  'id': 1,
  'userId': 1,
  'name': 'Alex Tan',
  'registrationNo': 'DCX-0001',
  'studentCode': 'DCX-0001',
  'icNo': '000000-00-0000',
  'currentGrade': 'Green Belt',
  'tCenterName': 'Sample Training Centre',
  'eCenterName': 'Sample Exam Centre',
  'instructorName': 'Sensei Sample',
  'trainingTme': '8:00 PM - 9:30 PM',
  // The grading and tournament keys a student's MyInfo carries (Home's "Your info" card).
  'lastGradingDate': '2026-08-08T00:00:00',
  'tournamentName': 'Sample Open Championship 2026 @ Sample Sports Complex',
  'tournamentDate': '2026-10-10T00:00:00',
  'tournamentToDate': '2026-10-10T00:00:00',
  'handPhone': '000-0000000',
  'emailAddress': 'member@example.com',
  'gender': 'Male',
  'address1': '1 Sample Street',
  'postalCode': '43000',
  'clubName': 'D-CLIX Sample Academy',
  'clubId': 1,
  'branchId': 1,
  'attendancePercentage': '92',
};

const _booking = {
  'id': 9001,
  'bookingDate': '2026-09-12T20:00:00',
  'classDate': '2026-09-12T20:00:00',
  'tCenterName': 'Sample Training Centre',
  'instructorName': 'Sensei Sample',
  'tTimeFrom': '8:00 PM',
  'tTimeTo': '9:30 PM',
  'dayOfWeek': 'Saturday',
  'status': 'Confirmed',
  'studentName': 'Alex Tan',
};

final Map<String, dynamic> _routes = {
  '/Profile/MyInfo': _env(_member),
  '/Profile/StudentAddtnlInfo': _env({
    'schoolname': 'Sample Secondary School',
    'dob': '2010-04-02T00:00:00',
    'bloodtype': 'O+',
    'healthstatus': 'Good',
    'mobileNo': '000-0000000',
  }),
  '/Profile/MyClubStats': _env([
    {'id': 1, 'text': 'Members', 'value': '128'},
    {'id': 2, 'text': 'Centres', 'value': '6'},
  ]),
  '/Profile/MyUnreadNotificationCount': _env(2),
  '/Profile/MyNotifications': _env([
    {
      'id': 101,
      'groupId': 'g-101',
      'notificationType': '',
      'text': 'Fee reminder',
      'value':
          'Your September fee of RM85.00 is now due. Tap Pay Now to settle it.',
      'isRead': false,
      'createdDate': '2026-09-09T09:15:00',
    },
    {
      'id': 102,
      'groupId': 'g-102',
      'notificationType': '',
      'text': 'Class Activity',
      'value':
          'Grading practice this Saturday at 10:00 AM. Please attend in full uniform.',
      'isRead': false,
      'createdDate': '2026-09-08T18:40:00',
    },
    {
      'id': 103,
      'groupId': 'g-103',
      'notificationType': '',
      'text': 'Announcement',
      'value': 'The centre will be closed on the public holiday next Monday.',
      'isRead': true,
      'createdDate': '2026-09-05T12:00:00',
    },
  ]),
  '/Reports/HomePageStats': _env({
    'invoiceCount': 2,
    'dueAmount': 170.00,
    'currentGrade': 'Green Belt',
    'myoffers': [
      {
        'code': 'SAMPLE10',
        'title': 'Members save 10% on uniforms',
        'description': 'Show this screen at the counter. Sample offer.',
        'expiryDate': '2099-12-31T00:00:00',
      },
      {
        'code': 'SAMPLE20',
        'title': 'Bring a friend — free trial class',
        'description': 'Sample offer for illustration only.',
      },
    ],
    'mynews': [
      {
        'title': 'Inter-club tournament',
        'value': 'Registration opens next week.'
      },
    ],
  }),
  '/Outstanding/Fetch': _env([
    {
      'id': 5001,
      'invoiceNo': 'INV-2026-0091',
      'invoiceDescription': 'Monthly fee — September 2026',
      'transactionType': 'Monthly Fee',
      'period': 'Sep 2026',
      'dueAmount': 85.00,
      'invoiceDate': '2026-09-01T00:00:00',
      'studentId': 1,
      'studentName': 'Alex Tan',
      'centerName': 'Sample Training Centre',
    },
    {
      'id': 5002,
      'invoiceNo': 'INV-2026-0078',
      'invoiceDescription': 'Monthly fee — August 2026',
      'transactionType': 'Monthly Fee',
      'period': 'Aug 2026',
      'dueAmount': 85.00,
      'invoiceDate': '2026-08-01T00:00:00',
      'studentId': 1,
      'studentName': 'Alex Tan',
      'centerName': 'Sample Training Centre',
    },
  ]),
  '/Outstanding/CollectionCount': _env({'cash': 3, 'fpx': 5, 'dbt': 2}),
  '/Listing/MySiblings': _env([
    {'id': 1, 'text': 'Alex Tan', 'value': '1'},
    {'id': 2, 'text': 'Sam Tan', 'value': '2'},
  ]),
  '/Listing/InvoceTypes': _env([
    {'id': 1, 'text': 'Monthly Fee', 'value': '1'},
  ]),
  '/Listing/TrainingCenters': _env([
    {'id': 1, 'text': 'Sample Training Centre', 'value': '1'},
    {'id': 2, 'text': 'Second Sample Centre', 'value': '2'},
  ]),
  '/Listing/Instructors': _env([
    {'id': 1, 'text': 'Sensei Sample', 'value': '1'},
  ]),
  '/Listing/TrainingTimeByTcId': _env([
    {
      'id': 1,
      'dayOfWeek': 'Tuesday',
      'tTimeFrom': '8:00 PM',
      'tTimeTo': '9:30 PM',
      'tCenterName': 'Sample Training Centre',
      'instructorName': 'Sensei Sample',
    },
    {
      'id': 2,
      'dayOfWeek': 'Saturday',
      'tTimeFrom': '10:00 AM',
      'tTimeTo': '11:30 AM',
      'tCenterName': 'Sample Training Centre',
      'instructorName': 'Sensei Sample',
    },
  ]),
  // The member's weekly timetable: Schedule's orange dots and session cards.
  '/Reports/StudentDetails': _env([
    for (final (day, from, to) in const [('Tuesday', '8:00 PM', '9:30 PM'), ('Saturday', '10:00 AM', '11:30 AM')])
      {
        'studentId': 1,
        'studentName': 'Alex Tan',
        'dayOfWeek': day,
        'tTimeFrom': from,
        'tTimeTo': to,
        'tCenterName': 'Sample Training Centre',
        'instructorName': 'Sensei Sample',
        'currentGrade': 'Green Belt',
      },
  ]),
  '/ClassBooking/NextBookings': _env([_booking]),
  '/ClassBooking/GetBookings': _env([
    _booking,
    {..._booking, 'id': 9002, 'bookingDate': '2026-09-19T20:00:00'},
  ]),
  '/ClassBooking/PackageInfo':
      _env({'packageName': 'Standard', 'sessionsLeft': 8}),
  '/ClassBooking/TrainingTimeWithDateAndInstructor': _env([
    {
      'id': 1,
      'dayOfWeek': 'Saturday',
      'tTimeFrom': '10:00 AM',
      'tTimeTo': '11:30 AM',
      'tCenterName': 'Sample Training Centre',
      'instructorName': 'Sensei Sample',
      'classDates': ['2026-09-12T10:00:00', '2026-09-19T10:00:00'],
    },
  ]),
  '/Reports/Attendance': _env([
    {
      'id': 1,
      'attendanceDate': '2026-09-09T20:05:00',
      'status': 'Present',
      'tCenterName': 'Sample Training Centre',
      'studentName': 'Alex Tan',
    },
    {
      'id': 2,
      'attendanceDate': '2026-09-05T20:02:00',
      'status': 'Present',
      'tCenterName': 'Sample Training Centre',
      'studentName': 'Alex Tan',
    },
    {
      'id': 3,
      'attendanceDate': '2026-09-02T20:00:00',
      'status': 'Absent',
      'tCenterName': 'Sample Training Centre',
      'studentName': 'Alex Tan',
    },
  ]),
  '/Reports/GradingSchedule': _env([
    {
      'id': 1,
      'gradingDate': '2026-11-15T09:00:00',
      'grade': 'Blue Belt',
      'eCenterName': 'Sample Exam Centre',
      'paymentStatus': 'Not Paid',
      'studentName': 'Alex Tan',
    },
    {
      'id': 2,
      'gradingDate': '2026-05-10T09:00:00',
      'grade': 'Green Belt',
      'eCenterName': 'Sample Exam Centre',
      'paymentStatus': 'Paid',
      'studentName': 'Alex Tan',
    },
  ]),
  '/Reports/TournamentSummary': _env([
    {
      'id': 1,
      'name': 'Sample Open 2026',
      'ageGroup': 'U14',
      'gender': 'Male',
      'category': 'Kata',
      'playerCount': 4,
      'medalGold': 1,
      'medalSilver': 1,
      'medalBronze': 2,
    },
    {
      'id': 2,
      'name': 'Sample Invitational',
      'ageGroup': 'U16',
      'gender': 'Mixed',
      'category': 'Kumite',
      'playerCount': 6,
      'medalGold': 0,
      'medalSilver': 2,
      'medalBronze': 1,
    },
  ]),
  '/Reports/PurchaseRequests': _env([
    {
      'id': 1,
      'itemName': 'Training uniform (size 4)',
      'requestDate': '2026-08-14T00:00:00',
      'status': 'Approved',
      'amount': 120.00,
    },
    {
      'id': 2,
      'itemName': 'Club badge',
      'requestDate': '2026-07-02T00:00:00',
      'status': 'Collected',
      'amount': 15.00,
    },
  ]),
  '/PurchaseRequest/FetchProducts': _env([
    {
      'productId': 1,
      'name': 'Training uniform',
      'category': 'Uniform',
      'code': 'UNI-01',
      'price': 120.00,
    },
    {
      'productId': 2,
      'name': 'Club badge',
      'category': 'Accessory',
      'code': 'ACC-02',
      'price': 15.00,
    },
    {
      'productId': 3,
      'name': 'Sparring gloves',
      'category': 'Equipment',
      'code': 'EQP-03',
      'price': 88.50,
    },
  ]),
};

/// Longest-prefix match, so parameterised paths (`/Listing/TrainingTimeByTcId/1`) still
/// find their fixture.
dynamic lookupFixture(String path) {
  if (_routes.containsKey(path)) return _routes[path];
  String? best;
  for (final key in _routes.keys) {
    if (path.startsWith(key) && (best == null || key.length > best.length))
      best = key;
  }
  // An unknown route returns an empty list rather than an error: a screen showing its
  // empty state is a truthful picture, an exception is a blank one.
  return best == null ? _env(const []) : _routes[best];
}

/// A client that answers every request from the fixture above.
http.Client fakeApiClient() => MockClient((request) async {
      if (request.url.path.startsWith('/Utilities/QRCode/')) {
        // Generate a real QR for an explicitly fictional guide payload. Never use a member ID.
        final qr = QrImage(QrCode.fromData(
            data: 'DCLIX-GUIDE-SAMPLE-ONLY',
            errorCorrectLevel: QrErrorCorrectLevel.M));
        const cell = 8.0;
        final side = ((qr.moduleCount + 8) * cell).toInt();
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawPaint(ui.Paint()..color = const ui.Color(0xFFFFFFFF));
        for (var y = 0; y < qr.moduleCount; y++) {
          for (var x = 0; x < qr.moduleCount; x++) {
            if (qr.isDark(y, x))
              canvas.drawRect(
                  ui.Rect.fromLTWH((x + 4) * cell, (y + 4) * cell, cell, cell),
                  ui.Paint()..color = const ui.Color(0xFF000000));
          }
        }
        final picture = recorder.endRecording();
        final image = await picture.toImage(side, side);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return http.Response.bytes(bytes!.buffer.asUint8List(), 200,
            headers: {'content-type': 'image/png'});
      }
      return http.Response(jsonEncode(lookupFixture(request.url.path)), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
