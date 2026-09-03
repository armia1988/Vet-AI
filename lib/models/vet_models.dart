enum AnimalGroup { livestock, poultry, dogs }

enum SubscriptionTier { software, smartMonitoring }

enum BillingCycle { monthly, annual }

enum RiskLevel { none, yellow, orange, red, insufficientData }

class FarmProfile {
  String ownerName = '';
  String email = '';
  String phone = '';
  String companyName = '';
  String farmName = '';
  String country = '';
  String region = '';
  int workers = 0;
  int veterinarians = 0;
  int barns = 1;
  double totalIndoorAreaM2 = 0;
  final Set<AnimalGroup> groups = {};
  int livestockCount = 0;
  int poultryCount = 0;
  int dogCount = 0;
  String breeds = '';
  String ageRange = '';
  String productionPurpose = '';
  String ventilation = '';
  String vaccinationNotes = '';
  String diseaseHistory = '';
  SubscriptionTier subscriptionTier = SubscriptionTier.software;
  BillingCycle billingCycle = BillingCycle.monthly;
}

class SensorSnapshot {
  const SensorSnapshot({
    required this.animalId,
    required this.bodyTemperatureC,
    required this.ambientTemperatureC,
    required this.humidityPercent,
    required this.activityIndex,
    required this.distanceFromHerdMeters,
    required this.steps,
    required this.lyingMinutesToday,
    required this.feedingMinutesToday,
    required this.ruminationMinutesToday,
    required this.calvingRiskPercent,
    required this.lastUpdate,
  });

  final String animalId;
  final double bodyTemperatureC;
  final double ambientTemperatureC;
  final double humidityPercent;
  final double activityIndex;
  final double distanceFromHerdMeters;
  final int steps;
  final int lyingMinutesToday;
  final int feedingMinutesToday;
  final int ruminationMinutesToday;
  final double calvingRiskPercent;
  final DateTime lastUpdate;
}

class HealthAlert {
  const HealthAlert({
    required this.title,
    required this.details,
    required this.level,
    required this.animalId,
    required this.createdAt,
  });

  final String title;
  final String details;
  final RiskLevel level;
  final String animalId;
  final DateTime createdAt;
}
