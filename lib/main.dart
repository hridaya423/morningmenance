import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  final Map<String, DateTime> _snoozedUntil = {};
  final Set<String> _minuteLocks = {};

  List<AlarmItem> _alarms = [];
  DateTime _now = DateTime.now();
  AlarmItem? _ringingAlarm;

  Timer? _clockTimer;
  StreamSubscription<String>? _alarmEventSubscription;

  bool _loading = true;
  String? _loadingError;

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
    return const [
      AlarmItem(
        id: 'a1',
        time: TimeOfDay(hour: 6, minute: 30),
        label: 'Morning training',
        enabled: true,
      ),
      AlarmItem(
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
    await _syncSystemAlarms();
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

    final message = info.pluginAvailable
        ? 'Notifications are active. Scheduled alarms: ${info.pendingCount ?? 0}.'
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
    final snoozeTime = DateTime.now().add(const Duration(minutes: 5));
    setState(() {
      _snoozedUntil[current.id] = snoozeTime;
      _ringingAlarm = null;
    });
    unawaited(AlarmScheduler.instance.scheduleSnooze(current, snoozeTime));
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
