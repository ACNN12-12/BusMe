import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- МОДЕЛИ ДАННЫХ ---

class Departure {
  final String id;
  final String time; // Формат "HH:mm"
  final int stopOffsetMinutes; // Смещение для остановки в минутах (0 если нет)

  Departure({
    required this.id,
    required this.time,
    required this.stopOffsetMinutes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time,
        'stopOffsetMinutes': stopOffsetMinutes,
      };

  factory Departure.fromJson(Map<String, dynamic> json) {
    return Departure(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      time: json['time'] ?? "08:00",
      stopOffsetMinutes: json['stopOffsetMinutes'] ?? 0,
    );
  }
}

class BusPoint {
  final String id;
  final String name;
  final String? priorityStart; // "HH:mm"
  final String? priorityEnd; // "HH:mm"
  final List<Departure> departures;

  BusPoint({
    required this.id,
    required this.name,
    this.priorityStart,
    this.priorityEnd,
    required this.departures,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'priorityStart': priorityStart,
        'priorityEnd': priorityEnd,
        'departures': departures.map((d) => d.toJson()).toList(),
      };

  factory BusPoint.fromJson(Map<String, dynamic> json) {
    var depList = json['departures'] as List? ?? [];
    return BusPoint(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] ?? "Без названия",
      priorityStart: json['priorityStart'],
      priorityEnd: json['priorityEnd'],
      departures: depList.map((d) => Departure.fromJson(d)).toList(),
    );
  }

  BusPoint copyWith({
    String? name,
    String? priorityStart,
    String? priorityEnd,
    List<Departure>? departures,
  }) {
    return BusPoint(
      id: this.id,
      name: name ?? this.name,
      priorityStart: priorityStart ?? this.priorityStart,
      priorityEnd: priorityEnd ?? this.priorityEnd,
      departures: departures ?? this.departures,
    );
  }
}

// --- УПРАВЛЕНИЕ СОСТОЯНИЕМ (STATE MANAGEMENT) ---

class AppState extends ChangeNotifier {
  List<BusPoint> _points = [];
  ThemeMode _themeMode = ThemeMode.system;
  double _fontSizeScale = 1.0;

  List<BusPoint> get points => _points;
  ThemeMode get themeMode => _themeMode;
  double get fontSizeScale => _fontSizeScale;

  AppState() {
    _loadData();
  }

  // Загрузка данных из локальной памяти
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Загрузка темы
    final themeStr = prefs.getString('themeMode') ?? 'system';
    _themeMode = ThemeMode.values.firstWhere(
      (e) => e.toString().split('.').last == themeStr,
      orElse: () => ThemeMode.system,
    );

    // Загрузка размера шрифта
    _fontSizeScale = prefs.getDouble('fontSizeScale') ?? 1.0;

    // Загрузка расписания
    final pointsJson = prefs.getString('pointsData');
    if (pointsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(pointsJson);
        _points = decoded.map((item) => BusPoint.fromJson(item)).toList();
      } catch (e) {
        _points = [];
      }
    } else {
      _points = _getMockData(); // Начальные данные при первом запуске
    }
    notifyListeners();
  }

  // Сохранение данных
  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pointsData', jsonEncode(_points.map((p) => p.toJson()).toList()));
    await prefs.setString('themeMode', _themeMode.toString().split('.').last);
    await prefs.setDouble('fontSizeScale', _fontSizeScale);
  }

  // Метод определения активного пункта по приоритетному времени
  BusPoint? getActivePoint() {
    if (_points.isEmpty) return null;

    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    for (var point in _points) {
      if (point.priorityStart != null && point.priorityEnd != null) {
        final start = _parseTimeToMinutes(point.priorityStart!);
        final end = _parseTimeToMinutes(point.priorityEnd!);

        if (start != null && end != null) {
          if (start <= end) {
            if (currentMinutes >= start && currentMinutes < end) return point;
          } else {
            // Если интервал переходит через полночь (например, с 23:00 до 06:00)
            if (currentMinutes >= start || currentMinutes < end) return point;
          }
        }
      }
    }
    return _points.first; // Если ничего не подошло, возвращаем первый
  }

  int? _parseTimeToMinutes(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return hour * 60 + minute;
  }

  // Действия с пунктами
  void addPoint(String name, String? priorityStart, String? priorityEnd) {
    _points.add(BusPoint(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      priorityStart: priorityStart,
      priorityEnd: priorityEnd,
      departures: [],
    ));
    _saveData();
    notifyListeners();
  }

  void updatePoint(String id, String name, String? priorityStart, String? priorityEnd) {
    final index = _points.indexWhere((p) => p.id == id);
    if (index != -1) {
      _points[index] = _points[index].copyWith(
        name: name,
        priorityStart: priorityStart,
        priorityEnd: priorityEnd,
      );
      _saveData();
      notifyListeners();
    }
  }

  void deletePoint(String id) {
    _points.removeWhere((p) => p.id == id);
    _saveData();
    notifyListeners();
  }

  void reorderPoints(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _points.removeAt(oldIndex);
    _points.insert(newIndex, item);
    _saveData();
    notifyListeners();
  }

  // Действия с отправлениями
  void addDeparture(String pointId, String time, int stopOffset) {
    final index = _points.indexWhere((p) => p.id == pointId);
    if (index != -1) {
      final list = List<Departure>.from(_points[index].departures);
      list.add(Departure(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        time: time,
        stopOffsetMinutes: stopOffset,
      ));
      // Сортировка по времени отправления
      list.sort((a, b) => a.time.compareTo(b.time));
      _points[index] = _points[index].copyWith(departures: list);
      _saveData();
      notifyListeners();
    }
  }

  void deleteDeparture(String pointId, String departureId) {
    final index = _points.indexWhere((p) => p.id == pointId);
    if (index != -1) {
      final list = List<Departure>.from(_points[index].departures);
      list.removeWhere((d) => d.id == departureId);
      _points[index] = _points[index].copyWith(departures: list);
      _saveData();
      notifyListeners();
    }
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _saveData();
    notifyListeners();
  }

  void setFontSizeScale(double scale) {
    _fontSizeScale = scale;
    _saveData();
    notifyListeners();
  }

  // Экспорт/Импорт в формате JSON (строка для вставки/копирования)
  String exportToJson() {
    return jsonEncode({
      'points': _points.map((p) => p.toJson()).toList(),
      'fontSizeScale': _fontSizeScale,
    });
  }

  bool importFromJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded['points'] != null) {
        final List<dynamic> list = decoded['points'];
        _points = list.map((item) => BusPoint.fromJson(item)).toList();
        _fontSizeScale = decoded['fontSizeScale'] ?? 1.0;
        _saveData();
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  // Демонстрационные данные при первом чистом запуске
  List<BusPoint> _getMockData() {
    return [
      BusPoint(
        id: "1",
        name: "На учёбу",
        priorityStart: "06:00",
        priorityEnd: "13:30",
        departures: [
          Departure(id: "d1", time: "08:30", stopOffsetMinutes: 10),
          Departure(id: "d2", time: "10:15", stopOffsetMinutes: 5),
          Departure(id: "d3", time: "12:00", stopOffsetMinutes: 10),
        ],
      ),
      BusPoint(
        id: "2",
        name: "Домой",
        priorityStart: "13:30",
        priorityEnd: "06:00",
        departures: [
          Departure(id: "d4", time: "14:10", stopOffsetMinutes: 8),
          Departure(id: "d5", time: "16:45", stopOffsetMinutes: 10),
          Departure(id: "d6", time: "19:30", stopOffsetMinutes: 5),
        ],
      ),
    ];
  }
}

// --- ЗАПУСК ПРИЛОЖЕНИЯ ---

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const BusMeApp(),
    ),
  );
}

class BusMeApp extends StatelessWidget {
  const BusMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return MaterialApp(
      title: 'BusMe',
      themeMode: appState.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber, // Желтый акцент, как просил пользователь
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          brightness: Brightness.dark,
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      const ScheduleTab(),
      const ManagePointsTab(),
      const SettingsTab(),
    ];

    return Scaffold(
      body: SafeArea(child: screens[_currentIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.schedule),
            label: 'Расписание',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_road),
            label: 'Пункты',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}

// --- ВКЛАДКА 1: РАСПИСАНИЕ (ОСНОВНОЙ ЭКРАН) ---

class ScheduleTab extends StatefulWidget {
  const ScheduleTab({super.key});

  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<ScheduleTab> {
  BusPoint? _selectedPoint;
  late Stream<DateTime> _timeStream;

  @override
  void initState() {
    super.initState();
    // Стрим для ежесекундного обновления таймеров
    _timeStream = Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final activePoint = appState.getActivePoint();

    // Если пункт еще не выбран вручную, берем системно-приоритетный
    final currentPoint = _selectedPoint ?? activePoint;

    if (appState.points.isEmpty) {
      return const Center(child: Text("Нет добавленных пунктов.\nСоздайте их во вкладке «Пункты»", textAlign: TextAlign.center));
    }

    return Column(
      children: [
        // Панель переключения пунктов (Сверху)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: appState.points.map((point) {
              final isSelected = currentPoint?.id == point.id;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(point.name),
                  selected: isSelected,
                  onSelected: (val) {
                    setState(() {
                      _selectedPoint = point;
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),

        // Список рейсов с таймерами
        Expanded(
          child: currentPoint == null || currentPoint.departures.isEmpty
              ? const Center(child: Text("В этом пункте нет отправлений"))
              : StreamBuilder<DateTime>(
                  stream: _timeStream,
                  builder: (context, snapshot) {
                    final now = snapshot.data ?? DateTime.now();
                    final departures = currentPoint.departures;

                    // Находим ближайший рейс
                    Departure? nearestDep;
                    int minDiff = 99999;

                    for (var dep in departures) {
                      final depTime = _getDateTimeFromTimeStr(dep.time, dep.stopOffsetMinutes);
                      final diff = depTime.difference(now).inMinutes;
                      if (diff >= 0 && diff < minDiff) {
                        minDiff = diff;
                        nearestDep = dep;
                      }
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: departures.length,
                      itemBuilder: (context, index) {
                        final dep = departures[index];
                        final isNearest = nearestDep != null && nearestDep.id == dep.id;

                        return _buildDeparturePill(context, dep, isNearest, now, appState.fontSizeScale);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // Построение красивой пилюли рейса (в 2 строки, адаптивно)
  Widget _buildDeparturePill(BuildContext context, Departure dep, bool isNearest, DateTime now, double fontScale) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // Время на остановке
    final stopTimeStr = _calculateStopTime(dep.time, dep.stopOffsetMinutes);
    
    // Расчет оставшегося времени
    final stopDateTime = _getDateTimeFromTimeStr(dep.time, dep.stopOffsetMinutes);
    final diffInMinutes = stopDateTime.difference(now).inMinutes;

    String countdownText = "";
    bool isPast = diffInMinutes < 0;

    if (isPast) {
      countdownText = "завтра в: ${dep.time}";
    } else {
      final hours = diffInMinutes ~/ 60;
      final minutes = diffInMinutes % 60;
      if (hours > 0) {
        countdownText = "осталось: ${hours}ч ${minutes}м";
      } else {
        countdownText = "осталось: $minutes мин";
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      decoration: BoxDecoration(
        color: isNearest 
            ? colorScheme.primaryContainer 
            : (isPast ? colorScheme.surfaceVariant.withOpacity(0.4) : colorScheme.surfaceVariant),
        borderRadius: BorderRadius.circular(isNearest ? 28.0 : 20.0),
        border: isNearest ? Border.all(color: colorScheme.primary, width: 2.0) : null,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isNearest ? 20.0 : 16.0,
        vertical: isNearest ? 18.0 : 12.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Крупное время отправления
              Text(
                dep.time,
                style: TextStyle(
                  fontSize: (isNearest ? 28.0 : 22.0) * fontScale,
                  fontWeight: FontWeight.bold,
                  color: isNearest ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                ),
              ),
              // Таймер обратного отсчета
              Text(
                countdownText,
                style: TextStyle(
                  fontSize: (isNearest ? 16.0 : 14.0) * fontScale,
                  fontWeight: FontWeight.bold,
                  color: isNearest ? colorScheme.primary : (isPast ? Colors.grey : colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4.0),
          // Вторая строка пилюли
          if (dep.stopOffsetMinutes > 0)
            Text(
              "на остановке в: $stopTimeStr (+${dep.stopOffsetMinutes} мин)",
              style: TextStyle(
                fontSize: 14.0 * fontScale,
                color: isNearest 
                    ? colorScheme.onPrimaryContainer.withOpacity(0.8) 
                    : colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
            )
          else
            Text(
              "без заезда на остановку",
              style: TextStyle(
                fontSize: 14.0 * fontScale,
                color: colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
            ),
        ],
      ),
    );
  }

  DateTime _getDateTimeFromTimeStr(String timeStr, int offsetMinutes) {
    final now = DateTime.now();
    final parts = timeStr.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    
    var date = DateTime(now.year, now.month, now.day, hour, minute);
    date = date.add(Duration(minutes: offsetMinutes));
    
    // Если время уже прошло сегодня, переносим на завтра для расчета
    if (date.isBefore(now)) {
      date = date.add(const Duration(days: 1));
    }
    return date;
  }

  String _calculateStopTime(String timeStr, int offsetMinutes) {
    final parts = timeStr.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    
    final tempDate = DateTime(2020, 1, 1, hour, minute).add(Duration(minutes: offsetMinutes));
    final newHour = tempDate.hour.toString().padLeft(2, '0');
    final newMinute = tempDate.minute.toString().padLeft(2, '0');
    
    return "$newHour:$newMinute";
  }
}

// --- ВКЛАДКА 2: УПРАВЛЕНИЕ ПУНКТАМИ И РАСПИСАНИЕМ ---

class ManagePointsTab extends StatelessWidget {
  const ManagePointsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Управление пунктами"),
        centerTitle: true,
      ),
      body: appState.points.isEmpty
          ? const Center(child: Text("Список пунктов пуст"))
          : ReorderableListView.builder(
              itemCount: appState.points.length,
              onReorder: appState.reorderPoints,
              itemBuilder: (context, index) {
                final point = appState.points[index];
                return Card(
                  key: ValueKey(point.id),
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                  child: ListTile(
                    title: Text(point.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: point.priorityStart != null
                        ? Text("Приоритет: с ${point.priorityStart} до ${point.priorityEnd}")
                        : const Text("Без временного приоритета"),
                    trailing: const Icon(Icons.drag_handle),
                    onTap: () {
                      // При нажатии переходим к редактированию рейсов пункта
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditDeparturesScreen(point: point),
                        ),
                      );
                    },
                    onLongPress: () {
                      _showPointDialog(context, point);
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showPointDialog(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  // Окно создания/редактирования пункта
  void _showPointDialog(BuildContext context, BusPoint? point) {
    final nameController = TextEditingController(text: point?.name ?? "");
    final startController = TextEditingController(text: point?.priorityStart ?? "");
    final endController = TextEditingController(text: point?.priorityEnd ?? "");

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(point == null ? "Добавить пункт" : "Редактировать пункт"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Название пункта (например, На учёбу)"),
              ),
              const SizedBox(height: 8.0),
              const Text("Приоритет по времени (необязательно):", style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: startController,
                      decoration: const InputDecoration(labelText: "С (HH:mm)"),
                      maxLength: 5,
                    ),
                  ),
                  const SizedBox(width: 16.0),
                  Expanded(
                    child: TextField(
                      controller: endController,
                      decoration: const InputDecoration(labelText: "До (HH:mm)"),
                      maxLength: 5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          if (point != null)
            TextButton(
              onPressed: () {
                context.read<AppState>().deletePoint(point.id);
                Navigator.pop(context);
              },
              child: const Text("Удалить", style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Отмена"),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                final start = startController.text.trim().isEmpty ? null : startController.text.trim();
                final end = endController.text.trim().isEmpty ? null : endController.text.trim();

                if (point == null) {
                  context.read<AppState>().addPoint(name, start, end);
                } else {
                  context.read<AppState>().updatePoint(point.id, name, start, end);
                }
                Navigator.pop(context);
              }
            },
            child: const Text("Сохранить"),
          ),
        ],
      ),
    );
  }
}

// Экран управления отправлениями внутри выбранного пункта
class EditDeparturesScreen extends StatelessWidget {
  final BusPoint point;
  const EditDeparturesScreen({super.key, required this.point});

  @override
  Widget build(BuildContext context) {
    // Получаем актуальный пункт из состояния
    final appState = context.watch<AppState>();
    final currentPoint = appState.points.firstWhere((p) => p.id == point.id, orElse: () => point);

    return Scaffold(
      appBar: AppBar(
        title: Text(currentPoint.name),
      ),
      body: currentPoint.departures.isEmpty
          ? const Center(child: Text("Нет рейсов. Добавьте первый рейс кнопкой +"))
          : ListView.builder(
              itemCount: currentPoint.departures.length,
              itemBuilder: (context, index) {
                final dep = currentPoint.departures[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: ListTile(
                    title: Text("Отправление с АС: ${dep.time}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: dep.stopOffsetMinutes > 0
                        ? Text("Смещение остановки: +${dep.stopOffsetMinutes} минут")
                        : const Text("Без остановки"),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        context.read<AppState>().deleteDeparture(currentPoint.id, dep.id);
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDepartureDialog(context, currentPoint.id),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDepartureDialog(BuildContext context, String pointId) {
    final timeController = TextEditingController();
    final offsetController = TextEditingController(text: "0");

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Добавить рейс"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: timeController,
              decoration: const InputDecoration(labelText: "Время отправления с АС (HH:mm)"),
              maxLength: 5,
            ),
            const SizedBox(height: 8.0),
            TextField(
              controller: offsetController,
              decoration: const InputDecoration(labelText: "Смещение остановки (в минутах)"),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Отмена"),
          ),
          ElevatedButton(
            onPressed: () {
              final time = timeController.text.trim();
              final offset = int.tryParse(offsetController.text.trim()) ?? 0;

              if (time.isNotEmpty) {
                context.read<AppState>().addDeparture(pointId, time, offset);
                Navigator.pop(context);
              }
            },
            child: const Text("Добавить"),
          ),
        ],
      ),
    );
  }
}

// --- ВКЛАДКА 3: НАСТРОЙКИ ---

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final jsonController = TextEditingController();

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const Text("Внешний вид", style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8.0),
        
        // Переключение тем
        ListTile(
          title: const Text("Тема оформления"),
          trailing: DropdownButton<ThemeMode>(
            value: appState.themeMode,
            onChanged: (ThemeMode? newMode) {
              if (newMode != null) {
                appState.setThemeMode(newMode);
              }
            },
            items: const [
              DropdownMenuItem(value: ThemeMode.system, child: Text("Системная")),
              DropdownMenuItem(value: ThemeMode.light, child: Text("Светлая")),
              DropdownMenuItem(value: ThemeMode.dark, child: Text("Тёмная")),
            ],
          ),
        ),

        // Масштаб шрифта
        ListTile(
          title: const Text("Размер текста интерфейса"),
          subtitle: Slider(
            value: appState.fontSizeScale,
            min: 0.8,
            max: 1.4,
            divisions: 6,
            label: "${(appState.fontSizeScale * 100).round()}%",
            onChanged: (val) {
              appState.setFontSizeScale(val);
            },
          ),
        ),

        const Divider(height: 32.0),
        const Text("Резервное копирование", style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8.0),

        // Кнопки импорта и экспорта
        ElevatedButton.icon(
          onPressed: () {
            final jsonStr = appState.exportToJson();
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("Экспорт настроек"),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Скопируйте этот текст в безопасное место. Это ваше расписание:"),
                    const SizedBox(height: 8.0),
                    SelectableText(
                      jsonStr,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12.0),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("ОК"),
                  ),
                ],
              ),
            );
          },
          icon: const Icon(Icons.download),
          label: const Text("Экспортировать в JSON (Скопировать)"),
        ),
        const SizedBox(height: 8.0),
        ElevatedButton.icon(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("Импорт настроек"),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Вставьте скопированный ранее JSON-код расписания:"),
                    const SizedBox(height: 8.0),
                    TextField(
                      controller: jsonController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '{"points": ...}',
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Отмена"),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final success = appState.importFromJson(jsonController.text.trim());
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(success 
                              ? "Расписание успешно импортировано!" 
                              : "Ошибка импорта. Неверный формат JSON."),
                        ),
                      );
                    },
                    child: const Text("Импортировать"),
                  ),
                ],
              ),
            );
          },
          icon: const Icon(Icons.upload),
          label: const Text("Импортировать из JSON (Вставить)"),
        ),
      ],
    );
  }
}