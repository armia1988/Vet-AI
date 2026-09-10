import 'package:flutter/material.dart';

import 'camera_alert_repository.dart';

class CameraAlertCenterPage extends StatefulWidget {
  const CameraAlertCenterPage({super.key, required this.farmId});

  final String farmId;

  @override
  State<CameraAlertCenterPage> createState() => _CameraAlertCenterPageState();
}

class _CameraAlertCenterPageState extends State<CameraAlertCenterPage> {
  final CameraAlertRepository repository = const CameraAlertRepository();
  final TextEditingController searchController = TextEditingController();

  bool loading = true;
  String? error;
  List<Map<String, dynamic>> alerts = const [];
  String riskFilter = 'all';
  String stateFilter = 'open';
  String categoryFilter = 'all';
  String cameraFilter = 'all';

  @override
  void initState() {
    super.initState();
    searchController.addListener(_refreshFilters);
    _load();
  }

  @override
  void dispose() {
    searchController
      ..removeListener(_refreshFilters)
      ..dispose();
    super.dispose();
  }

  void _refreshFilters() => setState(() {});

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await repository.recentForFarm(farmId: widget.farmId);
      if (!mounted) return;
      setState(() {
        alerts = rows;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  String _metric(Map<String, dynamic> row) => (row['metric'] ?? '').toString();

  String _cameraUid(Map<String, dynamic> row) {
    final parts = _metric(row).split(':');
    return parts.length >= 3 ? parts[1] : 'unknown';
  }

  String _category(Map<String, dynamic> row) {
    final parts = _metric(row).split(':');
    return parts.length >= 3 ? parts.sublist(2).join(':') : 'camera_event';
  }

  String _cameraName(Map<String, dynamic> row) {
    final details = (row['details'] ?? '').toString();
    final first = details.split('\n').firstWhere(
          (line) => line.startsWith('Camera:'),
          orElse: () => '',
        );
    if (first.isNotEmpty) return first.substring('Camera:'.length).trim();
    final title = (row['title'] ?? '').toString();
    final marker = title.indexOf(' — ');
    return marker > 0 ? title.substring(0, marker) : _cameraUid(row);
  }

  bool _isResolved(Map<String, dynamic> row) => (row['admin_status'] ?? 'open').toString() == 'resolved';
  bool _isAcknowledged(Map<String, dynamic> row) => row['acknowledged_at'] != null;

  int get _unacknowledgedCount => alerts.where((row) => !_isAcknowledged(row) && !_isResolved(row)).length;
  int get _criticalOpenCount => alerts.where((row) => (row['risk'] ?? '').toString() == 'red' && !_isResolved(row)).length;

  List<String> get _cameraOptions {
    final names = alerts.map(_cameraName).where((e) => e.isNotEmpty).toSet().toList()..sort();
    return names;
  }

  List<String> get _categoryOptions {
    final values = alerts.map(_category).where((e) => e.isNotEmpty).toSet().toList()..sort();
    return values;
  }

  List<Map<String, dynamic>> get _filtered {
    final query = searchController.text.trim().toLowerCase();
    return alerts.where((row) {
      final risk = (row['risk'] ?? '').toString();
      final resolved = _isResolved(row);
      final acknowledged = _isAcknowledged(row);
      final category = _category(row);
      final camera = _cameraName(row);

      if (riskFilter != 'all' && risk != riskFilter) return false;
      if (cameraFilter != 'all' && camera != cameraFilter) return false;
      if (categoryFilter != 'all' && category != categoryFilter) return false;
      if (stateFilter == 'open' && resolved) return false;
      if (stateFilter == 'unacknowledged' && (resolved || acknowledged)) return false;
      if (stateFilter == 'resolved' && !resolved) return false;
      if (query.isNotEmpty) {
        final haystack = '${row['title'] ?? ''} ${row['details'] ?? ''} $camera $category $risk'.toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  Color _riskColor(String risk) {
    switch (risk) {
      case 'red':
        return Colors.redAccent;
      case 'orange':
        return Colors.orangeAccent;
      default:
        return Colors.amberAccent;
    }
  }

  IconData _categoryIcon(String category) {
    if (category.contains('fire')) return Icons.local_fire_department_rounded;
    if (category.contains('thermal')) return Icons.thermostat_rounded;
    if (category.contains('intrusion')) return Icons.gpp_maybe_rounded;
    if (category.contains('motion')) return Icons.directions_run_rounded;
    if (category.contains('person')) return Icons.person_search_rounded;
    if (category.contains('vehicle')) return Icons.directions_car_rounded;
    return Icons.videocam_rounded;
  }

  Future<void> _acknowledge(Map<String, dynamic> row) async {
    final id = (row['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      await repository.acknowledge(id);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not acknowledge alert: $e')));
    }
  }

  Future<void> _resolve(Map<String, dynamic> row) async {
    final id = (row['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      await repository.resolve(id);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not resolve alert: $e')));
    }
  }

  Future<void> _reopen(Map<String, dynamic> row) async {
    final id = (row['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      await repository.reopen(id);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not reopen alert: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111419),
        foregroundColor: Colors.white,
        title: const Text('Camera Alerts'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? _errorState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                    children: [
                      _summary(),
                      const SizedBox(height: 12),
                      _filters(),
                      const SizedBox(height: 12),
                      if (_filtered.isEmpty)
                        _emptyState()
                      else
                        ..._filtered.map(_alertCard),
                    ],
                  ),
                ),
    );
  }

  Widget _summary() {
    final open = alerts.where((row) => !_isResolved(row)).length;
    final resolved = alerts.length - open;
    return Row(
      children: [
        Expanded(child: _summaryCard('Open', '$open', Icons.notifications_active_rounded, Colors.orangeAccent)),
        const SizedBox(width: 8),
        Expanded(child: _summaryCard('Unack.', '$_unacknowledgedCount', Icons.mark_email_unread_rounded, Colors.amberAccent)),
        const SizedBox(width: 8),
        Expanded(child: _summaryCard('Critical', '$_criticalOpenCount', Icons.error_rounded, Colors.redAccent)),
        const SizedBox(width: 8),
        Expanded(child: _summaryCard('Resolved', '$resolved', Icons.task_alt_rounded, Colors.greenAccent)),
      ],
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF15191F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 5),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19)),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 10)),
          ],
        ),
      );

  Widget _filters() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF15191F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            TextField(
              controller: searchController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search camera alerts',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _menuFilter('State', stateFilter, const {'open': 'Open', 'unacknowledged': 'Unack.', 'resolved': 'Resolved', 'all': 'All'}, (v) => setState(() => stateFilter = v)),
                  const SizedBox(width: 8),
                  _menuFilter('Risk', riskFilter, const {'all': 'All risks', 'red': 'Red', 'orange': 'Orange', 'yellow': 'Yellow'}, (v) => setState(() => riskFilter = v)),
                  const SizedBox(width: 8),
                  _dynamicFilter('Camera', cameraFilter, ['all', ..._cameraOptions], (v) => setState(() => cameraFilter = v)),
                  const SizedBox(width: 8),
                  _dynamicFilter('Type', categoryFilter, ['all', ..._categoryOptions], (v) => setState(() => categoryFilter = v)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _menuFilter(String label, String current, Map<String, String> values, ValueChanged<String> onChanged) => PopupMenuButton<String>(
        initialValue: current,
        onSelected: onChanged,
        itemBuilder: (context) => values.entries.map((e) => PopupMenuItem(value: e.key, child: Text(e.value))).toList(),
        child: _filterChip(label, values[current] ?? current),
      );

  Widget _dynamicFilter(String label, String current, List<String> values, ValueChanged<String> onChanged) => PopupMenuButton<String>(
        initialValue: current,
        onSelected: onChanged,
        itemBuilder: (context) => values.map((v) => PopupMenuItem(value: v, child: Text(v == 'all' ? 'All' : v))).toList(),
        child: _filterChip(label, current == 'all' ? 'All' : current),
      );

  Widget _filterChip(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(color: const Color(0xFF22272F), borderRadius: BorderRadius.circular(9), border: Border.all(color: Colors.white12)),
        child: Row(children: [Text('$label: $value', style: const TextStyle(color: Colors.white70)), const SizedBox(width: 4), const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 18)]),
      );

  Widget _alertCard(Map<String, dynamic> row) {
    final risk = (row['risk'] ?? 'yellow').toString();
    final color = _riskColor(risk);
    final category = _category(row);
    final resolved = _isResolved(row);
    final acknowledged = _isAcknowledged(row);
    final created = DateTime.tryParse((row['created_at'] ?? '').toString())?.toLocal();
    final temperature = row['value_numeric'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF15191F),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: resolved ? Colors.white10 : color.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(_categoryIcon(category), color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((row['title'] ?? 'Camera alert').toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    Text('${_cameraName(row)} • $category', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
              if (resolved)
                const Icon(Icons.task_alt_rounded, color: Colors.greenAccent)
              else if (acknowledged)
                const Icon(Icons.done_all_rounded, color: Colors.lightBlueAccent)
              else
                Icon(Icons.circle, color: color, size: 11),
            ],
          ),
          const SizedBox(height: 9),
          Text((row['details'] ?? '').toString(), maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
          if (temperature != null) ...[
            const SizedBox(height: 7),
            Text('Temperature: $temperature °C', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          ],
          const SizedBox(height: 7),
          Text(created?.toString() ?? 'Time not reported', style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 10),
          Row(
            children: [
              if (!acknowledged && !resolved)
                Expanded(child: OutlinedButton.icon(onPressed: () => _acknowledge(row), icon: const Icon(Icons.done_rounded), label: const Text('Acknowledge'))),
              if (!acknowledged && !resolved) const SizedBox(width: 8),
              if (!resolved)
                Expanded(child: FilledButton.icon(onPressed: () => _resolve(row), icon: const Icon(Icons.task_alt_rounded), label: const Text('Resolve')))
              else
                Expanded(child: OutlinedButton.icon(onPressed: () => _reopen(row), icon: const Icon(Icons.restart_alt_rounded), label: const Text('Reopen'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        alignment: Alignment.center,
        child: const Column(
          children: [
            Icon(Icons.notifications_none_rounded, color: Colors.white38, size: 52),
            SizedBox(height: 10),
            Text('No camera alerts match these filters.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
          ],
        ),
      );

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
              const SizedBox(height: 10),
              Text(error ?? 'Could not load camera alerts', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
            ],
          ),
        ),
      );
}
