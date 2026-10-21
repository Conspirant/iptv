class Channel {
  final String name;
  final String logoUrl;
  final String streamUrl;
  final String category;

  Channel({
    required this.name,
    required this.logoUrl,
    required this.streamUrl,
    this.category = 'Other',
  });
}
