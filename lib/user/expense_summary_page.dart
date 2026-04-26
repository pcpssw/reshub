import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

enum YearMetric { paid, water, electric }

// =============================================================
// 1. หน้าสรุปรายปี (ExpensePage) - ปรับปรุงให้ Compact
// =============================================================
class ExpensePage extends StatefulWidget {
  const ExpensePage({super.key});

  @override
  State<ExpensePage> createState() => _ExpensePageState();
}

class _ExpensePageState extends State<ExpensePage> {
  static const Color _bgColor = Color(0xFFF4EFE6);
  static const Color _textColor = Color(0xFF2A1F17); // ปรับให้เข้มคมชัดขึ้น
  static const Color _mutedColor = Color(0xFF8D7456);
  static const Color _lineColor = Color(0xFFDCD2C1);
  static const Color _primaryColor = Color(0xFF523D2D);

  // 📏 ปรับ Typography ให้เล็กลง (Compact)
  static const double fHeader = 14.0;
  static const double fBody = 13.0;
  static const double fDetail = 12.0;
  static const double fCaption = 10.0;

  int selectedYear = DateTime.now().year;
  int userId = 0;
  bool loading = true;
  String? loadError;
  YearMetric yearMetric = YearMetric.paid;

  final money = NumberFormat("#,##0", "en_US");
  final monthsText = const [
    "มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน", "พฤษภาคม", "มิถุนายน",
    "กรกฎาคม", "สิงหาคม", "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม"
  ];
  final monthsShort = const [
    "", "ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.",
    "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."
  ];

  double yearPaidSum = 0;
  List<Map<String, dynamic>> yearMonths = [];

  int _be(int ad) => ad + 543;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getInt("user_id") ?? int.tryParse(prefs.getString("user_id") ?? "0") ?? 0;
    await fetchYearSummary();
  }

  Future<void> fetchYearSummary() async {
    if (!mounted) return;
    setState(() { loading = true; loadError = null; });
    try {
      final uri = Uri.parse(AppConfig.url("finance_api.php")).replace(
        queryParameters: {
          "action": "summary_income",
          "user_id": userId.toString(),
          "year": selectedYear.toString(),
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      final data = jsonDecode(res.body);
      if (data["ok"] == true || data["success"] == true) {
        setState(() {
          yearPaidSum = (data["received_income"] as num?)?.toDouble() ?? 0;
          yearMonths = List<Map<String, dynamic>>.from(data["months"] ?? []);
        });
      } else {
        throw Exception(data["message"] ?? "โหลดข้อมูลไม่สำเร็จ");
      }
    } catch (e) {
      setState(() => loadError = "เชื่อมต่อล้มเหลว");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  double _yearValue(int m) {
    final row = yearMonths.firstWhere((e) => (e["month"] ?? 0) == m, orElse: () => {});
    if (yearMetric == YearMetric.paid) return (row["received_income"] as num?)?.toDouble() ?? 0;
    if (yearMetric == YearMetric.water) return (row["water"] as num?)?.toDouble() ?? 0;
    return (row["electric"] as num?)?.toDouble() ?? 0;
  }

  double _yearMonthsMax() {
    double m = 0;
    for (int i = 1; i <= 12; i++) {
      double v = _yearValue(i);
      if (v > m) m = v;
    }
    return m > 0 ? m : 1000;
  }

  int _yearBillCount(int m) {
    final row = yearMonths.firstWhere((e) => (e["month"] ?? 0) == m, orElse: () => {});
    return int.tryParse("${row["bill_count"] ?? 0}") ?? 0;
  }

  String _compact(double v) => v.abs() >= 1000 ? "${(v / 1000).toStringAsFixed(0)}K" : v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        toolbarHeight: 50,
        centerTitle: true,
        elevation: 0.5,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 24, color: _textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("สรุปค่าใช้จ่ายรายปี", style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: fHeader)),
      ),
      body: loading 
          ? const Center(child: CircularProgressIndicator(color: _primaryColor)) 
          : loadError != null ? _buildErrorState() : _buildBody(),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _buildYearSelector(),
        const SizedBox(height: 12),
        _buildHeroYearPaidCard(),
        const SizedBox(height: 16),
        Text("สถิติรายปี ${_be(selectedYear)}", style: const TextStyle(fontSize: fBody, fontWeight: FontWeight.bold, color: _textColor)),
        const SizedBox(height: 8),
        _buildYearMetricToggle(),
        const SizedBox(height: 12),
        _buildYearMetricChart(),
        const SizedBox(height: 16),
        for (int m = 1; m <= 12; m++) ...[
          _buildYearMonthRow(m),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildYearSelector() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: _lineColor)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: selectedYear,
          isExpanded: true,
          style: const TextStyle(color: _textColor, fontSize: fDetail, fontWeight: FontWeight.bold),
          items: [2024, 2025, 2026].map((y) => DropdownMenuItem(value: y, child: Text("  ${_be(y)}"))).toList(),
          onChanged: (v) { if (v != null) { setState(() => selectedYear = v); fetchYearSummary(); } },
        ),
      ),
    );
  }

  Widget _buildHeroYearPaidCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _primaryColor, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("ยอดชำระรวมทั้งปี", style: TextStyle(color: Colors.white70, fontSize: fCaption)),
          const SizedBox(height: 4),
          Text("${money.format(yearPaidSum)} ฿", style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildYearMetricToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: _lineColor.withOpacity(0.4), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          _toggleItem("ยอดรวม", YearMetric.paid),
          _toggleItem("น้ำ", YearMetric.water),
          _toggleItem("ไฟ", YearMetric.electric),
        ],
      ),
    );
  }

  Widget _toggleItem(String label, YearMetric m) {
    final active = yearMetric == m;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => yearMetric = m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: active ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(8)),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: active ? _textColor : _mutedColor, fontWeight: FontWeight.bold, fontSize: fCaption)),
        ),
      ),
    );
  }

  Widget _buildYearMetricChart() {
    Color mainColor = yearMetric == YearMetric.paid ? _primaryColor : yearMetric == YearMetric.water ? const Color(0xFF4A90E2) : const Color(0xFFF5A623);
    double maxVal = _yearMonthsMax();
    double chartMax = (maxVal * 1.2).ceilToDouble();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: _lineColor)),
      child: AspectRatio(
        aspectRatio: 1.8,
        child: BarChart(
          BarChartData(
            maxY: chartMax,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, m) => Text(_compact(v), style: const TextStyle(fontSize: 9, color: _mutedColor)))),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) => Text(monthsShort[v.toInt() % 13], style: const TextStyle(fontSize: 9, color: _mutedColor)))),
            ),
            barGroups: List.generate(12, (index) => BarChartGroupData(x: index + 1, barRods: [BarChartRodData(toY: _yearValue(index + 1), width: 14, color: mainColor, borderRadius: BorderRadius.circular(4))])),
          ),
        ),
      ),
    );
  }

  Widget _buildYearMonthRow(int m) {
    final val = _yearValue(m);
    final hasData = _yearBillCount(m) > 0;
    return InkWell(
      onTap: hasData ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => BillHistoryPage(userId: userId, year: selectedYear, month: m, monthName: monthsText[m - 1]))) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _lineColor.withOpacity(0.5))),
        child: Row(
          children: [
            Text(monthsText[m - 1], style: TextStyle(fontWeight: FontWeight.bold, fontSize: fDetail, color: hasData ? _textColor : Colors.grey.shade400)),
            const Spacer(),
            Text(hasData ? "${money.format(val)} ฿" : "ไม่มีข้อมูล", style: TextStyle(fontWeight: FontWeight.w900, fontSize: fDetail, color: hasData ? _textColor : Colors.grey.shade300)),
            if (hasData) const Icon(Icons.chevron_right_rounded, color: _mutedColor, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text(loadError ?? "เกิดข้อผิดพลาด", style: const TextStyle(color: _textColor, fontSize: fBody)),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ElevatedButton(
              onPressed: fetchYearSummary,
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, shape: const StadiumBorder()),
              child: const Text("ลองใหม่", style: TextStyle(color: Colors.white, fontSize: fDetail)),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// 2. หน้าประวัติบิลรายเดือน (BillHistoryPage) - ปรับปรุง UI
// =============================================================
class BillHistoryPage extends StatefulWidget {
  final int userId, year, month;
  final String monthName;
  const BillHistoryPage({super.key, required this.userId, required this.year, required this.month, required this.monthName});
  @override
  State<BillHistoryPage> createState() => _BillHistoryPageState();
}

class _BillHistoryPageState extends State<BillHistoryPage> {
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cText = Color(0xFF2A1F17);
  final money = NumberFormat("#,##0", "en_US");
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> items = [];

  @override
  void initState() { super.initState(); _fetchBills(); }

  Future<void> _fetchBills() async {
    try {
      final res = await http.get(Uri.parse(AppConfig.url("finance_api.php?action=bill_list&user_id=${widget.userId}&year=${widget.year}&month=${widget.month}")));
      final data = jsonDecode(res.body);
      if (data["ok"] == true) setState(() => items = List<Map<String, dynamic>>.from(data["items"] ?? []));
    } catch (e) { error = "โหลดไม่สำเร็จ"; }
    finally { if (mounted) setState(() => loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 50,
        backgroundColor: Colors.white,
        centerTitle: true,
        title: Text("บิล ${widget.monthName} ${_be(widget.year)}", style: const TextStyle(color: cText, fontWeight: FontWeight.bold, fontSize: 14)),
        leading: IconButton(icon: const Icon(Icons.chevron_left_rounded, color: cText), onPressed: () => Navigator.pop(context)),
      ),
      body: loading 
          ? const Center(child: CircularProgressIndicator(color: cText)) 
          : items.isEmpty 
              ? const Center(child: Text("ไม่มีข้อมูลบิล")) 
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _buildCompactBillCard(items[i]),
                ),
    );
  }

  int _be(int ad) => ad + 543;

  Widget _buildCompactBillCard(Map<String, dynamic> it) {
    final status = (it["status"] ?? "").toString().toLowerCase();
    final isPaid = status == "verified" || status == "paid";
    final total = double.tryParse(it["total"].toString()) ?? 0;
    final room = (it["room_number"] ?? "-").toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFDCD2C1).withOpacity(0.5))),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: isPaid ? Colors.green.shade50 : Colors.orange.shade50, child: Icon(isPaid ? Icons.check_circle : Icons.pending, color: isPaid ? Colors.green : Colors.orange, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("ห้อง $room", style: const TextStyle(fontWeight: FontWeight.bold, color: cText, fontSize: 14)), Text(isPaid ? "ชำระเรียบร้อย" : "รอตรวจสอบ", style: TextStyle(color: Colors.grey, fontSize: 11))])),
          Text("${money.format(total)} ฿", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: cText)),
        ],
      ),
    );
  }
}