import 'package:convert_the_spire_reborn/src/screens/player.dart';
import 'package:convert_the_spire_reborn/src/vault/widgets/torrent_settings_card.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Numbers written with a decimal comma, as across most of Europe.
void main() {
  test('a ReplayGain tag with a decimal comma keeps its value', () {
    expect(PlayerState.parseReplayGainDbForTesting('-6,54 dB'), -6.54);
    expect(PlayerState.parseReplayGainDbForTesting('-6.54 dB'), -6.54);
    expect(PlayerState.parseReplayGainDbForTesting('+2,5 dB'), 2.5);
  });

  test('the seeding ratio field takes a decimal comma as a point', () {
    var value = TextEditingValue.empty;
    for (final typed in ['2', '2,', '2,5']) {
      value = decimalInputFormatters().fold(
          TextEditingValue(text: typed),
          (v, f) => f.formatEditUpdate(value, v));
    }
    expect(value.text, '2.5');
  });
}
