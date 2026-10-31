import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';

const String kOptionExtraRendezvousServers = 'extra-rendezvous-servers';
const String kOptionExtraRendezvousOutgoing = 'extra-rendezvous-outgoing';

const String _kPublic = 'public';
const String _kNone = 'none';

enum ExtraOutgoingMode { same, off, custom }

const Color _kColorOnline = Color.fromARGB(255, 50, 190, 166);
const Color _kColorFailed = Color.fromARGB(255, 224, 79, 95);

/// One `extra-rendezvous-servers` entry as the service reports it in
/// `mainGetConnectStatus()['extra_servers']`.
class ExtraServerStatus {
  final String server;
  final bool isPublic;
  final String state;
  final String error;

  ExtraServerStatus(this.server, this.isPublic, this.state, this.error);

  static List<ExtraServerStatus> fromConnectStatus(
      Map<String, dynamic> status) {
    final list = status['extra_servers'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => ExtraServerStatus(
              (e['server'] ?? '').toString(),
              e['public'] == true,
              (e['state'] ?? '').toString(),
              (e['error'] ?? '').toString(),
            ))
        .toList();
  }

  String get name =>
      isPublic ? translate('Public server') : server.replaceAll(':21116', '');

  Color get color {
    switch (state) {
      case 'online':
        return _kColorOnline;
      case 'connecting':
        return kColorWarn;
      default:
        return _kColorFailed;
    }
  }

  String get description {
    switch (state) {
      case 'online':
        return translate('Registered');
      case 'connecting':
        return translate('Connecting...');
      case 'id-taken':
        return translate('ID is taken on this server');
      case 'not-deployed':
        return translate('This server requires deployment');
      default:
        return translate('Not reachable');
    }
  }

  String get tooltip =>
      error.isEmpty ? '$name: $description' : '$name: $description\n$error';
}

Widget extraServerDot(Color color, {double size = 8}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size / 2),
      ),
    );

/// Compact "Also on: ● Public server" for the main window's status bar.
Widget extraServersStatusBar(List<ExtraServerStatus> servers, double fontSize) {
  if (servers.isEmpty) return const SizedBox.shrink();
  return Flexible(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(' · ${translate('Also on')}: ',
            style: TextStyle(fontSize: fontSize)),
        ...servers.map((s) => Flexible(
              child: Tooltip(
                message: s.tooltip,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    extraServerDot(s.color, size: 7).marginOnly(right: 4),
                    Flexible(
                      child: Text(s.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: fontSize)),
                    ),
                  ],
                ).marginOnly(right: 8),
              ),
            )),
      ],
    ),
  );
}

/// Live per-server registration state, refreshed every second while shown.
class ExtraServersStatusList extends StatefulWidget {
  const ExtraServersStatusList({Key? key}) : super(key: key);

  @override
  State<ExtraServersStatusList> createState() => _ExtraServersStatusListState();
}

class _ExtraServersStatusListState extends State<ExtraServersStatusList> {
  List<ExtraServerStatus> _servers = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final status =
          jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
      final servers = ExtraServerStatus.fromConnectStatus(status);
      if (mounted) setState(() => _servers = servers);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    if (_servers.isEmpty) {
      return Text(translate('Not registered on any extra ID server'),
          style: style);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _servers
          .map((s) => Tooltip(
                message: s.tooltip,
                child: Row(
                  children: [
                    extraServerDot(s.color).marginOnly(right: 8),
                    Flexible(
                      child: Text('${s.name} — ${s.description}',
                          overflow: TextOverflow.ellipsis, style: style),
                    ),
                  ],
                ).marginOnly(bottom: 4),
              ))
          .toList(),
    );
  }
}

/// The two options behind the "Extra ID servers" section of the server
/// settings dialog, split into the pieces the section edits.
class ExtraServersConfig {
  final RxBool registerOnPublic;
  final TextEditingController others;
  final Rx<ExtraOutgoingMode> outgoingMode;
  final TextEditingController outgoingList;

  ExtraServersConfig._(
      this.registerOnPublic, this.others, this.outgoingMode, this.outgoingList);

  static List<String> _split(String s) =>
      s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  static Future<ExtraServersConfig> load() async {
    final extra =
        _split(await bind.mainGetOption(key: kOptionExtraRendezvousServers));
    final outgoing =
        (await bind.mainGetOption(key: kOptionExtraRendezvousOutgoing)).trim();
    bool isPublic(String e) => e.toLowerCase() == _kPublic;
    final mode = outgoing.isEmpty
        ? ExtraOutgoingMode.same
        : outgoing.toLowerCase() == _kNone
            ? ExtraOutgoingMode.off
            : ExtraOutgoingMode.custom;
    return ExtraServersConfig._(
      extra.any(isPublic).obs,
      TextEditingController(text: extra.where((e) => !isPublic(e)).join(', ')),
      mode.obs,
      TextEditingController(
          text: mode == ExtraOutgoingMode.custom ? outgoing : ''),
    );
  }

  bool get isConfigured =>
      registerOnPublic.value ||
      others.text.trim().isNotEmpty ||
      outgoingMode.value != ExtraOutgoingMode.same;

  String get extraValue => [
        if (registerOnPublic.value) _kPublic,
        ..._split(others.text),
      ].join(',');

  String get outgoingValue {
    switch (outgoingMode.value) {
      case ExtraOutgoingMode.same:
        return '';
      case ExtraOutgoingMode.off:
        return _kNone;
      case ExtraOutgoingMode.custom:
        final list = _split(outgoingList.text).join(',');
        return list.isEmpty ? _kNone : list;
    }
  }

  Future<void> save() async {
    await bind.mainSetOption(
        key: kOptionExtraRendezvousServers, value: extraValue);
    await bind.mainSetOption(
        key: kOptionExtraRendezvousOutgoing, value: outgoingValue);
  }
}

/// Collapsible "Extra ID servers" section for the server settings dialog.
class ExtraServersSection extends StatelessWidget {
  final ExtraServersConfig config;

  const ExtraServersSection({Key? key, required this.config}) : super(key: key);

  static bool get canRegister => !isIOS && !isWeb && !bind.isOutgoingOnly();
  static bool get canLookUp => !isWeb && !bind.isIncomingOnly();
  static bool get isSupported => canRegister || canLookUp;

  InputDecoration _decoration(String hint, {String? helper}) => InputDecoration(
        hintText: hint,
        helperText: helper,
        helperMaxLines: 3,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      );

  Widget _tip(BuildContext context, String key) =>
      Text(translate(key), style: Theme.of(context).textTheme.bodySmall)
          .marginOnly(bottom: 8);

  Widget _label(String key) =>
      Text(translate(key), style: const TextStyle(fontWeight: FontWeight.w600))
          .marginOnly(top: 8, bottom: 4);

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      initiallyExpanded: config.isConfigured,
      title: Text(translate('Extra ID servers')),
      children: [
        if (canRegister) ...[
          _tip(context, 'extra_id_servers_tip'),
          Obx(() => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: config.registerOnPublic.value,
                onChanged: (v) => config.registerOnPublic.value = v ?? false,
                title: Text(
                    translate('Also register on the public RustDesk server')),
                subtitle: Text(translate('register_public_tip')),
              )),
          _label('Other extra ID servers'),
          TextField(
            controller: config.others,
            autocorrect: false,
            enableSuggestions: false,
            decoration: _decoration('backup.example.com:21116?key=...',
                helper: translate('extra_id_servers_other_tip')),
          ),
          _label('Current status'),
          const ExtraServersStatusList(),
        ],
        if (canLookUp) ...[
          _label('Look up IDs on extra servers when connecting'),
          _tip(context, 'extra_outgoing_tip'),
          Obx(() => DropdownButton<ExtraOutgoingMode>(
                isExpanded: true,
                value: config.outgoingMode.value,
                onChanged: (v) {
                  if (v != null) config.outgoingMode.value = v;
                },
                items: [
                  if (canRegister)
                    DropdownMenuItem(
                        value: ExtraOutgoingMode.same,
                        child: Text(translate('Same servers as above'))),
                  if (!canRegister)
                    DropdownMenuItem(
                        value: ExtraOutgoingMode.same,
                        child: Text(translate('Default'))),
                  DropdownMenuItem(
                      value: ExtraOutgoingMode.off,
                      child: Text(translate('Off'))),
                  DropdownMenuItem(
                      value: ExtraOutgoingMode.custom,
                      child: Text(translate('Custom list'))),
                ],
              )),
          Obx(() => Offstage(
                offstage: config.outgoingMode.value != ExtraOutgoingMode.custom,
                child: TextField(
                  controller: config.outgoingList,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: _decoration(
                      'public, backup.example.com:21116?key=...',
                      helper: translate('extra_outgoing_custom_tip')),
                ).marginOnly(top: 4),
              )),
        ],
      ],
    );
  }
}
