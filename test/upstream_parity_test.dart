import 'package:adhan/adhan.dart';
import 'package:test/test.dart';

void main() {
  group('HighLatitudeRule.recommended', () {
    test('uses the distance from the equator in both hemispheres', () {
      expect(HighLatitudeRule.recommended(Coordinates(-54.8019, -68.3030)),
          HighLatitudeRule.seventh_of_the_night);
      expect(HighLatitudeRule.recommended(Coordinates(-53.1638, -70.9171)),
          HighLatitudeRule.seventh_of_the_night);
      expect(HighLatitudeRule.recommended(Coordinates(-45.8788, 170.5028)),
          HighLatitudeRule.middle_of_the_night);
      expect(HighLatitudeRule.recommended(Coordinates(-6.2088, 106.8456)),
          HighLatitudeRule.middle_of_the_night);
      expect(HighLatitudeRule.recommended(Coordinates(0, 0)),
          HighLatitudeRule.middle_of_the_night);
    });

    test('mirror latitudes agree', () {
      for (final latitude in [45.983226, 48.983226, 49.0, 50.0]) {
        expect(HighLatitudeRule.recommended(Coordinates(latitude, -3.216649)),
            HighLatitudeRule.recommended(Coordinates(-latitude, -3.216649)),
            reason: '$latitude');
      }
    });

    test('48 degrees is the boundary', () {
      for (final sign in [1, -1]) {
        expect(HighLatitudeRule.recommended(Coordinates(sign * 48.0, 0)),
            HighLatitudeRule.middle_of_the_night);
        expect(HighLatitudeRule.recommended(Coordinates(sign * 48.0001, 0)),
            HighLatitudeRule.seventh_of_the_night);
      }
    });
  });
}
