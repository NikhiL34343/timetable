import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

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
}

class TimetableScreen extends StatefulWidget {
  @override
  _TimetableScreenState createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _notificationsEnabled = false;
  bool _notificationsScheduled = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateFormat('EEEE').format(DateTime.now());
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    // Request notification permission
    final status = await Permission.notification.request();
    if (status.isGranted) {
      _notificationsEnabled = true;
    }

    // Initialize notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    
    await _notificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _toggleNotifications() async {
    if (!_notificationsEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enable notifications in app settings')),
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
    // Cancel all existing notifications first
    await _notificationsPlugin.cancelAll();

    final now = DateTime.now();
    final today = DateFormat('EEEE').format(now);
    
    // Get today's slots
    final todaySlots = _timetable[today] ?? [];
    
    if (todaySlots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No slots to set reminders for today')),
      );
      return;
    }

    int scheduledCount = 0;
    
    for (int i = 0; i < todaySlots.length; i++) {
      final slot = todaySlots[i];
      
      // Schedule start notification
      final startDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        slot.start.hour,
        slot.start.minute,
      );
      
      // Schedule end notification
      final endDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        slot.end.hour,
        slot.end.minute,
      );

      // Only schedule if the time is in the future
      if (startDateTime.isAfter(now)) {
        await _notificationsPlugin.zonedSchedule(
          i * 2, // Unique ID for start notification
          'Timetable Reminder',
          '${slot.title} is starting now',
          tz.TZDateTime.from(startDateTime, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'timetable_channel',
              'Timetable Notifications',
              channelDescription: 'Notifications for timetable slots',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
        scheduledCount++;
      }

      if (endDateTime.isAfter(now)) {
        await _notificationsPlugin.zonedSchedule(
          i * 2 + 1, // Unique ID for end notification
          'Timetable Reminder',
          '${slot.title} is ending now',
          tz.TZDateTime.from(endDateTime, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'timetable_channel',
              'Timetable Notifications',
              channelDescription: 'Notifications for timetable slots',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
        scheduledCount++;
      }
    }

    setState(() {
      _notificationsScheduled = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$scheduledCount notifications scheduled for today')),
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

    Map<String, bool> selectionMap = {
      for (var day in otherDays) day: false,
    };

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
                  onPressed: () {
                    setState(() {
                      for (var day in otherDays) {
                        if (selectionMap[day] == true) {
                          // Clear existing slots and copy from selected day
                          _timetable[day]!.clear();
                          for (var slot in _timetable[_selectedDay]!) {
                            _timetable[day]!.add(Slot(
                              slot.start,
                              slot.end,
                              slot.title,
                            ));
                          }
                          // Sort the copied slots
                          _timetable[day]!.sort((a, b) =>
                              a.start.hour * 60 +
                              a.start.minute -
                              b.start.hour * 60 -
                              b.start.minute);
                        }
                      }
                    });
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
              ElevatedButton(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: startTime!,
                  );
                  if (picked != null) startTime = picked;
                  setState(() {});
                },
                child: Text('Start: ${startTime!.format(context)}'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: endTime!,
                  );
                  if (picked != null) endTime = picked;
                  setState(() {});
                },
                child: Text('End: ${endTime!.format(context)}'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
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
                  Navigator.pop(context);
                }
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _deleteSlot(int index) {
    setState(() {
      _timetable[_selectedDay]!.removeAt(index);
    });
  }

  void _copySlot(int index) async {
    final List<String> otherDays = _timetable.keys
        .where((d) => d != _selectedDay)
        .toList();

    final original = _timetable[_selectedDay]![index];

    Map<String, bool> selectionMap = {
      for (var day in otherDays) day: false,
    };

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
                  onPressed: () {
                    setState(() {
                      for (var day in otherDays) {
                        if (selectionMap[day] == true) {
                          bool alreadyExists = _timetable[day]!.any((slot) =>
                            slot.start == original.start &&
                            slot.end == original.end &&
                            slot.title == original.title,
                          );
                          if (!alreadyExists) {
                            _timetable[day]!.add(Slot(
                              original.start,
                              original.end,
                              original.title,
                            ));
                            _timetable[day]!.sort((a, b) =>
                                a.start.hour * 60 +
                                a.start.minute -
                                b.start.hour * 60 -
                                b.start.minute);
                          }
                        }
                      }
                    });
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

  void _addSlotDialog() async {
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    String title = '';

    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text('Add Slot'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(labelText: 'Title'),
                onChanged: (val) => title = val,
              ),
              ElevatedButton(
                onPressed: () async {
                  startTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  setState(() {});
                },
                child: Text(
                  startTime == null
                      ? 'Select Start Time'
                      : 'Start: ${startTime!.format(context)}',
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  endTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  setState(() {});
                },
                child: Text(
                  endTime == null
                      ? 'Select End Time'
                      : 'End: ${endTime!.format(context)}',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (startTime != null && endTime != null && title.isNotEmpty) {
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
                  Navigator.of(context).pop();
                }
              },
              child: Text('Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Slot> slots = _timetable[_selectedDay]!;

    return Scaffold(
      appBar: AppBar(
        title: Text('Timetable - $_selectedDay'),
        actions: [
          IconButton(
            icon: Icon(_notificationsScheduled ? Icons.notifications_off : Icons.notifications),
            onPressed: _toggleNotifications,
            tooltip: _notificationsScheduled ? 'Turn Off Reminders' : 'Set Reminders for Today',
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
                    Text(
                      'Notifications are enabled',
                      style: TextStyle(color: Colors.green),
                    )
                  else
                    Text(
                      'Enable notifications in settings for reminders',
                      style: TextStyle(color: Colors.orange),
                    ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: slots.length,
              itemBuilder: (context, index) {
                final slot = slots[index];
                return Card(
                  margin: EdgeInsets.all(8),
                  child: ListTile(
                    title: Text(slot.title),
                    subtitle: Text(
                      '${slot.start.format(context)} - ${slot.end.format(context)}',
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
