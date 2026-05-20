import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  LocaleProvider() {
    _loadLocale();
  }

  void _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = prefs.getString('language_code') ?? 'en';
    _locale = Locale(langCode);
    notifyListeners();
  }

  void setLocale(Locale locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', locale.languageCode);
    notifyListeners();
  }

  // Traducciones rápidas (Sustitución simple para evitar dependencias pesadas en este paso)
  static Map<String, Map<String, String>> translations = {
    'en': {
      'app_title': 'StockManager',
      'login_title': 'Network Authentication',
      'login_subtitle': 'Access your node using global credentials.',
      'email': 'Email Address',
      'password': 'Password',
      'login_button': 'Authorize Access',
      'users_title': 'Global Infrastructure',
      'users_subtitle': 'Identity and access control.',
      'pricing_title': 'Pricing Engine',
      'pricing_subtitle': 'Configure global subscription plans.',
      'inventory_title': 'Central Inventory',
      'inventory_subtitle': 'Centralized stock and catalog management.',
      'pos_title': 'Point of Sale',
      'pos_checkout': 'PROCESS CHECKOUT',
      'sync': 'Sync',
      'refresh': 'Refresh',
      'actions': 'Actions',
      'cancel': 'Cancel',
      'save': 'Save',
      'analytics_title': 'Analytics',
      'sessions_title': 'Employee Sessions',
      'sales_history_title': 'Sales History',
      'tickets_title': 'Support Tickets',
      'employees_title': 'Employees',
    },
    'es': {
      'app_title': 'StockManager',
      'login_title': 'Autenticación de Red',
      'login_subtitle': 'Acceda a su nodo usando credenciales globales.',
      'email': 'Correo Electrónico',
      'password': 'Contraseña',
      'login_button': 'Autorizar Acceso',
      'users_title': 'Infraestructura Global',
      'users_subtitle': 'Control de identidades y accesos.',
      'pricing_title': 'Motor de Precios',
      'pricing_subtitle': 'Configura los planes de suscripción globales.',
      'inventory_title': 'Inventario Central',
      'inventory_subtitle': 'Gestión centralizada de stock y catálogo.',
      'pos_title': 'Terminal de Venta',
      'pos_checkout': 'PROCESAR PAGO',
      'sync': 'Sincronizar',
      'refresh': 'Refrescar',
      'actions': 'Acciones',
      'cancel': 'Cancelar',
      'save': 'Guardar',
      'analytics_title': 'Analíticas',
      'sessions_title': 'Sesiones',
      'sales_history_title': 'Historial Ventas',
      'tickets_title': 'Soporte y Tickets',
      'employees_title': 'Colaboradores',
    }
  };

  String t(String key) {
    return translations[_locale.languageCode]?[key] ?? key;
  }
}
