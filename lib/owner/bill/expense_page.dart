import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config.dart';

enum YearMetric { income, water, electric }

class ExpensePage extends StatefulWidget {
  const ExpensePage({super.key});

  @override
  State<ExpensePage> createState() => _ExpensePageState();
}

class _ExpensePageState extends State<ExpensePage> {
  static const Color cBg = Color(0xFFF4EFE6);       
  static const Color cAccent = Color(0xFFDCD2C1);   
  static const Color cTextMain = Color(0xFF2A1F17); 
  static const Color cDark = Color(0xFF523D2D);     

  // 📏 ปรับ Typography ให้เล็กลง (Compact)
  static const double fTitle = 16.0;
  static const double fHeader = 14.0;
  static const double fBody = 13.0;
  static const double fDetail = 12.0;
  static const double fCaption = 10.0;

  int get thaiYear => selectedYear + 543;
  bool isMonthly = true;
  int selectedMonth = DateTime.now().month;
  int selectedYear = DateTime.now().year;
  int dormId = 0;
  bool loading = true;
  String? loadError;
  YearMetric yearMetric = YearMetric.income;

  final money = NumberFormat("#,##0", "en_US");
  final monthsText = const [
    "มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน", "พฤษภาคม", "มิถุนายน",
    "กรกฎาคม", "สิงหาคม", "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม"
  ];
  final monthsShort = const [
    "", "ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.",
    "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."
  ];

  double expectedIncome = 0, receivedIncome = 0;
  Map<String, double> breakdown = {"rent": 0, "water": 0, "electric": 0};
  List<Map<String, dynamic>> yearMonths = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    dormId = prefs.getInt("dorm_id") ?? 0;
    if (dormId <= 0) {
      setState(() { loading = false; loadError = "ไม่พบรหัสหอพัก"; });
      return;
    }
    await fetchIncomeSummary();
  }

  Future<void> fetchIncomeSummary() async {
    if (!mounted) return;
    setState(() { loading = true; loadError = null; });
    try {
      final scope = isMonthly ? "month" : "year";
      final uri = Uri.parse(AppConfig.url("finance_api.php")).replace(queryParameters: {
        "action": "summary_income",
        "dorm_id": dormId.toString(),
        "scope": scope,
        "year": selectedYear.toString(),
        if (isMonthly) "month": selectedMonth.toString(),
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      final data = _safeJsonMap(res.body);

      if (res.statusCode == 200) {
        setState(() {
          expectedIncome = _toDouble(data["expected_income"]) ?? 0;
          receivedIncome = _toDouble(data["received_income"]) ?? 0;
          final b = data["breakdown"] is Map ? data["breakdown"] : data;
          breakdown = {
            "rent": _pickNumFromAny(b, ["rent", "rent_income"]),
            "water": _pickNumFromAny(b, ["water", "water_total", "water_income"]),
            "electric": _pickNumFromAny(b, ["electric", "electric_total", "electric_income"]),
          };
          yearMonths = List<Map<String, dynamic>>.from(data["months"] ?? []);
        });
      } else {
        setState(() => loadError = data["message"] ?? "เกิดข้อผิดพลาดจากเซิร์ฟเวอร์");
      }
    } catch (e) { 
      setState(() => loadError = "เชื่อมต่อไม่ได้"); 
    } finally { 
      if (mounted) setState(() => loading = false); 
    }
  }

  Map<String, dynamic> _safeJsonMap(String raw) {
    try {
      final body = raw.trimLeft();
      final i = body.indexOf(RegExp(r'[\{\[]'));
      return jsonDecode(i >= 0 ? body.substring(i) : body);
    } catch (_) { return {"ok": false}; }
  }

  double _pickNumFromAny(dynamic obj, List<String> keys) {
    if (obj is Map) {
      for (final k in keys) {
        final d = _toDouble(obj[k]);
        if (d != null && d != 0) return d;
      }
    }
    return 0.0;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(",", "").trim());
  }

  int _toInt(dynamic v) => (v is int) ? v : (int.tryParse(v?.toString() ?? "0") ?? 0);
  String _compact(double v) => v.abs() >= 1000 ? "${(v / 1000).toStringAsFixed(0)}K" : v.toStringAsFixed(0);
  Map<String, dynamic> _monthRowObj(int m) => yearMonths.firstWhere((e) => _toInt(e["month"]) == m, orElse: () => {});
  double _yearTotal(int m) => _toDouble(_monthRowObj(m)["received_income"]) ?? 0;
  double _yearWater(int m) => _pickNumFromAny(_monthRowObj(m), ["water", "water_total"]);
  double _yearElectric(int m) => _pickNumFromAny(_monthRowObj(m), ["electric", "electric_total"]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 50, elevation: 0.5, backgroundColor: Colors.white, centerTitle: true,
        iconTheme: const IconThemeData(color: cTextMain, size: 22),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("สรุปการเงิน", style: TextStyle(color: cTextMain, fontWeight: FontWeight.w900, fontSize: 16)),
      ),
      body: RefreshIndicator(
        onRefresh: fetchIncomeSummary,
        color: cDark,
        child: loading 
          ? const Center(child: CircularProgressIndicator(color: cDark))
          : loadError != null ? _buildErrorState() : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _buildTopSelector(),
        const SizedBox(height: 16),
        _buildHeroIncomeCard(),
        const SizedBox(height: 16),
        if (isMonthly) ...[
          const Text("สัดส่วนรายรับ", style: TextStyle(fontSize: fHeader, fontWeight: FontWeight.w900, color: cTextMain)),
          const SizedBox(height: 8),
          _buildBreakdownCard(),
        ],
        if (!isMonthly) ...[
          Text("สถิติรายปี $thaiYear", style: const TextStyle(fontSize: fHeader, fontWeight: FontWeight.w900, color: cTextMain)),
          const SizedBox(height: 8),
          _buildYearMetricToggle(),
          const SizedBox(height: 12),
          _buildYearMetricChart(),
          const SizedBox(height: 16),
          const Text("รายละเอียดรายเดือน", style: TextStyle(fontSize: fHeader, fontWeight: FontWeight.w900, color: cTextMain)),
          const SizedBox(height: 8),
          for (int m = 1; m <= 12; m++) ...[
            _buildYearMonthRow(m),
            const SizedBox(height: 4),
          ],
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildTopSelector() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: cAccent.withOpacity(0.4), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [ _toggleItem(0, "รายเดือน"), _toggleItem(1, "รายปี")]),
      ),
      const SizedBox(height: 8),
      Row(children: [
        if (isMonthly) Expanded(child: _dropdownWrapper(child: DropdownButton<int>(value: selectedMonth, isExpanded: true, style: const TextStyle(fontSize: fDetail, color: cTextMain, fontWeight: FontWeight.w700), items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(monthsText[i]))), onChanged: (v) { setState(() => selectedMonth = v ?? selectedMonth); fetchIncomeSummary(); }))),
        if (isMonthly) const SizedBox(width: 8),
        Expanded(child: _dropdownWrapper(child: DropdownButton<int>(value: selectedYear, isExpanded: true, style: const TextStyle(fontSize: fDetail, color: cTextMain, fontWeight: FontWeight.w700), items: [2024, 2025, 2026].map((y) => DropdownMenuItem(value: y, child: Text("${y + 543}"))).toList(), onChanged: (v) { setState(() => selectedYear = v ?? selectedYear); fetchIncomeSummary(); }))),
      ]),
    ]);
  }

  Widget _dropdownWrapper({required Widget child}) => Container(padding: const EdgeInsets.symmetric(horizontal: 10), height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: cAccent.withOpacity(0.6), width: 1.2)), child: DropdownButtonHideUnderline(child: child));

  Widget _toggleItem(int index, String label) {
    final active = (isMonthly && index == 0) || (!isMonthly && index == 1);
    return Expanded(child: GestureDetector(onTap: () { setState(() => isMonthly = index == 0); fetchIncomeSummary(); }, child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: active ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(8)), child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: active ? cTextMain : cDark.withOpacity(0.5), fontWeight: FontWeight.w900, fontSize: fDetail)))));
  }

  Widget _buildHeroIncomeCard() {
    final progress = (expectedIncome > 0 ? (receivedIncome / expectedIncome) : 0.0).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(20), 
      decoration: BoxDecoration(color: cTextMain, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isMonthly ? "รายรับรวมเดือนนี้" : "รายรับรวมปี $thaiYear", style: const TextStyle(color: Colors.white70, fontSize: fDetail, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text("${money.format(receivedIncome)} ฿", style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("เป้าหมายรายรับ ${money.format(expectedIncome)}", style: const TextStyle(color: Colors.white60, fontSize: fCaption)), Text("${(progress * 100).toStringAsFixed(1)}%", style: const TextStyle(color: Colors.white, fontSize: fCaption, fontWeight: FontWeight.w900))]),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: progress, backgroundColor: Colors.white12, color: cAccent, minHeight: 6)),
      ]),
    );
  }

  Widget _buildYearMetricToggle() {
    return Container(
      padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: cAccent.withOpacity(0.4), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [ _metricItem(YearMetric.income, "รายรับ"), _metricItem(YearMetric.water, "ค่าน้ำ"), _metricItem(YearMetric.electric, "ค่าไฟ")]),
    );
  }

  Widget _metricItem(YearMetric m, String label) {
    final active = yearMetric == m;
    return Expanded(child: GestureDetector(onTap: () => setState(() => yearMetric = m), child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: active ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(8)), child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: active ? cTextMain : cDark.withOpacity(0.5), fontWeight: FontWeight.w900, fontSize: fDetail)))));
  }

  Widget _buildYearMetricChart() {
    Color barColor = yearMetric == YearMetric.income ? const Color(0xFF1565C0) : (yearMetric == YearMetric.water ? const Color(0xFF0288D1) : const Color(0xFFE65100));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: AspectRatio(
        aspectRatio: 1.8,
        child: BarChart(BarChartData(
          maxY: _maxSingleYearY(yearMetric == YearMetric.income ? _yearTotal : (yearMetric == YearMetric.water ? _yearWater : _yearElectric)),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: _titlesData(),
          barGroups: List.generate(12, (i) {
            double value = yearMetric == YearMetric.income ? _yearTotal(i + 1) : (yearMetric == YearMetric.water ? _yearWater(i + 1) : _yearElectric(i + 1));
            return BarChartGroupData(x: i + 1, barRods: [BarChartRodData(toY: value, color: barColor, width: 8, borderRadius: BorderRadius.circular(2))]);
          }),
        )),
      ),
    );
  }

  FlTitlesData _titlesData() => FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: 4), child: Text(monthsShort[v.toInt() % 13], style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold))))),
    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, m) => Text(_compact(v), style: const TextStyle(fontSize: 9, color: Colors.grey)))),
  );

  Widget _buildYearMonthRow(int m) {
    final val = yearMetric == YearMetric.income ? _yearTotal(m) : (yearMetric == YearMetric.water ? _yearWater(m) : _yearElectric(m));
    final hasData = val > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Text(monthsText[m - 1], style: TextStyle(fontSize: fBody, color: hasData ? cTextMain : Colors.grey.shade400, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(hasData ? "${money.format(val)} ฿" : "ไม่มีข้อมูล", 
            style: TextStyle(fontSize: fBody, fontWeight: FontWeight.w900, color: hasData ? cTextMain : Colors.grey.shade300)),
        ],
      ),
    );
  }

  Widget _buildBreakdownCard() {
    double total = (breakdown["rent"] ?? 0) + (breakdown["water"] ?? 0) + (breakdown["electric"] ?? 0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
          ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(height: 10, width: double.infinity,
              child: Row(children: [
                if (total > 0 && (breakdown["rent"] ?? 0) > 0) Expanded(flex: ((breakdown["rent"]! / total) * 100).toInt(), child: Container(color: const Color(0xFF1565C0))),
                if (total > 0 && (breakdown["water"] ?? 0) > 0) Expanded(flex: ((breakdown["water"]! / total) * 100).toInt(), child: Container(color: const Color(0xFF0288D1))),
                if (total > 0 && (breakdown["electric"] ?? 0) > 0) Expanded(flex: ((breakdown["electric"]! / total) * 100).toInt(), child: Container(color: const Color(0xFFEF6C00))),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          _legendRow("ค่าเช่าห้อง", breakdown["rent"] ?? 0, const Color(0xFF1565C0)),
          const Divider(height: 12, thickness: 0.5),
          _legendRow("ค่าน้ำ", breakdown["water"] ?? 0, const Color(0xFF0288D1)),
          const Divider(height: 12, thickness: 0.5),
          _legendRow("ค่าไฟ", breakdown["electric"] ?? 0, const Color(0xFFEF6C00)),
        ],
      ),
    );
  }

  Widget _legendRow(String label, double val, Color color) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(children: [ Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 8), Text(label, style: const TextStyle(fontSize: fBody, fontWeight: FontWeight.w600, color: Colors.black87))]),
      Text("${money.format(val)} ฿", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: fBody, color: cTextMain)),
    ],
  );

  Widget _buildErrorState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.error_outline, size: 40, color: Color(0xFFD32F2F)),
    const SizedBox(height: 12),
    Text(loadError ?? "เกิดข้อผิดพลาด", style: const TextStyle(fontSize: fBody, fontWeight: FontWeight.w700, color: cTextMain)),
    TextButton(onPressed: fetchIncomeSummary, child: const Text("ลองใหม่", style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1565C0)))),
  ]));

  double _maxSingleYearY(double Function(int month) getter) {
    double maxY = 0;
    for (int m = 1; m <= 12; m++) {
      final v = getter(m);
      if (v > maxY) maxY = v;
    }
    return maxY <= 0 ? 1000 : (maxY * 1.2);
  }
}