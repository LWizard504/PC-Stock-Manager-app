import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pc_dev_flutter/models/app_user.dart';
import 'package:pc_dev_flutter/theme/app_theme.dart';
import 'package:pc_dev_flutter/context/locale_provider.dart';
import 'package:pc_dev_flutter/ui/screens/superadmin/dashboard_screen.dart';
import 'package:pc_dev_flutter/ui/screens/admin/dashboard_screen.dart';
import 'package:pc_dev_flutter/ui/screens/manager/dashboard_screen.dart';
import 'package:pc_dev_flutter/ui/screens/it/dashboard_screen.dart';
import 'package:pc_dev_flutter/ui/screens/inventory_screen.dart';
import 'package:pc_dev_flutter/ui/screens/superadmin/users_screen.dart';
import 'package:pc_dev_flutter/ui/screens/superadmin/pricing_screen.dart';
import 'package:pc_dev_flutter/ui/screens/superadmin/node_status_screen.dart';
import 'package:pc_dev_flutter/ui/screens/superadmin/downloads_screen.dart';
import 'package:pc_dev_flutter/ui/screens/shared/chat_screen.dart';
import 'package:pc_dev_flutter/ui/screens/shared/settings_screen.dart';
import 'package:pc_dev_flutter/ui/screens/employee/pos_screen.dart';
import 'package:pc_dev_flutter/ui/screens/admin/sales_screen.dart';
import 'package:pc_dev_flutter/ui/screens/admin/payments_screen.dart';
import 'package:pc_dev_flutter/ui/screens/login_screen.dart';

class SidebarItem {
  final String title;
  final IconData icon;
  final Widget screen;

  SidebarItem({required this.title, required this.icon, required this.screen});
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  bool _isExpanded = true;
  AppUser? _currentUser;
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
      }
      return;
    }

    try {
      final data = await Supabase.instance.client.from('profiles').select().eq('id', user.id).single();
      
      UserRole role;
      switch(data['role']) {
        case 'superadmin': role = UserRole.superadmin; break;
        case 'admin': role = UserRole.admin; break;
        case 'manager': role = UserRole.manager; break;
        case 'it': role = UserRole.it; break;
        case 'global_it': role = UserRole.it; break;
        default: role = UserRole.employee; break;
      }

      String name = data['full_name'] ?? '';
      if (name.isEmpty) {
        final first = data['first_name'] ?? '';
        final last = data['last_name'] ?? '';
        name = '$first $last'.trim();
      }
      if (name.isEmpty) name = 'Usuario';

      setState(() {
        _currentUser = AppUser(
          id: data['id'],
          name: name,
          email: user.email ?? '',
          role: role,
          avatarUrl: data['avatar_url'],
        );
        _isLoadingProfile = false;
      });
    } catch (e) {
      // Fallback
      setState(() {
        _currentUser = AppUser(
          id: user.id,
          name: user.userMetadata?['full_name'] ?? 'Guest',
          email: user.email ?? '',
          role: UserRole.admin,
          avatarUrl: user.userMetadata?['avatar_url'],
        );
        _isLoadingProfile = false;
      });
    }
  }

  void _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  List<SidebarItem> _getSidebarItemsForRole(UserRole role, String Function(String) t) {
    switch (role) {
      case UserRole.superadmin:
        return [
          SidebarItem(title: "Dashboard", icon: LucideIcons.layoutDashboard, screen: const SuperAdminDashboardScreen()),
          SidebarItem(title: t('users_title'), icon: LucideIcons.users, screen: const UsersScreen()),
          SidebarItem(title: t('pricing_title'), icon: LucideIcons.dollarSign, screen: const PricingScreen()),
          SidebarItem(title: "Node Status", icon: LucideIcons.activity, screen: const NodeStatusScreen()),
          SidebarItem(title: "Downloads", icon: LucideIcons.downloadCloud, screen: const DownloadsScreen()),
          SidebarItem(title: "Chat", icon: LucideIcons.messageSquare, screen: const ChatScreen()),
          SidebarItem(title: "Settings", icon: LucideIcons.settings, screen: const SettingsScreen()),
        ];
      case UserRole.admin:
        return [
          SidebarItem(title: "Dashboard", icon: LucideIcons.layoutDashboard, screen: const AdminDashboardScreen()),
          SidebarItem(title: t('inventory_title'), icon: LucideIcons.package2, screen: const InventoryScreen()),
          SidebarItem(title: t('users_title'), icon: LucideIcons.users, screen: const UsersScreen()),
          SidebarItem(title: "Ventas", icon: LucideIcons.receipt, screen: const SalesScreen()),
          SidebarItem(title: "Pagos", icon: LucideIcons.creditCard, screen: const PaymentsScreen()),
          SidebarItem(title: "Chat", icon: LucideIcons.messageSquare, screen: const ChatScreen()),
          SidebarItem(title: "Ajustes", icon: LucideIcons.settings, screen: const SettingsScreen()),
        ];
      case UserRole.manager:
        return [
          SidebarItem(title: "Dashboard", icon: LucideIcons.layoutDashboard, screen: const ManagerDashboardScreen()),
          SidebarItem(title: t('inventory_title'), icon: LucideIcons.package2, screen: const InventoryScreen()),
          SidebarItem(title: "Ventas", icon: LucideIcons.history, screen: const SalesScreen()),
          SidebarItem(title: "Chat", icon: LucideIcons.messageSquare, screen: const ChatScreen()),
          SidebarItem(title: "Ajustes", icon: LucideIcons.settings, screen: const SettingsScreen()),
        ];
      case UserRole.it:
        return [
          SidebarItem(title: "Dashboard", icon: LucideIcons.layoutDashboard, screen: const ITDashboardScreen()),
          SidebarItem(title: t('inventory_title'), icon: LucideIcons.package2, screen: const InventoryScreen()),
          SidebarItem(title: t('users_title'), icon: LucideIcons.users, screen: const UsersScreen()),
          SidebarItem(title: "Chat", icon: LucideIcons.messageSquare, screen: const ChatScreen()),
          SidebarItem(title: "Ajustes", icon: LucideIcons.settings, screen: const SettingsScreen()),
        ];
      case UserRole.employee:
        return [
          SidebarItem(title: t('pos_title'), icon: LucideIcons.shoppingCart, screen: const POSScreen()),
          SidebarItem(title: t('inventory_title'), icon: LucideIcons.package2, screen: const InventoryScreen()),
          SidebarItem(title: "Chat", icon: LucideIcons.messageSquare, screen: const ChatScreen()),
          SidebarItem(title: "Ajustes", icon: LucideIcons.settings, screen: const SettingsScreen()),
        ];
    }
  }

  void _toggleSidebar() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocaleProvider>(context).t;
    if (_isLoadingProfile || _currentUser == null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundDark,
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
      );
    }

    final items = _getSidebarItemsForRole(_currentUser!.role, t);
    
    if (_selectedIndex >= items.length) {
      _selectedIndex = 0;
    }

    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(items),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                bottomLeft: Radius.circular(24),
              ),
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: items[_selectedIndex].screen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(List<SidebarItem> items) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: _isExpanded ? 260 : 88,
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
      ),
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center, // center when collapsed
        children: [
          // Logo Area & Toggle
          Row(
            mainAxisAlignment: _isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              InkWell(
                onTap: _toggleSidebar,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(LucideIcons.boxes, color: Colors.white, size: 24),
                ),
              ),
              if (_isExpanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "StockManager",
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: _toggleSidebar,
                  icon: const Icon(LucideIcons.chevronLeft, color: Colors.white54),
                  tooltip: "Collapse Sidebar",
                ),
              ],
            ],
          ),
          const SizedBox(height: 32),
          
          // User Profile Area
          InkWell(
            onTap: () {
              // Show profile options or logout
            },
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: _isExpanded ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.surfaceLight.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: _isExpanded ? 40 : 32,
                    height: _isExpanded ? 40 : 32,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      image: _currentUser!.avatarUrl != null 
                        ? DecorationImage(image: NetworkImage(_currentUser!.avatarUrl!), fit: BoxFit.cover)
                        : null,
                    ),
                    child: _currentUser!.avatarUrl == null 
                      ? Center(
                          child: Text(
                            _currentUser!.name[0].toUpperCase(),
                            style: TextStyle(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: _isExpanded ? 16 : 14,
                            ),
                          ),
                        )
                      : null,
                  ),
                  if (_isExpanded) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentUser!.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _currentUser!.roleDisplayName,
                            style: const TextStyle(fontSize: 12, color: AppTheme.accentColor, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 32),
          
          if (_isExpanded)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "MENU",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(0.4),
                  letterSpacing: 1.2,
                ),
              ),
            )
          else
            const Divider(color: Colors.white24),
            
          const SizedBox(height: 16),

          // Menu Items
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _buildNavItem(index, item.icon, item.title);
              },
            ),
          ),
          
          // Footer Actions
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.logOut, size: 20, color: Colors.redAccent),
                    onPressed: _signOut,
                    tooltip: "Cerrar Sesión",
                  ),
                  const SizedBox(width: 8),
                  const Text("Finalizar Sesión", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          else
            Column(
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.refreshCw, size: 16, color: AppTheme.primaryColor),
                  onPressed: () {
                    final roles = UserRole.values;
                    final nextIndex = (roles.indexOf(_currentUser!.role) + 1) % roles.length;
                    setState(() {
                      _currentUser = AppUser(
                        id: _currentUser!.id,
                        name: _currentUser!.name,
                        email: _currentUser!.email,
                        avatarUrl: _currentUser!.avatarUrl,
                        role: roles[nextIndex],
                      );
                      _selectedIndex = 0;
                    });
                  },
                  tooltip: "Switch Role",
                ),
                IconButton(
                  icon: const Icon(LucideIcons.logOut, size: 16, color: Colors.redAccent),
                  onPressed: _signOut,
                  tooltip: "Cerrar Sesión",
                ),
              ],
            ),

          // Footer version
          if (_isExpanded)
            Center(
              child: Text(
                "Version 2.0.0",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.3),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String title) {
    final isSelected = _selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Tooltip(
        message: _isExpanded ? '' : title,
        preferBelow: false,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedIndex = index;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              horizontal: _isExpanded ? 16 : 0, 
              vertical: 12
            ),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryColor.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppTheme.primaryColor.withOpacity(0.5) : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: _isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isSelected ? AppTheme.primaryColor : Colors.white70,
                  size: 20,
                ),
                if (_isExpanded) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

