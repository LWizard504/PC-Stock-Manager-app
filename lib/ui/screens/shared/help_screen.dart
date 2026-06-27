import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';

class HelpScreen extends StatelessWidget {
  final String role;

  const HelpScreen({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.arrowLeft, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 12),
                Text("Centro de Ayuda",
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28, fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 8),
            const Text("Guías y documentación del sistema StockManager.",
              style: TextStyle(color: Colors.white38, fontSize: 14)),
            const SizedBox(height: 48),
            ..._getHelpSections(context),
          ],
        ),
      ),
    ).animate().fadeIn();
  }

  List<Widget> _getHelpSections(BuildContext context) {
    final sections = <HelpSection>[];

    sections.addAll([
      HelpSection(
        icon: LucideIcons.layoutDashboard,
        title: "Dashboard",
        items: [
          "Vista general de indicadores clave de rendimiento (KPI)",
          "Gráficos de actividad y tendencias",
          "Alertas de stock bajo y notificaciones del sistema",
          "Acceso rápido a las funciones más utilizadas",
        ],
      ),
      HelpSection(
        icon: LucideIcons.package2,
        title: "Inventario",
        items: [
          "Gestión completa de productos: crear, editar, eliminar",
          "Búsqueda por SKU o nombre del producto",
          "Indicadores visuales de stock bajo (menos de 5 unidades)",
          "Sincronización automática en modo offline",
          "Campos: nombre, SKU, categoría, precio, stock, ubicación, fecha de expiración",
        ],
      ),
      HelpSection(
        icon: LucideIcons.messageSquare,
        title: "Chat y Comunicación",
        items: [
          "Mensajería en tiempo real con otros usuarios del sistema",
          "Indicadores de escritura y grabación de audio",
          "Presencia online (usuarios conectados)",
          "Llamadas de voz y video (solo SuperAdmin)",
          "Grupos de chat (Neural Clusters)",
        ],
      ),
      HelpSection(
        icon: LucideIcons.settings,
        title: "Configuración",
        items: [
          "Editar perfil: nombre, apellido, teléfono",
          "Cambiar contraseña mediante correo de recuperación",
          "Activar/desactivar autenticación de dos factores (2FA)",
          "Configurar teclado táctil para POS",
          "Cambiar idioma (Español/English)",
          "Cerrar sesión",
        ],
      ),
    ]);

    switch (role) {
      case 'superadmin':
        sections.addAll([
          HelpSection(
            icon: LucideIcons.dollarSign,
            title: "Motor de Precios",
            items: [
              "Gestionar planes de suscripción (Starter, Pro, Enterprise, Custom)",
              "Editar precios de los planes",
              "Ver planes recomendados y características",
            ],
          ),
          HelpSection(
            icon: LucideIcons.users,
            title: "Gestión de Usuarios (Infraestructura Global)",
            items: [
              "Crear nuevos usuarios en cualquier tenant",
              "Restablecer contraseñas de usuarios",
              "Eliminar identidades de usuarios (purga)",
              "Asignar roles: superadmin, admin, manager, it, employee",
            ],
          ),
          HelpSection(
            icon: LucideIcons.activity,
            title: "Estado de Nodos",
            items: [
              "Monitorear todos los tenants (nodos) de la red",
              "Ver estado de conexión (online/offline)",
              "Cantidad de sucursales por nodo",
              "Latencia de conexión",
            ],
          ),
          HelpSection(
            icon: LucideIcons.downloadCloud,
            title: "Descargas y Actualizaciones",
            items: [
              "Gestionar binarios de la aplicación",
              "Distribuir actualizaciones a los clientes",
            ],
          ),
        ]);
        break;
      case 'admin':
        sections.addAll([
          HelpSection(
            icon: LucideIcons.users,
            title: "Colaboradores",
            items: [
              "Ver lista de empleados del tenant",
              "Gestionar accesos y roles",
            ],
          ),
          HelpSection(
            icon: LucideIcons.monitorSmartphone,
            title: "Sesiones de Empleados",
            items: [
              "Monitorear empleados conectados",
              "Ver estado online/offline",
              "Información: nombre, email, sucursal, rol",
            ],
          ),
          HelpSection(
            icon: LucideIcons.history,
            title: "Historial de Ventas",
            items: [
              "Buscar ventas por ID de recibo o vendedor",
              "Ver detalles: cajero, sucursal, monto, fecha",
            ],
          ),
          HelpSection(
            icon: LucideIcons.creditCard,
            title: "Pagos y Suscripción",
            items: [
              "Ver plan de suscripción activo",
              "Estado de la suscripción y ciclo de facturación",
              "Historial de pagos",
              "Terminar suscripción",
            ],
          ),
          HelpSection(
            icon: LucideIcons.receipt,
            title: "Ventas Activas",
            items: [
              "Libro de ventas con todas las transacciones",
              "Búsqueda por ID o vendedor",
              "Exportar a PDF",
            ],
          ),
        ]);
        break;
      case 'manager':
        sections.addAll([
          HelpSection(
            icon: LucideIcons.lineChart,
            title: "Analíticas",
            items: [
              "Ingresos totales, conteo de transacciones, ticket promedio",
              "Ventas por sucursal con barras de progreso",
              "Ventas por vendedor/cajero",
            ],
          ),
          HelpSection(
            icon: LucideIcons.monitorSmartphone,
            title: "Sesiones de Empleados",
            items: [
              "Monitorear empleados a cargo",
              "Ver estado de conexión",
            ],
          ),
          HelpSection(
            icon: LucideIcons.history,
            title: "Historial de Ventas",
            items: [
              "Consultar ventas anteriores",
              "Filtrar por recibo o vendedor",
            ],
          ),
        ]);
        break;
      case 'it':
        sections.addAll([
          HelpSection(
            icon: LucideIcons.users,
            title: "Restablecer Credenciales",
            items: [
              "Restablecer contraseñas de usuarios",
              "Gestionar identidades",
            ],
          ),
          HelpSection(
            icon: LucideIcons.ticket,
            title: "Tickets de Soporte",
            items: [
              "Ver tickets abiertos, en progreso y resueltos",
              "Filtrar por estado",
              "Actualizar estado de tickets",
              "Prioridades: baja, normal, alta",
            ],
          ),
        ]);
        break;
      case 'employee':
        sections.addAll([
          HelpSection(
            icon: LucideIcons.shoppingCart,
            title: "Punto de Venta (POS)",
            items: [
              "Seleccionar productos del grid categorizado",
              "Buscar por SKU o nombre",
              "Carrito de compras con control de cantidades",
              "Teclado numérico táctil para entrada rápida",
              "Cálculo automático de subtotal, IVA (15%) y total",
              "Procesar venta (checkout) con sincronización offline",
              "Escáner de código de barras (próximamente)",
            ],
          ),
        ]);
        break;
    }

    sections.add(
      HelpSection(
        icon: LucideIcons.shield,
        title: "Soporte Técnico",
        items: [
          "Para soporte adicional, contacte a su administrador de TI",
          "Reporte fallos técnicos a través del sistema de tickets",
          "Versión de la aplicación: 30.0.1",
        ],
      ),
    );

    return sections
        .expand((section) => [
              _buildHelpSection(section),
              const SizedBox(height: 24),
            ])
        .toList();
  }

  Widget _buildHelpSection(HelpSection section) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(section.icon, color: Colors.red, size: 20),
              ),
              const SizedBox(width: 16),
              Text(section.title,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 16),
          ...section.items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("  •  ", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                Expanded(
                  child: Text(item,
                    style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4)),
                ),
              ],
            ),
          )),
        ],
      ),
    ).animate().fadeIn().slideX(begin: 0.05, curve: Curves.easeOut);
  }
}

class HelpSection {
  final IconData icon;
  final String title;
  final List<String> items;

  HelpSection({required this.icon, required this.title, required this.items});
}
