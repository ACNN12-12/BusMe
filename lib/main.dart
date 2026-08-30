import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dynamic_color/dynamic_color.dart';

// --- МОДЕЛИ ДАННЫХ ---
class Departure {
  final String id;
  final String time;
  final int stopOffsetMinutes;
  final String routeNumber; // Новое поле для номера/имени маршрута

  Departure({
    required this.id,
    required this.time,
    required this.stopOffsetMinutes,
    this.routeNumber = "",
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time,
        'stopOffsetMinutes': stopOffsetMinutes,
        'routeNumber': routeNumber,
      };

  factory Departure.fromJson(Map<String, dynamic> json) {
    return Departure(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      time: json['time'] ?? "08:00",
      stopOffsetMinutes: json['stopOffsetMinutes'] ?? 0,
      routeNumber: json['routeNumber'] ?? "",
    );
  }

  Departure copyWith({
    String? time,
    int? stopOffsetMinutes,
    String? routeNumber,
  }) {
    return Departure(
      id: this.id,
      time: time ?? this.time,
      stopOffsetMinutes: stopOffsetMinutes ?? this.stopOffsetMinutes,
      routeNumber: routeNumber ?? this.routeNumber,
    );
  }
}

class BusPoint {
  final String id;
  final String name;
  final String? priorityStart;
  final String? priorityEnd;
  final List<Departure> departures;

  BusPoint({required this.id, required this.name, this.priorityStart, this.priorityEnd, required this.departures});

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

  BusPoint copyWith({String? name, String? priorityStart, String? priorityEnd, List<Departure>? departures}) {
    return BusPoint(
      id: this.id,
      name: name ?? this.name,
      priorityStart: priorityStart ?? this.priorityStart,
      priorityEnd: priorityEnd ?? this.priorityEnd,
      departures: departures ?? this.departures,
    );
  }
}

// --- СОСТОЯНИЕ (APP STATE) ---
class AppState extends ChangeNotifier {
  List<BusPoint> _points = [];
  ThemeMode _themeMode = ThemeMode.system;
  double _fontSizeScale = 1.0;
  bool _hidePastDepartures = false; // Состояние автоскрытия прошедших рейсов

  List<BusPoint> get points => _points;
  ThemeMode get themeMode => _themeMode;
  double get fontSizeScale => _fontSizeScale;
  bool get hidePastDepartures => _hidePastDepartures;

  AppState() { _loadData(); }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final themeStr = prefs.getString('themeMode') ?? 'system';
    _themeMode = ThemeMode.values.firstWhere((e) => e.toString().split('.').last == themeStr, orElse: () => ThemeMode.system);
    _fontSizeScale = prefs.getDouble('fontSizeScale') ?? 1.0;
    _hidePastDepartures = prefs.getBool('hidePastDepartures') ?? false;
    
    final pointsJson = prefs.getString('pointsData');
    if (pointsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(pointsJson);
        _points = decoded.map((item) => BusPoint.fromJson(item)).toList();
      } catch (e) { _points = []; }
    }
    notifyListeners();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pointsData', jsonEncode(_points.map((p) => p.toJson()).toList()));
    await prefs.setString('themeMode', _themeMode.toString().split('.').last);
    await prefs.setDouble('fontSizeScale', _fontSizeScale);
    await prefs.setBool('hidePastDepartures', _hidePastDepartures);
  }

  BusPoint? getActivePoint() {
    if (_points.isEmpty) return null;
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    for (var point in _points) {
      if (point.priorityStart != null && point.priorityEnd != null &&
          point.priorityStart!.isNotEmpty && point.priorityEnd!.isNotEmpty) {
        final start = _parseTimeToMinutes(point.priorityStart!);
        final end = _parseTimeToMinutes(point.priorityEnd!);
        if (start != null && end != null) {
          if (start <= end) {
            if (currentMinutes >= start && currentMinutes < end) return point;
          } else {
            if (currentMinutes >= start || currentMinutes < end) return point;
          }
        }
      }
    }

    for (var point in _points) {
      if ((point.priorityStart == null || point.priorityStart!.isEmpty) &&
          (point.priorityEnd == null || point.priorityEnd!.isEmpty)) {
        return point;
      }
    }

    return _points.first;
  }

  int? _parseTimeToMinutes(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length != 2) return null;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  void addPoint(String name, String? priorityStart, String? priorityEnd) {
    _points.add(BusPoint(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name, priorityStart: priorityStart, priorityEnd: priorityEnd, departures: []));
    _saveData();
    notifyListeners();
  }

  void updatePoint(String id, String name, String? priorityStart, String? priorityEnd) {
    final index = _points.indexWhere((p) => p.id == id);
    if (index != -1) {
      _points[index] = _points[index].copyWith(name: name, priorityStart: priorityStart, priorityEnd: priorityEnd);
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

  void addDeparture(String pointId, String time, int stopOffset, String routeNumber) {
    final index = _points.indexWhere((p) => p.id == pointId);
    if (index != -1) {
      final list = List<Departure>.from(_points[index].departures);
      list.add(Departure(
        id: DateTime.now().millisecondsSinceEpoch.toString(), 
        time: time, 
        stopOffsetMinutes: stopOffset,
        routeNumber: routeNumber,
      ));
      list.sort((a, b) => a.time.compareTo(b.time));
      _points[index] = _points[index].copyWith(departures: list);
      _saveData();
      notifyListeners();
    }
  }

  void updateDeparture(String pointId, String departureId, String time, int stopOffset, String routeNumber) {
    final index = _points.indexWhere((p) => p.id == pointId);
    if (index != -1) {
      final list = List<Departure>.from(_points[index].departures);
      final depIndex = list.indexWhere((d) => d.id == departureId);
      if (depIndex != -1) {
        list[depIndex] = list[depIndex].copyWith(
          time: time,
          stopOffsetMinutes: stopOffset,
          routeNumber: routeNumber,
        );
        list.sort((a, b) => a.time.compareTo(b.time));
        _points[index] = _points[index].copyWith(departures: list);
        _saveData();
        notifyListeners();
      }
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

  void setThemeMode(ThemeMode mode) { _themeMode = mode; _saveData(); notifyListeners(); }
  void setFontSizeScale(double scale) { _fontSizeScale = scale; _saveData(); notifyListeners(); }
  void setHidePastDepartures(bool value) { _hidePastDepartures = value; _saveData(); notifyListeners(); }

  String exportToJson() => jsonEncode({
    'points': _points.map((p) => p.toJson()).toList(), 
    'fontSizeScale': _fontSizeScale,
    'hidePastDepartures': _hidePastDepartures,
  });
  
  bool importFromJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded['points'] != null) {
        _points = (decoded['points'] as List).map((item) => BusPoint.fromJson(item)).toList();
        _fontSizeScale = (decoded['fontSizeScale'] ?? 1.0).toDouble();
        _hidePastDepartures = decoded['hidePastDepartures'] ?? false;
        _saveData();
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }
}

// --- УТИЛИТА: ВЫБОР ВРЕМЕНИ (КРУЖОЧЕК MD3) ---
Future<String?> pickTime(BuildContext context, String? initialTimeStr) async {
  TimeOfDay initialTime = TimeOfDay.now();
  if (initialTimeStr != null && initialTimeStr.contains(':')) {
    final parts = initialTimeStr.split(':');
    if (parts.length == 2) {
      initialTime = TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
    }
  }
  
  final TimeOfDay? picked = await showTimePicker(
    context: context,
    initialTime: initialTime,
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      );
    },
  );

  if (picked != null) {
    final h = picked.hour.toString().padLeft(2, '0');
    final m = picked.minute.toString().padLeft(2, '0');
    return "$h:$m";
  }
  return null;
}

// --- ЗАПУСК ---
void main() {
  runApp(
    ChangeNotifierProvider(create: (_) => AppState(), child: const BusMeApp()),
  );
}

class BusMeApp extends StatelessWidget {
  const BusMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    const Color defaultLavender = Color(0xFF8C71DF);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ColorScheme lightScheme;
        ColorScheme darkScheme;

        if (lightDynamic != null && darkDynamic != null) {
          lightScheme = lightDynamic.harmonized();
          darkScheme = darkDynamic.harmonized();
        } else {
          lightScheme = ColorScheme.fromSeed(seedColor: defaultLavender, brightness: Brightness.light);
          darkScheme = ColorScheme.fromSeed(seedColor: defaultLavender, brightness: Brightness.dark);
        }

        return MaterialApp(
          title: 'BusMe',
          themeMode: appState.themeMode,
          theme: ThemeData(useMaterial3: true, colorScheme: lightScheme),
          darkTheme: ThemeData(useMaterial3: true, colorScheme: darkScheme),
          home: const MainNavigationScreen(),
        );
      },
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
    final screens = [const ScheduleTab(), const ManagePointsTab(), const SettingsTab()];
    return Scaffold(
      body: SafeArea(child: screens[_currentIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.schedule), label: 'Расписание'),
          NavigationDestination(icon: Icon(Icons.edit_road), label: 'Пункты'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Настройки'),
        ],
      ),
    );
  }
}

// --- ВКЛАДКА 1: РАСПИСАНИЕ ---
class ScheduleTab extends StatefulWidget {
  const ScheduleTab({super.key});
  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<ScheduleTab> {
  String? _selectedPointId;
  String? _selectedRouteFilter; // Хранит выбранный фильтр маршрута (null - Все)
  late Stream<DateTime> _timeStream;

  @override
  void initState() {
    super.initState();
    _timeStream = Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
  }

  DateTime _getDepartureDateTime(String timeStr, int offsetMinutes, DateTime now) {
    final parts = timeStr.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return DateTime(now.year, now.month, now.day, hour, minute).add(Duration(minutes: offsetMinutes));
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    
    if (appState.points.isEmpty) {
      return const Center(child: Text("Нет пунктов.\nДобавьте их во вкладке «Пункты»", textAlign: TextAlign.center));
    }

    final activePoint = appState.getActivePoint();
    
    final currentPoint = _selectedPointId != null
        ? appState.points.firstWhere((p) => p.id == _selectedPointId, orElse: () => activePoint ?? appState.points.first)
        : (activePoint ?? appState.points.first);

    // Получаем уникальные маршруты для построения быстрых фильтров на экране
    final routes = currentPoint.departures
        .map((d) => d.routeNumber.trim())
        .where((r) => r.isNotEmpty)
        .toSet()
        .toList();
    routes.sort();

    // Защита от зависания несуществующего фильтра при смене пунктов
    if (_selectedRouteFilter != null && !routes.contains(_selectedRouteFilter)) {
      _selectedRouteFilter = null;
    }

    return Column(
      children: [
        // Горизонтальный список пунктов
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: appState.points.map((point) {
              final isSelected = currentPoint.id == point.id;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(point.name),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedPointId = selected ? point.id : null;
                      _selectedRouteFilter = null; // Сбрасываем фильтр маршрута при смене пункта
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),

        // Горизонтальный список маршрутов (Вариант Б) - показывается только если есть маршруты
        if (routes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: ChoiceChip(
                      label: const Text("Все маршруты"),
                      selected: _selectedRouteFilter == null,
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedRouteFilter = null);
                      },
                    ),
                  ),
                  ...routes.map((route) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: ChoiceChip(
                        label: Text("Маршрут $route"),
                        selected: _selectedRouteFilter == route,
                        onSelected: (selected) {
                          setState(() {
                            _selectedRouteFilter = selected ? route : null;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),

        // Список рейсов
        Expanded(
          child: currentPoint.departures.isEmpty
              ? const Center(child: Text("В этом пункте нет отправлений"))
              : StreamBuilder<DateTime>(
                  stream: _timeStream,
                  builder: (context, snapshot) {
                    final now = snapshot.data ?? DateTime.now();
                    final departures = currentPoint.departures;

                    // 1. Фильтруем по выбранному маршруту
                    var filteredDeps = departures;
                    if (_selectedRouteFilter != null) {
                      filteredDeps = filteredDeps.where((d) => d.routeNumber == _selectedRouteFilter).toList();
                    }

                    // 2. Рассчитываем признак прошедшего времени для каждого рейса
                    final List<MapEntry<Departure, bool>> depsWithPastStatus = [];
                    for (var dep in filteredDeps) {
                      final scheduledToday = _getDepartureDateTime(dep.time, dep.stopOffsetMinutes, now);
                      final truncatedNow = DateTime(now.year, now.month, now.day, now.hour, now.minute);
                      final bool isPast = scheduledToday.isBefore(truncatedNow);
                      depsWithPastStatus.add(MapEntry(dep, isPast));
                    }

                    // 3. Скрываем прошедшие рейсы, если опция включена (Вариант В)
                    var displayDeps = depsWithPastStatus;
                    if (appState.hidePastDepartures) {
                      displayDeps = displayDeps.where((entry) => !entry.value).toList();
                    }

                    if (displayDeps.isEmpty) {
                      return const Center(child: Text("Нет подходящих предстоящих рейсов"));
                    }

                    // 4. Поиск ближайшего рейса среди отображаемых
                    Departure? nearestDep;
                    int minDiff = 999999;

                    for (var entry in displayDeps) {
                      final dep = entry.key;
                      final isPast = entry.value;
                      if (isPast) continue;

                      final scheduledToday = _getDepartureDateTime(dep.time, dep.stopOffsetMinutes, now);
                      final truncatedNow = DateTime(now.year, now.month, now.day, now.hour, now.minute);
                      final diff = scheduledToday.difference(truncatedNow).inMinutes;

                      if (diff >= 0 && diff < minDiff) {
                        minDiff = diff;
                        nearestDep = dep;
                      }
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: displayDeps.length,
                      itemBuilder: (context, index) {
                        final dep = displayDeps[index].key;
                        final isPast = displayDeps[index].value;
                        final isNearest = nearestDep != null && nearestDep.id == dep.id;
                        return _buildDeparturePill(context, dep, isNearest, isPast, now, appState.fontSizeScale);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDeparturePill(BuildContext context, Departure dep, bool isNearest, bool isPast, DateTime now, double fontScale) {
    final colorScheme = Theme.of(context).colorScheme;
    final stopTimeStr = _calculateStopTime(dep.time, dep.stopOffsetMinutes);
    String countdownText = "";

    if (isPast) {
      countdownText = "завтра в: ${dep.time}";
    } else {
      final scheduledToday = _getDepartureDateTime(dep.time, dep.stopOffsetMinutes, now);
      final truncatedNow = DateTime(now.year, now.month, now.day, now.hour, now.minute);
      final diffInMinutes = scheduledToday.difference(truncatedNow).inMinutes;
      final hours = diffInMinutes ~/ 60;
      final minutes = diffInMinutes % 60;
      countdownText = hours > 0 ? "осталось: ${hours}ч ${minutes}м" : "осталось: $minutes мин";
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
      padding: EdgeInsets.symmetric(horizontal: isNearest ? 20.0 : 16.0, vertical: isNearest ? 18.0 : 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  // Визуальный бейдж с номером маршрута (буквы и цифры)
                  if (dep.routeNumber.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      decoration: BoxDecoration(
                        color: isNearest ? colorScheme.primary : colorScheme.outline.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Text(
                        dep.routeNumber,
                        style: TextStyle(
                          fontSize: 13.0 * fontScale,
                          fontWeight: FontWeight.bold,
                          color: isNearest ? colorScheme.onPrimary : colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8.0),
                  ],
                  Text(
                    dep.time,
                    style: TextStyle(
                      fontSize: (isNearest ? 28.0 : 22.0) * fontScale, 
                      fontWeight: FontWeight.bold, 
                      color: isNearest ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant
                    ),
                  ),
                ],
              ),
              Text(
                countdownText,
                style: TextStyle(
                  fontSize: (isNearest ? 16.0 : 14.0) * fontScale, 
                  fontWeight: FontWeight.bold, 
                  color: isNearest 
                      ? colorScheme.primary 
                      : (isPast ? Colors.grey : colorScheme.onSurfaceVariant)
                ),
              ),
            ],
          ),
          const SizedBox(height: 4.0),
          if (dep.stopOffsetMinutes > 0)
            Text(
              "на остановке в: $stopTimeStr (+${dep.stopOffsetMinutes} мин)", 
              style: TextStyle(
                fontSize: 14.0 * fontScale, 
                color: isNearest ? colorScheme.onPrimaryContainer.withOpacity(0.8) : colorScheme.onSurfaceVariant.withOpacity(0.7)
              )
            )
          else
            Text(
              "без заезда на остановку", 
              style: TextStyle(
                fontSize: 14.0 * fontScale, 
                color: colorScheme.onSurfaceVariant.withOpacity(0.5)
              )
            ),
        ],
      ),
    );
  }

  String _calculateStopTime(String timeStr, int offsetMinutes) {
    final parts = timeStr.split(':');
    final tempDate = DateTime(2020, 1, 1, int.parse(parts[0]), int.parse(parts[1])).add(Duration(minutes: offsetMinutes));
    return "${tempDate.hour.toString().padLeft(2, '0')}:${tempDate.minute.toString().padLeft(2, '0')}";
  }
}

// --- ВКЛАДКА 2: ПУНКТЫ И РЕЙСЫ ---
class ManagePointsTab extends StatelessWidget {
  const ManagePointsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text("Управление пунктами"), centerTitle: true),
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
                    subtitle: point.priorityStart != null && point.priorityStart!.isNotEmpty
                        ? Text("Приоритет: с ${point.priorityStart} до ${point.priorityEnd}")
                        : const Text("Без временного приоритета"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.edit), onPressed: () => _showPointDialog(context, point)),
                        const Icon(Icons.drag_handle, color: Colors.grey),
                      ],
                    ),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditDeparturesScreen(point: point))),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(onPressed: () => _showPointDialog(context, null), child: const Icon(Icons.add)),
    );
  }

  void _showPointDialog(BuildContext context, BusPoint? point) {
    final nameController = TextEditingController(text: point?.name ?? "");
    String? startStr = point?.priorityStart;
    String? endStr = point?.priorityEnd;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(point == null ? "Добавить пункт" : "Редактировать пункт"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: "Название пункта")),
                const SizedBox(height: 16.0),
                const Text("Приоритет по времени (необязательно):", style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(
                      onPressed: () async {
                        final res = await pickTime(context, startStr);
                        if (res != null) setStateDialog(() => startStr = res);
                      },
                      child: Text(startStr != null && startStr!.isNotEmpty ? "С $startStr" : "С (выбрать)"),
                    )),
                    const SizedBox(width: 8.0),
                    Expanded(child: OutlinedButton(
                      onPressed: () async {
                        final res = await pickTime(context, endStr);
                        if (res != null) setStateDialog(() => endStr = res);
                      },
                      child: Text(endStr != null && endStr!.isNotEmpty ? "До $endStr" : "До (выбрать)"),
                    )),
                  ],
                ),
                if ((startStr != null && startStr!.isNotEmpty) || (endStr != null && endStr!.isNotEmpty))
                  TextButton(
                    onPressed: () => setStateDialog(() { startStr = null; endStr = null; }),
                    child: const Text("Очистить время", style: TextStyle(color: Colors.red)),
                  )
              ],
            ),
          ),
          actions: [
            if (point != null)
              TextButton(
                onPressed: () { context.read<AppState>().deletePoint(point.id); Navigator.pop(context); },
                child: const Text("Удалить", style: TextStyle(color: Colors.red)),
              ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Отмена")),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  if (point == null) {
                    context.read<AppState>().addPoint(name, startStr, endStr);
                  } else {
                    context.read<AppState>().updatePoint(point.id, name, startStr, endStr);
                  }
                  Navigator.pop(context);
                }
              },
              child: const Text("Сохранить"),
            ),
          ],
        ),
      ),
    );
  }
}

class EditDeparturesScreen extends StatelessWidget {
  final BusPoint point;
  const EditDeparturesScreen({super.key, required this.point});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final currentPoint = appState.points.firstWhere((p) => p.id == point.id, orElse: () => point);

    return Scaffold(
      appBar: AppBar(title: Text(currentPoint.name)),
      body: currentPoint.departures.isEmpty
          ? const Center(child: Text("Нет рейсов. Добавьте первый рейс кнопкой +"))
          : ListView.builder(
              itemCount: currentPoint.departures.length,
              itemBuilder: (context, index) {
                final dep = currentPoint.departures[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: ListTile(
                    title: Text(
                      "${dep.routeNumber.isNotEmpty ? '[${dep.routeNumber}] ' : ''}Отправление с АС: ${dep.time}", 
                      style: const TextStyle(fontWeight: FontWeight.bold)
                    ),
                    subtitle: dep.stopOffsetMinutes > 0 ? Text("Остановка через: +${dep.stopOffsetMinutes} мин") : const Text("Без остановки"),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => context.read<AppState>().deleteDeparture(currentPoint.id, dep.id),
                    ),
                    onTap: () => _showDepartureDialog(context, currentPoint.id, dep), // Вызов диалога для редактирования
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDepartureDialog(context, currentPoint.id, null), 
        child: const Icon(Icons.add)
      ),
    );
  }

  // Объединенный диалог для добавления и редактирования рейсов
  void _showDepartureDialog(BuildContext context, String pointId, [Departure? existingDep]) {
    String? selectedTime = existingDep?.time;
    final offsetController = TextEditingController(text: existingDep?.stopOffsetMinutes.toString() ?? "0");
    final routeController = TextEditingController(text: existingDep?.routeNumber ?? "");

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(existingDep == null ? "Добавить рейс" : "Редактировать рейс"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.access_time),
                  label: Text(selectedTime != null ? "Отправление: $selectedTime" : "Выбрать время отправления"),
                  onPressed: () async {
                    final res = await pickTime(context, selectedTime);
                    if (res != null) setStateDialog(() => selectedTime = res);
                  },
                ),
                const SizedBox(height: 16.0),
                TextField(
                  controller: routeController,
                  decoration: const InputDecoration(
                    labelText: "Номер/Имя маршрута (например: 34, А-Д)",
                    hintText: "Необязательно",
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 16.0),
                TextField(
                  controller: offsetController,
                  decoration: const InputDecoration(labelText: "Смещение остановки (в минутах)"),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Отмена")),
            ElevatedButton(
              onPressed: () {
                final offset = int.tryParse(offsetController.text.trim()) ?? 0;
                final route = routeController.text.trim();
                if (selectedTime != null) {
                  if (existingDep == null) {
                    context.read<AppState>().addDeparture(pointId, selectedTime!, offset, route);
                  } else {
                    context.read<AppState>().updateDeparture(pointId, existingDep.id, selectedTime!, offset, route);
                  }
                  Navigator.pop(context);
                }
              },
              child: Text(existingDep == null ? "Добавить" : "Сохранить"),
            ),
          ],
        ),
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
        ListTile(
          title: const Text("Тема оформления"),
          trailing: DropdownButton<ThemeMode>(
            value: appState.themeMode,
            onChanged: (newMode) { if (newMode != null) appState.setThemeMode(newMode); },
            items: const [
              DropdownMenuItem(value: ThemeMode.system, child: Text("Системная")),
              DropdownMenuItem(value: ThemeMode.light, child: Text("Светлая")),
              DropdownMenuItem(value: ThemeMode.dark, child: Text("Тёмная")),
            ],
          ),
        ),
        ListTile(
          title: const Text("Размер текста интерфейса"),
          subtitle: Slider(
            value: appState.fontSizeScale, min: 0.8, max: 1.4, divisions: 6,
            label: "${(appState.fontSizeScale * 100).round()}%",
            onChanged: (val) => appState.setFontSizeScale(val),
          ),
        ),
        const Divider(height: 32.0),
        const Text("Поведение расписания", style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold)),
        SwitchListTile(
          title: const Text("Скрывать ушедшие рейсы"),
          subtitle: const Text("Оставляет в списке только предстоящие рейсы, автоматически убирая прошедшие до завтрашнего дня"),
          value: appState.hidePastDepartures,
          onChanged: (val) => appState.setHidePastDepartures(val),
        ),
        const Divider(height: 32.0),
        const Text("Резервное копирование", style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold)),
        ElevatedButton.icon(
          onPressed: () {
            showDialog(context: context, builder: (context) => AlertDialog(
              title: const Text("Экспорт настроек"),
              content: SelectableText(appState.exportToJson(), style: const TextStyle(fontFamily: 'monospace', fontSize: 12.0)),
            ));
          },
          icon: const Icon(Icons.download), label: const Text("Экспорт в JSON"),
        ),
        ElevatedButton.icon(
          onPressed: () {
            showDialog(context: context, builder: (context) => AlertDialog(
              title: const Text("Импорт настроек"),
              content: TextField(controller: jsonController, maxLines: 5),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    final success = appState.importFromJson(jsonController.text.trim());
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success ? "Данные успешно импортированы" : "Ошибка импорта. Проверьте формат JSON"),
                      ),
                    );
                  },
                  child: const Text("Импортировать"),
                ),
              ],
            ));
          },
          icon: const Icon(Icons.upload), label: const Text("Импорт из JSON"),
        ),
      ],
    );
  }
}
