import 'package:common_descent_listing/services/library_connection.dart';
import 'package:common_descent_listing/services/transcript_edits.dart';
import 'package:common_descent_listing/data/local_prepared_episodes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'library address supports LAN hosts without accepting embedded credentials',
    () {
      expect(
        LibraryConnection.validateAddress('http://library-mac.local:8766').host,
        'library-mac.local',
      );
      for (final value in [
        'file:///private/data',
        'http://user:secret@host:8766',
        'http://host/path',
        'http://host?token=secret',
      ]) {
        expect(
          () => LibraryConnection.validateAddress(value),
          throwsFormatException,
        );
      }
    },
  );
  test('server transcript journal cannot write corrections', () async {
    final store = ReadOnlyTranscriptEditStore();
    expect(await store.read('episode'), isNull);
    expect(
      await store.writeIfUnchanged(
        'episode',
        expectedDocument: null,
        document: '{}',
      ),
      isFalse,
    );
  });
  test('local worker editions override remote editions without losing remote library', () {
    LocalPreparedEdition edition(String id, {bool remote = false}) =>
        LocalPreparedEdition(
          guid: 'episode',
          edition: id,
          audioUri: Uri.parse('http://host/audio.opus'),
          audioIdentity: 'sha256:fixture',
          duration: const Duration(seconds: 1),
          passageCount: 1,
          readOnly: remote,
          loadText: (_) async => '{}',
        );
    addTearDown(() {
      LocalPreparedEpisodes.replace([]);
      LocalPreparedEpisodes.replaceRemote([]);
    });
    LocalPreparedEpisodes.replaceRemote([edition('remote', remote: true)]);
    LocalPreparedEpisodes.replace([edition('local')]);
    expect(LocalPreparedEpisodes.forGuid('episode')!.edition, 'local');
    LocalPreparedEpisodes.replace([]);
    expect(LocalPreparedEpisodes.forGuid('episode')!.readOnly, isTrue);
    expect(LocalPreparedEpisodes.editions, hasLength(1));
  });
}
