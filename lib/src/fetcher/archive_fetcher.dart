// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';

import 'package:dartx/dartx.dart';
import 'package:dfunc/dfunc.dart';
import 'package:mno_commons_dart/extensions/strings.dart';
import 'package:mno_commons_dart/utils/exceptions.dart';
import 'package:mno_shared_dart/fetcher.dart';
import 'package:mno_shared_dart/publication.dart';
import 'package:mno_shared_dart/src/mediatype/mediatype.dart';
import 'package:mno_shared_dart/src/util/archive/archive.dart';
import 'package:universal_io/io.dart';

import 'fetcher.dart';

/// Provides access to entries of an archive.
class ArchiveFetcher extends Fetcher {
  final Archive archive;

  ArchiveFetcher(this.archive);

  @override
  Future<List<Link>> links() async =>
      waitTryOr(<ArchiveEntry>[], () => archive.entries()).then(
          (entries) => Future.wait(entries.map((value) => value.toLink())));

  @override
  Resource get(Link link) => EntryResource(link, archive);

  @override
  Future<void> close() => archive.close();

  static Future<ArchiveFetcher> fromPath(String path,
          {ArchiveFactory archiveFactory = const DefaultArchiveFactory()}) =>
      waitTryOrNull(() async => await archiveFactory
          .open(File(path), null)
          ?.then((archive) => archive?.let((it) => ArchiveFetcher(it))));
}

class EntryResource extends Resource {
  final Link _originalLink;
  final Archive _archive;
  ResourceTry<ArchiveEntry> _entry;

  EntryResource(this._originalLink, this._archive);

  Future<ResourceTry<ArchiveEntry>> entry() async {
    if (_entry == null) {
      try {
        ArchiveEntry entry =
            await _archive.entry(_originalLink.href.removePrefix("/"));
        _entry = ResourceTry.success(entry);
      } on Exception {
        _entry = ResourceTry.failure(ResourceException.notFound);
      }
    }
    return _entry;
  }

  @override
  Future<Link> link() async {
    int compressedLength =
        (await entry()).map((it) => it.compressedLength).getOrNull();
    if (compressedLength == null) {
      return _originalLink;
    }

    return _originalLink.addProperties({"compressedLength": compressedLength});
  }

  @override
  Future<ResourceTry<ByteData>> read({IntRange range}) async =>
      (await entry()).mapWait((it) => it.read(range: range));

  @override
  Future<ResourceTry<int>> length() async {
    int length = await _metadataLength();
    if (length != null) {
      return ResourceTry.success(length);
    }
    return read()
        .then((data) => data.mapCatching((value) => value.lengthInBytes));
  }

  @override
  Future<void> close() async {}

  Future<int> _metadataLength() =>
      entry().then((entry) => entry.getOrNull()?.length);

  @override
  String toString() =>
      'EntryResource{${_archive.runtimeType}, ${_originalLink.href}}';
}

extension ArchiveFileExtension on ArchiveEntry {
  Future<Link> toLink() async {
    Link link = Link(
        id: path.addPrefix("/"),
        href: path.addPrefix("/"),
        type: (await MediaType.ofSingleHint(fileExtension: path.extension()))
            ?.toString());

    if (compressedLength != null) {
      link.addProperties({"compressedLength": compressedLength});
    }

    return link;
  }
}