import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/cue_models.dart';

class CueRoutine {
  const CueRoutine(this.name, this.steps);
  final String name;
  final List<PlannedToolCall> steps;
  Map<String, dynamic> toJson() => {
    'name': name,
    'steps': [
      for (final step in steps) {'tool': step.tool, 'args': step.args},
    ],
  };
  factory CueRoutine.fromJson(Map<String, dynamic> json) {
    final steps = (json['steps'] as List).map((raw) {
      final map = Map<String, dynamic>.from(raw as Map);
      final tool = '${map['tool']}';
      if (!{
        'set_brightness',
        'set_dnd',
        'set_alarm',
        'media_control',
      }.contains(tool)) {
        throw const FormatException('Unsupported routine action.');
      }
      return PlannedToolCall(
        tool: tool,
        args: Map<String, dynamic>.from(map['args'] as Map),
      );
    }).toList();
    final name = '${json['name']}'.trim();
    if (name.isEmpty || steps.isEmpty || steps.length > 12) {
      throw const FormatException('A routine needs a name and 1–12 actions.');
    }
    return CueRoutine(name, steps);
  }
}

class CueRoutineService extends ChangeNotifier {
  CueRoutineService({this.storageFile});
  final Future<File> Function()? storageFile;
  List<CueRoutine> routines = const [
    CueRoutine('Bedtime', [
      PlannedToolCall(tool: 'set_brightness', args: {'percent': 15}),
      PlannedToolCall(tool: 'set_dnd', args: {'enabled': true}),
      PlannedToolCall(
        tool: 'set_alarm',
        args: {'hour': 7, 'minute': 0, 'label': 'CueUI wake up'},
      ),
    ]),
    CueRoutine('Morning', [
      PlannedToolCall(tool: 'set_dnd', args: {'enabled': false}),
      PlannedToolCall(tool: 'set_brightness', args: {'percent': 70}),
    ]),
    CueRoutine('Focus', [
      PlannedToolCall(tool: 'set_dnd', args: {'enabled': true}),
      PlannedToolCall(tool: 'set_brightness', args: {'percent': 40}),
    ]),
  ];
  Future<File> _file() async => storageFile != null
      ? storageFile!()
      : File('${(await getApplicationSupportDirectory()).path}/routines.json');
  Future<void> load() async {
    final file = await _file();
    if (await file.exists()) {
      final decoded = jsonDecode(await file.readAsString()) as List;
      routines = decoded
          .map(
            (raw) => CueRoutine.fromJson(Map<String, dynamic>.from(raw as Map)),
          )
          .toList();
      notifyListeners();
    }
  }

  Future<void> save(CueRoutine routine, {String? originalName}) async {
    CueRoutine.fromJson(routine.toJson());
    final next = [
      ...routines.where(
        (item) =>
            item.name.toLowerCase() != routine.name.toLowerCase() &&
            item.name.toLowerCase() != originalName?.toLowerCase(),
      ),
      routine,
    ];
    final file = await _file();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode(next.map((item) => item.toJson()).toList()),
      flush: true,
    );
    await temp.rename(file.path);
    routines = next;
    notifyListeners();
  }

  CueRoutine? find(String name) => routines
      .where((item) => item.name.toLowerCase() == name.toLowerCase().trim())
      .firstOrNull;
}
