import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() {
  tz.initializeTimeZones();
  runApp(TimetableApp());
}

class TimetableApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timetable',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: TimetableScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class Slot {
  final TimeOfDay start;
  final TimeOfDay end;
  final String title;

  Slot(this.start, this.end, this.title);

  // Convert Slot to JSON
  Map<String, dynamic> toJson() {
    return {
      'startHour': start.hour,
      'startMinute': start.minute,
      'endHour': end.hour,
      'endMinute': end.minute,
      'title': title,
    };
  }

  // Create Slot from JSON
  factory Slot.fromJson(Map<String, dynamic> json) {
    return Slot(
      TimeOfDay(hour: json['startHour'], minute: json['startMinute']),
      TimeOfDay(hour: json['endHour'], minute: json['endMinute']),
      json['title'],
    );
  }
}

class TimetableScreen extends StatefulWidget {
  @override
  _TimetableScreenState createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _notificationsEnabled = false;
  bool _notificationsScheduled = false;
  SharedPreferences? _prefs;

  final Map<String, List<Slot>> _timetable = {
    'Monday': [],
    'Tuesday': [],
    'Wednesday': [],
    'Thursday': [],
    'Friday': [],
    'Saturday': [],
    'Sunday': [],
  };

  late String _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateFormat('EEEE').format(DateTime.now());
    _initializeApp();
  }

  // Fixed method to format TimeOfDay in 12-hour format consistently
  String _formatTime12Hour(TimeOfDay time) {
    final hour = time.hour == 0 
        ? 12 
        : time.hour > 12 
            ? time.hour - 12 
            : time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<void> _initializeApp() async {
    await _initializePreferences();
    await _loadTimetableData();
    await _initializeNotifications();
  }

  Future<void> _initializePreferences() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<void> _loadTimetableData() async {
    if (_prefs == null) return;

    for (String day in _timetable.keys) {
      String? jsonString = _prefs!.getString('timetable_$day');
      if (jsonString != null) {
        List<dynamic> jsonList = jsonDecode(jsonString);
        _timetable[day] = jsonList.map((json) => Slot.fromJson(json)).toList();
      }
    }
    setState(() {});
  }

  Future<void> _saveTimetableData() async {
    if (_prefs == null) return;

    for (String day in _timetable.keys) {
      List<Map<String, dynamic>> jsonList = _timetable[day]!
          .map((slot) => slot.toJson())
          .toList();
      String jsonString = jsonEncode(jsonList);
      await _prefs!.setString('timetable_$day', jsonString);
    }
  }

  Future<void> _initializeNotifications() async {
    // Request notification permission first
    final notificationStatus = await Permission.notification.request();
    
    // For Android 13+ request additional permissions
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
    
    // Check if notification permission is granted
    if (notificationStatus.isGranted) {
      _notificationsEnabled = true;
    }

    // Initialize notifications with proper channel setup
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap if needed
        print('Notification tapped: ${response.payload}');
      },
    );

    // Create notification channel for Android with proper configuration
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'timetable_slot_channel',
      'Timetable Slot Reminders',
      description: 'Notifications for timetable slot start and end times',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channel);
    }

    // Update state after initialization
    setState(() {});
  }

  Future<void> _toggleNotifications() async {
    if (!_notificationsEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enable notifications in app settings'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => openAppSettings(),
          ),
        ),
      );
      return;
    }

    if (_notificationsScheduled) {
      // Turn off notifications
      await _notificationsPlugin.cancelAll();
      setState(() {
        _notificationsScheduled = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('All notifications cancelled')),
      );
    } else {
      // Schedule notifications
      await _scheduleNotificationsForToday();
    }
  }

  Future<void> _scheduleNotificationsForToday() async {
    await _notificationsPlugin.cancelAll();

    final now = DateTime.now();
    final today = DateFormat('EEEE').format(now);
    final todaySlots = _timetable[today] ?? [];

    if (todaySlots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No slots found for today')),
      );
      return;
    }

    int notificationId = 1000; // Start with a higher ID to avoid conflicts
    int scheduledCount = 0;

    for (var slot in todaySlots) {
      final startDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        slot.start.hour,
        slot.start.minute,
      );

      final endDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        slot.end.hour,
        slot.end.minute,
      );

      // Schedule start notification (5 minutes before)
      final startNotificationTime = startDateTime.subtract(Duration(minutes: 5));
      if (startNotificationTime.isAfter(now)) {
        try {
          await _notificationsPlugin.zonedSchedule(
            notificationId++,
            'Upcoming Slot',
            '${slot.title} starts in 5 minutes at ${_formatTime12Hour(slot.start)}',
            tz.TZDateTime.from(startNotificationTime, tz.local),
            NotificationDetails(
              android: AndroidNotificationDetails(
                'timetable_slot_channel',
                'Timetable Slot Reminders',
                channelDescription: 'Notifications for timetable slot start and end times',
                importance: Importance.high,
                priority: Priority.high,
                playSound: true,
                enableVibration: true,
                icon: '@mipmap/ic_launcher',
                largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
                styleInformation: BigTextStyleInformation(
                  '${slot.title} starts in 5 minutes at ${_formatTime12Hour(slot.start)}',
                  contentTitle: 'Upcoming Slot',
                ),
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
          scheduledCount++;
        } catch (e) {
          print('Error scheduling start notification: $e');
        }
      }

      // Schedule actual start notification
      if (startDateTime.isAfter(now)) {
        try {
          await _notificationsPlugin.zonedSchedule(
            notificationId++,
            'Slot Started',
            '${slot.title} has started at ${_formatTime12Hour(slot.start)}',
            tz.TZDateTime.from(startDateTime, tz.local),
            NotificationDetails(
              android: AndroidNotificationDetails(
                'timetable_slot_channel',
                'Timetable Slot Reminders',
                channelDescription: 'Notifications for timetable slot start and end times',
                importance: Importance.high,
                priority: Priority.high,
                playSound: true,
                enableVibration: true,
                icon: '@mipmap/ic_launcher',
                largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
                styleInformation: BigTextStyleInformation(
                  '${slot.title} has started at ${_formatTime12Hour(slot.start)}',
                  contentTitle: 'Slot Started',
                ),
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
          scheduledCount++;
        } catch (e) {
          print('Error scheduling start notification: $e');
        }
      }

      // Schedule end notification
      if (endDateTime.isAfter(now)) {
        try {
          await _notificationsPlugin.zonedSchedule(
            notificationId++,
            'Slot Ended',
            '${slot.title} has ended at ${_formatTime12Hour(slot.end)}',
            tz.TZDateTime.from(endDateTime, tz.local),
            NotificationDetails(
              android: AndroidNotificationDetails(
                'timetable_slot_channel',
                'Timetable Slot Reminders',
                channelDescription: 'Notifications for timetable slot start and end times',
                importance: Importance.high,
                priority: Priority.high,
                playSound: true,
                enableVibration: true,
                icon: '@mipmap/ic_launcher',
                largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
                styleInformation: BigTextStyleInformation(
                  '${slot.title} has ended at ${_formatTime12Hour(slot.end)}',
                  contentTitle: 'Slot Ended',
                ),
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
          scheduledCount++;
        } catch (e) {
          print('Error scheduling end notification: $e');
        }
      }
    }

    setState(() {
      _notificationsScheduled = scheduledCount > 0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$scheduledCount notifications scheduled for ${todaySlots.length} slots'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _copyDaySchedule() async {
    final List<String> otherDays = _timetable.keys
        .where((d) => d != _selectedDay)
        .toList();

    if (_timetable[_selectedDay]!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No slots to copy on $_selectedDay')),
      );
      return;
    }

    Map<String, bool> selectionMap = {for (var day in otherDays) day: false};

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text('Copy $_selectedDay\'s schedule to:'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('This will replace existing slots on selected days.'),
                  SizedBox(height: 10),
                  ...otherDays.map((day) {
                    return CheckboxListTile(
                      title: Text(day),
                      subtitle: Text('${_timetable[day]!.length} slots'),
                      value: selectionMap[day],
                      onChanged: (selected) {
                        setLocalState(() {
                          selectionMap[day] = selected!;
                        });
                      },
                    );
                  }).toList(),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    setState(() {
                      for (var day in otherDays) {
                        if (selectionMap[day] == true) {
                          // Clear existing slots and copy from selected day
                          _timetable[day]!.clear();
                          for (var slot in _timetable[_selectedDay]!) {
                            _timetable[day]!.add(
                              Slot(slot.start, slot.end, slot.title),
                            );
                          }
                          // Sort the copied slots
                          _timetable[day]!.sort(
                            (a, b) =>
                                a.start.hour * 60 +
                                a.start.minute -
                                b.start.hour * 60 -
                                b.start.minute,
                          );
                        }
                      }
                    });
                    await _saveTimetableData(); // Save after copying
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Schedule copied successfully')),
                    );
                  },
                  child: Text('Copy'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _editSlot(int index) async {
    final currentSlot = _timetable[_selectedDay]![index];
    TimeOfDay? startTime = currentSlot.start;
    TimeOfDay? endTime = currentSlot.end;
    String title = currentSlot.title;

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Edit Slot'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: TextEditingController(text: title),
                    decoration: InputDecoration(labelText: 'Title'),
                    onChanged: (val) => title = val,
                  ),
                  SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: startTime!,
                        builder: (context, child) {
                          return MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              alwaysUse24HourFormat: false,
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        startTime = picked;
                        setDialogState(() {});
                      }
                    },
                    child: Text('Start: ${_formatTime12Hour(startTime!)}'),
                  ),
                  SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: endTime!,
                        builder: (context, child) {
                          return MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              alwaysUse24HourFormat: false,
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        endTime = picked;
                        setDialogState(() {});
                      }
                    },
                    child: Text('End: ${_formatTime12Hour(endTime!)}'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    if (title.isNotEmpty) {
                      setState(() {
                        _timetable[_selectedDay]![index] = Slot(
                          startTime!,
                          endTime!,
                          title,
                        );
                        _timetable[_selectedDay]!.sort(
                          (a, b) =>
                              a.start.hour * 60 +
                              a.start.minute -
                              b.start.hour * 60 -
                              b.start.minute,
                        );
                      });
                      await _saveTimetableData(); // Save after editing
                      Navigator.pop(context);
                    }
                  },
                  child: Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteSlot(int index) async {
    setState(() {
      _timetable[_selectedDay]!.removeAt(index);
    });
    await _saveTimetableData(); // Save after deleting
  }

  void _copySlot(int index) async {
    final List<String> otherDays = _timetable.keys
        .where((d) => d != _selectedDay)
        .toList();

    final original = _timetable[_selectedDay]![index];

    Map<String, bool> selectionMap = {for (var day in otherDays) day: false};

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text('Copy slot to days'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: otherDays.map((day) {
                  return CheckboxListTile(
                    title: Text(day),
                    value: selectionMap[day],
                    onChanged: (selected) {
                      setLocalState(() {
                        selectionMap[day] = selected!;
                      });
                    },
                  );
                }).toList(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    setState(() {
                      for (var day in otherDays) {
                        if (selectionMap[day] == true) {
                          bool alreadyExists = _timetable[day]!.any(
                            (slot) =>
                                slot.start == original.start &&
                                slot.end == original.end &&
                                slot.title == original.title,
                          );
                          if (!alreadyExists) {
                            _timetable[day]!.add(
                              Slot(
                                original.start,
                                original.end,
                                original.title,
                              ),
                            );
                            _timetable[day]!.sort(
                              (a, b) =>
                                  a.start.hour * 60 +
                                  a.start.minute -
                                  b.start.hour * 60 -
                                  b.start.minute,
                            );
                          }
                        }
                      }
                    });
                    await _saveTimetableData(); // Save after copying
                    Navigator.pop(context);
                  },
                  child: Text('Copy'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _addSlotDialog() async {
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    String title = '';

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Add Slot'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: InputDecoration(labelText: 'Title'),
                    onChanged: (val) => title = val,
                  ),
                  SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                        builder: (context, child) {
                          return MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              alwaysUse24HourFormat: false,
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        startTime = picked;
                        setDialogState(() {}); // Update dialog state
                      }
                    },
                    child: Text(
                      startTime == null
                          ? 'Select Start Time'
                          : 'Start: ${_formatTime12Hour(startTime!)}',
                    ),
                  ),
                  SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                        builder: (context, child) {
                          return MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              alwaysUse24HourFormat: false,
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        endTime = picked;
                        setDialogState(() {}); // Update dialog state
                      }
                    },
                    child: Text(
                      endTime == null
                          ? 'Select End Time'
                          : 'End: ${_formatTime12Hour(endTime!)}',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    if (startTime != null &&
                        endTime != null &&
                        title.isNotEmpty) {
                      setState(() {
                        _timetable[_selectedDay]!.add(
                          Slot(startTime!, endTime!, title),
                        );
                        _timetable[_selectedDay]!.sort(
                          (a, b) =>
                              a.start.hour * 60 +
                              a.start.minute -
                              b.start.hour * 60 -
                              b.start.minute,
                        );
                      });
                      await _saveTimetableData(); // Save after adding
                      Navigator.of(context).pop();
                    }
                  },
                  child: Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Add method to clear all data (optional - for testing or reset functionality)
  Future<void> _clearAllData() async {
    if (_prefs == null) return;

    // Clear from memory
    setState(() {
      for (String day in _timetable.keys) {
        _timetable[day]!.clear();
      }
    });

    // Clear from storage
    for (String day in _timetable.keys) {
      await _prefs!.remove('timetable_$day');
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('All timetable data cleared')));
  }

  @override
  Widget build(BuildContext context) {
    List<Slot> slots = _timetable[_selectedDay]!;

    return Scaffold(
      appBar: AppBar(
        title: Text('Timetable - $_selectedDay'),
        actions: [
          IconButton(
            icon: Icon(
              _notificationsScheduled
                  ? Icons.notifications_active
                  : Icons.notifications_none,
              color: _notificationsScheduled ? Colors.green : null,
            ),
            onPressed: _toggleNotifications,
            tooltip: _notificationsScheduled
                ? 'Turn Off Reminders'
                : 'Set Reminders for Today',
          ),
          IconButton(
            icon: Icon(Icons.copy),
            onPressed: _copyDaySchedule,
            tooltip: 'Copy Day Schedule',
          ),
          PopupMenuButton<String>(
            onSelected: (day) => setState(() => _selectedDay = day),
            itemBuilder: (context) {
              return _timetable.keys.map((day) {
                return PopupMenuItem(value: day, child: Text(day));
              }).toList();
            },
            icon: Icon(Icons.calendar_today),
          ),
        ],
      ),
      body: slots.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('No slots added for $_selectedDay'),
                  SizedBox(height: 20),
                  if (_notificationsEnabled)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 8),
                        Text(
                          'Notifications are enabled',
                          style: TextStyle(color: Colors.green),
                        ),
                      ],
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.warning, color: Colors.orange),
                        SizedBox(width: 8),
                        Text(
                          'Enable notifications in settings for reminders',
                          style: TextStyle(color: Colors.orange),
                        ),
                      ],
                    ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: slots.length,
              itemBuilder: (context, index) {
                final slot = slots[index];
                // Alternating colors - light grey for even indices, darker grey for odd indices
                final cardColor = index % 2 == 0
                    ? Colors
                          .grey[100] // Very light grey for even indices (0, 2, 4...)
                    : Colors
                          .grey[300]; // Slightly darker grey for odd indices (1, 3, 5...)

                return Card(
                  margin: EdgeInsets.all(8),
                  color: cardColor, // Apply the alternating color
                  child: ListTile(
                    title: Text(slot.title),
                    subtitle: Text(
                      '${_formatTime12Hour(slot.start)} - ${_formatTime12Hour(slot.end)}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _editSlot(index);
                        if (value == 'delete') _deleteSlot(index);
                        if (value == 'copy') _copySlot(index);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                        PopupMenuItem(value: 'copy', child: Text('Copy to...')),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSlotDialog,
        child: Icon(Icons.add),
        tooltip: 'Add Slot',
      ),
    );
  }
}
