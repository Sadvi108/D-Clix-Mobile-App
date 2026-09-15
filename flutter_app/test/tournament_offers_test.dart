// Parsing for the Tournament and Offers screens.
import 'package:flutter_test/flutter_test.dart';
import 'package:dclix_app/screens/tournament_screen.dart';
import 'package:dclix_app/screens/offers_screen.dart';

void main() {
  group('parseTournaments', () {
    test('reads rows out of the report envelope', () {
      final rows = parseTournaments({
        'status': true,
        'data': [
          {
            'name': 'MSSM 2026',
            'ageGroup': 'U14',
            'gender': 'Male',
            'category': 'Kata',
            'playerCount': 4,
            'medalGold': 1,
            'medalSilver': 0,
            'medalBronze': 2,
          }
        ]
      });
      expect(rows, hasLength(1));
      expect(rows.single.name, 'MSSM 2026');
      expect(rows.single.medals, 3);
      expect(rows.single.players, 4);
    });

    test('gender grouped medal rows remain visible without a tournament name',
        () {
      final rows = parseTournaments({
        'data': [
          {'name': '', 'gender': 'Female', 'medalGold': 5},
          {'name': 'Real Cup'},
        ]
      });
      expect(rows.map((r) => r.title), ['Female', 'Real Cup']);
      expect(rows.first.gold, 5);
      expect(tournamentNames(rows), ['Real Cup']);
    });

    test('counts arriving as strings still add up', () {
      final rows = parseTournaments({
        'data': [
          {
            'name': 'X',
            'medalGold': '2',
            'medalSilver': '1',
            'medalBronze': null
          }
        ]
      });
      expect(rows.single.medals, 3);
    });

    test('a junk payload is an empty list, not a crash', () {
      expect(parseTournaments(null), isEmpty);
      expect(parseTournaments({'data': 'nope'}), isEmpty);
    });
  });

  group('tournamentTotals', () {
    test('adds medals and players across rows', () {
      final t = tournamentTotals(parseTournaments([
        {'gender': 'Male', 'playerCount': 3, 'medalGold': 1, 'medalSilver': 2, 'medalBronze': 0},
        {'gender': 'Female', 'playerCount': 2, 'medalGold': 0, 'medalSilver': 1, 'medalBronze': 4},
      ]));
      expect((t.gold, t.silver, t.bronze, t.players), (1, 3, 4, 5));
    });

    test('no rows is all zero', () {
      final t = tournamentTotals(const []);
      expect((t.gold, t.silver, t.bronze, t.players), (0, 0, 0, 0));
    });
  });

  group('tournamentNames', () {
    test('distinct, in report order', () {
      final rows = parseTournaments({
        'data': [
          {'name': 'B'},
          {'name': 'A'},
          {'name': 'B'},
        ]
      });
      expect(tournamentNames(rows), ['B', 'A']);
    });
  });

  group('parseOffers', () {
    test('picks the first attachment image and resolves a relative path', () {
      final offers = parseOffers([
        {
          'code': 'RAYA25',
          'title': 'Raya Special',
          'description': '20% off uniforms',
          'attachments': [
            {'documentUrl': '/Uploads/Offers/raya.png'}
          ],
          'expiryDate': '2099-01-01T00:00:00',
        }
      ]);
      expect(offers.single.code, 'RAYA25');
      expect(offers.single.imageUrl, startsWith('http'));
      expect(offers.single.imageUrl, endsWith('/Uploads/Offers/raya.png'));
      expect(offers.single.isExpired, isFalse);
    });

    test('falls back to previewImages when there is no attachment', () {
      final offers = parseOffers([
        {
          'code': 'X',
          'previewImages': [
            {'documentUrl': 'http://cdn/x.png'}
          ]
        }
      ]);
      expect(offers.single.imageUrl, 'http://cdn/x.png');
    });

    test('an attachment entry with no url does not become a broken image', () {
      final offers = parseOffers([
        {
          'code': 'X',
          'attachments': [
            {'documentUrl': ''},
            {'documentUrl': '/Uploads/ok.png'}
          ]
        }
      ]);
      expect(offers.single.imageUrl, endsWith('/Uploads/ok.png'));
    });

    test('a past expiry marks the offer expired', () {
      final offers = parseOffers([
        {'code': 'OLD', 'expiryDate': '2020-01-01T00:00:00'}
      ]);
      expect(offers.single.isExpired, isTrue);
    });

    test('no expiry date never counts as expired', () {
      expect(
          parseOffers([
            {'code': 'FOREVER'}
          ]).single.isExpired,
          isFalse);
    });

    test('rows with neither code nor title are dropped', () {
      expect(
          parseOffers([
            {'description': 'orphan'}
          ]),
          isEmpty);
      expect(parseOffers([]), isEmpty);
    });
  });
}
