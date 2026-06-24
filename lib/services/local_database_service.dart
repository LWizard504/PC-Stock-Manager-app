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
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
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

    // 2. Unified Inventory Table (merged products + inventory)
    await db.execute('''
      CREATE TABLE inventory (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        branch_id TEXT,
        name TEXT NOT NULL,
        sku TEXT,
        category TEXT,
        price REAL DEFAULT 0,
        stock_level INTEGER DEFAULT 0,
        min_stock INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        metadata_json TEXT,
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');

    // 3. Sync Queue Table
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

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS products');
      await db.execute('DROP TABLE IF EXISTS inventory');
      await db.execute('DROP TABLE IF EXISTS sync_queue');
      await db.execute('DROP TABLE IF EXISTS users');
      await _onCreate(db, newVersion);
    }
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

  Future<void> saveProductsAndInventory(List<Map<String, dynamic>> inventoryItems) async {
    final db = await database;
    
    await db.transaction((txn) async {
      await txn.delete('inventory');

      for (var item in inventoryItems) {
        await txn.insert(
          'inventory',
          {
            'id': item['id'],
            'tenant_id': item['tenant_id'],
            'branch_id': item['branch_id'],
            'name': item['name'] ?? '',
            'sku': item['sku'],
            'category': item['category'],
            'price': (item['price'] as num?)?.toDouble() ?? 0.0,
            'stock_level': (item['stock_level'] as num?)?.toInt() ?? 0,
            'min_stock': (item['min_stock'] as num?)?.toInt() ?? 0,
            'is_active': (item['is_active'] as bool?) == false ? 0 : 1,
            'metadata_json': jsonEncode(item['metadata'] ?? {}),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    
    debugPrint("SQLite: Cached ${inventoryItems.length} inventory items.");
  }

  Future<List<Map<String, dynamic>>> getCachedProducts() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('inventory');

    return maps.map((p) => {
      'id': p['id'],
      'name': p['name'],
      'sku': p['sku'],
      'price': p['price'],
      'category': p['category'],
      'is_active': p['is_active'] == 1,
      'metadata': jsonDecode(p['metadata_json'] as String? ?? '{}'),
      'tenant_id': p['tenant_id'],
      'branch_id': p['branch_id'],
      'stock_level': p['stock_level'],
      'min_stock': p['min_stock'],
    }).toList();
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
      await txn.delete('users');
    });
  }
}
