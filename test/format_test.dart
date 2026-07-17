import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/util/format.dart';

void main() {
  group('parseLeadingAmount', () {
    test('parses "k" shorthand', () {
      expect(parseLeadingAmount('Rent 10k (utilities 2k)'), 10000);
      expect(parseLeadingAmount('Loan 33k - 600 fee'), 33000);
      expect(parseLeadingAmount('Buying a powerbank 1.5k'), 1500);
    });

    test('parses plain 3+ digit numbers', () {
      expect(parseLeadingAmount('Sim 800 (family plan)'), 800);
      expect(parseLeadingAmount('Jane Doe 400'), 400);
    });

    test('returns null when no amount is present', () {
      expect(parseLeadingAmount('Fix guitars must.'), isNull);
      expect(parseLeadingAmount('Airtags'), isNull);
    });
  });

  group('money / moneyK', () {
    test('money formats with thousands separators and ৳', () {
      expect(money(40000), '৳40,000');
      expect(money(800), '৳800');
      expect(money(null), '');
    });

    test('moneyK compacts round thousands', () {
      expect(moneyK(33000), '৳33k');
      expect(moneyK(1500), '৳1.5k');
      expect(moneyK(400), '৳400');
    });
  });
}
