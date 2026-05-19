import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/services/local_database_service.dart';

class SyncOperation {
  final String id;
  final String type; // 'insert_product', 'update_product', 'delete_product', 'update_inventory', 'process_complete_sale'
  final Map<String, dynamic> payload;
  final int timestamp;

  SyncOperation({
    required this.id,
    required this.type,
    required this.payload,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'payload': payload,
    'timestamp': timestamp,
  };

  factory SyncOperation.fromJson(Map<String, dynamic> json) => SyncOperation(
    id: json['id'] as String,
    type: json['type'] as String,
    payload: json['payload'] as Map<String, dynamic>,
    timestamp: json['timestamp'] as int,
  );
}

class OfflineSyncManager {
  static final OfflineSyncManager instance = OfflineSyncManager._internal();
  OfflineSyncManager._internal();

  final ValueNotifier<bool> isOffline = ValueNotifier<bool>(false);
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);
  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  List<SyncOperation> _queue = [];
  Timer? _checkTimer;

  Future<void> init() async {
    // Initialize Local SQLite Database
    await LocalDatabaseService.instance.database;
    await _loadQueue();
    _startPeriodicCheck();
  }

  Future<void> _loadQueue() async {
    try {
      final queued = await LocalDatabaseService.instance.getQueuedOperations();
      _queue = queued.map((op) => SyncOperation(
        id: op['id'] as String,
        type: op['type'] as String,
        payload: op['payload'] as Map<String, dynamic>,
        timestamp: op['timestamp'] as int,
      )).toList();
      pendingCount.value = _queue.length;
    } catch (e) {
      debugPrint("Error loading SQLite sync queue: $e");
    }
  }

  void _startPeriodicCheck() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      checkConnectivityAndSync();
    });
  }

  Future<bool> checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> checkConnectivityAndSync() async {
    if (isSyncing.value) return;
    
    final online = await checkInternet();
    isOffline.value = !online;
    
    if (online && _queue.isNotEmpty) {
      await syncPendingOperations();
    }
  }

  /// Queues an operation for offline execution inside SQLite database.
  Future<void> queueOperation(String type, Map<String, dynamic> payload) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString() + '_' + type;
    final op = SyncOperation(
      id: id,
      type: type,
      payload: payload,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    try {
      await LocalDatabaseService.instance.queueOperation(id, type, payload);
      _queue.add(op);
      pendingCount.value = _queue.length;
      isOffline.value = true; // Mark as offline since we queued an operation
      
      // Trigger an async check
      Future.microtask(() => checkConnectivityAndSync());
    } catch (e) {
      debugPrint("Failed to queue operation in SQLite: $e");
    }
  }

  /// Wrapper to execute dynamic Supabase calls safely.
  /// If it fails due to network, it will automatically queue itself,
  /// print a warning and return true to the user (offline optimism).
  Future<bool> executeWithSync({
    required String type,
    required Map<String, dynamic> payload,
    required Future<void> Function(SupabaseClient client) onlineAction,
  }) async {
    final supabase = Supabase.instance.client;
    final hasInternet = await checkInternet();

    if (!hasInternet || isOffline.value) {
      debugPrint("Offline Mode Active: Queuing operation $type");
      await queueOperation(type, payload);
      return false; // Executed in offline optimistic mode
    }

    try {
      await onlineAction(supabase).timeout(const Duration(seconds: 8));
      return true; // Successfully executed online
    } catch (e) {
      if (e is SocketException || e is TimeoutException || e.toString().contains('Failed host lookup') || e.toString().contains('ClientException')) {
        debugPrint("Network Disconnected during action. Queuing $type: $e");
        await queueOperation(type, payload);
        isOffline.value = true;
        return false; // Optimistic return
      } else {
        // Core database error, rethrow to let UI handle validation error
        debugPrint("Core Database Error in $type: $e");
        rethrow;
      }
    }
  }

  /// Flushes the pending operation queue to Supabase
  Future<void> syncPendingOperations() async {
    if (isSyncing.value || _queue.isEmpty) return;
    isSyncing.value = true;
    debugPrint("OfflineSyncManager: Flushing SQLite sync queue (${_queue.length} items)...");

    final supabase = Supabase.instance.client;
    List<SyncOperation> successfullySynced = [];

    try {
      for (var op in _queue) {
        bool opSuccess = false;
        try {
          switch (op.type) {
            case 'insert_product':
              final prodData = Map<String, dynamic>.from(op.payload['product_data']);
              final quantity = op.payload['quantity'] as int? ?? 0;
              final branchId = op.payload['branch_id'] as String?;
              final tenantId = op.payload['tenant_id'] as String?;

              final response = await supabase.from('products').insert(prodData).select().single();
              if (branchId != null && tenantId != null) {
                await supabase.from('inventory').insert({
                  'tenant_id': tenantId,
                  'product_id': response['id'],
                  'branch_id': branchId,
                  'stock_level': quantity,
                });
              }
              opSuccess = true;
              break;

            case 'update_product':
              final id = op.payload['id'] as String;
              final prodData = Map<String, dynamic>.from(op.payload['product_data']);
              final quantity = op.payload['quantity'] as int?;
              final branchId = op.payload['branch_id'] as String?;
              final tenantId = op.payload['tenant_id'] as String?;

              await supabase.from('products').update(prodData).eq('id', id);

              if (quantity != null && branchId != null) {
                final existingInv = await supabase.from('inventory')
                    .select('id')
                    .eq('product_id', id)
                    .eq('branch_id', branchId)
                    .maybeSingle();

                if (existingInv != null) {
                  await supabase.from('inventory').update({'stock_level': quantity}).eq('id', existingInv['id']);
                } else {
                  await supabase.from('inventory').insert({
                    'tenant_id': tenantId,
                    'product_id': id,
                    'branch_id': branchId,
                    'stock_level': quantity,
                  });
                }
              }
              opSuccess = true;
              break;

            case 'delete_product':
              final id = op.payload['id'] as String;
              await supabase.from('products').delete().eq('id', id);
              opSuccess = true;
              break;

            case 'process_complete_sale':
              final tenantId = op.payload['p_tenant_id'] as String?;
              final branchId = op.payload['p_branch_id'] as String?;
              final employeeId = op.payload['p_employee_id'] as String?;
              final total = op.payload['p_total'] as num?;
              final items = op.payload['p_items'] as List<dynamic>?;

              await supabase.rpc('process_complete_sale', params: {
                'p_tenant_id': tenantId,
                'p_branch_id': branchId,
                'p_employee_id': employeeId,
                'p_total': total,
                'p_items': items,
              });
              opSuccess = true;
              break;
          }
        } catch (e) {
          if (e is SocketException || e is TimeoutException || e.toString().contains('Failed host lookup') || e.toString().contains('ClientException')) {
            debugPrint("Network interrupted during sync processing, aborting flush.");
            break; // Pause syncing and retry later
          } else {
            // Unrecoverable data mismatch error (e.g. duplicate key), log it and skip to avoid blocking the queue
            debugPrint("Skipping unrecoverable error in sync operation ${op.id}: $e");
            opSuccess = true; 
          }
        }

        if (opSuccess) {
          successfullySynced.add(op);
        }
      }

      // Remove successfully synced operations from SQLite queue
      for (var op in successfullySynced) {
        try {
          await LocalDatabaseService.instance.removeQueuedOperation(op.id);
          _queue.removeWhere((item) => item.id == op.id);
        } catch (e) {
          debugPrint("Failed to remove sync queue item from SQLite: $e");
        }
      }
      
      pendingCount.value = _queue.length;
      debugPrint("OfflineSyncManager: Synced ${successfullySynced.length} items successfully.");
    } finally {
      isSyncing.value = false;
      isOffline.value = _queue.isNotEmpty || !(await checkInternet());
    }
  }

  /// Offline Caching & Authentication Methods (Using SQLite tables)

  String _hashPassword(String password) {
    final bytes = utf8.encode("stockmanager_salt_" + password);
    return base64Encode(bytes);
  }

  Future<void> cacheUserCredentials(String email, String password, Map<String, dynamic> profile) async {
    final hash = _hashPassword(password);
    await LocalDatabaseService.instance.saveUserCredentials(email, hash, profile);
  }

  Future<Map<String, dynamic>?> authenticateOffline(String email, String password) async {
    final enteredHash = _hashPassword(password);
    final profile = await LocalDatabaseService.instance.getOfflineUser(email, enteredHash);
    if (profile != null) {
      isOffline.value = true; // Actively transition to offline state
    }
    return profile;
  }

  Future<void> cacheUserProfile(Map<String, dynamic> profile) async {
    // Save to users table with a dummy email/password hash if needed, or update last logged in record
    final email = profile['email'] as String? ?? 'cached_user';
    await LocalDatabaseService.instance.saveUserCredentials(email, 'cached_only', profile);
  }

  Future<Map<String, dynamic>?> getCachedUserProfile() async {
    return await LocalDatabaseService.instance.getLastLoggedInProfile();
  }

  Future<void> cacheProducts(List<Map<String, dynamic>> products) async {
    await LocalDatabaseService.instance.saveProductsAndInventory(products);
  }

  Future<List<Map<String, dynamic>>?> getCachedProducts() async {
    final products = await LocalDatabaseService.instance.getCachedProducts();
    return products.isEmpty ? null : products;
  }

  void dispose() {
    _checkTimer?.cancel();
  }
}
