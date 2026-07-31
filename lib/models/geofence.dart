class Geofence{
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int radius;
  final String description;

  Geofence({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radius,
    required this.description,
  });

  factory Geofence.fromJson(Map<String, dynamic> json) {
    return Geofence(
      id: json['Geofence_ID']?.toString() ?? 'no_id',
      name: json['Geofence_Name'] ?? 'no_name',
      latitude: double.tryParse(json['Latitude']?.toString() ?? '0.0') ?? 0.0,
      longitude: double.tryParse(json['Longitude']?.toString() ?? '0.0') ?? 0.0,
      radius: int.tryParse(json['Radius']?.toString() ?? '0.0') ?? 0,
      description: json['Description'] ?? '',
    );
  }


}