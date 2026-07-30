import 'dart:typed_data';

import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/pm3_offline_tools.dart';
import 'package:flutter/material.dart';

enum Pm3OfflineTool { number, xor, lrc, nuid, checksum }

class Pm3OfflineToolPage extends StatefulWidget {
  final Pm3OfflineTool tool;

  const Pm3OfflineToolPage({super.key, required this.tool});

  @override
  State<Pm3OfflineToolPage> createState() => _Pm3OfflineToolPageState();
}

class _Pm3OfflineToolPageState extends State<Pm3OfflineToolPage> {
  final _input = TextEditingController();
  final _mask = TextEditingController();
  Pm3NumberBase _base = Pm3NumberBase.hexadecimal;
  Map<String, String>? _result;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _mask.dispose();
    super.dispose();
  }

  String get _title => switch (widget.tool) {
    Pm3OfflineTool.number => 'PM3 data num',
    Pm3OfflineTool.xor => 'PM3 data xor',
    Pm3OfflineTool.lrc => 'PM3 analyse lrc',
    Pm3OfflineTool.nuid => 'PM3 analyse nuid',
    Pm3OfflineTool.checksum => 'PM3 analyse chksum',
  };

  String get _description => switch (widget.tool) {
    Pm3OfflineTool.number =>
      'Convert one arbitrary-precision value between decimal, hexadecimal, binary, and printable ASCII.',
    Pm3OfflineTool.xor =>
      'XOR two equal-length byte strings. With no mask, PM3 uses the most frequent input byte.',
    Pm3OfflineTool.lrc =>
      'Calculate the rolling XOR byte used by the PM3 LRC helper.',
    Pm3OfflineTool.nuid =>
      'Generate a four-byte NUID from a seven-byte UID using the PM3 AN10927 implementation.',
    Pm3OfflineTool.checksum =>
      'Calculate the PM3 checksum matrix: byte, nibble, crumb, complement, XOR, and BSD variants.',
  };

  Uint8List _hex(String input, {bool allowEmpty = false}) {
    final normalized = input.trim().replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty && allowEmpty) return Uint8List(0);
    if (normalized.isEmpty ||
        normalized.length.isOdd ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalized)) {
      throw const FormatException('Enter whole hexadecimal bytes');
    }
    return Uint8List.fromList(hexToBytes(normalized));
  }

  void _execute() {
    setState(() {
      _error = null;
      _result = null;
    });
    try {
      final result = switch (widget.tool) {
        Pm3OfflineTool.number => _number(),
        Pm3OfflineTool.xor => _xor(),
        Pm3OfflineTool.lrc => _lrc(),
        Pm3OfflineTool.nuid => _nuid(),
        Pm3OfflineTool.checksum => _checksum(),
      };
      setState(() => _result = result);
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Map<String, String> _number() {
    final conversion = pm3ConvertNumber(_input.text, _base);
    return {
      'Decimal': conversion.decimal,
      'Hexadecimal': conversion.hexadecimal,
      'Binary': conversion.binary,
      'ASCII': conversion.ascii,
    };
  }

  Map<String, String> _xor() {
    final input = _hex(_input.text);
    final mask = _hex(_mask.text, allowEmpty: true);
    final effectiveMask = mask.isEmpty ? null : mask;
    final output = pm3Xor(input, effectiveMask);
    return {
      'Input': bytesToHexSpace(input).toUpperCase(),
      'Mask': effectiveMask == null
          ? 'Automatic most-frequent byte'
          : bytesToHexSpace(effectiveMask).toUpperCase(),
      'Output': bytesToHexSpace(output).toUpperCase(),
    };
  }

  Map<String, String> _lrc() {
    final input = _hex(_input.text);
    final lrc = pm3Lrc(input);
    return {
      'Input': bytesToHexSpace(input).toUpperCase(),
      'LRC XOR byte':
          '0x${lrc.toRadixString(16).padLeft(2, '0').toUpperCase()}',
    };
  }

  Map<String, String> _nuid() {
    final uid = _hex(_input.text);
    final nuid = pm3GenerateNuid(uid);
    return {
      'UID': bytesToHexSpace(uid).toUpperCase(),
      'NUID': bytesToHexSpace(nuid).toUpperCase(),
    };
  }

  Map<String, String> _checksum() {
    final input = _hex(_input.text);
    final maskText = _mask.text.trim().replaceFirst(
      RegExp(r'^0x', caseSensitive: false),
      '',
    );
    final mask = maskText.isEmpty ? 0xffff : int.parse(maskText, radix: 16);
    final result = pm3Checksums(input, mask: mask);
    String hex(int value) => '0x${value.toRadixString(16).toUpperCase()}';
    return {
      'Byte add': hex(result.byteAdd),
      'Nibble add': hex(result.nibbleAdd),
      'Crumb add': hex(result.crumbAdd),
      'Byte subtract': hex(result.byteSubtract),
      'Nibble subtract': hex(result.nibbleSubtract),
      'Byte add 1s complement': hex(result.byteAddOnesComplement),
      'Nibble add 1s complement': hex(result.nibbleAddOnesComplement),
      'Crumb add 1s complement': hex(result.crumbAddOnesComplement),
      'Byte subtract 1s complement': hex(result.byteSubtractOnesComplement),
      'Nibble subtract 1s complement': hex(result.nibbleSubtractOnesComplement),
      'Byte XOR': hex(result.byteXor),
      'Nibble XOR': hex(result.nibbleXor),
      'Crumb XOR': hex(result.crumbXor),
      'BSD 8-bit': hex(result.bsd8),
      'BSD 4-bit': hex(result.bsd4),
      '0xFF - byte XOR': hex(result.xorComplement),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_description, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 16),
              if (widget.tool == Pm3OfflineTool.number) ...[
                DropdownButtonFormField<Pm3NumberBase>(
                  initialValue: _base,
                  decoration: const InputDecoration(
                    labelText: 'Input base',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: Pm3NumberBase.decimal,
                      child: Text('Decimal'),
                    ),
                    DropdownMenuItem(
                      value: Pm3NumberBase.hexadecimal,
                      child: Text('Hexadecimal'),
                    ),
                    DropdownMenuItem(
                      value: Pm3NumberBase.binary,
                      child: Text('Binary'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _base = value!),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _input,
                decoration: InputDecoration(
                  labelText: widget.tool == Pm3OfflineTool.number
                      ? 'Number'
                      : widget.tool == Pm3OfflineTool.nuid
                      ? 'Seven-byte UID (hex)'
                      : 'Input bytes (hex)',
                  border: const OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'RobotoMono'),
              ),
              if (widget.tool == Pm3OfflineTool.xor ||
                  widget.tool == Pm3OfflineTool.checksum) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _mask,
                  decoration: InputDecoration(
                    labelText: widget.tool == Pm3OfflineTool.xor
                        ? 'XOR mask (optional)'
                        : 'Result mask (optional hex, default FFFF)',
                    helperText: widget.tool == Pm3OfflineTool.xor
                        ? 'When provided, it must have the same byte length as the input.'
                        : 'Use 0000..FFFF.',
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'RobotoMono'),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _execute,
                icon: const Icon(Icons.calculate),
                label: const Text('Run tool'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!),
                  ),
                ),
              ],
              if (_result != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final entry in _result!.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: SelectableText(
                              '${entry.key}: ${entry.value}',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _ResonanceTarget { frequency, inductance, capacitance }

class Pm3FrequencyPage extends StatefulWidget {
  const Pm3FrequencyPage({super.key});

  @override
  State<Pm3FrequencyPage> createState() => _Pm3FrequencyPageState();
}

class _Pm3FrequencyPageState extends State<Pm3FrequencyPage> {
  final _first = TextEditingController(text: '0.001');
  final _second = TextEditingController(text: '0.000000001');
  _ResonanceTarget _target = _ResonanceTarget.frequency;
  String? _result;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  (String, String) get _labels => switch (_target) {
    _ResonanceTarget.frequency => ('Inductance (H)', 'Capacitance (F)'),
    _ResonanceTarget.inductance => ('Frequency (Hz)', 'Capacitance (F)'),
    _ResonanceTarget.capacitance => ('Frequency (Hz)', 'Inductance (H)'),
  };

  void _calculate() {
    try {
      final first = double.parse(_first.text.trim());
      final second = double.parse(_second.text.trim());
      final result = switch (_target) {
        _ResonanceTarget.frequency => pm3ResonantFrequency(
          inductanceHenries: first,
          capacitanceFarads: second,
        ),
        _ResonanceTarget.inductance => pm3ResonantInductance(
          frequencyHz: first,
          capacitanceFarads: second,
        ),
        _ResonanceTarget.capacitance => pm3ResonantCapacitance(
          frequencyHz: first,
          inductanceHenries: second,
        ),
      };
      final unit = switch (_target) {
        _ResonanceTarget.frequency => 'Hz',
        _ResonanceTarget.inductance => 'H',
        _ResonanceTarget.capacitance => 'F',
      };
      setState(() {
        _error = null;
        _result = '${result.toStringAsPrecision(10)} $unit';
      });
    } catch (error) {
      setState(() {
        _result = null;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = _labels;
    return Scaffold(
      appBar: AppBar(title: const Text('PM3 analyse freq')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Calculate PM3 wavelength, near-field range, antenna fractions, and LC resonance values.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          for (final band in pm3FrequencyBands())
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      band.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Wavelength: ${band.wavelengthMeters.toStringAsFixed(6)} m',
                    ),
                    Text(
                      'Near-field range: ${band.nearFieldRangeMeters.toStringAsFixed(6)} m',
                    ),
                    Text(
                      'Half / quarter wave: ${band.halfWaveMeters.toStringAsFixed(6)} m / ${band.quarterWaveMeters.toStringAsFixed(6)} m',
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('LC resonance', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<_ResonanceTarget>(
            initialValue: _target,
            decoration: const InputDecoration(
              labelText: 'Calculate',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: _ResonanceTarget.frequency,
                child: Text('Frequency'),
              ),
              DropdownMenuItem(
                value: _ResonanceTarget.inductance,
                child: Text('Inductance'),
              ),
              DropdownMenuItem(
                value: _ResonanceTarget.capacitance,
                child: Text('Capacitance'),
              ),
            ],
            onChanged: (value) => setState(() {
              _target = value!;
              _result = null;
              _error = null;
            }),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  key: ValueKey(labels.$1),
                  controller: _first,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: labels.$1,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  key: ValueKey(labels.$2),
                  controller: _second,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: labels.$2,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _calculate,
            icon: const Icon(Icons.calculate),
            label: const Text('Calculate resonance'),
          ),
          if (_result != null) _OfflineMessage(_result!),
          if (_error != null) _OfflineMessage(_error!, error: true),
        ],
      ),
    );
  }
}

enum _UnitSource { etu, microseconds }

class Pm3UnitsPage extends StatefulWidget {
  const Pm3UnitsPage({super.key});

  @override
  State<Pm3UnitsPage> createState() => _Pm3UnitsPageState();
}

class _Pm3UnitsPageState extends State<Pm3UnitsPage> {
  final _input = TextEditingController(text: '10');
  _UnitSource _source = _UnitSource.etu;
  Pm3UnitConversion? _result;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _convert() {
    try {
      final value = int.parse(_input.text.trim());
      final result = switch (_source) {
        _UnitSource.etu => pm3UnitsFromEtu(value),
        _UnitSource.microseconds => pm3UnitsFromMicroseconds(value),
      };
      setState(() {
        _result = result;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _result = null;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('PM3 analyse units')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Convert ISO14443-A ETU, microseconds, and the PM3-compatible 3.39 MHz SSP clock.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<_UnitSource>(
            initialValue: _source,
            decoration: const InputDecoration(
              labelText: 'Input unit',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: _UnitSource.etu, child: Text('ETU')),
              DropdownMenuItem(
                value: _UnitSource.microseconds,
                child: Text('Microseconds'),
              ),
            ],
            onChanged: (value) => setState(() {
              _source = value!;
              _result = null;
              _error = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Non-negative integer value',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _convert,
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Convert units'),
          ),
          if (result != null)
            _OfflineMessage(
              'ETU: ${result.etu.toStringAsFixed(4)}\n'
              'Microseconds: ${result.microseconds.toStringAsFixed(4)}\n'
              'SSP clock cycles: ${result.sspClock}',
            ),
          if (_error != null) _OfflineMessage(_error!, error: true),
        ],
      ),
    );
  }
}

class _OfflineMessage extends StatelessWidget {
  final String message;
  final bool error;

  const _OfflineMessage(this.message, {this.error = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        color: error ? colors.errorContainer : colors.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText(message),
        ),
      ),
    );
  }
}
