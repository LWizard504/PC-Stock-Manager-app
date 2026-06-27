class InventoryPredictor {
  static ({int? daysRemaining, String status}) predictRestockDate({
    required int currentStock,
    required List<({String date, int quantity})> salesHistory,
    int threshold = 5,
  }) {
    if (salesHistory.length < 3) {
      return (daysRemaining: null, status: 'Insufficient Data');
    }

    final totalSales = salesHistory.fold<int>(0, (sum, s) => sum + s.quantity);
    final firstDate = DateTime.parse(salesHistory.last.date);
    final lastDate = DateTime.parse(salesHistory.first.date);
    final daysDiff = lastDate.difference(firstDate).inDays;
    final effectiveDays = daysDiff > 0 ? daysDiff : 1;

    final dailyRate = totalSales / effectiveDays;
    if (dailyRate <= 0) {
      return (daysRemaining: null, status: 'Stable');
    }

    final daysRemaining = ((currentStock - threshold) / dailyRate).floor();
    if (daysRemaining <= 2) return (daysRemaining: daysRemaining, status: 'CRITICAL');
    if (daysRemaining <= 7) return (daysRemaining: daysRemaining, status: 'WARNING');
    return (daysRemaining: daysRemaining, status: 'HEALTHY');
  }
}
