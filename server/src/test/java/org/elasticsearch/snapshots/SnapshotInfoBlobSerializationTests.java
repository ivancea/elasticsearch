/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the "Elastic License
 * 2.0", the "GNU Affero General Public License v3.0 only", and the "Server Side
 * Public License v 1"; you may not use this file except in compliance with, at
 * your election, the "Elastic License 2.0", the "GNU Affero General Public
 * License v3.0 only", or the "Server Side Public License, v 1".
 */

package org.elasticsearch.snapshots;

import org.elasticsearch.TransportVersion;
import org.elasticsearch.common.io.stream.BytesStreamOutput;
import org.elasticsearch.repositories.ProjectRepo;
import org.elasticsearch.repositories.blobstore.BlobStoreRepository;
import org.elasticsearch.test.AbstractWireTestCase;
import org.elasticsearch.xcontent.NamedXContentRegistry;

import java.io.IOException;

public class SnapshotInfoBlobSerializationTests extends AbstractWireTestCase<SnapshotInfo> {

    @Override
    protected SnapshotInfo createTestInstance() {
        return SnapshotInfoTestUtils.createRandomSnapshotInfo();
    }

    @Override
    protected SnapshotInfo mutateInstance(SnapshotInfo instance) {
        return SnapshotInfoTestUtils.mutateSnapshotInfo(instance);
    }

    @Override
    protected SnapshotInfo copyInstance(SnapshotInfo instance, TransportVersion version) throws IOException {
        final BytesStreamOutput out = new BytesStreamOutput();
        BlobStoreRepository.SNAPSHOT_FORMAT.serialize(instance, "test", randomBoolean(), out);
        return BlobStoreRepository.SNAPSHOT_FORMAT.deserialize(
            new ProjectRepo(instance.projectId(), instance.repository()),
            NamedXContentRegistry.EMPTY,
            out.bytes().streamInput()
        );
    }

}
