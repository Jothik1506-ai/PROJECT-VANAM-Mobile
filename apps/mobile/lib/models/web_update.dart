class WebUpdate {
  const WebUpdate({
    required this.title,
    required this.status,
    required this.description,
    required this.path,
    required this.iconLabel,
  });

  final String title;
  final String status;
  final String description;
  final String path;
  final String iconLabel;
}

const webUpdates = [
  WebUpdate(
    title: 'Varalakshmi Vratham',
    status: 'Ready for launch',
    description:
        'Telugu puja materials, procedure, mantras, story, search, font controls, and printable reading view.',
    path: 'Varalakshmi%20vratham/',
    iconLabel: 'Vratham',
  ),
  WebUpdate(
    title: 'VANAM Central Library',
    status: 'Live hub',
    description:
        'Central page for Telugu devotional reading projects, feedback, and workflow links.',
    path: '',
    iconLabel: 'Library',
  ),
];
