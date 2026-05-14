enum UserRole {
  superadmin,
  admin,
  manager,
  it,
  employee
}

class AppUser {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String? avatarUrl;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.avatarUrl,
  });

  String get roleDisplayName {
    switch (role) {
      case UserRole.superadmin:
        return 'SuperAdmin';
      case UserRole.admin:
        return 'Administrator';
      case UserRole.manager:
        return 'Manager';
      case UserRole.it:
        return 'IT Support';
      case UserRole.employee:
        return 'Cashier';
    }
  }
}
