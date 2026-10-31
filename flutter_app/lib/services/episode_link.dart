import 'package:url_launcher/url_launcher.dart';

typedef EpisodeLinkOpener = Future<bool> Function(Uri uri);

Future<bool> openEpisodeLink(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
