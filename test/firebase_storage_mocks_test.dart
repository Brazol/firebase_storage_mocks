import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file/memory.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:firebase_storage_mocks/src/mock_storage_reference.dart';
import 'package:test/test.dart';

final filename = 'someimage.png';
final random = Random.secure();

void main() {
  group('MockFirebaseStorage Tests', () {
    test('Puts File', () async {
      final storage = MockFirebaseStorage();
      final storageRef = storage.ref().child(filename);
      final task = storageRef.putFile(getFakeImageFile());
      await task;

      expect(
          task.snapshot.ref.fullPath, equals('gs://some-bucket/someimage.png'));
      expect(storage.storedFilesMap.containsKey('/$filename'), isTrue);
    });

    test('Puts Data', () async {
      final storage = MockFirebaseStorage();
      final storageRef = storage.ref().child(filename);
      final imageData = randomData(256);
      final task = storageRef.putData(imageData);
      await task;

      expect(
          task.snapshot.ref.fullPath, equals('gs://some-bucket/someimage.png'));
      expect(storage.storedDataMap.containsKey('/$filename'), isTrue);
    });

    group('Gets Data', () {
      late MockFirebaseStorage storage;
      late Reference reference;
      final imageData = randomData(256);
      setUp(() async {
        storage = MockFirebaseStorage();
        reference = storage.ref().child(filename);
        final task = reference.putData(imageData);
        await task;
      });
      test('for valid reference', () async {
        final data = await reference.getData();
        expect(data, imageData);
      });
      test('for invalid reference', () async {
        final invalidReference = reference.child("invalid");
        final data = await invalidReference.getData();
        expect(data, isNull);
      });
    });

    test('Get download url', () async {
      final storage = MockFirebaseStorage();
      final downloadUrl = await storage.ref('/some/path').getDownloadURL();
      expect(downloadUrl.startsWith('http'), isTrue);
      expect(downloadUrl.contains('/some/path'), isTrue);
    });

    test('Ref from url', () async {
      final storage = MockFirebaseStorage();
      final downloadUrl = await storage.ref('/some/path').getDownloadURL();
      final ref = storage.refFromURL(downloadUrl);
      expect(ref, isA<Reference>());
    });
    test('Set, get and update metadata', () async {
      final storage = MockFirebaseStorage();
      final storageRef = storage.ref().child(filename);
      final task = storageRef.putFile(getFakeImageFile());
      await task;
      await storageRef.updateMetadata(SettableMetadata(
        cacheControl: 'public,max-age=300',
        contentType: 'image/jpeg',
        customMetadata: <String, String>{
          'userId': 'ABC123',
        },
      ));

      final metadata = await storageRef.getMetadata();
      expect(metadata.cacheControl, equals('public,max-age=300'));
      expect(metadata.contentType, equals('image/jpeg'));
      expect(metadata.customMetadata!['userId'], equals('ABC123'));
      expect(metadata.name, equals(storageRef.name));
      expect(metadata.fullPath, equals(storageRef.fullPath));
      expect(metadata.timeCreated, isNotNull);

      await storageRef.updateMetadata(SettableMetadata(
        cacheControl: 'max-age=60',
        customMetadata: <String, String>{
          'userId': 'ABC123',
        },
      ));
      final metadata2 = await storageRef.getMetadata();
      expect(metadata2.cacheControl, equals('max-age=60'));

      ///Old informations persist over updates
      expect(metadata2.contentType, equals('image/jpeg'));
    });

    test('Stream upload with snapshotEvents', () async {
      final storage = MockFirebaseStorage();
      final storageRef = storage.ref().child(filename);
      final task = storageRef.putFile(getFakeImageFile());

      task.snapshotEvents.listen((event) async {
        expect(event.state, equals(TaskState.success));

        final downloadUrl = await event.ref.getDownloadURL();

        expect(downloadUrl.startsWith('http'), isTrue);
        expect(downloadUrl.contains('some-bucket/o/someimage.png'), isTrue);
      });
    });

    test('Ref listAll', () async {
      final basePath = 'this/is/basic';
      final otherPath = 'another/path';
      final storage = MockFirebaseStorage();
      await storage.ref(basePath + '/data2').putData(randomData(255));
      await storage.ref(basePath + '/subdir1/data1').putData(randomData(255));
      await storage.ref(basePath + '/data2').putData(randomData(255));
      await storage.ref(otherPath + '/data3').putData(randomData(255));
      await storage.ref(basePath + '/file3').putFile(getFakeImageFile());
      await storage.ref(basePath + '/data3').putData(randomData(255));
      await storage
          .ref(basePath + '/subdir2/file2')
          .putFile(getFakeImageFile());
      await storage
          .ref(basePath + '/subdir1/file1')
          .putFile(getFakeImageFile());

      final listResult = await storage.ref(basePath).listAll();
      expect(listResult.prefixes.length, 2);
      expectRef(listResult.prefixes[0], name: 'subdir1');
      expectRef(listResult.prefixes[1], name: 'subdir2');
      expect(listResult.items.length, 3);
      expectRef(listResult.items[0], name: 'data2');
      expectRef(listResult.items[1], name: 'data3');
      expectRef(listResult.items[2], name: 'file3');
    });
  });
}

void expectRef(Reference actualReference, {required String name}) {
  expect(actualReference,
      isA<MockReference>().having((ref) => ref.name, 'Right name', name));
}

Uint8List randomData(int n) {
  final elements = List.generate(n, (index) => random.nextInt(255));
  return Uint8List.fromList(elements);
}

File getFakeImageFile() {
  var fs = MemoryFileSystem();
  final image = fs.file(filename);
  image.writeAsStringSync('contents');
  return image;
}
