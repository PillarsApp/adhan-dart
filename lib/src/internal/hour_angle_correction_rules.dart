import '../hour_angle_correction.dart';

extension HourAngleCorrectionRules on HourAngleCorrection {
  int get maximumIterations => this == HourAngleCorrection.iterative ? 10 : 1;

  bool get validatesTimes => this == HourAngleCorrection.iterative;

  bool get keepsTransitOnRequestedDay => this == HourAngleCorrection.iterative;
}
