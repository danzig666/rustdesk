import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// For the status bar, where space is short: "Public" or the host's first label.
  String get shortName {
    if (isPublic) return translate('Public');
    final host = name.split(':').first;
    final isIp = RegExp(r'^[0-9.]+$').hasMatch(host) || host.contains('[');
    return isIp ? host : host.split('.').first;
  }

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
    flex: 4,
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
                      child: Text(s.shortName,
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
          ...[
            (
              ExtraOutgoingMode.same,
              canRegister ? 'Same servers as above' : 'Default'
            ),
            (ExtraOutgoingMode.off, 'Off'),
            (ExtraOutgoingMode.custom, 'Custom list'),
          ].map((e) => Obx(() => RadioListTile<ExtraOutgoingMode>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                value: e.$1,
                groupValue: config.outgoingMode.value,
                onChanged: (v) {
                  if (v != null) config.outgoingMode.value = v;
                },
                title: Text(translate(e.$2)),
              ))),
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
          _label('Public server sign-in'),
          _tip(context, 'public_account_tip'),
          const PublicAccountTile(),
        ],
      ],
    );
  }
}

/// Sign-in to the public server's account service, separate from the main
/// account: sent only when connecting through the public server.
class PublicAccountTile extends StatefulWidget {
  const PublicAccountTile({Key? key}) : super(key: key);

  @override
  State<PublicAccountTile> createState() => _PublicAccountTileState();
}

class _PublicAccountTileState extends State<PublicAccountTile> {
  static const _providers = [
    ('google', 'Google'),
    ('github', 'GitHub'),
    ('microsoft', 'Microsoft'),
  ];

  String _user = bind.mainGetPublicAccount();
  bool _waiting = false;
  String _error = '';
  String _openedUrl = '';
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    if (_waiting) bind.mainAccountAuthCancel();
    super.dispose();
  }

  Future<void> _signIn(String op) async {
    setState(() {
      _waiting = true;
      _error = '';
      _openedUrl = '';
    });
    await bind.mainAccountAuthCancel();
    await bind.mainPublicAccountAuth(op: op);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  Future<void> _poll() async {
    final Map<String, dynamic> r;
    try {
      r = jsonDecode(await bind.mainPublicAccountAuthResult());
    } catch (_) {
      return;
    }
    if (!mounted || !_waiting) return;
    final url = (r['url'] ?? '').toString();
    switch (r['state']) {
      case 'signed-in':
        _stop(user: (r['user'] ?? '').toString());
        break;
      case 'failed':
        _stop(error: (r['error'] ?? '').toString());
        break;
      default:
        if (url.isNotEmpty && url != _openedUrl) {
          _openedUrl = url;
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
    }
  }

  void _stop({String? user, String error = ''}) {
    _timer?.cancel();
    setState(() {
      _waiting = false;
      _error = error;
      if (user != null) _user = user;
    });
  }

  Future<void> _cancel() async {
    await bind.mainAccountAuthCancel();
    if (mounted) _stop();
  }

  Future<void> _signOut() async {
    await bind.mainPublicAccountLogout();
    if (mounted) setState(() => _user = '');
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    if (_user.isNotEmpty) {
      return Row(children: [
        extraServerDot(_kColorOnline).marginOnly(right: 8),
        Expanded(
          child: Text(translate('Signed in to the public server as {$_user}'),
              overflow: TextOverflow.ellipsis),
        ),
        TextButton(onPressed: _signOut, child: Text(translate('Logout'))),
      ]);
    }
    if (_waiting) {
      return Row(children: [
        const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2)),
        Expanded(
          child: Text(translate('Finish signing in in your browser'),
                  style: style)
              .marginOnly(left: 8),
        ),
        TextButton(onPressed: _cancel, child: Text(translate('Cancel'))),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: _providers
              .map((p) => OutlinedButton.icon(
                    onPressed: () => _signIn(p.$1),
                    icon: SvgPicture.asset('assets/auth-${p.$1}.svg',
                        width: 16, height: 16),
                    label: Text(translate('Continue with {${p.$2}}')),
                  ))
              .toList(),
        ),
        if (_error.isNotEmpty)
          Text(translate(_error),
                  style: style?.copyWith(color: _kColorFailed))
              .marginOnly(top: 4),
      ],
    );
  }
}
