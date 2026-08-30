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
  final String routeNumber;
  final String workingDays; // "daily", "weekdays", "weekends"

  Departure({
    required this.id,
    required this.time,
    required this.stopOffsetMinutes,
    this.routeNumber = "",
    this.workingDays = "daily",
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time,
        'stopOffsetMinutes': stopOffsetMinutes,
        'routeNumber': routeNumber,
        'workingDays': workingDays,
      };

  factory Departure.fromJson(Map<String, dynamic> json) {
    return Departure(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      time: json['time']?.toString() ?? "08:00",
      stopOffsetMinutes: (json['stopOffsetMinutes'] as num?)?.toInt() ?? 0,
      routeNumber: json['routeNumber']?.toString() ?? "",
      workingDays: json['workingDays']?.toString() ?? "daily",
    );
  }

  Departure copyWith({
    String? time,
    int? stopOffsetMinutes,
    String? routeNumber,
    String? workingDays,
  }) {
    return Departure(
      id: this.id,
      time: time ?? this.time,
      stopOffsetMinutes: stopOffsetMinutes ?? this.stopOffsetMinutes,
      routeNumber: routeNumber ?? this.routeNumber,
      workingDays: workingDays ?? this.workingDays,
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
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name']?.toString() ?? "Без названия",
      priorityStart: json['priorityStart']?.toString(),
      priorityEnd: json['priorityEnd']?.toString(),
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
  bool _hidePastDepartures = false;
  bool _compactMode = false;

  List<BusPoint> get points => _points;
  ThemeMode get themeMode => _themeMode;
  double get fontSizeScale => _fontSizeScale;
  bool get hidePastDepartures => _hidePastDepartures;
  bool get compactMode => _compactMode;

  AppState() { _loadData(); }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final themeStr = prefs.getString('themeMode') ?? 'system';
    _themeMode = ThemeMode.values.firstWhere((e) => e.toString().split('.').last == themeStr, orElse: () => ThemeMode.system);
    _fontSizeScale = prefs.getDouble('fontSizeScale') ?? 1.0;
    _hidePastDepartures = prefs.getBool('hidePastDepartures') ?? false;
    _compactMode = prefs.getBool('compactMode') ?? false;
    
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
    await prefs.setBool('compactMode', _compactMode);
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
      _points[index] = BusPoint(
        id: id,
        name: name,
        priorityStart: priorityStart,
        priorityEnd: priorityEnd,
        departures: _points[index].departures,
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

  void addDeparture(String pointId, String time, int stopOffset, String routeNumber, String workingDays) {
    final index = _points.indexWhere((p) => p.id == pointId);
    if (index != -1) {
      final list = List<Departure>.from(_points[index].departures);
      list.add(Departure(
        id: DateTime.now().millisecondsSinceEpoch.toString(), 
        time: time, 
        stopOffsetMinutes: stopOffset,
        routeNumber: routeNumber,
        workingDays: workingDays,
      ));
      list.sort((a, b) => a.time.compareTo(b.time));
      _points[index] = _points[index].copyWith(departures: list);
      _saveData();
      notifyListeners();
    }
  }

  void updateDeparture(String pointId, String departureId, String time, int stopOffset, String routeNumber, String workingDays) {
    final index = _points.indexWhere((p) => p.id == pointId);
    if (index != -1) {
      final list = List<Departure>.from(_points[index].departures);
      final depIndex = list.indexWhere((d) => d.id == departureId);
      if (depIndex != -1) {
        list[depIndex] = list[depIndex].copyWith(
          time: time,
          stopOffsetMinutes: stopOffset,
          routeNumber: routeNumber,
          workingDays: workingDays,
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
  void setCompactMode(bool value) { _compactMode = value; _saveData(); notifyListeners(); }

  String exportToJson() => jsonEncode({
    'points': _points.map((p) => p.toJson()).toList(), 
    'fontSizeScale': _fontSizeScale,
    'hidePastDepartures': _hidePastDepartures,
    'compactMode': _compactMode,
  });
  
  bool importFromJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map && decoded['points'] != null) {
        _points = (decoded['points'] as List).map((item) => BusPoint.fromJson(item)).toList();
        _fontSizeScale = (decoded['fontSizeScale'] ?? 1.0).toDouble();
        _hidePastDepartures = decoded['hidePastDepartures'] ?? false;
        _compactMode = decoded['compactMode'] ?? false;
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
  String? _selectedRouteFilter; 
  String _searchQuery = "";
  bool _isSearching = false;
  final _searchController = TextEditingController();
  late Stream<DateTime> _timeStream;

  @override
  void initState() {
    super.initState();
    _timeStream = Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime _getDepartureDateTime(String timeStr, int offsetMinutes, DateTime now) {
    final parts = timeStr.split(':');
    final hour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 0) : 0;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
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

    // Безопасная фильтрация списка пунктов по поисковому запросу
    final filteredPointsList = appState.points.where((p) =>
        p.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    // Получаем список уникальных маршрутов для построения фильтров
    final routes = currentPoint.departures
        .map((d) => d.routeNumber.trim())
        .where((r) => r.isNotEmpty)
        .toSet()
        .toList();
    routes.sort();

    if (_selectedRouteFilter != null && !routes.contains(_selectedRouteFilter)) {
      _selectedRouteFilter = null;
    }

    return Column(
      children: [
        // Шапка с кнопкой поиска и списком пунктов
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              if (_isSearching)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: "Поиск пункта...",
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = "";
                              _isSearching = false;
                            });
                          },
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24.0)),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    ),
                  ),
                )
              else ...[
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => setState(() => _isSearching = true),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Row(
                      children: filteredPointsList.map((point) {
                        final isSelected = currentPoint.id == point.id;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: FilterChip(
                            label: Text(point.name),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _selectedPointId = selected ? point.id : null;
                                _selectedRouteFilter = null;
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ]
            ],
          ),
        ),

        // Горизонтальный список чип-фильтров по маршрутам (Вариант Б)
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

                    final weekday = now.weekday;
                    final isWeekend = weekday == DateTime.saturday || weekday == DateTime.sunday;

                    // 1. Фильтруем рейсы по будням и выходным дням недели
                    final dayFilteredDeps = departures.where((dep) {
                      if (dep.workingDays == "weekdays" && isWeekend) return false;
                      if (dep.workingDays == "weekends" && !isWeekend) return false;
                      return true;
                    }).toList();

                    // 2. Фильтруем рейсы по быстрому чип-выбору
                    var filteredDeps = dayFilteredDeps;
                    if (_selectedRouteFilter != null) {
                      filteredDeps = filteredDeps.where((d) => d.routeNumber == _selectedRouteFilter).toList();
                    }

                    // 3. Рассчитываем временные интервалы
                    final List<MapEntry<Departure, bool>> depsWithPastStatus = [];
                    for (var dep in filteredDeps) {
                      final scheduledToday = _getDepartureDateTime(dep.time, dep.stopOffsetMinutes, now);
                      final truncatedNow = DateTime(now.year, now.month, now.day, now.hour, now.minute);
                      final bool isPast = scheduledToday.isBefore(truncatedNow);
                      depsWithPastStatus.add(MapEntry(dep, isPast));
                    }

                    // 4. Скрываем прошедшие, если это задано настройками
                    var displayDeps = depsWithPastStatus;
                    if (appState.hidePastDepartures) {
                      displayDeps = displayDeps.where((entry) => !entry.value).toList();
                    }

                    if (displayDeps.isEmpty) {
                      return const Center(child: Text("Нет подходящих предстоящих рейсов"));
                    }

                    // 5. Определение самого близкого рейса
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

                    // Отрисовка расписания
                    if (appState.compactMode) {
                      return Container(
                        alignment: Alignment.topCenter,
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        height: 140.0 * appState.fontSizeScale,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          itemCount: displayDeps.length,
                          itemBuilder: (context, index) {
                            final dep = displayDeps[index].key;
                            final isPast = displayDeps[index].value;
                            final isNearest = nearestDep != null && nearestDep.id == dep.id;
                            return _buildCompactPill(context, dep, isNearest, isPast, now, appState.fontSizeScale);
                          },
                        ),
                      );
                    } else {
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
                    }
                  },
                ),
        ),
      ],
    );
  }

  // Обычный список по высоте («Горочкой»)
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

    final double opacity = isNearest ? 1.0 : (isPast ? 0.45 : 0.85);
    final double verticalPadding = isNearest ? 18.0 : (isPast ? 6.0 : 12.0);
    final double fontSize = (isNearest ? 26.0 : (isPast ? 17.0 : 21.0)) * fontScale;

    return Opacity(
      opacity: opacity,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(vertical: 6.0),
        decoration: BoxDecoration(
          color: isNearest 
              ? colorScheme.primaryContainer 
              : (isPast ? colorScheme.surfaceVariant.withOpacity(0.3) : colorScheme.surfaceVariant),
          borderRadius: BorderRadius.circular(isNearest ? 28.0 : 16.0),
          border: isNearest ? Border.all(color: colorScheme.primary, width: 2.0) : null,
        ),
        padding: EdgeInsets.symmetric(horizontal: isNearest ? 20.0 : 16.0, vertical: verticalPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
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
                            fontSize: (isNearest ? 13.0 : 11.0) * fontScale,
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
                        fontSize: fontSize, 
                        fontWeight: FontWeight.bold, 
                        color: isNearest ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant
                      ),
                    ),
                  ],
                ),
                Text(
                  countdownText,
                  style: TextStyle(
                    fontSize: (isNearest ? 16.0 : (isPast ? 12.0 : 14.0)) * fontScale, 
                    fontWeight: FontWeight.bold, 
                    color: isNearest 
                        ? colorScheme.primary 
                        : (isPast ? Colors.grey : colorScheme.onSurfaceVariant)
                  ),
                ),
              ],
            ),
            if (!isPast) ...[
              const SizedBox(height: 4.0),
              if (dep.stopOffsetMinutes > 0)
                Text(
                  "на остановке в: $stopTimeStr (+${dep.stopOffsetMinutes} мин)", 
                  style: TextStyle(
                    fontSize: 13.0 * fontScale, 
                    color: isNearest ? colorScheme.onPrimaryContainer.withOpacity(0.8) : colorScheme.onSurfaceVariant.withOpacity(0.7)
                  )
                )
              else
                Text(
                  "без заезда на остановку", 
                  style: TextStyle(
                    fontSize: 13.0 * fontScale, 
                    color: colorScheme.onSurfaceVariant.withOpacity(0.5)
                  )
                ),
            ]
          ],
        ),
      ),
    );
  }

  // Горизонтальный штакетник
  Widget _buildCompactPill(BuildContext context, Departure dep, bool isNearest, bool isPast, DateTime now, double fontScale) {
    final colorScheme = Theme.of(context).colorScheme;
    String countdownText = "";

    if (isPast) {
      countdownText = "завтра";
    } else {
      final scheduledToday = _getDepartureDateTime(dep.time, dep.stopOffsetMinutes, now);
      final truncatedNow = DateTime(now.year, now.month, now.day, now.hour, now.minute);
      final diffInMinutes = scheduledToday.difference(truncatedNow).inMinutes;
      final hours = diffInMinutes ~/ 60;
      final minutes = diffInMinutes % 60;
      countdownText = hours > 0 ? "${hours}ч ${minutes}м" : "$minutes мин";
    }

    return Opacity(
      opacity: isNearest ? 1.0 : (isPast ? 0.5 : 0.85),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 100.0 * fontScale,
        margin: const EdgeInsets.only(right: 8.0),
        decoration: BoxDecoration(
          color: isNearest 
              ? colorScheme.primaryContainer 
              : (isPast ? colorScheme.surfaceVariant.withOpacity(0.3) : colorScheme.surfaceVariant),
          borderRadius: BorderRadius.circular(16.0),
          border: isNearest ? Border.all(color: colorScheme.primary, width: 2.0) : null,
        ),
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (dep.routeNumber.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                margin: const EdgeInsets.only(bottom: 4.0), // Конструктор EdgeInsets.only использован корректно
                decoration: BoxDecoration(
                  color: isNearest ? colorScheme.primary : colorScheme.outline.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(6.0),
                ),
                child: Text(
                  dep.routeNumber,
                  style: TextStyle(
                    fontSize: 10.0 * fontScale,
                    fontWeight: FontWeight.bold,
                    color: isNearest ? colorScheme.onPrimary : colorScheme.onSurface,
                  ),
                ),
              ),
            Text(
              dep.time,
              style: TextStyle(
                fontSize: 18.0 * fontScale,
                fontWeight: FontWeight.bold,
                color: isNearest ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2.0),
            Text(
              countdownText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.0 * fontScale,
                fontWeight: FontWeight.bold,
                color: isNearest 
                    ? colorScheme.primary 
                    : (isPast ? Colors.grey : colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _calculateStopTime(String timeStr, int offsetMinutes) {
    final parts = timeStr.split(':');
    final hour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 0) : 0;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final tempDate = DateTime(2020, 1, 1, hour, minute).add(Duration(minutes: offsetMinutes));
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
                TextField(
                  controller: nameController, 
                  decoration: const InputDecoration(labelText: "Название пункта"),
                  onChanged: (_) => setStateDialog(() {}), 
                ),
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
              onPressed: nameController.text.trim().isEmpty ? null : () {
                final name = nameController.text.trim();
                if (point == null) {
                  context.read<AppState>().addPoint(name, startStr, endStr);
                } else {
                  context.read<AppState>().updatePoint(point.id, name, startStr, endStr);
                }
                Navigator.pop(context);
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
                
                String scheduleDaysText = "Ежедневно";
                if (dep.workingDays == "weekdays") scheduleDaysText = "Будни";
                if (dep.workingDays == "weekends") scheduleDaysText = "Выходные";

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: ListTile(
                    title: Text(
                      "${dep.routeNumber.isNotEmpty ? '[${dep.routeNumber}] ' : ''}Отправление: ${dep.time} ($scheduleDaysText)", 
                      style: const TextStyle(fontWeight: FontWeight.bold)
                    ),
                    subtitle: dep.stopOffsetMinutes > 0 ? Text("Остановка через: +${dep.stopOffsetMinutes} мин") : const Text("Без остановки"),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => context.read<AppState>().deleteDeparture(currentPoint.id, dep.id),
                    ),
                    onTap: () => _showDepartureDialog(context, currentPoint.id, dep),
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

  void _showDepartureDialog(BuildContext context, String pointId, [Departure? existingDep]) {
    String? selectedTime = existingDep?.time;
    String selectedWorkingDays = existingDep?.workingDays ?? "daily";
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
                DropdownButtonFormField<String>(
                  value: selectedWorkingDays,
                  decoration: const InputDecoration(labelText: "Дни работы"),
                  items: const [
                    DropdownMenuItem(value: "daily", child: Text("Ежедневно")),
                    DropdownMenuItem(value: "weekdays", child: Text("По будням (Пн-Пт)")),
                    DropdownMenuItem(value: "weekends", child: Text("По выходным (Сб-Вс)")),
                  ],
                  onChanged: (val) {
                    if (val != null) setStateDialog(() => selectedWorkingDays = val);
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
              onPressed: selectedTime == null ? null : () { 
                final offset = int.tryParse(offsetController.text.trim()) ?? 0;
                final route = routeController.text.trim();
                if (existingDep == null) {
                  context.read<AppState>().addDeparture(pointId, selectedTime!, offset, route, selectedWorkingDays);
                } else {
                  context.read<AppState>().updateDeparture(pointId, existingDep.id, selectedTime!, offset, route, selectedWorkingDays);
                }
                Navigator.pop(context);
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
        SwitchListTile(
          title: const Text("Компактный штакетник"),
          subtitle: const Text("Отображает список рейсов в виде компактных вертикальных пилюль с горизонтальной прокруткой"),
          value: appState.compactMode,
          onChanged: (val) => appState.setCompactMode(val),
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
