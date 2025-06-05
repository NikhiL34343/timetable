import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(TimetableApp());
}

class TimetableApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timetable',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
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
  }

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
                child: Text(startTime == null ? 'Select Start Time' : 'Start: ${startTime!.format(context)}'),
              ),
              ElevatedButton(
                onPressed: () async {
                  endTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  setState(() {});
                },
                child: Text(endTime == null ? 'Select End Time' : 'End: ${endTime!.format(context)}'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (startTime != null && endTime != null && title.isNotEmpty) {
                  setState(() {
                    _timetable[_selectedDay]!.add(Slot(startTime!, endTime!, title));
                    _timetable[_selectedDay]!
                        .sort((a, b) => a.start.hour * 60 + a.start.minute - b.start.hour * 60 - b.start.minute);
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
          PopupMenuButton<String>(
            onSelected: (day) => setState(() => _selectedDay = day),
            itemBuilder: (context) {
              return _timetable.keys.map((day) {
                return PopupMenuItem(
                  value: day,
                  child: Text(day),
                );
              }).toList();
            },
            icon: Icon(Icons.calendar_today),
          ),
        ],
      ),
      body: slots.isEmpty
          ? Center(child: Text('No slots added for $_selectedDay'))
          : ListView.builder(
              itemCount: slots.length,
              itemBuilder: (context, index) {
                final slot = slots[index];
                return Card(
                  margin: EdgeInsets.all(8),
                  child: ListTile(
                    title: Text(slot.title),
                    subtitle: Text('${slot.start.format(context)} - ${slot.end.format(context)}'),
                    trailing: Icon(Icons.more_vert), // For future options
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

