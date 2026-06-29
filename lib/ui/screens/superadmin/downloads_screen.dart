import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/ui/widgets/toast_utils.dart';
import 'package:intl/intl.dart';

class _Release {
  final String id;
  final String tag;
  final String title;
  final String description;
  final String releaseType;
  final String assetUrl;
  final String assetName;
  final DateTime publishedAt;

  _Release({
    required this.id,
    required this.tag,
    required this.title,
    this.description = '',
    this.releaseType = 'latest',
    this.assetUrl = '',
    this.assetName = '',
    required this.publishedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'tag': tag,
    'title': title,
    'description': description,
    'release_type': releaseType,
    'asset_url': assetUrl,
    'asset_name': assetName,
    'published_at': publishedAt.toIso8601String(),
  };

  factory _Release.fromMap(Map<String, dynamic> map) => _Release(
    id: map['id']?.toString() ?? '',
    tag: map['tag']?.toString() ?? '',
    title: map['title']?.toString() ?? '',
    description: map['description']?.toString() ?? '',
    releaseType: map['release_type']?.toString() ?? 'latest',
    assetUrl: map['asset_url']?.toString() ?? '',
    assetName: map['asset_name']?.toString() ?? '',
    publishedAt: map['published_at'] != null ? DateTime.parse(map['published_at'].toString()) : DateTime.now(),
  );
}

class DownloadsScreen extends StatefulWidget {
  final bool isSuperAdmin;

  const DownloadsScreen({super.key, this.isSuperAdmin = true});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<_Release> _releases = [];

  @override
  void initState() {
    super.initState();
    _fetchReleases();
  }

  Future<void> _fetchReleases() async {
    try {
      if (mounted) setState(() => _loading = true);

      List<_Release> releases = [];

      try {
        final response = await _supabase.from('releases').select('*').order('published_at', ascending: false);
        releases = (response as List).map((r) => _Release.fromMap(Map<String, dynamic>.from(r))).toList();
      } catch (_) {
        try {
          final response = await _supabase.from('app_updates').select('*').order('published_at', ascending: false);
          releases = (response as List).map((r) => _Release.fromMap(Map<String, dynamic>.from(r))).toList();
        } catch (_) {
          releases = [];
        }
      }

      if (mounted) setState(() {
        _releases = releases;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveRelease(Map<String, dynamic> data) async {
    try {
      await _supabase.from('releases').insert(data);
    } catch (_) {
      try {
        await _supabase.from('app_updates').insert(data);
      } catch (_) {
        rethrow;
      }
    }
  }

  Future<void> _deleteRelease(String id) async {
    try {
      await _supabase.from('releases').delete().eq('id', id);
    } catch (_) {
      try {
        await _supabase.from('app_updates').delete().eq('id', id);
      } catch (_) {
        rethrow;
      }
    }
  }

  String _formatDate(DateTime d) {
    return DateFormat('MMM dd, yyyy').format(d);
  }

  void _showCreateReleaseDialog() {
    final tagCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final assetUrlCtrl = TextEditingController();
    final assetNameCtrl = TextEditingController();
    String releaseType = 'latest';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF121212),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.white10),
          ),
          title: const Text("New Release", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: tagCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Tag Name",
                      labelStyle: TextStyle(color: Colors.white38),
                      hintText: "v21.0.0",
                      hintStyle: TextStyle(color: Colors.white24),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Title",
                      labelStyle: TextStyle(color: Colors.white38),
                      hintText: "v21.0.0",
                      hintStyle: TextStyle(color: Colors.white24),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descCtrl,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Description",
                      labelStyle: TextStyle(color: Colors.white38),
                      hintText: "Release notes...",
                      hintStyle: TextStyle(color: Colors.white24),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: releaseType,
                    dropdownColor: const Color(0xFF1A1A1A),
                    decoration: const InputDecoration(
                      labelText: "Release Type",
                      labelStyle: TextStyle(color: Colors.white38),
                    ),
                    style: const TextStyle(color: Colors.white),
                    items: const [
                      DropdownMenuItem(value: 'latest', child: Text("Latest")),
                      DropdownMenuItem(value: 'prerelease', child: Text("Pre-release")),
                      DropdownMenuItem(value: 'draft', child: Text("Draft")),
                    ],
                    onChanged: (val) => setDialogState(() => releaseType = val!),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: assetUrlCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Asset URL",
                      labelStyle: TextStyle(color: Colors.white38),
                      hintText: "https://github.com/.../app.apk",
                      hintStyle: TextStyle(color: Colors.white24),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: assetNameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Asset Name",
                      labelStyle: TextStyle(color: Colors.white38),
                      hintText: "StockManager-Android-v21.apk",
                      hintStyle: TextStyle(color: Colors.white24),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () {
                if (tagCtrl.text.trim().isEmpty) {
                  ToastUtils.showCustomToast(context, "Tag is required", isError: true);
                  return;
                }
                Navigator.pop(ctx);
                _createRelease(
                  tag: tagCtrl.text.trim(),
                  title: titleCtrl.text.trim().isNotEmpty ? titleCtrl.text.trim() : tagCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  releaseType: releaseType,
                  assetUrl: assetUrlCtrl.text.trim(),
                  assetName: assetNameCtrl.text.trim(),
                );
              },
              child: const Text("Publish"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createRelease({
    required String tag,
    required String title,
    required String description,
    required String releaseType,
    required String assetUrl,
    required String assetName,
  }) async {
    ToastUtils.showPromiseToast(
      context,
      message: "Publishing release...",
      promise: _executeCreateRelease(tag, title, description, releaseType, assetUrl, assetName),
      successMessage: "Release published",
      errorMessage: "Publish failed",
    );
  }

  Future<void> _executeCreateRelease(
    String tag, String title, String description, String releaseType, String assetUrl, String assetName,
  ) async {
    try {
      await _saveRelease({
        'tag': tag,
        'title': title,
        'description': description,
        'release_type': releaseType,
        'asset_url': assetUrl,
        'asset_name': assetName,
        'published_at': DateTime.now().toIso8601String(),
      });
      await _fetchReleases();
    } catch (e) {
      rethrow;
    }
  }

  void _showDeleteConfirmDialog(_Release release) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white10),
        ),
        title: const Text("Delete Release", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Are you sure you want to delete ${release.tag}?",
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              release.title,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteReleaseById(release);
            },
            child: const Text("DELETE"),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteReleaseById(_Release release) async {
    ToastUtils.showPromiseToast(
      context,
      message: "Deleting...",
      promise: _executeDelete(release),
      successMessage: "Release deleted",
      errorMessage: "Delete failed",
    );
  }

  Future<void> _executeDelete(_Release release) async {
    try {
      await _deleteRelease(release.id);
      await _fetchReleases();
    } catch (e) {
      rethrow;
    }
  }

  IconData _iconForFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (ext == 'apk') return LucideIcons.smartphone;
    if (ext == 'zip' || ext == 'tar' || ext == 'gz') return LucideIcons.fileArchive;
    if (ext == 'exe' || ext == 'msi') return LucideIcons.monitor;
    return LucideIcons.file;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isSuperAdmin) return _buildUserDownloadsView();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader().animate().fadeIn().slideY(begin: -0.2),
            const SizedBox(height: 48),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.package, size: 20, color: Colors.white54),
                            const SizedBox(width: 12),
                            const Text("Releases", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(width: 12),
                            Text(
                              "${_releases.length} total",
                              style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_loading)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(64),
                        child: CircularProgressIndicator(color: Colors.green),
                      ))
                    else if (_releases.isEmpty)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(64),
                        child: Text("No releases found", style: TextStyle(color: Colors.white24)),
                      ))
                    else
                      _buildReleasesTable(),
                  ],
                ),
              ),
            ).animate().fadeIn().slideY(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Distribution Hub",
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
            ),
            const SizedBox(height: 8),
            const Text(
              "GitHub Release Manager",
              style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
          ],
        ),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _fetchReleases,
              icon: Icon(_loading ? LucideIcons.loader2 : LucideIcons.refreshCw, size: 16),
              label: const Text("Refresh"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.surfaceLight,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: _showCreateReleaseDialog,
              icon: const Icon(LucideIcons.rocket, size: 16),
              label: const Text("Create Release"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReleasesTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1),
        columns: const [
          DataColumn(label: Text("TAG")),
          DataColumn(label: Text("NAME")),
          DataColumn(label: Text("PUBLISHED")),
          DataColumn(label: Text("ASSETS")),
          DataColumn(label: Text("")),
        ],
        rows: _releases.map((r) {
          return DataRow(cells: [
            DataCell(
              Row(
                children: [
                  Text(r.tag, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace')),
                  if (r.releaseType == 'prerelease')
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.yellow.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.yellow.withOpacity(0.3)),
                      ),
                      child: const Text("Pre", style: TextStyle(color: Colors.yellow, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                  if (r.releaseType == 'draft')
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: const Text("Draft", style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                ],
              ),
            ),
            DataCell(Text(r.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white), overflow: TextOverflow.ellipsis)),
            DataCell(
              Row(
                children: [
                  const Icon(LucideIcons.calendar, size: 12, color: Colors.white38),
                  const SizedBox(width: 6),
                  Text(_formatDate(r.publishedAt), style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace')),
                ],
              ),
            ),
            DataCell(
              r.assetUrl.isNotEmpty
                  ? InkWell(
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceLight.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_iconForFile(r.assetName), size: 12, color: Colors.greenAccent),
                            const SizedBox(width: 6),
                            Text(r.assetName.isNotEmpty ? r.assetName : "asset", style: const TextStyle(color: Colors.white54, fontSize: 9, fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                    )
                  : const Text("—", style: TextStyle(color: Colors.white24)),
            ),
            DataCell(
              PopupMenuButton<String>(
                icon: const Icon(LucideIcons.moreVertical, size: 16, color: Colors.white38),
                color: const Color(0xFF1A1A1A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Colors.white10),
                ),
                onSelected: (val) {
                  if (val == 'delete') _showDeleteConfirmDialog(r);
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text("Delete Release", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildUserDownloadsView() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<List<_Release>>(
        future: _fetchLatestReleases(),
        builder: (context, snapshot) {
          final releases = snapshot.data ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.downloadCloud, size: 32, color: Colors.greenAccent),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Downloads", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(
                          "${releases.length} available release${releases.length == 1 ? '' : 's'}",
                          style: const TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ).animate().fadeIn().slideY(begin: -0.2),
                const SizedBox(height: 48),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(64),
                    child: CircularProgressIndicator(color: Colors.green),
                  ))
                else if (releases.isEmpty)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(64),
                    child: Column(
                      children: [
                        Icon(LucideIcons.packageOpen, size: 48, color: Colors.white12),
                        SizedBox(height: 16),
                        Text("No downloads available", style: TextStyle(color: Colors.white24)),
                      ],
                    ),
                  ))
                else
                  Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    children: releases.map((r) => _buildDownloadCard(r)).toList(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<List<_Release>> _fetchLatestReleases() async {
    try {
      final response = await _supabase.from('releases').select('*').neq('release_type', 'draft').order('published_at', ascending: false);
      return (response as List).map((r) => _Release.fromMap(Map<String, dynamic>.from(r))).toList();
    } catch (_) {
      try {
        final response = await _supabase.from('app_updates').select('*').neq('release_type', 'draft').order('published_at', ascending: false);
        return (response as List).map((r) => _Release.fromMap(Map<String, dynamic>.from(r))).toList();
      } catch (_) {
        return [];
      }
    }
  }

  Widget _buildDownloadCard(_Release release) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    release.assetName.contains('.apk') ? LucideIcons.smartphone
                        : release.assetName.contains('.exe') || release.assetName.contains('.msi') ? LucideIcons.monitor
                        : LucideIcons.package,
                    color: Colors.greenAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(release.title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(release.tag, style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontFamily: 'monospace')),
                    ],
                  ),
                ),
                if (release.releaseType == 'prerelease')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.yellow.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.yellow.withOpacity(0.3)),
                    ),
                    child: const Text("Pre", style: TextStyle(color: Colors.yellow, fontSize: 8, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            if (release.description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(release.description, style: const TextStyle(color: Colors.white54, fontSize: 12), maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(LucideIcons.calendar, size: 12, color: Colors.white38),
                const SizedBox(width: 6),
                Text(_formatDate(release.publishedAt), style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
            if (release.assetUrl.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(LucideIcons.download, size: 16),
                  label: Text(release.assetName.isNotEmpty ? release.assetName : "Download"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn().scale(delay: 100.ms);
  }
}
