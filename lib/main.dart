import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class _Palette {
  static const ink = Color(0xFF161012);
  static const blood = Color(0xFFC6313A);
  static const bloodDeep = Color(0xFF8F1A24);
  static const paper = Color(0xFFF3E7E1);
  static const paperMuted = Color(0xFFD8C0B6);
  static const surface = Color(0xFF2A1A1F);
}

void main() {
  runApp(const MorningMenaceApp());
}

class MorningMenaceApp extends StatelessWidget {
  const MorningMenaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Morning Menace',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _Palette.blood,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: _Palette.ink,
        textTheme: const TextTheme(
          displayMedium: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
          ),
          headlineMedium: TextStyle(fontWeight: FontWeight.w900),
          titleLarge: TextStyle(fontWeight: FontWeight.w800),
          titleMedium: TextStyle(fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(fontWeight: FontWeight.w600),
          bodyMedium: TextStyle(fontWeight: FontWeight.w500),
          labelLarge: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      home: const AlarmDashboardScreen(),
    );
  }
}

class AlarmDashboardScreen extends StatefulWidget {
  const AlarmDashboardScreen({super.key});

  @override
  State<AlarmDashboardScreen> createState() => _AlarmDashboardScreenState();
}

class _AlarmDashboardScreenState extends State<AlarmDashboardScreen> {
  static const _prefsKey = 'alarm_items_v1';
  static const _blastConfigKey = 'image_blast_config_v1';

  final Map<String, DateTime> _snoozedUntil = {};
  final Set<String> _minuteLocks = {};
  final Map<String, DateTime> _penaltyLocks = {};

  List<AlarmItem> _alarms = [];
  DateTime _now = DateTime.now();
  AlarmItem? _ringingAlarm;

  Timer? _clockTimer;
  StreamSubscription<String>? _alarmEventSubscription;

  bool _loading = true;
  String? _loadingError;

  final Random _random = Random();
  bool _imageBlastPenaltyEnabled = true;
  bool _sendingBlast = false;
  String? _lastBlastStatus;
  final List<PenaltyContact> _approvedContacts = [];
  final List<PenaltyImage> _penaltyImagePool = [];
  final List<ImageBlastDispatch> _blastHistory = [];

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      _checkForRinging(now);
      if (!mounted) {
        return;
      }
      setState(() {
        _now = now;
      });
    });
  }

  Future<void> _initializeApp() async {
    try {
      final launchPayload = await AlarmScheduler.instance.initialize();
      _alarmEventSubscription = AlarmScheduler.instance.alarmEvents.listen(
        _handleAlarmEvent,
      );

      final loadedAlarms = await _loadAlarms();
      await _loadBlastConfig();

      if (!mounted) {
        return;
      }
      setState(() {
        _alarms = loadedAlarms;
        _loading = false;
        _loadingError = AlarmScheduler.instance.pluginAvailable
            ? null
            : 'Notification plugin not loaded. Do a full restart (stop + flutter run).';
      });

      await _syncSystemAlarms();

      if (launchPayload != null && launchPayload.isNotEmpty) {
        _openAlarmFromPayload(launchPayload);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _alarms = _defaultAlarms();
        _loading = false;
        _loadingError =
            'System alarm permissions unavailable. Running in app-only mode.';
      });
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _alarmEventSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nextRing = _nextRingDateTime();

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _Backdrop()),
          SafeArea(
            child: Column(
              children: [
                const _Header(),
                if (_loadingError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: _brutalDecoration(
                        color: _Palette.paperMuted,
                        borderRadius: 10,
                        borderWidth: 2,
                        shadowOffset: const Offset(3, 3),
                      ),
                      child: Text(
                        _loadingError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _Palette.ink,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: _Palette.paper,
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ClockHero(now: _now, nextRing: nextRing),
                              const SizedBox(height: 14),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  if (constraints.maxWidth > 700) {
                                    return Row(
                                      children: [
                                        Expanded(
                                          flex: 5,
                                          child: _ActionCard(
                                            title: 'Add alarm',
                                            subtitle:
                                                'Create a new daily alarm',
                                            icon: Icons.add_alarm_rounded,
                                            color: _Palette.blood,
                                            onTap: () => _openAlarmSheet(),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          flex: 5,
                                          child: _ActionCard(
                                            title: 'Notification status',
                                            subtitle:
                                                AlarmScheduler
                                                    .instance
                                                    .pluginAvailable
                                                ? 'System alerts ready'
                                                : 'System alerts unavailable',
                                            icon:
                                                AlarmScheduler
                                                    .instance
                                                    .pluginAvailable
                                                ? Icons.check_circle_rounded
                                                : Icons.warning_amber_rounded,
                                            color:
                                                AlarmScheduler
                                                    .instance
                                                    .pluginAvailable
                                                ? _Palette.paper
                                                : _Palette.paperMuted,
                                            onTap: () {
                                              unawaited(
                                                _showNotificationStatus(),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    );
                                  }

                                  return Column(
                                    children: [
                                      _ActionCard(
                                        title: 'Add alarm',
                                        subtitle: 'Create a new daily alarm',
                                        icon: Icons.add_alarm_rounded,
                                        color: _Palette.blood,
                                        onTap: () => _openAlarmSheet(),
                                      ),
                                      const SizedBox(height: 10),
                                      _ActionCard(
                                        title: 'Notification status',
                                        subtitle:
                                            AlarmScheduler
                                                .instance
                                                .pluginAvailable
                                            ? 'System alerts ready'
                                            : 'System alerts unavailable',
                                        icon:
                                            AlarmScheduler
                                                .instance
                                                .pluginAvailable
                                            ? Icons.check_circle_rounded
                                            : Icons.warning_amber_rounded,
                                        color:
                                            AlarmScheduler
                                                .instance
                                                .pluginAvailable
                                            ? _Palette.paper
                                            : _Palette.paperMuted,
                                        onTap: () {
                                          unawaited(_showNotificationStatus());
                                        },
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              _SnoozeBlastCard(
                                enabled: _imageBlastPenaltyEnabled,
                                contactCount: _approvedContacts.length,
                                imageCount: _penaltyImagePool.length,
                                latestDispatch: _blastHistory.isEmpty
                                    ? null
                                    : _blastHistory.first,
                                sending: _sendingBlast,
                                lastStatus: _lastBlastStatus,
                                onEnabledChanged: (enabled) {
                                  setState(() {
                                    _imageBlastPenaltyEnabled = enabled;
                                  });
                                  unawaited(_persistBlastConfig());
                                },
                                onManageContactsTap: _openContactPoolSheet,
                                onManageImagesTap: _openImagePoolSheet,
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Alarms',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: _Palette.paper,
                                  fontSize: 30,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (_alarms.isEmpty)
                                const _EmptyAlarmState()
                              else
                                ListView.separated(
                                  itemCount: _alarms.length,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (_, index) {
                                    final alarm = _alarms[index];
                                    return _AlarmCard(
                                      alarm: alarm,
                                      onToggle: (enabled) {
                                        setState(() {
                                          _alarms[index] = alarm.copyWith(
                                            enabled: enabled,
                                          );
                                        });
                                        unawaited(_saveAndSync());
                                      },
                                      onEdit: () =>
                                          _openAlarmSheet(existingIndex: index),
                                      onDelete: () {
                                        setState(() {
                                          _alarms.removeAt(index);
                                          _snoozedUntil.remove(alarm.id);
                                        });
                                        unawaited(
                                          AlarmScheduler.instance.cancelSnooze(
                                            alarm,
                                          ),
                                        );
                                        unawaited(_saveAndSync());
                                      },
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (_ringingAlarm != null)
            _RingingOverlay(
              alarm: _ringingAlarm!,
              now: _now,
              onStop: _stopRinging,
              onSnooze: _snoozeRinging,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAlarmSheet(),
        backgroundColor: _Palette.blood,
        foregroundColor: _Palette.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _Palette.ink, width: 3),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New alarm'),
      ),
    );
  }

  List<AlarmItem> _defaultAlarms() {
    return [
      const AlarmItem(
        id: 'a1',
        time: TimeOfDay(hour: 6, minute: 30),
        label: 'Morning training',
        enabled: true,
      ),
      const AlarmItem(
        id: 'a2',
        time: TimeOfDay(hour: 7, minute: 45),
        label: 'Work prep',
        enabled: true,
      ),
    ];
  }

  Future<List<AlarmItem>> _loadAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) {
        return _defaultAlarms();
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return _defaultAlarms();
      }

      final alarms = decoded
          .whereType<Map>()
          .map((map) => AlarmItem.fromJson(Map<String, dynamic>.from(map)))
          .toList();

      if (alarms.isEmpty) {
        return _defaultAlarms();
      }
      return alarms;
    } catch (_) {
      return _defaultAlarms();
    }
  }

  Future<void> _saveAndSync() async {
    await _persistAlarms();
    await _persistBlastConfig();
    await _syncSystemAlarms();
  }

  Future<void> _loadBlastConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_blastConfigKey);
      if (raw == null || raw.isEmpty) {
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final enabled = decoded['enabled'] as bool?;
      final contacts = decoded['contacts'];
      final images = decoded['images'];

      if (enabled != null) {
        _imageBlastPenaltyEnabled = enabled;
      }
      if (contacts is List) {
        final parsedContacts = contacts
            .whereType<Map>()
            .map(
              (value) =>
                  PenaltyContact.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList();
        if (parsedContacts.isNotEmpty) {
          _approvedContacts
            ..clear()
            ..addAll(parsedContacts);
        }
      }

      if (images is List) {
        final parsedImages = images
            .whereType<Map>()
            .map(
              (value) =>
                  PenaltyImage.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList();
        if (parsedImages.isNotEmpty) {
          _penaltyImagePool
            ..clear()
            ..addAll(parsedImages);
        }
      }

    } catch (_) {
      // keep defaults on malformed local data
    }
  }

  Future<void> _persistBlastConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = {
        'enabled': _imageBlastPenaltyEnabled,
        'contacts': _approvedContacts
            .map((contact) => contact.toJson())
            .toList(),
        'images': _penaltyImagePool.map((image) => image.toJson()).toList(),
      };
      await prefs.setString(_blastConfigKey, jsonEncode(payload));
    } catch (_) {
      // keep app operational if persistence fails
    }
  }

  Future<void> _persistAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _alarms.map((alarm) => alarm.toJson()).toList(),
      );
      await prefs.setString(_prefsKey, encoded);
    } catch (_) {
      // ignore persistence failures in MVP
    }
  }

  Future<void> _syncSystemAlarms() async {
    try {
      await AlarmScheduler.instance.syncAlarms(_alarms);
    } catch (_) {}
  }

  void _openAlarmFromPayload(String alarmId) {
    final match = _alarms.where((alarm) => alarm.id == alarmId).toList();
    if (match.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _ringingAlarm = match.first;
    });
  }

  void _handleAlarmEvent(String event) {
    if (event.startsWith('snooze:')) {
      final alarmId = event.substring('snooze:'.length);
      final match = _alarms.where((alarm) => alarm.id == alarmId).toList();
      if (match.isEmpty) {
        return;
      }
      unawaited(_runImageBlastPenalty(match.first));
      final snoozeTime = DateTime.now().add(const Duration(minutes: 5));
      _snoozedUntil[alarmId] = snoozeTime;
      unawaited(
        AlarmScheduler.instance.scheduleSnooze(match.first, snoozeTime),
      );
      if (_ringingAlarm?.id == alarmId && mounted) {
        setState(() {
          _ringingAlarm = null;
        });
      }
      return;
    }

    if (event.startsWith('stop:')) {
      final alarmId = event.substring('stop:'.length);
      if (_ringingAlarm?.id == alarmId && mounted) {
        setState(() {
          _ringingAlarm = null;
        });
      }
      return;
    }

    _openAlarmFromPayload(event);
  }

  void _checkForRinging(DateTime now) {
    if (_loading || _ringingAlarm != null) {
      return;
    }

    for (final alarm in _alarms.where((alarm) => alarm.enabled)) {
      final snoozeTime = _snoozedUntil[alarm.id];
      final matchesSnooze = snoozeTime != null && _sameMinute(snoozeTime, now);
      final matchesMain =
          alarm.time.hour == now.hour && alarm.time.minute == now.minute;

      if (!matchesSnooze && !matchesMain) {
        continue;
      }

      final key =
          '${alarm.id}-${now.year}-${now.month}-${now.day}-${now.hour}-${now.minute}';
      if (_minuteLocks.contains(key)) {
        continue;
      }

      _minuteLocks.add(key);
      if (_minuteLocks.length > 300) {
        _minuteLocks.remove(_minuteLocks.first);
      }

      if (matchesSnooze) {
        _snoozedUntil.remove(alarm.id);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _ringingAlarm = alarm;
      });
      break;
    }
  }

  DateTime? _nextRingDateTime() {
    final candidates = <DateTime>[];

    for (final alarm in _alarms.where((alarm) => alarm.enabled)) {
      var candidate = DateTime(
        _now.year,
        _now.month,
        _now.day,
        alarm.time.hour,
        alarm.time.minute,
      );
      if (candidate.isBefore(_now) || _sameMinute(candidate, _now)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      candidates.add(candidate);

      final snooze = _snoozedUntil[alarm.id];
      if (snooze != null && snooze.isAfter(_now)) {
        candidates.add(snooze);
      }
    }

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((a, b) => a.compareTo(b));
    return candidates.first;
  }

  Future<void> _showNotificationStatus() async {
    final info = await AlarmScheduler.instance.debugInfo();
    if (!mounted) {
      return;
    }

    final enabledCount = _imageBlastPenaltyEnabled ? 1 : 0;
    final message = info.pluginAvailable
        ? 'Alerts are on • alarms ${info.pendingCount ?? 0} • rules $enabledCount/1.'
        : 'Notifications are unavailable on this run. Full restart usually fixes this.';

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _stopRinging() {
    final current = _ringingAlarm;
    if (current != null) {
      unawaited(AlarmScheduler.instance.cancelSnooze(current));
    }
    setState(() {
      _ringingAlarm = null;
    });
  }

  void _snoozeRinging() {
    final current = _ringingAlarm;
    if (current == null) {
      return;
    }
    unawaited(_runImageBlastPenalty(current));
    final snoozeTime = DateTime.now().add(const Duration(minutes: 5));
    setState(() {
      _snoozedUntil[current.id] = snoozeTime;
      _ringingAlarm = null;
    });
    unawaited(AlarmScheduler.instance.scheduleSnooze(current, snoozeTime));
  }

  Future<void> _runImageBlastPenalty(AlarmItem alarm) async {
    if (!_imageBlastPenaltyEnabled) {
      return;
    }
    final minuteBucket = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final lockKey = 'image-${alarm.id}-$minuteBucket';
    if (!_acquirePenaltyLock(lockKey)) {
      return;
    }
    final contactsSource = List<PenaltyContact>.from(_approvedContacts);
    final imagesSource = List<PenaltyImage>.from(_penaltyImagePool);

    if (contactsSource.length < 5) {
      final deviceContacts = await _fetchRandomContactsFromDevice(5);
      for (final contact in deviceContacts) {
        if (contactsSource.any(
          (existing) =>
              _normalizeHandle(existing.handle) ==
              _normalizeHandle(contact.handle),
        )) {
          continue;
        }
        contactsSource.add(contact);
      }
    }

    if (imagesSource.length < 5) {
      final deviceImages = await _fetchRandomImagesFromDevice(5);
      for (final image in deviceImages) {
        if (imagesSource.any((existing) => existing.url == image.url)) {
          continue;
        }
        imagesSource.add(image);
      }
    }

    if (contactsSource.length < 5 || imagesSource.length < 5) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Need access to at least 5 contacts and 5 photos for image blast.',
          ),
        ),
      );
      return;
    }

    final contacts = _pickRandomUnique(contactsSource, 5);
    final images = _pickRandomUnique(imagesSource, 5);
    final targets = List<ImageBlastTarget>.generate(
      5,
      (index) =>
          ImageBlastTarget(contact: contacts[index], image: images[index]),
    );

    final dispatch = ImageBlastDispatch(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      alarmLabel: alarm.label,
      triggeredAt: DateTime.now(),
      targets: targets,
      deliveredCount: 0,
      failedCount: 0,
      status: 'queued',
    );

    setState(() {
      _blastHistory.insert(0, dispatch);
      if (_blastHistory.length > 10) {
        _blastHistory.removeLast();
      }
    });

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Snooze penalty fired: 5x5 blast queued.')),
    );

    await _sendImageBlastViaSms(dispatch);
  }

  Future<void> _sendImageBlastViaSms(ImageBlastDispatch dispatch) async {
    setState(() {
      _sendingBlast = true;
      _replaceDispatch(dispatch.copyWith(status: 'sending'));
    });

    final recipients = dispatch.targets
        .map((target) => _normalizePhoneForSms(target.contact.handle))
        .where((value) => value.isNotEmpty)
        .toList();

    if (recipients.isEmpty) {
      setState(() {
        _sendingBlast = false;
        _lastBlastStatus =
            'Could not find valid phone numbers in selected contacts.';
        _replaceDispatch(dispatch.copyWith(status: 'failed', failedCount: 5));
      });
      return;
    }

    final body = StringBuffer('Morning Menace snooze drop\n\n');
    for (final target in dispatch.targets) {
      final imageRef = target.image.isLocal
          ? target.image.name
          : target.image.url;
      body.writeln('${target.contact.name}: $imageRef');
    }

    final launched = await _openSmsComposer(recipients, body.toString());
    if (!mounted) {
      return;
    }

    setState(() {
      _sendingBlast = false;
      if (launched) {
        _lastBlastStatus =
            'Opened Messages with selected contacts. Tap Send to complete.';
        _replaceDispatch(
          dispatch.copyWith(
            status: 'partial',
            deliveredCount: recipients.length,
          ),
        );
      } else {
        _lastBlastStatus = 'Could not open Messages app on this device.';
        _replaceDispatch(dispatch.copyWith(status: 'failed', failedCount: 5));
      }
    });
  }


  void _replaceDispatch(ImageBlastDispatch updated) {
    final index = _blastHistory.indexWhere((item) => item.id == updated.id);
    if (index == -1) {
      return;
    }
    _blastHistory[index] = updated;
  }

  List<T> _pickRandomUnique<T>(List<T> source, int count) {
    final shuffled = List<T>.from(source)..shuffle(_random);
    return shuffled.take(count).toList();
  }

  Future<List<PenaltyContact>> _fetchRandomContactsFromDevice(
    int needed,
  ) async {
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        return const [];
      }

      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      final pool = <PenaltyContact>[];
      for (final contact in contacts) {
        for (final phone in contact.phones) {
          final number = phone.number.trim();
          if (number.isEmpty) {
            continue;
          }
          final name = contact.displayName.trim().isEmpty
              ? 'Device Contact'
              : contact.displayName.trim();
          pool.add(PenaltyContact(name: name, handle: number));
        }
      }

      if (pool.isEmpty) {
        return const [];
      }
      return _pickRandomUnique(pool, min(needed, pool.length));
    } catch (_) {
      return const [];
    }
  }

  Future<List<PenaltyImage>> _fetchRandomImagesFromDevice(int needed) async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) {
        return const [];
      }

      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );
      if (paths.isEmpty) {
        return const [];
      }

      final assets = await paths.first.getAssetListPaged(page: 0, size: 500);
      if (assets.isEmpty) {
        return const [];
      }

      final picked = _pickRandomUnique(assets, min(needed, assets.length));
      final images = <PenaltyImage>[];
      for (final asset in picked) {
        final file = await asset.file;
        if (file == null) {
          continue;
        }
        images.add(
          PenaltyImage(
            name: _filenameFromPath(file.path),
            url: file.path,
            isLocal: true,
          ),
        );
      }
      return images;
    } catch (_) {
      return const [];
    }
  }

  bool _acquirePenaltyLock(String key) {
    final now = DateTime.now();
    _penaltyLocks.removeWhere(
      (_, timestamp) => now.difference(timestamp) > const Duration(minutes: 2),
    );
    if (_penaltyLocks.containsKey(key)) {
      return false;
    }
    _penaltyLocks[key] = now;
    return true;
  }

  Future<void> _openContactPoolSheet() async {
    final nameController = TextEditingController();
    final handleController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: _brutalDecoration(
                  color: _Palette.paper,
                  borderRadius: 16,
                  shadowOffset: const Offset(6, 6),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Approved contacts',
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: _Palette.ink),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.24,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _approvedContacts.length,
                        itemBuilder: (_, index) {
                          final contact = _approvedContacts[index];
                          return Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${contact.name} • ${contact.handle}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: _Palette.surface),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  if (_approvedContacts.length <= 5) {
                                    return;
                                  }
                                  setState(() {
                                    _approvedContacts.remove(contact);
                                  });
                                  setModalState(() {});
                                  unawaited(_persistBlastConfig());
                                },
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    _PressButton(
                      text: 'Add from device contacts',
                      color: _Palette.paper,
                      textColor: _Palette.ink,
                      onTap: () {
                        unawaited(_importContactFromDevice());
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        hintText: 'Contact name',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: handleController,
                      decoration: const InputDecoration(
                        hintText: 'Phone, email, or handle',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _PressButton(
                      text: 'Add contact',
                      color: _Palette.blood,
                      textColor: _Palette.paper,
                      onTap: () {
                        final name = nameController.text.trim();
                        final handle = handleController.text.trim();
                        if (name.isEmpty || handle.isEmpty) {
                          return;
                        }
                        setState(() {
                          _approvedContacts.add(
                            PenaltyContact(name: name, handle: handle),
                          );
                        });
                        setModalState(() {
                          nameController.clear();
                          handleController.clear();
                        });
                        unawaited(_persistBlastConfig());
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    nameController.dispose();
    handleController.dispose();
  }

  Future<void> _openImagePoolSheet() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: _brutalDecoration(
                  color: _Palette.paper,
                  borderRadius: 16,
                  shadowOffset: const Offset(6, 6),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Image pool',
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: _Palette.ink),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.24,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _penaltyImagePool.length,
                        itemBuilder: (_, index) {
                          final image = _penaltyImagePool[index];
                          return Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${image.name} • ${image.isLocal ? 'Device photo' : image.url}',
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: _Palette.surface),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  if (_penaltyImagePool.length <= 5) {
                                    return;
                                  }
                                  setState(() {
                                    _penaltyImagePool.remove(image);
                                  });
                                  setModalState(() {});
                                  unawaited(_persistBlastConfig());
                                },
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    _PressButton(
                      text: 'Import from device gallery',
                      color: _Palette.paper,
                      textColor: _Palette.ink,
                      onTap: () {
                        unawaited(_importImagesFromDevice());
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        hintText: 'Image label',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(
                        hintText: 'https://...',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _PressButton(
                      text: 'Add image URL',
                      color: _Palette.blood,
                      textColor: _Palette.paper,
                      onTap: () {
                        final name = nameController.text.trim();
                        final url = urlController.text.trim();
                        final uri = Uri.tryParse(url);
                        if (name.isEmpty || url.isEmpty || uri == null) {
                          return;
                        }
                        setState(() {
                          _penaltyImagePool.add(
                            PenaltyImage(name: name, url: url),
                          );
                        });
                        setModalState(() {
                          nameController.clear();
                          urlController.clear();
                        });
                        unawaited(_persistBlastConfig());
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    nameController.dispose();
    urlController.dispose();
  }

  Future<void> _importContactFromDevice() async {
    try {
      final contacts = await _fetchRandomContactsFromDevice(1);
      if (contacts.isEmpty) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No readable device contacts available.'),
          ),
        );
        return;
      }

      final picked = contacts.first;
      final normalized = _normalizeHandle(picked.handle);
      final exists = _approvedContacts.any(
        (entry) => _normalizeHandle(entry.handle) == normalized,
      );
      if (exists) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact already in approved pool.')),
        );
        return;
      }

      setState(() {
        _approvedContacts.add(picked);
      });
      await _persistBlastConfig();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not read device contact. Check permission.'),
        ),
      );
    }
  }

  Future<void> _importImagesFromDevice() async {
    try {
      final picker = ImagePicker();
      final selected = await picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1800,
      );
      if (selected.isEmpty) {
        return;
      }

      var added = 0;
      for (final file in selected) {
        final path = file.path.trim();
        if (path.isEmpty) {
          continue;
        }
        final exists = _penaltyImagePool.any((image) => image.url == path);
        if (exists) {
          continue;
        }
        _penaltyImagePool.add(
          PenaltyImage(name: _filenameFromPath(path), url: path, isLocal: true),
        );
        added += 1;
      }

      if (added > 0) {
        setState(() {});
        await _persistBlastConfig();
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $added images from gallery.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not import gallery images. Check permission.'),
        ),
      );
    }
  }

  String _filenameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final last = normalized.split('/').last;
    return last.isEmpty ? 'device_image' : last;
  }

  String _normalizeHandle(String value) {
    return value.replaceAll(RegExp(r'[^0-9a-zA-Z@._+-]'), '').toLowerCase();
  }

  String _normalizePhoneForSms(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final normalized = trimmed.replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.replaceAll('+', '').isEmpty) {
      return '';
    }
    return normalized;
  }

  Future<bool> _openSmsComposer(List<String> recipients, String body) async {
    if (recipients.isEmpty) {
      return false;
    }
    final uri = Uri(
      scheme: 'sms',
      path: recipients.join(','),
      queryParameters: {'body': body},
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openAlarmSheet({int? existingIndex}) async {
    final existing = existingIndex == null ? null : _alarms[existingIndex];

    final labelController = TextEditingController(
      text: existing?.label ?? 'New alarm',
    );
    TimeOfDay selectedTime = existing?.time ?? TimeOfDay.now();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                top: 12,
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: _brutalDecoration(
                  color: _Palette.paper,
                  borderRadius: 18,
                  shadowOffset: const Offset(7, 7),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing == null ? 'Create alarm' : 'Edit alarm',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _Palette.ink,
                        fontSize: 28,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Alarm time',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: _Palette.ink),
                    ),
                    const SizedBox(height: 6),
                    _PressButton(
                      text: _formatTimeOfDay(selectedTime),
                      color: _Palette.blood,
                      textColor: _Palette.paper,
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setModalState(() {
                            selectedTime = picked;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Label',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: _Palette.ink),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: labelController,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: _Palette.ink),
                      decoration: InputDecoration(
                        hintText: 'Alarm name',
                        isDense: true,
                        filled: true,
                        fillColor: _Palette.paper,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: _Palette.ink,
                            width: 2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: _Palette.blood,
                            width: 2.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _PressButton(
                            text: 'Cancel',
                            color: _Palette.paperMuted,
                            textColor: _Palette.ink,
                            onTap: () => Navigator.pop(context),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PressButton(
                            text: existing == null ? 'Create' : 'Save',
                            color: _Palette.blood,
                            textColor: _Palette.paper,
                            onTap: () {
                              final label = labelController.text.trim();
                              if (label.isEmpty) {
                                return;
                              }

                              setState(() {
                                if (existingIndex == null) {
                                  _alarms.add(
                                    AlarmItem(
                                      id: DateTime.now().microsecondsSinceEpoch
                                          .toString(),
                                      time: selectedTime,
                                      label: label,
                                      enabled: true,
                                    ),
                                  );
                                } else {
                                  final current = _alarms[existingIndex];
                                  _alarms[existingIndex] = current.copyWith(
                                    time: selectedTime,
                                    label: label,
                                  );
                                }
                              });

                              unawaited(_saveAndSync());
                              Navigator.pop(context);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    labelController.dispose();
  }
}

class AlarmScheduler {
  AlarmScheduler._();

  static final AlarmScheduler instance = AlarmScheduler._();

  static const _channelId = 'morning_menace_alarms';
  static const _channelName = 'Alarm Alerts';
  static const _channelDescription = 'Daily alarm notifications';
  static const _actionSnooze = 'snooze_action';
  static const _actionStop = 'stop_action';
  static const _iosCategory = 'alarm_controls';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _eventController =
      StreamController<String>.broadcast();

  bool _initialized = false;
  bool _pluginAvailable = true;
  String? _lastError;

  Stream<String> get alarmEvents => _eventController.stream;
  bool get pluginAvailable => _pluginAvailable;
  bool get initialized => _initialized;

  Future<String?> initialize() async {
    if (_initialized) {
      return null;
    }

    tz_data.initializeTimeZones();
    try {
      final zoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zoneName));
    } catch (_) {
      // fallback to tz.local default
    }

    final settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        defaultPresentAlert: true,
        defaultPresentBanner: true,
        defaultPresentList: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
        notificationCategories: <DarwinNotificationCategory>[
          DarwinNotificationCategory(
            _iosCategory,
            actions: <DarwinNotificationAction>[
              DarwinNotificationAction.plain(_actionSnooze, 'Snooze 5 min'),
              DarwinNotificationAction.plain(
                _actionStop,
                'Stop',
                options: <DarwinNotificationActionOption>{
                  DarwinNotificationActionOption.foreground,
                },
              ),
            ],
          ),
        ],
      ),
    );

    try {
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            if (response.actionId == _actionSnooze) {
              _eventController.add('snooze:$payload');
            } else if (response.actionId == _actionStop) {
              _eventController.add('stop:$payload');
            } else {
              _eventController.add(payload);
            }
          }
        },
      );

      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max,
        ),
      );
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestExactAlarmsPermission();

      final iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      final details = await _plugin.getNotificationAppLaunchDetails();

      _initialized = true;
      _pluginAvailable = true;
      _lastError = null;
      if (details?.didNotificationLaunchApp ?? false) {
        return details?.notificationResponse?.payload;
      }
      return null;
    } catch (error) {
      _initialized = true;
      _pluginAvailable = false;
      _lastError = 'initialize failed: $error';
      return null;
    }
  }

  Future<void> syncAlarms(List<AlarmItem> alarms) async {
    if (!_pluginAvailable) {
      return;
    }
    try {
      final ids = alarms.map((alarm) => alarm.notificationId).toList();
      for (final id in ids) {
        await _plugin.cancel(id);
      }
      for (final alarm in alarms) {
        await cancelSnooze(alarm);
      }
      for (final alarm in alarms.where((alarm) => alarm.enabled)) {
        await scheduleDaily(alarm);
      }
      _lastError = null;
    } catch (error) {
      _lastError = 'sync failed: $error';
      rethrow;
    }
  }

  Future<void> scheduleDaily(AlarmItem alarm) async {
    if (!_pluginAvailable) {
      return;
    }
    final scheduledDate = _nextInstanceOfTime(alarm.time);
    try {
      await _plugin.zonedSchedule(
        alarm.notificationId,
        alarm.label,
        'Alarm is ringing',
        scheduledDate,
        _alarmNotificationDetails(),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: alarm.id,
      );
      _lastError = null;
    } catch (error) {
      _lastError = 'scheduleDaily failed: $error';
      rethrow;
    }
  }

  Future<void> scheduleSnooze(AlarmItem alarm, DateTime when) async {
    if (!_pluginAvailable) {
      return;
    }
    try {
      await _plugin.zonedSchedule(
        alarm.snoozeNotificationId,
        '${alarm.label} (snoozed)',
        'Snooze finished',
        tz.TZDateTime.from(when, tz.local),
        _alarmNotificationDetails(),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: alarm.id,
      );
      _lastError = null;
    } catch (error) {
      _lastError = 'scheduleSnooze failed: $error';
      rethrow;
    }
  }

  Future<void> cancelSnooze(AlarmItem alarm) async {
    if (!_pluginAvailable) {
      return;
    }
    try {
      await _plugin.cancel(alarm.snoozeNotificationId);
      _lastError = null;
    } catch (error) {
      _lastError = 'cancelSnooze failed: $error';
    }
  }

  NotificationDetails _alarmNotificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(_actionSnooze, 'Snooze 5 min'),
          AndroidNotificationAction(_actionStop, 'Stop'),
        ],
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
        categoryIdentifier: _iosCategory,
      ),
    );
  }

  Future<NotificationDebugInfo> debugInfo() async {
    int? pendingCount;
    if (_pluginAvailable) {
      try {
        final pending = await _plugin.pendingNotificationRequests();
        pendingCount = pending.length;
      } catch (error) {
        _lastError = 'pending requests failed: $error';
      }
    }

    return NotificationDebugInfo(
      initialized: _initialized,
      pluginAvailable: _pluginAvailable,
      pendingCount: pendingCount,
      lastError: _lastError,
    );
  }

  tz.TZDateTime _nextInstanceOfTime(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}

class NotificationDebugInfo {
  const NotificationDebugInfo({
    required this.initialized,
    required this.pluginAvailable,
    required this.pendingCount,
    required this.lastError,
  });

  final bool initialized;
  final bool pluginAvailable;
  final int? pendingCount;
  final String? lastError;
}

class PenaltyContact {
  const PenaltyContact({required this.name, required this.handle});

  final String name;
  final String handle;

  Map<String, dynamic> toJson() => {'name': name, 'handle': handle};

  factory PenaltyContact.fromJson(Map<String, dynamic> json) {
    return PenaltyContact(
      name: (json['name'] ?? '').toString(),
      handle: (json['handle'] ?? '').toString(),
    );
  }
}

class PenaltyImage {
  const PenaltyImage({
    required this.name,
    required this.url,
    this.isLocal = false,
  });

  final String name;
  final String url;
  final bool isLocal;

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'isLocal': isLocal,
  };

  factory PenaltyImage.fromJson(Map<String, dynamic> json) {
    return PenaltyImage(
      name: (json['name'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      isLocal: (json['isLocal'] as bool?) ?? false,
    );
  }
}

class ImageBlastTarget {
  const ImageBlastTarget({required this.contact, required this.image});

  final PenaltyContact contact;
  final PenaltyImage image;
}

class ImageBlastDispatch {
  const ImageBlastDispatch({
    required this.id,
    required this.alarmLabel,
    required this.triggeredAt,
    required this.targets,
    required this.deliveredCount,
    required this.failedCount,
    required this.status,
  });

  final String id;
  final String alarmLabel;
  final DateTime triggeredAt;
  final List<ImageBlastTarget> targets;
  final int deliveredCount;
  final int failedCount;
  final String status;

  ImageBlastDispatch copyWith({
    int? deliveredCount,
    int? failedCount,
    String? status,
  }) {
    return ImageBlastDispatch(
      id: id,
      alarmLabel: alarmLabel,
      triggeredAt: triggeredAt,
      targets: targets,
      deliveredCount: deliveredCount ?? this.deliveredCount,
      failedCount: failedCount ?? this.failedCount,
      status: status ?? this.status,
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BackdropPainter(),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_Palette.ink, Color(0xFF201316), _Palette.ink],
          ),
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = _Palette.blood.withValues(alpha: 0.13)
      ..strokeWidth = 2;

    for (double x = -size.height; x < size.width; x += 34) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        linePaint,
      );
    }

    final stripPaint = Paint()..color = _Palette.blood.withValues(alpha: 0.22);
    canvas.drawRect(Rect.fromLTWH(0, 78, size.width, 12), stripPaint);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 132, size.width, 12),
      stripPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: _brutalDecoration(
                color: _Palette.paper,
                borderRadius: 14,
                shadowOffset: const Offset(6, 6),
              ),
              child: Text(
                'MORNING MENACE',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: _Palette.ink,
                  fontSize: 33,
                  letterSpacing: -0.9,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 52,
            height: 52,
            decoration: _brutalDecoration(
              color: _Palette.blood,
              borderRadius: 12,
              shadowOffset: const Offset(4, 4),
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: _Palette.paper,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClockHero extends StatelessWidget {
  const _ClockHero({required this.now, required this.nextRing});

  final DateTime now;
  final DateTime? nextRing;

  @override
  Widget build(BuildContext context) {
    final countdownText = nextRing == null
        ? 'No alarms active.'
        : 'Next ring in ${_formatDuration(nextRing!.difference(now))}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _brutalDecoration(
        color: _Palette.bloodDeep,
        borderRadius: 18,
        shadowOffset: const Offset(7, 7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: _brutalDecoration(
                  color: _Palette.paper,
                  borderRadius: 999,
                  borderWidth: 2,
                  shadowOffset: const Offset(2, 2),
                ),
                child: Text(
                  'ACTIVE',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: _Palette.ink,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'SNOOZE 5M',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _Palette.paperMuted,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatTime(now),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: _Palette.paper,
                  fontSize: 68,
                  height: 0.95,
                  letterSpacing: -2,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  _isAm(now) ? 'AM' : 'PM',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: _Palette.paper),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _Palette.paperMuted, width: 2),
            ),
            child: Text(
              _formatDate(now),
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: _Palette.paper),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: _brutalDecoration(
              color: _Palette.paper,
              borderRadius: 12,
              borderWidth: 2,
              shadowOffset: const Offset(3, 3),
            ),
            child: Text(
              countdownText,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: _Palette.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: _brutalDecoration(
          color: color,
          borderRadius: 14,
          shadowOffset: const Offset(5, 5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: _brutalDecoration(
                    color: _Palette.paper,
                    borderRadius: 8,
                    borderWidth: 2,
                    shadowOffset: const Offset(2, 2),
                  ),
                  child: Icon(icon, size: 20, color: _Palette.ink),
                ),
                const Spacer(),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _Palette.ink,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _Palette.ink,
                fontSize: 21,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _Palette.surface),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.tone,
    required this.textColor,
  });

  final String label;
  final Color tone;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: _brutalDecoration(
        color: tone,
        borderRadius: 999,
        borderWidth: 1.8,
        shadowOffset: const Offset(2, 2),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: textColor, letterSpacing: 0.3),
      ),
    );
  }
}

class _SnoozeBlastCard extends StatelessWidget {
  const _SnoozeBlastCard({
    required this.enabled,
    required this.contactCount,
    required this.imageCount,
    required this.latestDispatch,
    required this.sending,
    required this.lastStatus,
    required this.onEnabledChanged,
    required this.onManageContactsTap,
    required this.onManageImagesTap,
  });

  final bool enabled;
  final int contactCount;
  final int imageCount;
  final ImageBlastDispatch? latestDispatch;
  final bool sending;
  final String? lastStatus;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onManageContactsTap;
  final VoidCallback onManageImagesTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _brutalDecoration(
        color: _Palette.paper,
        borderRadius: 14,
        borderWidth: 2,
        shadowOffset: const Offset(5, 5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Snooze consequence #1',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: _Palette.ink,
                    fontSize: 24,
                  ),
                ),
              ),
              Switch(
                value: enabled,
                activeThumbColor: _Palette.paper,
                activeTrackColor: _Palette.blood,
                inactiveThumbColor: _Palette.ink,
                inactiveTrackColor: _Palette.surface,
                onChanged: onEnabledChanged,
              ),
            ],
          ),
          Row(
            children: [
              _StatusBadge(
                label: enabled ? 'ON' : 'OFF',
                tone: enabled ? _Palette.blood : _Palette.paperMuted,
                textColor: enabled ? _Palette.paper : _Palette.ink,
              ),
              const SizedBox(width: 8),
              const _StatusBadge(
                label: 'AUTO SEND',
                tone: _Palette.paperMuted,
                textColor: _Palette.ink,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'On snooze: pick 5 random contacts and blast 5 random images.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _Palette.surface),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _PressButton(
                  text: 'Contacts',
                  color: _Palette.paper,
                  textColor: _Palette.ink,
                  onTap: onManageContactsTap,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PressButton(
                  text: 'Images',
                  color: _Palette.paper,
                  textColor: _Palette.ink,
                  onTap: onManageImagesTap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Contacts armed',
                  value: '$contactCount',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(label: 'Images loaded', value: '$imageCount'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: 'Last trigger',
                  value: latestDispatch == null
                      ? 'Never'
                      : _formatTime(latestDispatch!.triggeredAt),
                ),
              ),
            ],
          ),
          if (sending || lastStatus != null) ...[
            const SizedBox(height: 8),
            Text(
              sending ? 'Sending blast payloads...' : (lastStatus ?? ''),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _Palette.surface),
            ),
          ],
          if (latestDispatch != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Latest blast (${latestDispatch!.alarmLabel})',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: _Palette.ink),
                  ),
                ),
                _StatusBadge(
                  label: _statusLabel(latestDispatch!.status),
                  tone: _statusTone(latestDispatch!.status),
                  textColor: _statusTextColor(latestDispatch!.status),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Delivered ${latestDispatch!.deliveredCount} • Failed ${latestDispatch!.failedCount}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _Palette.surface),
            ),
            const SizedBox(height: 4),
            ...latestDispatch!.targets.map(
              (target) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${target.contact.name}  <-  ${target.image.name}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: _Palette.surface),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: _brutalDecoration(
        color: _Palette.paperMuted,
        borderRadius: 10,
        borderWidth: 1.8,
        shadowOffset: const Offset(2, 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: _Palette.surface),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: _Palette.ink),
          ),
        ],
      ),
    );
  }
}

class _AlarmCard extends StatelessWidget {
  const _AlarmCard({
    required this.alarm,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final AlarmItem alarm;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(alarm.enabled ? -3 : 0, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _brutalDecoration(
          color: alarm.enabled ? _Palette.paper : _Palette.paperMuted,
          borderRadius: 14,
          shadowOffset: const Offset(6, 6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 42,
                  decoration: BoxDecoration(
                    color: alarm.enabled ? _Palette.blood : _Palette.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _formatTimeOfDay(alarm.time),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: _Palette.ink,
                    fontSize: 36,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  alarm.time.period == DayPeriod.am ? 'AM' : 'PM',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: _Palette.ink),
                ),
                const Spacer(),
                Switch(
                  value: alarm.enabled,
                  activeThumbColor: _Palette.paper,
                  activeTrackColor: _Palette.blood,
                  inactiveThumbColor: _Palette.ink,
                  inactiveTrackColor: _Palette.surface,
                  onChanged: onToggle,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              alarm.label,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: _Palette.ink),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _PressButton(
                    text: 'Edit',
                    color: _Palette.paper,
                    textColor: _Palette.ink,
                    onTap: onEdit,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PressButton(
                    text: 'Delete',
                    color: _Palette.blood,
                    textColor: _Palette.paper,
                    onTap: onDelete,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyAlarmState extends StatelessWidget {
  const _EmptyAlarmState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _brutalDecoration(color: _Palette.paper, borderRadius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No alarms yet.',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: _Palette.ink),
          ),
          const SizedBox(height: 6),
          Text(
            'Create one alarm to start the ring + snooze flow.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _Palette.surface),
          ),
        ],
      ),
    );
  }
}

class _PressButton extends StatefulWidget {
  const _PressButton({
    required this.text,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  final String text;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;

  @override
  State<_PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<_PressButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.translationValues(0, _pressed ? 1 : 0, 0),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: _brutalDecoration(
          color: widget.color,
          borderRadius: 12,
          borderWidth: 2.2,
          shadowOffset: _pressed ? const Offset(1, 1) : const Offset(3, 3),
        ),
        child: Center(
          child: Text(
            widget.text,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: widget.textColor),
          ),
        ),
      ),
    );
  }
}

class _RingingOverlay extends StatelessWidget {
  const _RingingOverlay({
    required this.alarm,
    required this.now,
    required this.onStop,
    required this.onSnooze,
  });

  final AlarmItem alarm;
  final DateTime now;
  final VoidCallback onStop;
  final VoidCallback onSnooze;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: _Palette.ink.withValues(alpha: 0.92),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Container(
                width: 560,
                constraints: const BoxConstraints(maxWidth: 560),
                padding: const EdgeInsets.all(18),
                decoration: _brutalDecoration(
                  color: _Palette.blood,
                  borderRadius: 20,
                  shadowOffset: const Offset(8, 8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RINGING',
                      style: Theme.of(context).textTheme.displayMedium
                          ?.copyWith(
                            color: _Palette.paper,
                            fontSize: 52,
                            height: 0.95,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatTime(now),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(color: _Palette.paper, fontSize: 42),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: _brutalDecoration(
                        color: _Palette.paper,
                        borderRadius: 12,
                        borderWidth: 2.2,
                        shadowOffset: const Offset(3, 3),
                      ),
                      child: Text(
                        alarm.label,
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(color: _Palette.ink),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _PressButton(
                            text: 'Snooze 5 min',
                            color: _Palette.paper,
                            textColor: _Palette.ink,
                            onTap: onSnooze,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PressButton(
                            text: 'Stop',
                            color: _Palette.bloodDeep,
                            textColor: _Palette.paper,
                            onTap: onStop,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AlarmItem {
  const AlarmItem({
    required this.id,
    required this.time,
    required this.label,
    required this.enabled,
  });

  final String id;
  final TimeOfDay time;
  final String label;
  final bool enabled;

  int get notificationId => id.hashCode.abs() % 1000000;
  int get snoozeNotificationId => notificationId + 1000000;

  AlarmItem copyWith({TimeOfDay? time, String? label, bool? enabled}) {
    return AlarmItem(
      id: id,
      time: time ?? this.time,
      label: label ?? this.label,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'hour': time.hour,
      'minute': time.minute,
      'label': label,
      'enabled': enabled,
    };
  }

  factory AlarmItem.fromJson(Map<String, dynamic> json) {
    return AlarmItem(
      id: (json['id'] ?? '').toString(),
      time: TimeOfDay(
        hour: (json['hour'] as num?)?.toInt() ?? 7,
        minute: (json['minute'] as num?)?.toInt() ?? 0,
      ),
      label: (json['label'] ?? 'Alarm').toString(),
      enabled: (json['enabled'] as bool?) ?? true,
    );
  }
}

BoxDecoration _brutalDecoration({
  required Color color,
  required double borderRadius,
  double borderWidth = 2.8,
  Offset shadowOffset = const Offset(5, 5),
}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(color: _Palette.ink, width: borderWidth),
    boxShadow: [
      BoxShadow(color: _Palette.ink, offset: shadowOffset, blurRadius: 0),
    ],
  );
}

String _formatTime(DateTime now) {
  final hourOfPeriod = now.hour % 12;
  final hour = hourOfPeriod == 0 ? 12 : hourOfPeriod;
  return '${hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
}

String _formatTimeOfDay(TimeOfDay time) {
  final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  return '${hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

bool _isAm(DateTime dateTime) => dateTime.hour < 12;

bool _sameMinute(DateTime a, DateTime b) {
  return a.year == b.year &&
      a.month == b.month &&
      a.day == b.day &&
      a.hour == b.hour &&
      a.minute == b.minute;
}

String _formatDate(DateTime dateTime) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final weekday = weekdays[dateTime.weekday - 1];
  final month = months[dateTime.month - 1];
  return '$weekday, $month ${dateTime.day}';
}

String _formatDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final hours = safe.inHours;
  final minutes = safe.inMinutes.remainder(60);
  if (hours == 0) {
    return '$minutes min';
  }
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}

Color _statusTone(String status) {
  switch (status) {
    case 'sent':
      return _Palette.paperMuted;
    case 'partial':
      return const Color(0xFFEFC16A);
    case 'failed':
      return _Palette.blood;
    case 'sending':
      return const Color(0xFF8AD9E7);
    default:
      return _Palette.paper;
  }
}

Color _statusTextColor(String status) {
  if (status == 'failed') {
    return _Palette.paper;
  }
  return _Palette.ink;
}

String _statusLabel(String status) {
  switch (status) {
    case 'sent':
      return 'SENT';
    case 'partial':
      return 'PARTIAL';
    case 'failed':
      return 'FAILED';
    case 'sending':
      return 'SENDING';
    default:
      return 'QUEUED';
  }
}
