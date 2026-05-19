import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalDatabaseService {
  static final LocalDatabaseService instance = LocalDatabaseService._internal();
  LocalDatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, "stockmanager_local_v1.db");
    debugPrint("Initializing SQLite Database at: $path");

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. Users Table
    await db.execute('''
      CREATE TABLE users (
        email TEXT PRIMARY KEY,
        password_hash TEXT NOT NULL,
        profile_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 2. Products Table
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sku TEXT,
        price REAL,
        category TEXT,
        is_active INTEGER DEFAULT 1,
        metadata_json TEXT,
        tenant_id TEXT
      )
    ''');

    // 3. Inventory Table
    await db.execute('''
      CREATE TABLE inventory (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        tenant_id TEXT,
        stock_level INTEGER DEFAULT 0,
        min_stock INTEGER DEFAULT 0,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');

    // 4. Sync Queue Table
    await db.execute('''
      CREATE TABLE sync_queue (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');

    debugPrint("SQLite database tables created successfully.");
  }

  // --- USER PERSISTENCE ---

  Future<void> saveUserCredentials(String email, String passwordHash, Map<String, dynamic> profile) async {
    final db = await database;
    final normalizedEmail = email.toLowerCase().trim();
    
    await db.insert(
      'users',
      {
        'email': normalizedEmail,
        'password_hash': passwordHash,
        'profile_json': jsonEncode(profile),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getOfflineUser(String email, String passwordHash) async {
    final db = await database;
    final normalizedEmail = email.toLowerCase().trim();
    
    final List<Map<String, dynamic>> maps = await db.query(
      'users',
      where: 'email = ? AND password_hash = ?',
      whereArgs: [normalizedEmail, passwordHash],
    );

    if (maps.isNotEmpty) {
      try {
        return jsonDecode(maps.first['profile_json'] as String) as Map<String, dynamic>;
      } catch (e) {
        debugPrint("Error decoding local user profile: $e");
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> getLastLoggedInProfile() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'users',
      orderBy: 'updated_at DESC',
      limit: 1,
    );

    if (maps.isNotEmpty) {
      try {
        return jsonDecode(maps.first['profile_json'] as String) as Map<String, dynamic>;
      } catch (_) {}
    }
    return null;
  }

  // --- PRODUCTS & INVENTORY CACHING ---

  Future<void> saveProductsAndInventory(List<Map<String, dynamic>> products) async {
    final db = await database;
    
    await db.transaction((txn) async {
      // Clear existing records to ensure cache consistency
      await txn.delete('inventory');
      await txn.delete('products');

      for (var p in products) {
        // Save product
        await txn.insert(
          'products',
          {
            'id': p['id'],
            'name': p['name'] ?? '',
            'sku': p['sku'],
            'price': (p['price'] as num?)?.toDouble() ?? 0.0,
            'category': p['category'],
            'is_active': (p['is_active'] as bool?) == false ? 0 : 1,
            'metadata_json': jsonEncode(p['metadata'] ?? {}),
            'tenant_id': p['tenant_id'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // Save nested inventory records
        final invList = p['inventory'];
        if (invList != null && invList is List) {
          for (var inv in invList) {
            await txn.insert(
              'inventory',
              {
                'id': inv['id'] ?? (p['id'] + '_' + (inv['branch_id'] ?? 'default')),
                'product_id': p['id'],
                'branch_id': inv['branch_id'] ?? '',
                'tenant_id': inv['tenant_id'],
                'stock_level': (inv['stock_level'] as num?)?.toInt() ?? 0,
                'min_stock': (inv['min_stock'] as num?)?.toInt() ?? 0,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }
    });
    
    debugPrint("SQLite: Cached ${products.length} products and inventory levels.");
  }

  Future<List<Map<String, dynamic>>> getCachedProducts() async {
    final db = await database;
    
    final List<Map<String, dynamic>> prodMaps = await db.query('products');
    final List<Map<String, dynamic>> invMaps = await db.query('inventory');

    List<Map<String, dynamic>> result = [];

    for (var p in prodMaps) {
      // Get associated inventories
      final inventories = invMaps
          .where((inv) => inv['product_id'] == p['id'])
          .map((inv) => {
                'id': inv['id'],
                'product_id': inv['product_id'],
                'branch_id': inv['branch_id'],
                'tenant_id': inv['tenant_id'],
                'stock_level': inv['stock_level'],
                'min_stock': inv['min_stock'],
              })
          .toList();

      result.add({
        'id': p['id'],
        'name': p['name'],
        'sku': p['sku'],
        'price': p['price'],
        'category': p['category'],
        'is_active': p['is_active'] == 1,
        'metadata': jsonDecode(p['metadata_json'] as String? ?? '{}'),
        'tenant_id': p['tenant_id'],
        'inventory': inventories,
      });
    }

    return result;
  }

  // --- OFFLINE SYNC QUEUE ---

  Future<void> queueOperation(String id, String type, Map<String, dynamic> payload) async {
    final db = await database;
    await db.insert(
      'sync_queue',
      {
        'id': id,
        'type': type,
        'payload_json': jsonEncode(payload),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getQueuedOperations() async {
    final db = await database;
    final maps = await db.query('sync_queue', orderBy: 'timestamp ASC');
    
    return maps.map((row) => {
      'id': row['id'],
      'type': row['type'],
      'payload': jsonDecode(row['payload_json'] as String) as Map<String, dynamic>,
      'timestamp': row['timestamp'],
    }).toList();
  }

  Future<void> removeQueuedOperation(String id) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearDatabase() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('sync_queue');
      await txn.delete('inventory');
      await txn.delete('products');
      await txn.delete('users');
    });
  }
}
